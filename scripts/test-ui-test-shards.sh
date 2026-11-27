#!/usr/bin/env bash
# Tests for scripts/ui-test-shards.sh, the classification, second-run and retry rules of
# scripts/ui-test-run-lib.sh, scripts/flaky-tests.sh, scripts/stop-simulator-push.sh,
# scripts/stop-simulator-background-tasks.sh, scripts/wait-for-simulator-runtimes.sh,
# scripts/with-timeout.sh, scripts/prepare-simulator.sh and scripts/add-simulator-runtime.sh:
# each case builds a small tree, log or stand-in and checks the result.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/ui-test-shards.sh"
failures=0

tests='import XCTest

final class FirstUITests: XCTestCase {
    func testOne() {}
    // func testCommentedOut() {}
    private func helper() {}
}

extension FirstUITests {
    @MainActor
    func testTwo() throws {}
}

final class SecondUITests: XCTestCase {
    func testThree() {}
}'

case_tree() { # case_tree "want" "name" "shard list" [mode args…]
  local want=$1 name=$2 shards=$3 d got
  shift 3
  d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts"
  printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
  printf '%s\n' "$shards" >"$d/scripts/ui-test-shards.txt"
  if "$script" "${@:-check}" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

# Two iPhone shards and one iPad shard.
all='# comment
1 1 FirstUITests/testOne 10 12
2 1 FirstUITests/testTwo 20e 22

2 1 SecondUITests/testThree 30 32e'

case_tree pass "every test in one shard per device" "$all"
case_tree fail "an empty list" "# no shards yet"
case_tree fail "a test in no shard" "1 1 FirstUITests/testOne 10 12
2 1 FirstUITests/testTwo 20 22"
case_tree fail "a test listed twice" "$all
1 1 FirstUITests/testTwo 20 22"
case_tree fail "a listed test that doesn't exist" "$all
1 1 FirstUITests/testGone 5 5"
case_tree fail "a commented-out test is not a test" "$all
1 1 FirstUITests/testCommentedOut 5 5"
case_tree fail "a test listed under the wrong class" "1 1 FirstUITests/testOne 10 12
2 1 SecondUITests/testTwo 20 22
2 1 SecondUITests/testThree 30 32"
case_tree fail "a gap in the iPhone shard numbers" "1 1 FirstUITests/testOne 10 12
3 1 FirstUITests/testTwo 20 22
3 1 SecondUITests/testThree 30 32"
case_tree fail "a gap in the iPad shard numbers" "1 1 FirstUITests/testOne 10 12
2 3 FirstUITests/testTwo 20 22
2 3 SecondUITests/testThree 30 32"
case_tree fail "a bad shard number" "x 1 FirstUITests/testOne 10 12
2 1 FirstUITests/testTwo 20 22
2 1 SecondUITests/testThree 30 32"
case_tree fail "a line without the iPad shard" "1 FirstUITests/testOne 10 12
2 1 FirstUITests/testTwo 20 22
2 1 SecondUITests/testThree 30 32"
case_tree fail "a time that isn't a number" "1 1 FirstUITests/testOne ten 12
2 1 FirstUITests/testTwo 20 22
2 1 SecondUITests/testThree 30 32"
case_tree pass "arguments of an iPhone shard" "$all" args iphone 2
case_tree pass "arguments of the iPad shard" "$all" args ipad 1
case_tree fail "arguments of a shard that doesn't exist" "$all" args iphone 3
case_tree fail "arguments of an iPad shard that doesn't exist" "$all" args ipad 2
case_tree fail "arguments without a device" "$all" args 2
case_tree pass "the number of a device's shards" "$all" count ipad

# The workflow's shard matrices and job names must match each device's shards (2 and 1 here).
case_workflow() { # case_workflow "want" "name" "workflow"
  local want=$1 name=$2 workflow=$3 d got
  d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts" "$d/.github/workflows"
  printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
  printf '%s\n' "$all" >"$d/scripts/ui-test-shards.txt"
  printf '%s\n' "$workflow" >"$d/.github/workflows/build.yml"
  if "$script" check "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}
workflow_with() { # workflow_with <iPhone job count> <iPhone matrix> <iPad job count> <iPad matrix>
  printf '%s\n' 'jobs:' '  a:' "    name: ui-tests \${{ matrix.shard }}/$1" '    strategy:' '      matrix:' "        shard: $2" \
    '  b:' "    name: ui-tests-ipad \${{ matrix.shard }}/$3" '    strategy:' '      matrix:' "        shard: $4"
}
case_workflow pass "workflow runs every shard of both devices" "$(workflow_with 2 '[1, 2]' 1 '[1]')"
case_workflow fail "workflow runs too few iPhone shards" "$(workflow_with 2 '[1]' 1 '[1]')"
case_workflow fail "workflow runs too many iPad shards" "$(workflow_with 2 '[1, 2]' 1 '[1, 2]')"
case_workflow fail "an iPhone job name has the wrong count" "$(workflow_with 3 '[1, 2]' 1 '[1]')"
case_workflow fail "an iPad job name has the wrong count" "$(workflow_with 2 '[1, 2]' 2 '[1]')"

# The arguments name the target, class and test; the count and the times follow the list.
d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts"
printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
printf '%s\n' "$all" >"$d/scripts/ui-test-shards.txt"
got=$("$script" args iphone 2 "$d" | tr '\n' ' ')
want="-only-testing:NopeAppUITests/FirstUITests/testTwo -only-testing:NopeAppUITests/SecondUITests/testThree "
if [[ $got == "$want" ]]; then echo "ok   iPhone argument text"; else echo "FAIL iPhone argument text: $got"; failures=$((failures + 1)); fi
got=$("$script" args ipad 1 "$d" | wc -l | tr -d ' ')
if [[ $got == 3 ]]; then echo "ok   the iPad shard has every test"; else echo "FAIL the iPad shard has every test: $got"; failures=$((failures + 1)); fi
got="$("$script" count iphone "$d") $("$script" count ipad "$d")"
if [[ $got == "2 1" ]]; then echo "ok   shard counts"; else echo "FAIL shard counts: $got"; failures=$((failures + 1)); fi
got=$("$script" times "$d" | tr '\n' ';')
want="iPhone shard 1: 10 s (0 min);iPhone shard 2: 50 s (1 min);iPad shard 1: 66 s (1 min);"
if [[ $got == "$want" ]]; then echo "ok   shard times"; else echo "FAIL shard times: $got"; failures=$((failures + 1)); fi
rm -rf "$d"

# A failed run is a test failure when a test failed with a result, and an infrastructure
# failure when no test failed with a result and no test started or the Simulator died.
lib="$here/ui-test-run-lib.sh"
case_class() { # case_class "want" "name" "xcodebuild status" "host crashed" "log text"
  local want=$1 name=$2 log got
  log=$(mktemp); printf '%s\n' "$5" >"$log"
  got=$("$lib" --classify "$log" "$3" "$4")
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -f "$log"
}
started="Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started."
case_class passed "every test passed" 0 0 "$started
Test Case '-[NopeAppUITests.NopeAppUITests testOne]' passed (3.0 seconds)."
case_class test "a test failed" 65 0 "$started
error: -[NopeAppUITests.NopeAppUITests testOne] : XCTAssertTrue failed
Test Case '-[NopeAppUITests.NopeAppUITests testOne]' failed (3.0 seconds)."
case_class test "a test failed and the Simulator died later" 65 1 "$started
Test Case '-[NopeAppUITests.NopeAppUITests testOne]' failed (3.0 seconds).
Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' started.
The iOS 27.2 simulator runtime is not available."
case_class infrastructure "the runner crashed while preparing" 65 0 "Testing started
NopeAppUITests-Runner (11895) encountered an error (The test runner crashed while preparing to run tests: x)"
case_class infrastructure "a build error before any test" 65 0 "xcodebuild: error: Unknown build action ''."
case_class infrastructure "a test cut short and a host process crash report" 65 1 "$started
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
case_class infrastructure "the runtime became unavailable" 65 0 "$started
	The iOS 27.2 simulator runtime is not available."
case_class infrastructure "the Simulator's service died" 65 0 "$started
The operation couldn’t be completed. (Mach error -308 - (ipc/mig) server died)"
case_class test "a test cut short with no sign that the Simulator died" 65 0 "$started
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."

# The second run after an infrastructure failure skips the tests that passed or were skipped,
# and only those.
case_skip() { # case_skip "name" "log text" "expected arguments, space separated"
  local name=$1 log got
  log=$(mktemp); printf '%s\n' "$2" >"$log"
  got=$("$lib" --passed-tests "$log" | tr '\n' ' ')
  if [[ $got == "$3" ]]; then echo "ok   $name"; else echo "FAIL $name: $got"; failures=$((failures + 1)); fi
  rm -f "$log"
}
case_skip "passed and skipped tests are not run again" "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' started.
Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' passed (3.0 seconds).
Test Case '-[NopeAppUITests.OverlayUITests testThree]' started.
Test Case '-[NopeAppUITests.OverlayUITests testThree]' skipped (0.1 seconds).
Test Case '-[NopeAppUITests.OverlayUITests testFour]' started." \
  "-skip-testing:NopeAppUITests/NopeAppUITests/testTwo -skip-testing:NopeAppUITests/OverlayUITests/testThree "
case_skip "nothing is skipped when nothing finished" "Testing started" ""

# The per-test results name each test once per run, with a test cut short as interrupted.
log=$(mktemp)
printf '%s\n' "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started." \
  "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' passed (3.5 seconds)." \
  "Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' started." \
  "Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' failed (4.0 seconds)." \
  "Test Case '-[NopeAppUITests.NopeAppUITests testThree]' started." >"$log"
got=$(NOPE_JOB_LABEL="ui-tests 1/3" NOPE_HEAD_SHA=abc GITHUB_RUN_ID=7 ImageOS=macos27 ImageVersion=1.2 "$lib" --results "$log" 2 \
  | python3 -c 'import json, sys
rows = [json.loads(line) for line in sys.stdin]
print(" ".join(r["test"] + "=" + r["result"] for r in rows), rows[0]["seconds"], rows[0]["attempt"], rows[0]["job"], rows[0]["sha"], rows[0]["run_id"], rows[0]["runner_image"])')
want="NopeAppUITests/testOne=passed NopeAppUITests/testTwo=failed NopeAppUITests/testThree=interrupted 3.5 2 ui-tests 1/3 abc 7 macos27 1.2"
if [[ $got == "$want" ]]; then echo "ok   per-test results"; else echo "FAIL per-test results: $got"; failures=$((failures + 1)); fi
rm -f "$log"

case_host() { # case_host "want" "name" "report file name, or none" "older|newer"
  local want=$1 name=$2 d got
  d=$(mktemp -d); mkdir "$d/reports"
  if [[ $4 == older && $3 != none ]]; then touch -t 202501010000 "$d/reports/$3"; fi
  touch -t 202601010000 "$d/marker"
  if [[ $4 == newer && $3 != none ]]; then touch "$d/reports/$3"; fi
  if "$lib" --simulator-host-crashed "$d/reports" "$d/marker"; then got=crashed; else got=no-crash; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}
case_host crashed "a new crash report of the Simulator's host" "SimLaunchHost.arm64-2026-11-17-174107.000.ips" newer
case_host no-crash "a crash report from before the run" "SimLaunchHost.arm64-2026-11-17-174107.000.ips" older
case_host no-crash "another process's crash report" "intelligencetasksd-2026-11-17-175520.ips" newer
case_host no-crash "no crash reports" none newer

# A whole job, with a stand-in for xcodebuild that prints a prepared log and exits with a
# prepared status for each run (and, given a number of seconds, then waits that long): an
# infrastructure failure is run again once without the finished tests, a failed test runs once
# more alone, and the summary names the classification.
case_job() { # case_job "name" "want exit" "want runs" "want summary text" "prepare: ok|fails|once" ["run n status" "run n log"]…
  local name=$1 want_exit=$2 want_runs=$3 want_text=$4 prepare=$5 d got_exit=0 runs n=0 status
  shift 5
  d=$(mktemp -d); mkdir "$d/bin" "$d/reports"
  while [[ $# -ge 2 ]]; do
    n=$((n + 1)); status=$1
    printf '%s\n' "$2" >"$d/run$n.log"
    if [[ $status == *+sleep* ]]; then echo "${status#*+sleep}" >"$d/run$n.sleep"; status=${status%%+*}; fi
    echo "$status" >"$d/run$n.status"
    shift 2
  done
  cat >"$d/bin/xcodebuild" <<STUB
#!/usr/bin/env bash
n=\$(( \$(cat "$d/runs" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"$d/runs"
printf '%s\n' "\$*" >"$d/args\$n"
cat "$d/run\$n.log" 2>/dev/null
[[ ! -e "$d/run\$n.sleep" ]] || exec sleep "\$(cat "$d/run\$n.sleep")"
exit "\$(cat "$d/run\$n.status" 2>/dev/null || echo 0)"
STUB
  chmod +x "$d/bin/xcodebuild"
  cat >"$d/job.sh" <<JOB
#!/usr/bin/env bash
set -euo pipefail
source "$lib"
prepare() {
  echo x >>"$d/prepares"
  case $prepare in ok) true ;; once) [[ \$(wc -l <"$d/prepares") -gt 1 ]] ;; *) false ;; esac
}
reboot() { :; }
tests=(-only-testing:T/C/testOne -only-testing:T/C/testTwo -only-testing:T/C/testThree)
xcodebuild_args=(-xctestrun x)
result="$d/out.xcresult" job_label="ui-tests 1/3" device_label="iPhone" shard_label="1/3"
run_classified
JOB
  touch "$d/output"
  PATH="$d/bin:$PATH" NOPE_CRASH_REPORTS="$d/reports" GITHUB_STEP_SUMMARY="$d/summary" GITHUB_OUTPUT="$d/output" \
    bash "$d/job.sh" >"$d/out" 2>&1 </dev/null || got_exit=$?
  runs=$(cat "$d/runs" 2>/dev/null || echo 0)
  if [[ $got_exit == "$want_exit" && $runs == "$want_runs" ]] && grep -q -- "$want_text" "$d/summary" \
      && { [[ -z ${CASE_JOB_SECOND_RUN_ARGS:-} ]] || grep -q -- "$CASE_JOB_SECOND_RUN_ARGS" "$d/args2"; } \
      && { [[ -z ${CASE_JOB_NOT_IN_SECOND_RUN:-} ]] || ! grep -q -- "$CASE_JOB_NOT_IN_SECOND_RUN" "$d/args2"; } \
      && { [[ -z ${CASE_JOB_LAST_RUN_ARGS:-} ]] || grep -q -- "$CASE_JOB_LAST_RUN_ARGS" "$d/args$runs"; } \
      && { [[ -z ${CASE_JOB_NOT_IN_LAST_RUN:-} ]] || ! grep -q -- "$CASE_JOB_NOT_IN_LAST_RUN" "$d/args$runs"; } \
      && { [[ -z ${CASE_JOB_RESULTS_TEXT:-} ]] || grep -q -- "$CASE_JOB_RESULTS_TEXT" "$d/out-results.jsonl"; } \
      && { [[ ${CASE_JOB_OUTPUT-unset} == unset ]] || [[ $(cat "$d/output") == "$CASE_JOB_OUTPUT" ]]; }; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $got_exit, $runs run(s)): $(cat "$d/summary" 2>/dev/null) $(cat "$d/args$runs" 2>/dev/null)"
    cat "$d/out-results.jsonl" 2>/dev/null
    failures=$((failures + 1))
  fi
  rm -rf "$d"
}
one="Test Case '-[T.C testOne]' started.
Test Case '-[T.C testOne]' passed (1.0 seconds)."
two="Test Case '-[T.C testTwo]' started.
Test Case '-[T.C testTwo]' passed (1.0 seconds)."
three="Test Case '-[T.C testThree]' started.
Test Case '-[T.C testThree]' passed (1.0 seconds)."
two_failed="Test Case '-[T.C testTwo]' started.
/x/C.swift:12: error: -[T.C testTwo] : XCTAssertTrue failed - the readout isn't there
Test Case '-[T.C testTwo]' failed (1.0 seconds)."
three_failed="Test Case '-[T.C testThree]' started.
/x/C.swift:30: error: -[T.C testThree] : XCTAssertEqual failed
Test Case '-[T.C testThree]' failed (1.0 seconds)."
cut_short="Test Case '-[T.C testTwo]' started.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
case_job "a job whose tests pass" 0 1 "ui-tests 1/3: Passed" ok 0 "$one
$two
$three"
CASE_JOB_OUTPUT="" case_job "a job without a retry sets no step output" 0 1 "Every test passed." ok 0 "$one
$two
$three"
case_job "no test started: the whole job runs once more" 0 2 "ui-tests 1/3: Passed" ok 65 "Testing started
The test runner crashed while preparing to run tests" 0 "$one
$two
$three"
# The Simulator died in the second test and xcodebuild gave up: the first test keeps its result,
# and the test cut short and the test that never started both run again.
CASE_JOB_SECOND_RUN_ARGS="-skip-testing:T/C/testOne" CASE_JOB_NOT_IN_SECOND_RUN="-skip-testing:T/C/testT[hw]" \
  case_job "unfinished and unstarted tests run again, finished ones don't" 0 2 "the 1 test(s) it finished were kept" ok 65 "$one
Test Case '-[T.C testTwo]' started.
	The iOS 27.2 simulator runtime is not available." 0 "$two
$three"
CASE_JOB_RESULTS_TEXT='"retry": "infrastructure"' \
  case_job "the second run's results say it followed an infrastructure failure" 0 2 "Passed" ok 65 "Testing started" 0 "$one
$two
$three"
case_job "an infrastructure failure twice fails the job as one" 1 2 "ui-tests 1/3: Infrastructure failure" ok 65 "Testing started" 65 "Testing started"
case_job "preparing the Simulator fails twice: no test runs" 1 0 "Preparing the Simulator failed twice" fails 0 ""
case_job "preparing the Simulator fails once: it is done again and the tests run" 0 1 "Preparing the Simulator failed once" once 0 "$one
$two
$three"

# A test failure: each failed test runs once more, alone. Failed and then passed is a pass,
# recorded as flaky; failed twice fails the job.
CASE_JOB_LAST_RUN_ARGS="-only-testing:T/C/testTwo -resultBundlePath .*/out-retry-1.xcresult" \
  CASE_JOB_NOT_IN_LAST_RUN="-only-testing:T/C/testOne\|-only-testing:T/C/testThree" \
  case_job "failed, then passed alone: the job passes" 0 2 "ui-tests 1/3: Passed with 1 flaky test(s)" ok 65 "$one
$two_failed
$three" 0 "$two"
case_job "the summary lists the flaky test with its first failure and its retry" 0 2 \
  "C/testTwo. (ui-tests 1/3 on iPhone): first failure: XCTAssertTrue failed - the readout isn't there; passed on the retry (flaky)" ok 65 "$one
$two_failed
$three" 0 "$two"
CASE_JOB_RESULTS_TEXT='"test": "C/testTwo", "result": "passed", "seconds": 1.0, "attempt": 2, .*"retry": "test-failure", "first_failure": "XCTAssertTrue failed - the readout isn.t there"' \
  case_job "the result file records the retry as a test-failure retry" 0 2 "Passed" ok 65 "$one
$two_failed
$three" 0 "$two"
CASE_JOB_RESULTS_TEXT='"test": "C/testTwo", "result": "failed", .*"attempt": 1, .*"message": "XCTAssertTrue failed' \
  case_job "the result file keeps the first failure's message" 0 2 "Passed" ok 65 "$one
$two_failed
$three" 0 "$two"
CASE_JOB_OUTPUT="retried=1" case_job "a retry sets the step output that keeps the result bundles" 0 2 "Passed" ok 65 "$one
$two_failed
$three" 0 "$two"
case_job "failed twice: the job fails" 1 2 "ui-tests 1/3: Test failure" ok 65 "$one
$two_failed
$three" 65 "$two_failed"
case_job "failed twice: the summary says so" 1 2 "C/testTwo. failed on its retry too (failed)" ok 65 "$one
$two_failed
$three" 65 "$two_failed"
case_job "failed twice: the test is listed as failed on its retry" 1 2 "failed on the retry too" ok 65 "$one
$two_failed
$three" 65 "$two_failed"
case_job "two failed tests both pass alone: the job passes with two flaky tests" 0 3 "Passed with 2 flaky test(s)" ok 65 "$one
$two_failed
$three_failed" 0 "$two" 0 "$three"
case_job "a test that fails twice stops the retries" 1 2 "Test failure" ok 65 "$one
$two_failed
$three_failed" 65 "$two_failed"
# A test cut short (the app or the test runner crashed) with no sign of the Simulator dying.
case_job "cut short, then passed alone: the job passes" 0 2 "Passed with 1 flaky test(s)" ok 65 "$one
$cut_short
$three" 0 "$two"
case_job "cut short, and cut short again on the retry: the job fails" 1 2 "failed on its retry too (interrupted)" ok 65 "$one
$cut_short
$three" 65 "$cut_short"
case_job "a retry in which the test never starts: the job fails" 1 2 "failed on its retry too (interrupted)" ok 65 "$one
$two_failed
$three" 65 "Testing started
The test runner crashed while preparing to run tests"
case_job "a retry that passes while a test of the shard never ran: the job fails" 1 2 "these tests have no result: C/testThree" ok 65 "$one
$two_failed" 0 "$two"
case_job "a failed run without a failed test to name: nothing is retried" 1 1 "none was retried" ok 65 "$one
$two
$three"
case_job "a test failure after an infrastructure failure: the failed test is retried too" 0 3 "Passed with 1 flaky test(s)" ok \
  65 "Testing started" 65 "$one
$two_failed
$three" 0 "$two"
# The time limit: a retry runs only when it fits in what is left, and is ended when it doesn't
# finish in it.
NOPE_TEST_TIME_LIMIT_MINUTES=1 NOPE_TEST_TIME_MARGIN_SECONDS=60 \
  case_job "a retry that doesn't fit in the time left isn't run" 1 1 "was not retried: its retry needs about 121 s and 0 s of the 1-minute limit were left" ok 65 "$one
$two_failed
$three"
NOPE_TEST_TIME_LIMIT_MINUTES=1 NOPE_TEST_TIME_MARGIN_SECONDS=55 NOPE_RETRY_STARTUP_SECONDS=0 \
  case_job "a retry that runs past the time left is ended and fails the job" 1 2 "ran past the [0-9]* s left of the 1-minute limit and was ended" ok 65 "$one
$two_failed
$three" "0+sleep30" "Test Case '-[T.C testTwo]' started."
NOPE_TEST_TIME_LIMIT_MINUTES=150 case_job "a retry that fits in the time left runs" 0 2 "Passed with 1 flaky test(s)" ok 65 "$one
$two_failed
$three" 0 "$two"

# The retry candidates are the tests whose last line failed or that have no result, with their target.
log=$(mktemp)
printf '%s\n' "$one" "$two_failed" "Test Case '-[T.C testThree]' started." "Test Case '-[T.D testFour]' started." \
  "Test Case '-[T.D testFour]' failed (1.0 seconds)." "Test Case '-[T.D testFour]' started." "Test Case '-[T.D testFour]' passed (1.0 seconds)." >"$log"
got=$("$lib" --retry-candidates "$log" | tr '\n' ' ')
if [[ $got == "T/C/testTwo T/C/testThree " ]]; then echo "ok   retry candidates"; else echo "FAIL retry candidates: $got"; failures=$((failures + 1)); fi
rm -f "$log"

# The flaky list across result files, as the owner's Mac proof prints it.
d=$(mktemp -d)
printf '%s\n' '{"test": "C/testOne", "result": "passed", "attempt": 1, "job": "ui-tests 1/6", "device": "iPhone 18 Pro"}' \
  '{"test": "C/testTwo", "result": "failed", "attempt": 1, "job": "ui-tests 1/6", "device": "iPhone 18 Pro", "message": "m"}' \
  '{"test": "C/testTwo", "result": "passed", "attempt": 2, "job": "ui-tests 1/6", "device": "iPhone 18 Pro", "retry": "test-failure", "first_failure": "m"}' >"$d/a-results.jsonl"
printf '%s\n' '{"test": "W/testThree", "result": "interrupted", "attempt": 2, "job": "ui-tests-watch", "device": "Watch", "retry": "test-failure", "first_failure": "x"}' >"$d/b-results.jsonl"
got=$("$lib" --flaky "$d/a-results.jsonl" "$d/b-results.jsonl")
# shellcheck disable=SC2016 # the backticks are Markdown
want='- `C/testTwo` (ui-tests 1/6 on iPhone 18 Pro): first failure: m; passed on the retry (flaky)
- `W/testThree` (ui-tests-watch on Watch): first failure: x; interrupted on the retry too'
if [[ $got == "$want" ]]; then echo "ok   flaky list"; else echo "FAIL flaky list: $got"; failures=$((failures + 1)); fi
rm -rf "$d"

# The flaky test report: a test that passed and failed on one commit, tests that did across
# commits, and a test that passed only in the second run after an infrastructure failure.
d=$(mktemp -d); mkdir -p "$d/1/a" "$d/2/a"
row() { # row <test> <result> <attempt> <job> <sha> <run>
  printf '{"test": "%s", "result": "%s", "seconds": 3, "attempt": %s, "job": "%s", "sha": "%s", "run_id": "%s", "run_attempt": "1"}\n' "$@"
}
{ row C/testOne passed 1 "ui-tests 1/3" aaaaaaa1 1; row C/testTwo failed 1 "ui-tests 1/3" aaaaaaa1 1
  row C/testThree interrupted 1 "ui-tests-ipad 1/2" aaaaaaa1 1; row C/testThree passed 2 "ui-tests-ipad 1/2" aaaaaaa1 1
} >"$d/1/a/results.jsonl"
{ row C/testTwo passed 1 "ui-tests 1/3" aaaaaaa1 2; row C/testOne failed 1 "ui-tests 1/3" bbbbbbb2 3; } >"$d/2/a/results.jsonl"
# A test retried after failing, in two runs: it passed on one retry and failed on the other.
retry_row() { # retry_row <result> <run>
  printf '{"test": "C/testFour", "result": "%s", "seconds": 3, "attempt": 2, "job": "ui-tests-watch", "sha": "aaaaaaa1", "run_id": "%s", "run_attempt": "1", "retry": "test-failure", "first_failure": "m"}\n' "$@"
}
{ row C/testFour failed 1 ui-tests-watch aaaaaaa1 1; retry_row passed 1
  row C/testFour failed 1 ui-tests-watch aaaaaaa1 2; retry_row failed 2; } >"$d/1/a/retried.jsonl"
got=$("$here/flaky-tests.sh" --from "$d")
want="7 results of 4 tests from 3 run(s) on 2 commit(s)

Run once more after a test failure (flaky when the retry passed):
  C/testFour (watch): 2 run(s), 1 passed on the retry, 1 failed on the retry too; retried in 2 or more runs: needs an issue

Passed and failed on the same commit:
  C/testTwo (iPhone) at aaaaaaa: 1 passed, 1 failed
  C/testFour (watch) at aaaaaaa: 1 passed, 1 failed

Passed and failed across these commits:
  C/testTwo (iPhone): 1 passed, 1 failed
  C/testOne (iPhone): 1 passed, 1 failed
  C/testFour (watch): 1 passed, 1 failed

Passed only in the second run after an infrastructure failure:
  C/testThree (iPad): 1 time(s)"
if [[ $got == "$want" ]]; then echo "ok   flaky test report"; else echo "FAIL flaky test report: $got"; failures=$((failures + 1)); fi
rm -rf "$d"
got=$("$here/flaky-tests.sh" --from "$(mktemp -d)")
if [[ $got == "No per-test results found." ]]; then echo "ok   flaky test report without results"; else echo "FAIL flaky test report without results: $got"; failures=$((failures + 1)); fi

# The push service is stopped when launchd has it, and a service that stays is reported without
# failing the run. A stand-in for xcrun plays the Simulator's launchctl: the service is loaded
# while the state file exists, and bootout removes the file unless told to refuse.
push="$(cd "$(dirname "$0")" && pwd)/stop-simulator-push.sh"
case_push() { # case_push "name" "loaded|absent" "works|refuses" "expected text"
  local name=$1 d got
  d=$(mktemp -d)
  [[ $2 == loaded ]] && touch "$d/loaded"
  cat >"$d/xcrun" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"launchctl print system/com.apple.apsd") [[ -e "$d/loaded" ]] ;;
  *"launchctl print "*) exit 1 ;;
  *"launchctl bootout system/com.apple.apsd") [[ $3 == refuses ]] || rm -f "$d/loaded" ;;
  *"log show"*) echo "apsd Could not get certificate from simulator" ;;
esac
STUB
  chmod +x "$d/xcrun"
  if got=$(PATH="$d:$PATH" "$push" TEST-DEVICE 2>&1) && grep -q "gave up its connection 1 time" <<<"$got" && grep -q "$4" <<<"$got"; then
    echo "ok   $name"
  else
    echo "FAIL $name: $got"; failures=$((failures + 1))
  fi
  rm -rf "$d"
}
case_push "push service stopped" loaded works "Push service on TEST-DEVICE stopped"
case_push "push service already gone" absent works "Push service on TEST-DEVICE stopped"
case_push "push service that stays is a warning" loaded refuses "::warning::The push service of Simulator TEST-DEVICE is still loaded"

