#!/usr/bin/env bash
# Tests for scripts/ui-test-shards.sh, the classification and second-run rules of
# scripts/ui-test-run-lib.sh, scripts/flaky-tests.sh, scripts/stop-simulator-push.sh,
# scripts/stop-simulator-background-tasks.sh and scripts/wait-for-simulator-runtimes.sh: each
# case builds a small tree or log and checks the result.
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
# prepared status for each run: a test failure is never run again, an infrastructure failure is
# run again once without the finished tests, and the summary names the classification.
case_job() { # case_job "name" "want exit" "want runs" "want summary text" "prepare: ok|fails" "run 1 status" "run 1 log" ["run 2 status" "run 2 log"]
  local name=$1 want_exit=$2 want_runs=$3 want_text=$4 prepare=$5 d got_exit=0 runs
  d=$(mktemp -d); mkdir "$d/bin" "$d/reports"
  printf '%s\n' "$7" >"$d/run1.log"; echo "$6" >"$d/run1.status"
  printf '%s\n' "${9:-}" >"$d/run2.log"; echo "${8:-0}" >"$d/run2.status"
  cat >"$d/bin/xcodebuild" <<STUB
#!/usr/bin/env bash
n=\$(( \$(cat "$d/runs" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"$d/runs"
printf '%s\n' "\$*" >"$d/args\$n"
cat "$d/run\$n.log"
exit "\$(cat "$d/run\$n.status")"
STUB
  chmod +x "$d/bin/xcodebuild"
  cat >"$d/job.sh" <<JOB
#!/usr/bin/env bash
set -euo pipefail
source "$lib"
prepare() { [[ $prepare == ok ]]; }
reboot() { :; }
tests=(-only-testing:T/C/testOne -only-testing:T/C/testTwo -only-testing:T/C/testThree)
xcodebuild_args=(-xctestrun x)
result="$d/out.xcresult" job_label="ui-tests 1/3" device_label="iPhone" shard_label="1/3"
run_classified
JOB
  PATH="$d/bin:$PATH" NOPE_CRASH_REPORTS="$d/reports" GITHUB_STEP_SUMMARY="$d/summary" bash "$d/job.sh" >"$d/out" 2>&1 || got_exit=$?
  runs=$(cat "$d/runs" 2>/dev/null || echo 0)
  if [[ $got_exit == "$want_exit" && $runs == "$want_runs" ]] && grep -q "$want_text" "$d/summary" \
      && { [[ -z ${CASE_JOB_SECOND_RUN_ARGS:-} ]] || grep -q -- "$CASE_JOB_SECOND_RUN_ARGS" "$d/args2"; } \
      && { [[ -z ${CASE_JOB_NOT_IN_SECOND_RUN:-} ]] || ! grep -q -- "$CASE_JOB_NOT_IN_SECOND_RUN" "$d/args2"; }; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $got_exit, $runs run(s)): $(cat "$d/summary" 2>/dev/null) $(cat "$d/args2" 2>/dev/null)"; failures=$((failures + 1))
  fi
  rm -rf "$d"
}
one="Test Case '-[T.C testOne]' started.
Test Case '-[T.C testOne]' passed (1.0 seconds)."
two="Test Case '-[T.C testTwo]' started.
Test Case '-[T.C testTwo]' passed (1.0 seconds)."
three="Test Case '-[T.C testThree]' started.
Test Case '-[T.C testThree]' passed (1.0 seconds)."
case_job "a job whose tests pass" 0 1 "ui-tests 1/3: Passed" ok 0 "$one
$two
$three"
case_job "a test failure is not run again" 1 1 "ui-tests 1/3: Test failure" ok 65 "$one
Test Case '-[T.C testTwo]' started.
Test Case '-[T.C testTwo]' failed (1.0 seconds).
$three"
case_job "a failed test is listed in the summary" 1 1 "C/testTwo.: failed" ok 65 "$one
Test Case '-[T.C testTwo]' started.
Test Case '-[T.C testTwo]' failed (1.0 seconds)."
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
case_job "an infrastructure failure twice fails the job as one" 1 2 "ui-tests 1/3: Infrastructure failure" ok 65 "Testing started" 65 "Testing started"
case_job "a test failure in the second run is a test failure" 1 2 "ui-tests 1/3: Test failure" ok 65 "Testing started" 65 "$one
Test Case '-[T.C testTwo]' started.
Test Case '-[T.C testTwo]' failed (1.0 seconds)."
case_job "preparing the Simulator fails twice: no test runs" 1 0 "Preparing the Simulator failed twice" fails 0 ""
case_job "a test cut short without a sign of the Simulator dying is not run again" 1 1 "ui-tests 1/3: Test failure" ok 65 "$one
Test Case '-[T.C testTwo]' started.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
$three"

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
got=$("$here/flaky-tests.sh" --from "$d")
want="5 results of 3 tests from 3 run(s) on 2 commit(s)

Passed and failed on the same commit:
  C/testTwo (iPhone) at aaaaaaa: 1 passed, 1 failed

Passed and failed across these commits:
  C/testTwo (iPhone): 1 passed, 1 failed
  C/testOne (iPhone): 1 passed, 1 failed

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
  if got=$(PATH="$d:$PATH" SIMULATOR_RUNTIMES_ON_DISK_IMAGES="com.apple.CoreSimulator.SimRuntime.watchOS-27-0" \
      SIMULATOR_RUNTIME_SETTLE_SECONDS=2 SIMULATOR_RUNTIME_POLL_SECONDS=1 SIMULATOR_RUNTIME_FIRST_LOOK_SECONDS=0 \
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
case_runtimes "the runtime under test on a plain disk image: wait" \
  "/Library/Developer/CoreSimulator/Volumes/iOS_24B8117" "Simulator runtimes: waited"
case_runtimes "the wait names the runtime" \
  "/Library/Developer/CoreSimulator/Volumes/iOS_24B8117" "iOS-27-2 (24B8117) at /Library/Developer/CoreSimulator/Volumes/iOS_24B8117"

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all UI test shard tests passed"
