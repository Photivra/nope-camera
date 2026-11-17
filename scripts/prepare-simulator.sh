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
echo "Booting $name ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
[[ -n $app ]] || exit 0
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
echo "Installing and launching $bundle_id once"
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" "$bundle_id" ${@+"$@"} >/dev/null || true
sleep 5
xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