# The background task scheduler is stopped the same way, with the same stand-in.
tasks="$(cd "$(dirname "$0")" && pwd)/stop-simulator-background-tasks.sh"
case_tasks() { # case_tasks "name" "loaded|absent" "works|refuses" "expected text"
  local name=$1 d got
  d=$(mktemp -d)
  [[ $2 == loaded ]] && touch "$d/loaded"
  cat >"$d/xcrun" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"launchctl print system/com.apple.dasd") [[ -e "$d/loaded" ]] ;;
  *"launchctl print "*) exit 1 ;;
  *"launchctl bootout system/com.apple.dasd") [[ $3 == refuses ]] || rm -f "$d/loaded" ;;
esac
STUB
  chmod +x "$d/xcrun"
  if got=$(PATH="$d:$PATH" "$tasks" TEST-DEVICE 2>&1) && grep -q "$4" <<<"$got"; then
    echo "ok   $name"
  else
    echo "FAIL $name: $got"; failures=$((failures + 1))
  fi
  rm -rf "$d"
}
case_tasks "scheduler stopped" loaded works "Background task scheduler on TEST-DEVICE stopped"
case_tasks "scheduler already gone" absent works "Background task scheduler on TEST-DEVICE stopped"
case_tasks "scheduler that stays is a warning" loaded refuses "::warning::The background task scheduler of Simulator TEST-DEVICE is still loaded"

