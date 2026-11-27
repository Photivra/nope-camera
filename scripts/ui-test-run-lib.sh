#!/usr/bin/env bash
# Shared by scripts/run-ui-test-shard.sh and scripts/run-watch-ui-tests.sh: runs xcodebuild
# test-without-building, says whether a failed run is a test failure or an infrastructure
# failure, runs an infrastructure failure's unfinished tests once more, runs each test that
# failed once more on its own (a pass there is recorded as flaky), and writes the job summary
# and the per-test result file (docs/TESTING.md, "Infrastructure and test failures").
#
# A run is classified from its xcodebuild log:
#   passed          xcodebuild succeeded
#   test            a test failed with a result ("Test Case '…' failed"), or a test was cut
#                   short with no sign that the Simulator died
#   infrastructure  no test failed with a result, and no test started, or the Simulator's host
#                   process (SimLaunchHost) left a new crash report, or the log has "simulator
#                   runtime is not available" or "(ipc/mig) server died"; preparing the
#                   Simulator failing counts too
#
# After a test failure each test that failed or was cut short runs once more, alone
# (-only-testing, with its own result bundle <result>-retry-<n>.xcresult), in the same job on
# the same Simulator. The job passes when each of them passed on its retry and every test of the
# shard has a result; they are listed as flaky in the summary and the result file. A test that
# fails on its retry too fails the job, and no further test is retried. With
# NOPE_TEST_TIME_LIMIT_MINUTES set (the test step's limit, from the start of this script), a
# retry runs only when the test's first time plus NOPE_RETRY_STARTUP_SECONDS (default 120) fits
# in what is left of the limit less NOPE_TEST_TIME_MARGIN_SECONDS (default 60), and is ended
# when it runs past that (scripts/with-timeout.sh); either fails the job with a message.
#
# The caller sets: xcodebuild_args (array, without -resultBundlePath and the tests), tests
# (array of -only-testing arguments, may be empty for a whole scheme), result (the result
# bundle), job_label, device_label, shard_label, and defines prepare (boots and prepares the
# Simulator; non-zero when that fails) and reboot (shuts the Simulator down before prepare runs
# again). It then calls run_classified.
#
#   scripts/ui-test-run-lib.sh --classify <log> <xcodebuild status> <host crashed: 0|1>
#   scripts/ui-test-run-lib.sh --passed-tests <log>      -skip-testing arguments of the tests
#                                                        that passed or were skipped
#   scripts/ui-test-run-lib.sh --retry-candidates <log>  Target/Class/test of each test that
#                                                        failed or was cut short
#   scripts/ui-test-run-lib.sh --results <log> <attempt> [retry kind] [first failure] [expected test]
#                                                        the log's per-test results, JSON Lines
#   scripts/ui-test-run-lib.sh --flaky <results file…>   the tests retried after a failure
#   scripts/ui-test-run-lib.sh --simulator-host-crashed <reports dir> <marker file>
set -euo pipefail

lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Whether an xcodebuild log shows the run ending before any test started.
no_test_started() {
  ! grep -qE "^Test Case '.*' started" "$1"
}

# Whether the Simulator's host process left a crash report newer than the marker file. Every
# booted Simulator runs under SimLaunchHost, so its crash ends them all.
simulator_host_crashed() {
  [[ -d $1 ]] && [[ -n $(find "$1" -maxdepth 1 -name 'SimLaunchHost*.ips' -newer "$2" 2>/dev/null | head -1) ]]
}

# classify <log> <xcodebuild status> <host crashed: 0|1>
classify() {
  local log=$1 status=$2 crashed=$3
  if grep -qE "^Test Case '.*' failed \(" "$log"; then echo test; return; fi
  if [[ $status -eq 0 ]]; then echo passed; return; fi
  if no_test_started "$log" || [[ $crashed -eq 1 ]] \
      || grep -qE "simulator runtime is not available|\(ipc/mig\) server died" "$log"; then
    echo infrastructure
    return
  fi
  echo test
}

