#!/usr/bin/env bash
# Runs one CI shard of the UI tests (docs/TESTING.md, "UI test shards") from a build made with
# xcodebuild build-for-testing:
#
#   scripts/run-ui-test-shard.sh <shard> <device name> <products dir> <result bundle> [xcodebuild args…]
#
# 1. Finds the Simulator by name and iOS version (SIMULATOR_OS, default 27.2), boots it and waits
#    until it has finished booting (simctl bootstatus -b), so the test runner doesn't start on a
#    Simulator that is still booting, stops its background task scheduler
#    (scripts/stop-simulator-background-tasks.sh) and its push service
#    (scripts/stop-simulator-push.sh), then switches it to dark and back with simctl: when a Simulator's first change of the light
#    or dark setting came from a test, it didn't apply.
# 2. Installs the app and launches it once, so the first test's launch isn't the Simulator's
#    first launch of the app.
# 3. Runs the shard's tests (scripts/ui-test-shards.sh args <shard>) with test-without-building.
# 4. Retries once, after rebooting the Simulator, only when the test runner failed before any
#    test started ("The test runner crashed while preparing to run tests", or it never began
#    executing tests), or when installing the app in step 2 failed. A run in which any test
#    started is never retried, so a failing test always fails the shard.
# 5. One exception, for a Simulator that died under the tests: when the Simulator's host
#    process (SimLaunchHost) crashed during the run, the tests it cut short (started, with no
#    result) are run once more after rebooting the Simulator. Tests that passed or failed keep
#    their result, and the first run's result bundle is kept as <result>-interrupted.xcresult
#    (docs/TESTING.md, "A Simulator that dies on the runner").
#
#   scripts/run-ui-test-shard.sh --is-setup-failure <log>   exit 0 when the log is such a failure
#   scripts/run-ui-test-shard.sh --interrupted-tests <log>  the -only-testing arguments of the
#                                                           tests that started and have no result
#   scripts/run-ui-test-shard.sh --simulator-host-crashed <reports dir> <marker file>
#                                                           exit 0 when the directory has a
#                                                           SimLaunchHost crash report newer
#                                                           than the marker
set -euo pipefail

# Whether an xcodebuild log shows the test runner failing before any test started.
is_setup_failure() {
  local log=$1
  grep -qE "Test Case '.*' started" "$log" && return 1
  # "The test runner crashed while preparing to run tests", "… timed out while preparing …", and
  # "Test crashed with signal term while preparing to run tests." (a runner killed during setup).
  grep -qE "while preparing to run tests|Test runner never began executing tests" "$log"
}