# Before a Simulator is booted: no wait when every runtime is mounted as expected, and a wait
# when one is mounted from a plain disk image that isn't named as always mounted that way. A
# stand-in for xcrun lists the runtimes.
runtimes="$(cd "$(dirname "$0")" && pwd)/wait-for-simulator-runtimes.sh"
case_runtimes() { # case_runtimes "name" "mount path of iOS 27.2" "expected text"
  local name=$1 d got
  d=$(mktemp -d)
  cat >"$d/xcrun" <<STUB
#!/usr/bin/env bash
cat <<JSON
{"A": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2", "build": "24B8117", "mountPath": "$2"},
 "B": {"runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.watchOS-27-0", "build": "24R362",
       "mountPath": "/Library/Developer/CoreSimulator/Volumes/watchOS_24R362"}}
JSON
STUB
  chmod +x "$d/xcrun"
  # A job that first used simctl long ago has nothing left to wait for.
  [[ -z ${CASE_RUNTIMES_FIRST_USE:-} ]] || echo "$CASE_RUNTIMES_FIRST_USE" >"$d/first-use"
  if got=$(PATH="$d:$PATH" SIMULATOR_RUNTIMES_ON_DISK_IMAGES="com.apple.CoreSimulator.SimRuntime.watchOS-27-0" \
      SIMULATOR_RUNTIME_SETTLE_SECONDS=2 SIMULATOR_RUNTIME_POLL_SECONDS=1 SIMULATOR_RUNTIME_FIRST_LOOK_SECONDS=0 \
      SIMULATOR_FIRST_USE_FILE="$d/first-use" \
      "$runtimes" 2>&1) && grep -q "$3" <<<"$got"; then
    echo "ok   $name"
  else
    echo "FAIL $name: $got"; failures=$((failures + 1))
  fi
  rm -rf "$d"
}
case_runtimes "runtimes mounted as expected: no wait" \
  "/private/var/run/com.apple.security.cryptexd/mnt/com.apple.iPhoneOS.SimulatorRuntime-v24.2.8117.0.abc" \
  "Simulator runtimes: mounted as expected"