# "-[Target.Class test]" names of a log's tests with the given results, as Target/Class/test.
tests_with_result() { # tests_with_result <log> <result regex>
  awk -F"'" -v want="$2" '
    $0 ~ "^Test Case .* (" want ")( \\(|\\.$)" {
      name = $2; gsub(/^-\[|\]$/, "", name); sub(/\./, "/", name); sub(/ /, "/", name)
      if (!seen[name]++) print name
    }' "$1"
}

# The -skip-testing arguments that keep a second run from repeating finished tests.
passed_tests() {
  tests_with_result "$1" "passed|skipped" | sed 's/^/-skip-testing:/'
}

# The log's per-test results as JSON Lines: test, result (passed, failed, skipped, or
# interrupted for a test that started and has no result), seconds, attempt, and the job's labels.
# A failed test has message, the first failure the log gives for it. With a retry kind
# (infrastructure: the second run after an infrastructure failure; test-failure: the retry of a
# failed test) each row has retry, and a test-failure retry has first_failure. An expected test
# (Target/Class/test) that never started gets a row with the result interrupted.
results() { # results <log> <attempt> [retry kind] [first failure] [expected test]
  python3 - "$@" <<'PY'
import json, os, re, sys
log, attempt = sys.argv[1], int(sys.argv[2])
retry, first_failure, expected = (sys.argv[3:] + ["", "", ""])[:3]
started, done, messages = [], {}, {}
pattern = re.compile(r"^Test Case '-\[(\S+?)\.(\S+) (\S+)\]' (started|passed|failed|skipped)(?: \(([\d.]+) seconds\))?")
failure = re.compile(r"error: -\[(\S+?)\.(\S+) (\S+)\] : (.*)$")
for line in open(log, errors="replace"):
    line = line.rstrip("\n")
    match = failure.search(line)
    if match:
        messages.setdefault(match.group(2) + "/" + match.group(3), match.group(4).strip()[:300])
        continue
    match = pattern.match(line)
    if not match:
        continue
    name = match.group(2) + "/" + match.group(3)
    if match.group(4) == "started":
        if name not in started:
            started.append(name)
    else:
        done[name] = (match.group(4), float(match.group(5) or 0))
if expected:
    expected = "/".join(expected.split("/")[-2:])
    if expected not in started:
        started.append(expected)
common = {
    "attempt": attempt,
    "job": os.environ.get("NOPE_JOB_LABEL", ""),
    "device": os.environ.get("NOPE_DEVICE_LABEL", ""),
    "shard": os.environ.get("NOPE_SHARD_LABEL", ""),
    "runner_image": " ".join(filter(None, [os.environ.get("ImageOS"), os.environ.get("ImageVersion")])),
    "run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", ""),
    "sha": os.environ.get("NOPE_HEAD_SHA") or os.environ.get("GITHUB_SHA", ""),
}
for name in started:
    result, seconds = done.get(name, ("interrupted", 0.0))
    row = {"test": name, "result": result, "seconds": seconds, **common}
    if result == "failed" and name in messages:
        row["message"] = messages[name]
    if retry:
        row["retry"] = retry
    if retry == "test-failure":
        row["first_failure"] = first_failure
    print(json.dumps(row))
PY
}

# Target/Class/test of each test in the log whose last line is a failure, or that started and
# has no result: the tests a test failure retries.
retry_candidates() { # retry_candidates <log>
  python3 - "$1" <<'PY'
import re, sys
pattern = re.compile(r"^Test Case '-\[(\S+?)\.(\S+) (\S+)\]' (started|passed|failed|skipped)")
order, last = [], {}
for line in open(sys.argv[1], errors="replace"):
    match = pattern.match(line)
    if match:
        name = "/".join(match.group(1, 2, 3))
        if name not in last:
            order.append(name)
        last[name] = match.group(4)
for name in order:
    if last[name] in ("failed", "started"):
        print(name)
PY
}