# The -only-testing arguments of the tests an xcodebuild log shows as started without a result
# line (passed or failed): the tests a dying Simulator cut short.
interrupted_tests() {
  awk -F"'" '
    /^Test Case .* started\.$/ { started[$2] = 1; order[++n] = $2 }
    /^Test Case .* (passed|failed) \(/ { done[$2] = 1 }
    END {
      for (i = 1; i <= n; i++) {
        name = order[i]
        if (done[name] || printed[name]++) continue
        # "-[Target.Class test]" becomes Target/Class/test.
        gsub(/^-\[|\]$/, "", name); sub(/\./, "/", name); sub(/ /, "/", name)
        print "-only-testing:" name
      }
    }' "$1"
}

# Whether the Simulator's host process left a crash report newer than the marker file. Every
# booted Simulator runs under SimLaunchHost, so its crash ends them all.
simulator_host_crashed() {
  [[ -d $1 ]] && [[ -n $(find "$1" -maxdepth 1 -name 'SimLaunchHost*.ips' -newer "$2" 2>/dev/null | head -1) ]]
}

if [[ ${1:-} == --interrupted-tests ]]; then
  [[ -f ${2:-} ]] || { echo "usage: $0 --interrupted-tests <log>" >&2; exit 2; }
  interrupted_tests "$2"
  exit
fi

if [[ ${1:-} == --simulator-host-crashed ]]; then
  [[ $# -eq 3 && -f $3 ]] || { echo "usage: $0 --simulator-host-crashed <reports dir> <marker file>" >&2; exit 2; }
  simulator_host_crashed "$2" "$3"
  exit
fi

if [[ ${1:-} == --is-setup-failure ]]; then
  [[ -f ${2:-} ]] || { echo "usage: $0 --is-setup-failure <log>" >&2; exit 2; }
  is_setup_failure "$2"
  exit
fi

[[ $# -ge 4 ]] || { echo "usage: $0 <shard> <device name> <products dir> <result bundle> [xcodebuild args…]" >&2; exit 2; }
shard=$1 device=$2 products=$3 result=$4
shift 4
os=${SIMULATOR_OS:-27.2}

tests=()
while IFS= read -r arg; do
  [[ -n $arg ]] && tests+=("$arg")
done < <(scripts/ui-test-shards.sh args "$shard")
[[ ${#tests[@]} -gt 0 ]] || { echo "error: shard $shard has no tests" >&2; exit 1; }

xctestrun=$(find "$products" -maxdepth 1 -name '*.xctestrun' | head -1)
app=$(find "$products" -maxdepth 2 -path '*-iphonesimulator/*.app' ! -name '*-Runner.app' | head -1)
[[ -n $xctestrun && -n $app ]] || { echo "error: no .xctestrun or app in $products" >&2; exit 1; }
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")

runtime_prefix="com.apple.CoreSimulator.SimRuntime.iOS-${os//./-}"
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name, prefix = sys.argv[1], sys.argv[2]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if runtime == prefix or runtime.startswith(prefix + "-"):
        for device in devices:
            if device["name"] == name:
                print(device["udid"]); sys.exit()
' "$device" "$runtime_prefix")
[[ -n $udid ]] || { echo "error: no $device Simulator with iOS $os" >&2; exit 1; }

prepare() {
  echo "Booting $device ($udid)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b || return 1
  # The Simulator's scheduler starts first-boot background tasks a few minutes after boot, and
  # the runner stalls while they run; no test needs it. It is stopped first, before they start.
  "$(dirname "$0")/stop-simulator-background-tasks.sh" "$udid"
  # The Simulator's push service reconnects without a pause on the runner; no test needs it.
  "$(dirname "$0")/stop-simulator-push.sh" "$udid"
  # The first change of a Simulator's light or dark setting must come from simctl: when the
  # first one came from a test (XCUIDevice.appearance), the setting stayed light for every app,
  # the system's Settings included, until the Simulator booted again, and the appearance tests
  # failed. Switching to dark and back here makes the tests' changes apply.
  echo "Switching $device to dark and back, so the tests' light and dark changes apply"
  local style
  for style in dark light; do
    xcrun simctl ui "$udid" appearance "$style"
    if [[ $(xcrun simctl ui "$udid" appearance) != "$style" ]]; then
      echo "error: $device didn't switch to $style" >&2
      exit 1
    fi
  done
  echo "Installing and launching $bundle_id once"
  xcrun simctl install "$udid" "$app" || return 1
  xcrun simctl launch "$udid" "$bundle_id" -NopeSimulatedCamera allow >/dev/null || true
  sleep 5
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
}

run() {
  rm -rf "$result"
  set +e
  xcodebuild test-without-building -xctestrun "$xctestrun" -destination "id=$udid" \
    "${tests[@]}" ${@+"$@"} -resultBundlePath "$result" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

# Prepares the Simulator, once more after rebooting it when booting or installing failed: in
# build 44124454610 the install on one iPad shard ended with "Mach error -308 (ipc/mig) server
# died" before any test ran.
prepare_with_retry() {
  if ! prepare; then
    echo "::warning::Preparing the Simulator failed; rebooting it and preparing once more."
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    prepare || { echo "error: the Simulator couldn't be prepared" >&2; exit 1; }
  fi
}

log=$(mktemp)
marker=$(mktemp)
trap 'rm -f "$log" "$marker"' EXIT
reports=${NOPE_CRASH_REPORTS:-$HOME/Library/Logs/DiagnosticReports}
prepare_with_retry
status=0
run ${@+"$@"} || status=$?
if [[ $status -ne 0 ]] && is_setup_failure "$log"; then
  echo "::warning::The test runner failed before any test started; rebooting the Simulator and running shard $shard once more."
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  prepare_with_retry
  status=0
  run ${@+"$@"} || status=$?
elif [[ $status -ne 0 ]] && simulator_host_crashed "$reports" "$marker"; then
  interrupted=()
  while IFS= read -r arg; do
    [[ -n $arg ]] && interrupted+=("$arg")
  done < <(interrupted_tests "$log")
  if [[ ${#interrupted[@]} -gt 0 ]]; then
    echo "::warning::The Simulator's host process crashed during the tests; rebooting the Simulator and running the ${#interrupted[@]} test(s) it cut short once more: ${interrupted[*]}"
    # A test that failed with a result in the first run still fails the shard.
    failed_before=0
    grep -qE "^Test Case '.*' failed \(" "$log" && failed_before=1
    rm -rf "${result%.xcresult}-interrupted.xcresult"
    mv "$result" "${result%.xcresult}-interrupted.xcresult" 2>/dev/null || true
    tests=("${interrupted[@]}")
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    prepare_with_retry
    status=0
    run ${@+"$@"} || status=$?
    [[ $failed_before -eq 0 ]] || status=1
  fi
fi
exit "$status"