# The first poll's time is 1 second, or 2 on a busy machine.
case_runtimes "the runtime under test on a plain disk image: wait" \
  "/Library/Developer/CoreSimulator/Volumes/iOS_24B8117" "After [0-9]* seconds: "
case_runtimes "the wait names the runtime" \
  "/Library/Developer/CoreSimulator/Volumes/iOS_24B8117" "iOS-27-2 (24B8117) at /Library/Developer/CoreSimulator/Volumes/iOS_24B8117"
CASE_RUNTIMES_FIRST_USE=1000 case_runtimes "a later call in the job doesn't wait again" \
  "/Library/Developer/CoreSimulator/Volumes/iOS_24B8117" "since the job first used simctl"

# A command that doesn't return is ended, with status 124; one that returns keeps its status.
timeout="$here/with-timeout.sh"
case_timeout() { # case_timeout "name" "want status" <seconds> <command…>
  local name=$1 want=$2 got=0
  shift 2
  "$timeout" "$@" >/dev/null 2>&1 || got=$?
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
}
case_timeout "a command that returns in time" 0 5 true
case_timeout "a command's own failure" 3 5 bash -c 'exit 3'
case_timeout "a command that doesn't return" 124 1 sleep 30
case_timeout "a missing command" 127 5 /no/such/command
started=$SECONDS
"$timeout" 1 sleep 30 >/dev/null 2>&1 || true
if (( SECONDS - started < 10 )); then echo "ok   the time limit ends the command"; else echo "FAIL the time limit ends the command"; failures=$((failures + 1)); fi