# One fact about a test from a result file: message (its last failed or cut-short row's
# failure), seconds (its last row's time, whole seconds) or last (its last row's result).
result_field() { # result_field <results file> <Target/Class/test> message|seconds|last
  python3 - "$@" <<'PY'
import json, sys
path, name, field = sys.argv[1], "/".join(sys.argv[2].split("/")[-2:]), sys.argv[3]
rows = [row for row in map(json.loads, open(path)) if row["test"] == name]
if field == "last":
    print(rows[-1]["result"] if rows else "none")
elif field == "seconds":
    print(int(rows[-1].get("seconds", 0) + 0.5) if rows else 0)
else:
    for row in reversed(rows):
        if row["result"] == "failed":
            print(row.get("message") or "no failure message in the log"); break
        if row["result"] == "interrupted":
            print("cut short with no result"); break
PY
}

# The shard's tests (its -only-testing arguments, less those of any -skip-testing argument)
# whose last row in the result file isn't passed or skipped, as Class/test. Nothing for a job
# that runs a whole scheme.
unfinished_tests() { # unfinished_tests <results file> [xcodebuild arguments…]
  python3 - "$@" <<'PY'
import json, sys
path, args = sys.argv[1], sys.argv[2:]
last = {}
for line in open(path):
    row = json.loads(line); last[row["test"]] = row["result"]
skip = {a.split(":", 1)[1] for a in args if a.startswith("-skip-testing:")}
for arg in args:
    if not arg.startswith("-only-testing:"):
        continue
    name = arg.split(":", 1)[1]
    parts = name.split("/")
    if len(parts) != 3 or name in skip or "/".join(parts[:2]) in skip:
        continue
    if last.get("/".join(parts[1:])) not in ("passed", "skipped"):
        print("/".join(parts[1:]))
PY
}

# The tests retried after a test failure, from result files, one Markdown line each: the test,
# the job, the first failure and the retry's result.
flaky() { # flaky <results file…>
  python3 - "$@" <<'PY'
import json, sys
for path in sys.argv[1:]:
    for line in open(path):
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("retry") != "test-failure":
            continue
        where = " on ".join(filter(None, [row.get("job", ""), row.get("device", "")]))
        verdict = "passed on the retry (flaky)" if row["result"] == "passed" else row["result"] + " on the retry too"
        print("- `" + row["test"] + "`" + (" (" + where + ")" if where else "") + ": first failure: "
              + (row.get("first_failure") or "none recorded") + "; " + verdict)
PY
}

