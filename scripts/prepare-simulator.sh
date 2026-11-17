#!/usr/bin/env bash
# Boots a Simulator and launches an app on it once, before UI tests run on it:
#
#   scripts/prepare-simulator.sh "<xcodebuild destination>" [<app> [launch arguments…]]
#
# Without an app it only finds and boots the Simulator. It prints the Simulator's identifier
# ("udid=…"), and in a GitHub Actions step writes it to the step's outputs, so later steps can
# name the device by identifier: a watch Simulator's name also matches the iPhone it is paired
# with, and xcodebuild build-for-testing refused the name ("multiple devices matched").
#
# for example "platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.2". The first
# launch of an app on a Simulator that has just booted can take longer than XCTest waits for a
# launch, so the first test failed to launch the app and the next one failed to terminate it
# (the watch UI tests); after this, the tests' launches aren't the first. The iPhone and iPad
# shards do the same in scripts/run-ui-test-shard.sh.
#
# A watch Simulator's paired iPhone Simulator is booted too, and waited for: xcodebuild boots
# it for a watch test run if it isn't running, and in build 44075379089 it did so while the
# first watch test waited for its launch, which xcodebuild started two minutes later, past
# XCTest's limit ("Timed out while launching application via Xcode").
#
# The push service of each Simulator it boots is stopped (scripts/stop-simulator-push.sh).
set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: $0 <destination> [<app> [launch arguments…]]" >&2; exit 2; }
destination=$1 app=${2:-}
shift $(( $# >= 2 ? 2 : 1 ))
[[ -z $app || -d $app ]] || { echo "error: $app not found" >&2; exit 1; }

field() { sed -nE "s/.*(^|,)$1=([^,]*).*/\2/p" <<<"$destination"; }
name=$(field name)
os=$(field OS)
platform=$(field platform | sed -E 's/ Simulator$//')
[[ -n $name && -n $os && -n $platform ]] || { echo "error: the destination needs platform, name and OS" >&2; exit 2; }
runtime_prefix="com.apple.CoreSimulator.SimRuntime.${platform}-${os//./-}"

udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name, prefix = sys.argv[1], sys.argv[2]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if runtime == prefix or runtime.startswith(prefix + "-"):
        for device in devices:
            if device["name"] == name:
                print(device["udid"]); sys.exit()
' "$name" "$runtime_prefix")
[[ -n $udid ]] || { echo "error: no $name Simulator with $platform $os" >&2; exit 1; }

echo "udid=$udid"
[[ -z ${GITHUB_OUTPUT:-} ]] || echo "udid=$udid" >> "$GITHUB_OUTPUT"

# The iPhone Simulator paired with a watch Simulator, or nothing.
phone=$(xcrun simctl list pairs -j | python3 -c '
import json, sys
for pair in json.load(sys.stdin)["pairs"].values():
    if pair["watch"]["udid"] == sys.argv[1]:
        print(pair["phone"]["udid"]); sys.exit()
' "$udid")

# Both start booting before either is waited for, so they boot side by side.
echo "Booting $name ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true
if [[ -n $phone ]]; then
  echo "Booting the paired iPhone Simulator ($phone)"
  xcrun simctl boot "$phone" 2>/dev/null || true
fi
scripts=$(cd "$(dirname "$0")" && pwd)
for device in "$udid" $phone; do
  xcrun simctl bootstatus "$device" -b
  "$scripts/stop-simulator-push.sh" "$device"
done
[[ -n $app ]] || exit 0

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
echo "Installing and launching $bundle_id once"
xcrun simctl install "$udid" "$app"
# The launch must succeed: a failed one leaves the tests' first launch as the first after all.
launched=
for attempt in 1 2 3; do
  if xcrun simctl launch "$udid" "$bundle_id" ${@+"$@"}; then
    launched=1
    break
  fi
  echo "Launch $attempt of $bundle_id failed"
  sleep 10
done
[[ -n $launched ]] || { echo "error: $bundle_id didn't launch on $name" >&2; exit 1; }
sleep 5
xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
