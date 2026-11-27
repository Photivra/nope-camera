#!/usr/bin/env bash
# Runs one CI shard of the UI tests (docs/TESTING.md, "UI test shards") from a build made with
# xcodebuild build-for-testing:
#
#   scripts/run-ui-test-shard.sh <shard> <device name> <products dir> <result bundle> [xcodebuild args…]
#
# The shard is the iPad shard when the device name contains "iPad", the iPhone shard otherwise
# (scripts/ui-test-shards.txt lists both for every test).
#
# 0. On a runner that mounted a Simulator runtime from a plain disk image, waits until the
#    runner has remounted it (scripts/wait-for-simulator-runtimes.sh).
# 1. Finds the Simulator by name and iOS version (SIMULATOR_OS, default 27.2), boots it and waits
#    until it has finished booting (simctl bootstatus -b), so the test runner doesn't start on a
#    Simulator that is still booting, stops its background task scheduler
#    (scripts/stop-simulator-background-tasks.sh) and its push service
#    (scripts/stop-simulator-push.sh), then switches it to dark and back with simctl: when a
#    Simulator's first change of the light or dark setting came from a test, it didn't apply.
# 2. Installs the app and launches it once, so the first test's launch isn't the Simulator's
#    first launch of the app.
# 3. Runs the shard's tests (scripts/ui-test-shards.sh args <device> <shard>) with
#    test-without-building.
# 4. Classifies a failed run (scripts/ui-test-run-lib.sh). An infrastructure failure (preparing
#    the Simulator failed, no test started, or the Simulator died under the tests) is run again
#    once, after rebooting the Simulator, and only the tests without a result: tests that passed
#    keep their result. The first run's result bundle is kept as <result>-interrupted.xcresult.
#    A test failure (a test failed with a result, or was cut short) runs each such test once
#    more, alone, with its own result bundle <result>-retry-<n>.xcresult; the shard passes when
#    each passed on its retry, and they are recorded as flaky. A test that fails twice fails the
#    shard. With NOPE_TEST_TIME_LIMIT_MINUTES set, a retry that doesn't fit in the time left
#    isn't run, and the shard fails with a message.
# 5. Writes the classification and the retried tests to the job summary and the per-test
#    results to <result>-results.jsonl (docs/TESTING.md, "Flaky tests").
set -euo pipefail

[[ $# -ge 4 ]] || { echo "usage: $0 <shard> <device name> <products dir> <result bundle> [xcodebuild args…]" >&2; exit 2; }
shard=$1 device=$2 products=$3 result=$4
shift 4
os=${SIMULATOR_OS:-27.2}
scripts=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/ui-test-run-lib.sh
source "$scripts/ui-test-run-lib.sh"
# Runs a command with a time limit in seconds: a simctl call that never returns must not use up
# the job (scripts/with-timeout.sh).
limited() { "$scripts/with-timeout.sh" "$@"; }

kind=iphone
[[ $device == *iPad* ]] && kind=ipad

tests=()
while IFS= read -r arg; do
  [[ -n $arg ]] && tests+=("$arg")
done < <("$scripts/ui-test-shards.sh" args "$kind" "$shard")
[[ ${#tests[@]} -gt 0 ]] || { echo "error: $kind shard $shard has no tests" >&2; exit 1; }
total=$("$scripts/ui-test-shards.sh" count "$kind")

xctestrun=$(find "$products" -maxdepth 1 -name '*.xctestrun' | head -1)
app=$(find "$products" -maxdepth 2 -path '*-iphonesimulator/*.app' ! -name '*-Runner.app' | head -1)
[[ -n $xctestrun && -n $app ]] || { echo "error: no .xctestrun or app in $products" >&2; exit 1; }
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")

# Before anything is booted: on a runner that mounted a runtime from a plain disk image, wait
# until it has remounted it (scripts/wait-for-simulator-runtimes.sh).
"$scripts/wait-for-simulator-runtimes.sh"

runtime_prefix="com.apple.CoreSimulator.SimRuntime.iOS-${os//./-}"
udid=$(limited 120 xcrun simctl list devices available -j | python3 -c '
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
  local status=0
  limited 180 xcrun simctl boot "$udid" 2>/dev/null || status=$?
  [[ $status -ne 124 ]] || { echo "error: booting $device didn't return" >&2; return 1; }
  limited 600 xcrun simctl bootstatus "$udid" -b || return 1
  # The Simulator's scheduler starts first-boot background tasks a few minutes after boot, and
  # the runner stalls while they run; no test needs it. It is stopped first, before they start.
  limited 180 "$scripts/stop-simulator-background-tasks.sh" "$udid" || return 1
  # The Simulator's push service reconnects without a pause on the runner; no test needs it.
  limited 300 "$scripts/stop-simulator-push.sh" "$udid" || return 1
  # The first change of a Simulator's light or dark setting must come from simctl: when the
  # first one came from a test (XCUIDevice.appearance), the setting stayed light for every app,
  # the system's Settings included, until the Simulator booted again, and the appearance tests
  # failed. Switching to dark and back here makes the tests' changes apply.
  echo "Switching $device to dark and back, so the tests' light and dark changes apply"
  local style
  for style in dark light; do
    limited 60 xcrun simctl ui "$udid" appearance "$style" || return 1
    if [[ $(limited 60 xcrun simctl ui "$udid" appearance) != "$style" ]]; then
      echo "error: $device didn't switch to $style" >&2
      return 1
    fi
  done
  echo "Installing and launching $bundle_id once"
  limited 300 xcrun simctl install "$udid" "$app" || return 1
  limited 120 xcrun simctl launch "$udid" "$bundle_id" -NopeSimulatedCamera allow >/dev/null || true
  sleep 5
  limited 60 xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
}

# Shuts the Simulator down and waits, up to five minutes, until simctl lists it as available
# again: while the runner remounts the runtime's disk image, booting fails at once with "The
# iOS 27.2 simulator runtime is not available" (iPhone shard 8 of build 44149517211).
reboot() {
  limited 120 xcrun simctl shutdown "$udid" 2>/dev/null || true
  local waited=0
  until limited 60 xcrun simctl list devices available 2>/dev/null | grep -q "$udid"; do
    (( waited >= 300 )) && return 0
    sleep 10
    waited=$(( waited + 10 ))
  done
}

if [[ $kind == ipad ]]; then job_label="ui-tests-ipad $shard/$total"; else job_label="ui-tests $shard/$total"; fi
device_label=$device shard_label="$shard/$total"
xcodebuild_args=(-xctestrun "$xctestrun" -destination "id=$udid" ${@+"$@"})
run_classified
