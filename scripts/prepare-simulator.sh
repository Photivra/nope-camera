#!/usr/bin/env bash
# Boots a Simulator and launches an app on it once, before UI tests run on it:
#
#   scripts/prepare-simulator.sh --find "<xcodebuild destination>"
#   scripts/prepare-simulator.sh --start "<xcodebuild destination>"
#   scripts/prepare-simulator.sh "<xcodebuild destination>" [<app> [launch arguments…]]
#
# With --find it only looks the Simulator up, boots nothing, prints its identifier ("udid=…")
# and in a GitHub Actions step writes it to the step's outputs, so later steps can name the
# device by identifier: a watch Simulator's name also matches the iPhone it is paired with, and
# xcodebuild build-for-testing refused the name ("multiple devices matched").
#
# With --start it also starts booting the Simulator (and a watch's paired iPhone) without
# waiting for the boot to finish and without failing when that doesn't work, so a later step
# finds them booting or booted: the watch job builds meanwhile.
#
# Without either it boots the Simulator (for example "platform=watchOS Simulator,name=Apple
# Watch Series 12 (46mm),OS=27.2") and, given an app, installs it and launches it once. The
# first launch of an app on a Simulator that has just booted can take longer than XCTest waits
# for a launch, so the first test failed to launch the app and the next one failed to
# terminate it (the watch UI tests); after this, the tests' launches aren't the first. The
# iPhone and iPad shards do the same in scripts/run-ui-test-shard.sh.
#
# A watch Simulator's paired iPhone Simulator is booted too, and waited for: xcodebuild boots
# it for a watch test run if it isn't running, and in build 44075379089 it did so while the
# first watch test waited for its launch, which xcodebuild started two minutes later, past
# XCTest's limit ("Timed out while launching application via Xcode").
#
# Before anything is booted it waits for a runtime the runner has to remount
# (scripts/wait-for-simulator-runtimes.sh). The background task scheduler and the push service
# of each Simulator it boots are stopped (scripts/stop-simulator-background-tasks.sh,
# scripts/stop-simulator-push.sh).
#
# Every step has a time limit (scripts/with-timeout.sh), and the script exits non-zero when a
# step fails or runs out of time, so the caller can treat that as an infrastructure failure
# and prepare once more: in build 44222358365 the watch job's boot step never returned and the
# job ran to its limit (docs/TESTING.md, "Preparing the Simulator has a time limit").
set -euo pipefail

find_only= start_only=
if [[ ${1:-} == --find ]]; then find_only=1; shift; fi
if [[ ${1:-} == --start ]]; then start_only=1; shift; fi
[[ $# -ge 1 ]] || { echo "usage: $0 [--find|--start] <destination> [<app> [launch arguments…]]" >&2; exit 2; }
destination=$1 app=${2:-}
shift $(( $# >= 2 ? 2 : 1 ))
scripts=$(cd "$(dirname "$0")" && pwd)
# Runs a command with a time limit in seconds.
limited() { "$scripts/with-timeout.sh" "$@"; }
[[ -z $app || -d $app ]] || { echo "error: $app not found" >&2; exit 1; }

field() { sed -nE "s/.*(^|,)$1=([^,]*).*/\2/p" <<<"$destination"; }
name=$(field name)
os=$(field OS)
platform=$(field platform | sed -E 's/ Simulator$//')
[[ -n $name && -n $os && -n $platform ]] || { echo "error: the destination needs platform, name and OS" >&2; exit 2; }
runtime_prefix="com.apple.CoreSimulator.SimRuntime.${platform}-${os//./-}"

# Before anything is booted (scripts/wait-for-simulator-runtimes.sh).
[[ -n $find_only ]] || "$scripts/wait-for-simulator-runtimes.sh"

udid=$(limited 120 xcrun simctl list devices available -j | python3 -c '
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
[[ -z $find_only ]] || exit 0

# The iPhone Simulator paired with a watch Simulator, or nothing.
phone=$(limited 120 xcrun simctl list pairs -j | python3 -c '
import json, sys
for pair in json.load(sys.stdin)["pairs"].values():
    if pair["watch"]["udid"] == sys.argv[1]:
        print(pair["phone"]["udid"]); sys.exit()
' "$udid")

# Both start booting before either is waited for, so they boot side by side. A boot that fails
# because the Simulator is already booted is fine; one that runs out of time is not.
boot() { # boot <identifier>
  local status=0
  limited 180 xcrun simctl boot "$1" 2>/dev/null || status=$?
  [[ $status -ne 124 || -n $start_only ]] || { echo "error: booting $1 didn't return" >&2; exit 1; }
}
echo "Booting $name ($udid)"
boot "$udid"
if [[ -n $phone ]]; then
  echo "Booting the paired iPhone Simulator ($phone)"
  boot "$phone"
fi
[[ -z $start_only ]] || exit 0
for device in "$udid" $phone; do
  limited 600 xcrun simctl bootstatus "$device" -b
  limited 180 "$scripts/stop-simulator-background-tasks.sh" "$device"
  limited 300 "$scripts/stop-simulator-push.sh" "$device"
done
[[ -n $app ]] || exit 0

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
echo "Installing and launching $bundle_id once"
# The install is tried three times: right after a watch and its iPhone booted, the pairing
# service removed the watch app while it was being installed ("Client appconduitd … requested
# uninstall", seen on a Mac), and the next install went through.
installed=
for attempt in 1 2 3; do
  if limited 300 xcrun simctl install "$udid" "$app"; then
    installed=1
    break
  fi
  echo "Install $attempt of $bundle_id failed"
  sleep 15
done
[[ -n $installed ]] || { echo "error: $bundle_id couldn't be installed on $name" >&2; exit 1; }
# The launch must succeed: a failed one leaves the tests' first launch as the first after all.
launched=
for attempt in 1 2 3; do
  if limited 120 xcrun simctl launch "$udid" "$bundle_id" ${@+"$@"}; then
    launched=1
    break
  fi
  echo "Launch $attempt of $bundle_id failed"
  sleep 10
done
[[ -n $launched ]] || { echo "error: $bundle_id didn't launch on $name" >&2; exit 1; }
sleep 5
limited 60 xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