# Finding a Simulator boots nothing; preparing one fails, within its limits, when a simctl call
# fails. A stand-in for xcrun lists one watch Simulator and records what it is asked.
prepare="$here/prepare-simulator.sh"
case_prepare() { # case_prepare "name" "want exit" "want output text" "simctl boot: ok|fails" [script args…]
  local name=$1 want=$2 text=$3 boot=$4 d got status=0
  shift 4
  d=$(mktemp -d)
  cat >"$d/xcrun" <<STUB
#!/usr/bin/env bash
echo "\$*" >>"$d/calls"
case "\$*" in
  *"list devices available -j") echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.watchOS-27-2": [{"name": "Watch", "udid": "WATCH-1"}]}}' ;;
  *"list pairs -j") echo '{"pairs": {}}' ;;
  *"runtime list -j") echo '{}' ;;
  *"bootstatus"*) [[ $boot == ok ]] ;;
  *"launchctl print"*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$d/xcrun"
  got=$(PATH="$d:$PATH" SIMULATOR_FIRST_USE_FILE="$d/first-use" SIMULATOR_RUNTIME_FIRST_LOOK_SECONDS=0 \
    "$prepare" "$@" 2>&1) || status=$?
  if [[ $status == "$want" ]] && grep -q "$text" <<<"$got" \
      && { [[ -z ${CASE_PREPARE_NEVER:-} ]] || ! grep -q -- "$CASE_PREPARE_NEVER" "$d/calls"; }; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $status): $got"; failures=$((failures + 1))
  fi
  rm -rf "$d"
}
watch="platform=watchOS Simulator,name=Watch,OS=27.2"
CASE_PREPARE_NEVER="simctl boot" case_prepare "finding a Simulator boots nothing" 0 "udid=WATCH-1" ok --find "$watch"
case_prepare "starting a boot doesn't wait for it" 0 "Booting Watch (WATCH-1)" fails --start "$watch"
case_prepare "preparing boots the Simulator" 0 "Booting Watch (WATCH-1)" ok "$watch"
case_prepare "a Simulator that doesn't finish booting fails the preparation" 1 "Booting Watch" fails "$watch"
case_prepare "a Simulator that isn't there" 1 "no Other Simulator" ok "platform=watchOS Simulator,name=Other,OS=27.2"

