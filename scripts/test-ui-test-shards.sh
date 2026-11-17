#!/usr/bin/env bash
# Tests for scripts/ui-test-shards.sh, the retry rule of scripts/run-ui-test-shard.sh and
# scripts/stop-simulator-push.sh, scripts/stop-simulator-background-tasks.sh and
# scripts/wait-for-simulator-runtimes.sh: each case builds a small tree and checks pass or fail.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/ui-test-shards.sh"
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

all='# comment
1 FirstUITests/testOne
2 FirstUITests/testTwo

2 SecondUITests/testThree'

case_tree pass "every test in one shard" "$all"
case_tree fail "an empty list" "# no shards yet"
case_tree fail "a test in no shard" "1 FirstUITests/testOne
2 FirstUITests/testTwo"
case_tree fail "a test in two shards" "$all
1 FirstUITests/testTwo"
case_tree fail "a listed test that doesn't exist" "$all
1 FirstUITests/testGone"
case_tree fail "a commented-out test is not a test" "$all
1 FirstUITests/testCommentedOut"
case_tree fail "a test listed under the wrong class" "1 FirstUITests/testOne
2 SecondUITests/testTwo
2 SecondUITests/testThree"
case_tree fail "a gap in the shard numbers" "1 FirstUITests/testOne
3 FirstUITests/testTwo
3 SecondUITests/testThree"
case_tree fail "a bad shard number" "x FirstUITests/testOne
2 FirstUITests/testTwo
2 SecondUITests/testThree"
case_tree pass "arguments of a shard" "$all" args 2
case_tree fail "arguments of a shard that doesn't exist" "$all" args 3

# The workflow's shard matrices and job names must match the number of shards (2 here).
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
case_workflow pass "workflow runs every shard" 'jobs:
  a:
    name: ui-tests ${{ matrix.shard }}/2
    strategy:
      matrix:
        shard: [1, 2]'
case_workflow fail "workflow runs too few shards" 'jobs:
  a:
    name: ui-tests ${{ matrix.shard }}/2
    strategy:
      matrix:
        shard: [1]'
case_workflow fail "workflow job name has the wrong count" 'jobs:
  a:
    name: ui-tests ${{ matrix.shard }}/3
    strategy:
      matrix:
        shard: [1, 2]'

# The arguments name the target, class and test.
d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts"
printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
printf '%s\n' "$all" >"$d/scripts/ui-test-shards.txt"
got=$("$script" args 2 "$d" | tr '\n' ' ')
want="-only-testing:NopeAppUITests/FirstUITests/testTwo -only-testing:NopeAppUITests/SecondUITests/testThree "
if [[ $got == "$want" ]]; then echo "ok   argument text"; else echo "FAIL argument text: $got"; failures=$((failures + 1)); fi
rm -rf "$d"

# The shard runner retries only a test runner that failed before any test started.
runner="$(cd "$(dirname "$0")" && pwd)/run-ui-test-shard.sh"
case_log() { # case_log "want" "name" "log text"
  local want=$1 name=$2 log got
  log=$(mktemp); printf '%s\n' "$3" >"$log"
  if "$runner" --is-setup-failure "$log"; then got=retry; else got=no-retry; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -f "$log"
}
case_log retry "runner crashed while preparing" "Testing started
NopeAppUITests-Runner (11895) encountered an error (The test runner crashed while preparing to run tests: NopeAppUITests-Runner at -[XCTWaiter(StallHandling) handleStalledWait:])"
case_log retry "runner killed while preparing" "Testing started
Testing failed:
	NopeAppUITests-Runner (39493) encountered an error (Test crashed with signal term while preparing to run tests.)"
case_log retry "runner never began executing tests" "Test runner never began executing tests after launching."
case_log no-retry "a test failed" "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started.
error: -[NopeAppUITests.NopeAppUITests testOne] : XCTAssertTrue failed
Test Case '-[NopeAppUITests.NopeAppUITests testOne]' failed (3.0 seconds)."
case_log no-retry "a crash after a test started" "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started.
NopeAppUITests-Runner (1) encountered an error (The test runner crashed while preparing to run tests: x)"
case_log no-retry "a build error" "xcodebuild: error: Unknown build action ''."

# After a Simulator's host process crashed, only the tests that started and have no result are
# run again; a crash report of that process newer than the run's marker is the sign of it.
case_interrupted() { # case_interrupted "name" "log text" "expected arguments, space separated"
  local name=$1 log got
  log=$(mktemp); printf '%s\n' "$2" >"$log"
  got=$("$runner" --interrupted-tests "$log" | tr '\n' ' ')
  if [[ $got == "$3" ]]; then echo "ok   $name"; else echo "FAIL $name: $got"; failures=$((failures + 1)); fi
  rm -f "$log"
}
case_interrupted "a test cut short is run again" "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' started.
Test Case '-[NopeAppUITests.NopeAppUITests testTwo]' passed (3.0 seconds).
Test Case '-[NopeAppUITests.OverlayUITests testThree]' started.
Test Case '-[NopeAppUITests.OverlayUITests testThree]' failed (4.0 seconds)." "-only-testing:NopeAppUITests/NopeAppUITests/testOne "
case_interrupted "tests with a result are not run again" "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started.
Test Case '-[NopeAppUITests.NopeAppUITests testOne]' failed (3.0 seconds)." ""
case_interrupted "the last test cut short is run again" "Test Case '-[NopeAppUITests.NopeAppUITests testOne]' started.
Test Case '-[NopeAppUITests.NopeAppUITests testOne]' passed (3.0 seconds).
Test Case '-[NopeAppUITests.ShortcutUITests testFour]' started." "-only-testing:NopeAppUITests/ShortcutUITests/testFour "

case_host() { # case_host "want" "name" "report file name, or none" "older|newer"
  local want=$1 name=$2 d got
  d=$(mktemp -d); mkdir "$d/reports"
  if [[ $4 == older && $3 != none ]]; then touch "$d/reports/$3"; fi
  touch -t 202601010000 "$d/marker"
  if [[ $4 == older ]]; then touch "$d/marker"; touch -t 202501010000 "$d/reports/"* 2>/dev/null || true; fi
  if [[ $4 == newer && $3 != none ]]; then touch "$d/reports/$3"; fi
  if "$runner" --simulator-host-crashed "$d/reports" "$d/marker"; then got=crashed; else got=no-crash; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}
case_host crashed "a new crash report of the Simulator's host" "SimLaunchHost.arm64-2026-11-17-174107.000.ips" newer
case_host no-crash "a crash report from before the run" "SimLaunchHost.arm64-2026-11-17-174107.000.ips" older
case_host no-crash "another process's crash report" "intelligencetasksd-2026-11-17-175520.ips" newer
case_host no-crash "no crash reports" none newer

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
