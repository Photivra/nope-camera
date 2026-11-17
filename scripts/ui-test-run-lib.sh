#!/usr/bin/env bash
# Shared by scripts/run-ui-test-shard.sh and scripts/run-watch-ui-tests.sh: runs xcodebuild
# test-without-building, says whether a failed run is a test failure or an infrastructure
# failure, runs an infrastructure failure's unfinished tests once more, and writes the job
# summary and the per-test result file (docs/TESTING.md, "Infrastructure and test failures").
#
# A run is classified from its xcodebuild log:
#   passed          xcodebuild succeeded
#   test            a test failed with a result ("Test Case '…' failed"), or a test was cut
#                   short with no sign that the Simulator died; never run again
#   infrastructure  no test failed with a result, and no test started, or the Simulator's host
#                   process (SimLaunchHost) left a new crash report, or the log has "simulator
#                   runtime is not available" or "(ipc/mig) server died"; preparing the
#                   Simulator failing counts too
#
# The caller sets: xcodebuild_args (array, without -resultBundlePath and the tests), tests
# (array of -only-testing arguments, may be empty for a whole scheme), result (the result
# bundle), job_label, device_label, shard_label, and defines prepare (boots and prepares the
# Simulator; non-zero when that fails) and reboot (shuts the Simulator down before prepare runs
# again). It then calls run_classified.
#
#   scripts/ui-test-run-lib.sh --classify <log> <xcodebuild status> <host crashed: 0|1>
#   scripts/ui-test-run-lib.sh --passed-tests <log>     -skip-testing arguments of the tests
#                                                       that passed or were skipped
#   scripts/ui-test-run-lib.sh --results <log> <attempt> the log's per-test results, JSON Lines
#   scripts/ui-test-run-lib.sh --simulator-host-crashed <reports dir> <marker file>
set -euo pipefail

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
results() { # results <log> <attempt>
  python3 - "$1" "$2" <<'PY'
import json, os, re, sys
log, attempt = sys.argv[1], int(sys.argv[2])
started, done = [], {}
pattern = re.compile(r"^Test Case '-\[(\S+?)\.(\S+) (\S+)\]' (started|passed|failed|skipped)(?: \(([\d.]+) seconds\))?")
for line in open(log, errors="replace"):
    match = pattern.match(line)
    if not match:
        continue
    name = match.group(2) + "/" + match.group(3)
    if match.group(4) == "started":
        if name not in started:
            started.append(name)
    else:
        done[name] = (match.group(4), float(match.group(5) or 0))
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
    print(json.dumps({"test": name, "result": result, "seconds": seconds, **common}))
PY
}

case ${1:-} in
  --classify) [[ $# -eq 4 && -f $2 ]] || { echo "usage: $0 --classify <log> <status> <host crashed>" >&2; exit 2; }
    classify "$2" "$3" "$4"; exit ;;
  --passed-tests) [[ -f ${2:-} ]] || { echo "usage: $0 --passed-tests <log>" >&2; exit 2; }
    passed_tests "$2"; exit ;;
  --results) [[ $# -eq 3 && -f $2 ]] || { echo "usage: $0 --results <log> <attempt>" >&2; exit 2; }
    results "$2" "$3"; exit ;;
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

# Writes the job summary (the step summary on GitHub, and the log).
summarize() { # summarize <classification> <text>
  local heading
  case $1 in
    passed) heading="Passed" ;;
    test) heading="Test failure" ;;
    *) heading="Infrastructure failure" ;;
  esac
  {
    echo "### $job_label: $heading"
    echo
    echo "$2"
    if [[ -s $results_file ]]; then
      local failed
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
    fi
    echo
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Runs the tests, classifies the result, and runs an infrastructure failure's unfinished tests
# once more. Exits 0 when every test passed, 1 otherwise.
run_classified() {
  export NOPE_JOB_LABEL=$job_label NOPE_DEVICE_LABEL=$device_label NOPE_SHARD_LABEL=$shard_label
  local reports=${NOPE_CRASH_REPORTS:-$HOME/Library/Logs/DiagnosticReports}
  local marker crashed class retried=0 note=""
  log=$(mktemp); marker=$(mktemp)
  results_file=${NOPE_TEST_RESULTS:-${result%.xcresult}-results.jsonl}
  : >"$results_file"
  trap 'rm -f "$log" "$marker"' EXIT

  if ! prepare; then
    echo "::warning::Infrastructure: preparing the Simulator failed; rebooting it and preparing once more."
    retried=1 note="Preparing the Simulator failed once and was run again. "
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

  if [[ $class == infrastructure && $retried -eq 0 ]]; then
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
    run_tests ${skip[@]+"${skip[@]}"}
    results "$log" 2 >>"$results_file"
    crashed=0; simulator_host_crashed "$reports" "$marker" && crashed=1
    class=$(classify "$log" "$run_status" "$crashed")
    [[ $class != infrastructure ]] || note="${note}The second run ended with an infrastructure failure too. "
  elif [[ $class == infrastructure ]]; then
    note="${note}The run then ended with an infrastructure failure. "
  fi

  case $class in
    passed) summarize passed "${note}Every test passed."; exit 0 ;;
    test) summarize test "${note}A test failed with a result, or ended without one with no sign that the Simulator died. Not run again."; exit 1 ;;
    *) summarize infrastructure "${note}No test failed with a result."; exit 1 ;;
  esac
}