# An older runtime is downloaded only when it isn't installed, and a Simulator is created on it
# only when there isn't one. Stand-ins for xcrun and xcodebuild keep the runtime's state in a
# file: the download "installs" it unless told to fail.
add_runtime="$here/add-simulator-runtime.sh"
case_runtime_add() { # case_runtime_add "name" "want exit" "want output text" "installed|missing" "download: works|fails" "device: present|absent"
  local name=$1 want=$2 text=$3 d got status=0
  d=$(mktemp -d)
  [[ $4 == installed ]] && touch "$d/installed"
  [[ $6 == present ]] && touch "$d/device"
  [[ $4 == unanswered ]] && touch "$d/unanswered"
  cat >"$d/xcrun" <<STUB
#!/usr/bin/env bash
echo "\$*" >>"$d/calls"
case "\$*" in
  *"list runtimes -j")
    if [[ -e "$d/unanswered" ]]; then exit 1
    elif [[ -e "$d/installed" ]]; then
      echo '{"runtimes": [{"platform": "iOS", "version": "26.5", "isAvailable": true, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5"}]}'
    else echo '{"runtimes": []}'; fi ;;
  *"list devices available -j")
    if [[ -e "$d/device" ]]; then echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [{"name": "iPhone 17 Pro", "udid": "OLD-1"}]}}'
    else echo '{"devices": {}}'; fi ;;
  *"simctl create"*) touch "$d/device"; echo NEW-1 ;;
