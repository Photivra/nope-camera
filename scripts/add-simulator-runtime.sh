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
#
# Its simctl calls are the job's first use of the Simulator, which starts the runner's disk image
# service, so before the first one it notes the time in the file that
# scripts/wait-for-simulator-runtimes.sh counts from (SIMULATOR_FIRST_USE_FILE, the same default),
# unless an earlier step noted it. A simctl call that gives no result within its time limit is
# tried once more, and then ends the script with a message that says so.
set -euo pipefail

usage() { echo "usage: $0 <iOS|watchOS> <version> <device type> <device name>" >&2; exit 2; }
[[ $# -eq 4 ]] || usage
platform=$1 version=$2 device_type=$3 name=$4
[[ $platform =~ ^(iOS|watchOS)$ && $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || usage
scripts=$(cd "$(dirname "$0")" && pwd)
limited() { "$scripts/with-timeout.sh" "$@"; }

# The job's first use of simctl (scripts/wait-for-simulator-runtimes.sh counts from it).
first_use=${SIMULATOR_FIRST_USE_FILE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nope-simulator-first-use}
if ! [[ -s $first_use && $(cat "$first_use") =~ ^[0-9]+$ ]]; then
  date +%s >"$first_use" 2>/dev/null || true
fi

# Runs `xcrun simctl <arguments…>` with a 120-second limit, once more when it fails, and prints
# its output. When both tries fail it says why and returns 1.
simctl_query() {
  local attempt status output
  for attempt in 1 2; do
    status=0
    output=$(limited 120 xcrun simctl "$@") || status=$?
    if (( status == 0 )); then
      printf '%s\n' "$output"
      return 0
    fi
    if (( status == 124 )); then
      echo "simctl $* gave no result within 120 seconds (attempt $attempt)" >&2
    else
      echo "simctl $* failed with status $status (attempt $attempt)" >&2
    fi
  done
  echo "error: simctl $* failed twice; the Simulator service may not have started on this runner" >&2
  return 1
}

# The identifier of the installed runtime of this platform and version, or nothing.
runtime() {
  local list
  list=$(simctl_query list runtimes -j) || return 1
  python3 -c '
import json, sys
platform, version = sys.argv[1], sys.argv[2]
for runtime in json.load(sys.stdin)["runtimes"]:
    if runtime.get("platform") == platform and runtime.get("version") == version and runtime.get("isAvailable"):
        print(runtime["identifier"]); sys.exit()
' "$platform" "$version" <<<"$list"
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
  local list
  list=$(simctl_query list devices available -j) || return 1
  python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name:
        print(device["udid"]); sys.exit()
' "$name" "$id" <<<"$list"
}

udid=$(device)
if [[ -z $udid ]]; then
  udid=$(simctl_query create "$name" "com.apple.CoreSimulator.SimDeviceType.$device_type" "$id")
  echo "Created $name ($udid) on $id"
fi
echo "udid=$udid"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then echo "udid=$udid" >>"$GITHUB_OUTPUT"; fi