case ${1:-} in
  --classify) [[ $# -eq 4 && -f $2 ]] || { echo "usage: $0 --classify <log> <status> <host crashed>" >&2; exit 2; }
    classify "$2" "$3" "$4"; exit ;;
  --passed-tests) [[ -f ${2:-} ]] || { echo "usage: $0 --passed-tests <log>" >&2; exit 2; }
    passed_tests "$2"; exit ;;
  --retry-candidates) [[ -f ${2:-} ]] || { echo "usage: $0 --retry-candidates <log>" >&2; exit 2; }
    retry_candidates "$2"; exit ;;
  --results) [[ $# -ge 3 && $# -le 6 && -f $2 ]] || { echo "usage: $0 --results <log> <attempt> [retry kind] [first failure] [expected test]" >&2; exit 2; }
    shift; results "$@"; exit ;;
  --flaky) [[ $# -ge 2 ]] || { echo "usage: $0 --flaky <results file…>" >&2; exit 2; }
    shift; flaky "$@"; exit ;;
  --simulator-host-crashed) [[ $# -eq 3 && -f $3 ]] || { echo "usage: $0 --simulator-host-crashed <reports dir> <marker file>" >&2; exit 2; }
    simulator_host_crashed "$2" "$3"; exit ;;
esac

# One xcodebuild run. Sets run_status; the log is in $log.
run_tests() { # run_tests [extra xcodebuild args…]
  rm -rf "$result"
  set +e
  xcodebuild test-without-building "${xcodebuild_args[@]}" ${tests[@]+"${tests[@]}"} ${@+"$@"} \
    -resultBundlePath "$result" 2>&1 | tee "$log"
  run_status=${PIPESTATUS[0]}
  set -e
}

# One test alone, with its own result bundle and, given a number of seconds, a time limit (124
# when it ran out). Sets run_status; the log is in $retry_log.
run_retry() { # run_retry <Target/Class/test> <result bundle> [seconds]
  local limit=()
  [[ -z ${3:-} ]] || limit=("$lib_dir/with-timeout.sh" "$3")
  rm -rf "$2"
  set +e
  ${limit[@]+"${limit[@]}"} xcodebuild test-without-building "${xcodebuild_args[@]}" "-only-testing:$1" \
    -resultBundlePath "$2" 2>&1 | tee "$retry_log"
  run_status=${PIPESTATUS[0]}
  set -e
}

# After a test failure: runs each test that failed or was cut short once more, alone, while the
# time limit allows. Sets class to passed when each passed on its retry and every test of the
# shard has a result; adds to note and retried.
retry_test_failures() {
  local names=() name first seconds left need got missing n=0
  while IFS= read -r name; do [[ -n $name ]] && names+=("$name"); done < <(retry_candidates "$log")
  if [[ ${#names[@]} -eq 0 ]]; then
    note="${note}No test failed or was cut short by name, so none was retried. "
    return 0
  fi
  for name in "${names[@]}"; do
    n=$((n + 1))
    first=$(result_field "$results_file" "$name" message)
    seconds=$(result_field "$results_file" "$name" seconds)
    left=
    if [[ -n ${NOPE_TEST_TIME_LIMIT_MINUTES:-} ]]; then
      left=$(( NOPE_TEST_TIME_LIMIT_MINUTES * 60 - ${NOPE_TEST_TIME_MARGIN_SECONDS:-60} - (SECONDS - started_at) ))
      (( left > 0 )) || left=0
      need=$(( seconds + ${NOPE_RETRY_STARTUP_SECONDS:-120} ))
      if (( need > left )); then
        echo "::error::Not retried: ${name#*/} needs about $need s and $left s of the test step's ${NOPE_TEST_TIME_LIMIT_MINUTES}-minute limit are left."
        note="${note}\`${name#*/}\` failed and was not retried: its retry needs about $need s and $left s of the ${NOPE_TEST_TIME_LIMIT_MINUTES}-minute limit were left. "
        return 0
      fi
    fi
    echo "::warning::Test failure: running ${name#*/} once more, alone (first failure: $first)."
    attempt=$((attempt + 1)) retried=$((retried + 1))
    run_retry "$name" "${result%.xcresult}-retry-$n.xcresult" "$left"
    results "$retry_log" "$attempt" test-failure "$first" "$name" >>"$results_file"
    if [[ $run_status -eq 124 ]]; then
      note="${note}The retry of \`${name#*/}\` ran past the $left s left of the ${NOPE_TEST_TIME_LIMIT_MINUTES}-minute limit and was ended. "
      return 0
    fi
    got=$(result_field "$results_file" "$name" last)
    if [[ $got != passed ]]; then
      note="${note}\`${name#*/}\` failed on its retry too ($got). "
      return 0
    fi
  done
  missing=$(unfinished_tests "$results_file" ${tests[@]+"${tests[@]}"} "${xcodebuild_args[@]}")
  if [[ -n $missing ]]; then
    note="${note}Every retried test passed, but these tests have no result: $(echo "$missing" | tr '\n' ' ')"
    return 0
  fi
  class=passed
}

# Writes the job summary (the step summary on GitHub, and the log).
summarize() { # summarize <classification> <text>
  local heading
  case $1 in
    passed) heading="Passed"; [[ $retried -eq 0 ]] || heading="Passed with $retried flaky test(s)" ;;
    test) heading="Test failure" ;;
    *) heading="Infrastructure failure" ;;
  esac
  {
    echo "### $job_label: $heading"
    echo
    echo "$2"
    if [[ -s $results_file ]]; then
      local failed retries
      failed=$(python3 -c '
import json, sys
last = {}
for line in open(sys.argv[1]):
    row = json.loads(line); last[row["test"]] = row
for row in last.values():
    if row["result"] in ("failed", "interrupted"):
        print("- `" + row["test"] + "`: " + row["result"] + " (attempt " + str(row["attempt"]) + ")")
' "$results_file")
      [[ -z $failed ]] || { echo; echo "$failed"; }
      retries=$(flaky "$results_file")
      [[ -z $retries ]] || { echo; echo "Run once more after a test failure:"; echo; echo "$retries"; }
    fi
    echo
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
  # A step output, so the workflow can keep the result bundles of a job that passed on a retry.
  [[ $retried -eq 0 || -z ${GITHUB_OUTPUT:-} ]] || echo "retried=$retried" >>"$GITHUB_OUTPUT"
}

# Runs the tests, classifies the result, runs an infrastructure failure's unfinished tests once
# more, and retries each failed test once. Exits 0 when every test passed, on its first run or
# its retry, and 1 otherwise.
run_classified() {
  export NOPE_JOB_LABEL=$job_label NOPE_DEVICE_LABEL=$device_label NOPE_SHARD_LABEL=$shard_label
  local reports=${NOPE_CRASH_REPORTS:-$HOME/Library/Logs/DiagnosticReports}
  local marker crashed class infra_retried=0 note="" attempt=1
  started_at=$SECONDS retried=0
  log=$(mktemp); marker=$(mktemp); retry_log=$(mktemp)
  results_file=${NOPE_TEST_RESULTS:-${result%.xcresult}-results.jsonl}
  : >"$results_file"
  trap 'rm -f "$log" "$marker" "$retry_log"' EXIT

  if ! prepare; then
    echo "::warning::Infrastructure: preparing the Simulator failed; rebooting it and preparing once more."
    infra_retried=1 note="Preparing the Simulator failed once and was run again. "
    reboot
    if ! prepare; then
      summarize infrastructure "Preparing the Simulator failed twice; no test ran."
      exit 1
    fi
  fi

  run_tests
  results "$log" 1 >>"$results_file"
  crashed=0; simulator_host_crashed "$reports" "$marker" && crashed=1
  class=$(classify "$log" "$run_status" "$crashed")

  if [[ $class == infrastructure && $infra_retried -eq 0 ]]; then
    local skip=()
    while IFS= read -r arg; do [[ -n $arg ]] && skip+=("$arg"); done < <(passed_tests "$log")
    if [[ ${#tests[@]} -gt 0 && ${#skip[@]} -ge ${#tests[@]} ]]; then
      # Every test has its result; only xcodebuild's own ending failed.
      summarize passed "xcodebuild ended with status $run_status after every test had passed or been skipped."
      exit 0
    fi
    echo "::warning::Infrastructure failure (no test failed with a result); rebooting the Simulator and running the tests without a result once more. ${#skip[@]} finished test(s) are not run again."
    note="The first run ended with an infrastructure failure; the ${#skip[@]} test(s) it finished were kept and the others ran once more. "
    rm -rf "${result%.xcresult}-interrupted.xcresult"
    mv "$result" "${result%.xcresult}-interrupted.xcresult" 2>/dev/null || true
    touch "$marker"
    reboot
    if ! prepare; then
      summarize infrastructure "${note}Preparing the Simulator for the second run failed."
      exit 1
    fi
    attempt=2
    run_tests ${skip[@]+"${skip[@]}"}
    results "$log" 2 infrastructure >>"$results_file"
    crashed=0; simulator_host_crashed "$reports" "$marker" && crashed=1
    class=$(classify "$log" "$run_status" "$crashed")
    [[ $class != infrastructure ]] || note="${note}The second run ended with an infrastructure failure too. "
  elif [[ $class == infrastructure ]]; then
    note="${note}The run then ended with an infrastructure failure. "
  fi

  # A test failure, after the first run or the second: each failed test runs once more, alone.
  [[ $class != test ]] || retry_test_failures

  case $class in
    passed)
      if [[ $retried -eq 0 ]]; then summarize passed "${note}Every test passed."
      else summarize passed "${note}Every test passed; $retried test(s) passed only when run once more after failing, and are recorded as flaky."
      fi
      exit 0 ;;
    test) summarize test "${note}A test failed with a result, or ended without one with no sign that the Simulator died."; exit 1 ;;
    *) summarize infrastructure "${note}No test failed with a result."; exit 1 ;;
  esac
}