esac
STUB
  cat >"$d/xcodebuild" <<STUB
#!/usr/bin/env bash
echo "xcodebuild \$*" >>"$d/calls"
[[ $5 == works ]] && touch "$d/installed"
[[ $5 == works ]]
STUB
  chmod +x "$d/xcrun" "$d/xcodebuild"
  [[ -z ${CASE_RUNTIME_FIRST_USE:-} ]] || echo "$CASE_RUNTIME_FIRST_USE" >"$d/first-use"
  got=$(PATH="$d:$PATH" GITHUB_OUTPUT= SIMULATOR_FIRST_USE_FILE="$d/first-use" \
    "$add_runtime" iOS 26.5 iPhone-17-Pro "iPhone 17 Pro" 2>&1) || status=$?
  # The first use of simctl is noted for the runtime wait, and an earlier note is kept.
  if [[ $status == "$want" ]] && grep -q "$text" <<<"$got" \
      && grep -Eq "^${CASE_RUNTIME_FIRST_USE:-[0-9]+}$" "$d/first-use" \
      && { [[ -z ${CASE_RUNTIME_NEVER:-} ]] || ! grep -q -- "$CASE_RUNTIME_NEVER" "$d/calls"; }; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $status): $got"; failures=$((failures + 1))
  fi
  rm -rf "$d"
}
CASE_RUNTIME_NEVER="downloadPlatform" case_runtime_add "an installed runtime isn't downloaded again" 0 "udid=OLD-1" installed works present
CASE_RUNTIME_NEVER="simctl create" case_runtime_add "an existing Simulator is used" 0 "udid=OLD-1" installed works present
case_runtime_add "a missing runtime is downloaded and a Simulator created" 0 "udid=NEW-1" missing works absent
case_runtime_add "a download that fails twice fails the step" 1 "no iOS 26.5 Simulator runtime" missing fails absent
CASE_RUNTIME_FIRST_USE=1000 case_runtime_add "an earlier first use of simctl is kept" 0 "udid=OLD-1" installed works present
CASE_RUNTIME_NEVER="downloadPlatform" case_runtime_add "a simctl call that fails twice says so and stops" 1 \
  "simctl list runtimes -j failed twice" unanswered works absent
if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all UI test shard tests passed"
