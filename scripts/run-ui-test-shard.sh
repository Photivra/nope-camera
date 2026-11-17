#!/usr/bin/env bash
# Runs one CI shard of the UI tests (docs/TESTING.md, "UI test shards") from a build made with
# xcodebuild build-for-testing:
#
#   scripts/run-ui-test-shard.sh <shard> <device name> <products dir> <result bundle> [xcodebuild args…]
#
# 1. Finds the Simulator by name and iOS version (SIMULATOR_OS, default 27.2), boots it and waits
#    until it has finished booting (simctl bootstatus -b), so the test runner doesn't start on a
#    Simulator that is still booting, then switches it to dark and back with simctl: when a
#    Simulator's first change of the light or dark setting came from a test, it didn't apply.
# 2. Installs the app and launches it once, so the first test's launch isn't the Simulator's
#    first launch of the app.
# 3. Runs the shard's tests (scripts/ui-test-shards.sh args <shard>) with test-without-building.
# 4. Retries once, after rebooting the Simulator, only when the test runner failed before any
#    test started ("The test runner crashed while preparing to run tests", or it never began
#    executing tests). A run in which any test started is never retried, so a failing test
#    always fails the shard.
#
#   scripts/run-ui-test-shard.sh --is-setup-failure <log>   exit 0 when the log is such a failure
set -euo pipefail

# Whether an xcodebuild log shows the test runner failing before any test started.
is_setup_failure() {
  local log=$1
  grep -qE "Test Case '.*' started" "$log" && return 1
  # "The test runner crashed while preparing to run tests", "… timed out while preparing …", and
  # "Test crashed with signal term while preparing to run tests." (a runner killed during setup).
  grep -qE "while preparing to run tests|Test runner never began executing tests" "$log"
}

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
  xcrun simctl bootstatus "$udid" -b
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
  xcrun simctl install "$udid" "$app"
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

log=$(mktemp)
trap 'rm -f "$log"' EXIT
prepare
status=0
run ${@+"$@"} || status=$?
if [[ $status -ne 0 ]] && is_setup_failure "$log"; then
  echo "::warning::The test runner failed before any test started; rebooting the Simulator and running shard $shard once more."
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  prepare
  status=0
  run ${@+"$@"} || status=$?
fi
exit "$status"
