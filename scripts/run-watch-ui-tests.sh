#!/usr/bin/env bash
# Runs the Apple Watch app's UI tests in CI from a build made with xcodebuild build-for-testing:
#
#   scripts/run-watch-ui-tests.sh "<xcodebuild destination>" <derived data dir> <result bundle>
#
# It boots the watch Simulator and its paired iPhone and launches the watch app once
# (scripts/prepare-simulator.sh), runs the NopeWatch scheme's tests with test-without-building,
# and handles a failed run as the iPhone and iPad shards do (scripts/ui-test-run-lib.sh): a
# test failure is never run again; an infrastructure failure is run again once, without the
# tests that already passed. It writes the classification to the job summary and the per-test
# results to <result>-results.jsonl.
set -euo pipefail

[[ $# -eq 3 ]] || { echo "usage: $0 <destination> <derived data dir> <result bundle>" >&2; exit 2; }
destination=$1 derived=$2 result=$3
scripts=$(cd "$(dirname "$0")" && pwd)
set --
# shellcheck source=scripts/ui-test-run-lib.sh
source "$scripts/ui-test-run-lib.sh"

app="$derived/Build/Products/Debug-watchsimulator/NopeWatch.app"
[[ -d $app ]] || { echo "error: $app not found" >&2; exit 1; }

udid=
prepare() {
  local output
  output=$("$scripts/prepare-simulator.sh" "$destination" "$app" -NopeSimulatedPhone ready) || { echo "$output"; return 1; }
  echo "$output"
  udid=$(sed -n 's/^udid=//p' <<<"$output" | head -1)
  [[ -n $udid ]] || return 1
  xcodebuild_args=(
    -project App/NopeCamera.xcodeproj -scheme NopeWatch -destination "id=$udid"
    -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO)
}

# The watch and its paired iPhone both boot again in prepare.
reboot() {
  xcrun simctl shutdown all 2>/dev/null || true
}

tests=()
xcodebuild_args=()
job_label="ui-tests-watch" device_label=$(sed -nE 's/.*(^|,)name=([^,]*).*/\2/p' <<<"$destination") shard_label="1/1"
run_classified
