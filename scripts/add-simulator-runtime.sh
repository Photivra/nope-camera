#!/usr/bin/env bash
# Makes an older Simulator runtime available, with a Simulator on it, so CI can test the oldest
# supported iOS and watchOS (iOS, iPadOS and watchOS 26; AGENTS.md, "Code") on the Xcode 27
# runner, which has only the 27 runtimes (docs/TESTING.md, "Continuous integration"):
#
#   scripts/add-simulator-runtime.sh <iOS|watchOS> <version> <device type> <device name>
#
# for example `scripts/add-simulator-runtime.sh iOS 26.5 iPhone-17-Pro "iPhone 17 Pro"`.
#
# 1. When no runtime of that platform and version is installed, downloads Apple's with
#    `xcodebuild -downloadPlatform <platform> -buildVersion <version> -architectureVariant arm64`
#    (Xcode's documented way to add a Simulator runtime; the download comes from Apple), once
#    more when the first download fails.
# 2. When no available Simulator of that name runs on the runtime, creates one of the device
#    type (`com.apple.CoreSimulator.SimDeviceType.<device type>`).
#
# It prints the Simulator's identifier ("udid=…") and in a GitHub Actions step writes it to the
# step's outputs. The runtime isn't cached between jobs: at 4 to 9 GB it doesn't fit the
# repository's cache.
set -euo pipefail

usage() { echo "usage: $0 <iOS|watchOS> <version> <device type> <device name>" >&2; exit 2; }
[[ $# -eq 4 ]] || usage
platform=$1 version=$2 device_type=$3 name=$4
[[ $platform =~ ^(iOS|watchOS)$ && $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || usage
scripts=$(cd "$(dirname "$0")" && pwd)
limited() { "$scripts/with-timeout.sh" "$@"; }

# The identifier of the installed runtime of this platform and version, or nothing.
runtime() {
  limited 120 xcrun simctl list runtimes -j | python3 -c '
import json, sys
platform, version = sys.argv[1], sys.argv[2]
for runtime in json.load(sys.stdin)["runtimes"]:
    if runtime.get("platform") == platform and runtime.get("version") == version and runtime.get("isAvailable"):
        print(runtime["identifier"]); sys.exit()
' "$platform" "$version"
}

id=$(runtime)
if [[ -z $id ]]; then
  for attempt in 1 2; do
    echo "Downloading the $platform $version Simulator runtime (attempt $attempt)"
    if limited 2400 xcodebuild -downloadPlatform "$platform" -buildVersion "$version" -architectureVariant arm64; then
      break
    fi
  done
  id=$(runtime)
fi
[[ -n $id ]] || { echo "error: no $platform $version Simulator runtime after the download" >&2; exit 1; }
echo "Runtime: $id"

# The available Simulator of this name on the runtime, or nothing.
device() {
  limited 120 xcrun simctl list devices available -j | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name:
        print(device["udid"]); sys.exit()
' "$name" "$id"
}

udid=$(device)
if [[ -z $udid ]]; then
  udid=$(limited 120 xcrun simctl create "$name" "com.apple.CoreSimulator.SimDeviceType.$device_type" "$id")
  echo "Created $name ($udid) on $id"
fi
echo "udid=$udid"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then echo "udid=$udid" >>"$GITHUB_OUTPUT"; fi
