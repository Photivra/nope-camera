#!/usr/bin/env bash
# Waits, before a Simulator is booted, until the runner has finished remounting its Simulator
# runtime disk images:
#
#   scripts/wait-for-simulator-runtimes.sh
#
# On the GitHub macOS runner the Simulator's disk image service mounts each runtime when the
# job first uses the Simulator. On some runners a mount fails at that moment ("Disk image
# operation failed with error code 153") and the runtime is mounted from a plain disk image
# under /Library/Developer/CoreSimulator/Volumes instead. Minutes later the service mounts it
# again the usual way and unmounts the first mount, also when a Simulator is running on it: in
# builds 44124454610 and 44149517211 that ended the Simulator's host process (SimLaunchHost)
# and every booted Simulator with it, and once left the iOS runtime under test unavailable
# (docs/TESTING.md, "Simulator runtime disk images on the runner"). In the 14 result bundles we
# have, the last such unmount came 716 seconds after the service started, and the two jobs with
# a runtime mounted this way at the start were the two whose host process crashed.
#
# So: when a runtime is mounted under that directory, other than the ones named in
# SIMULATOR_RUNTIMES_ON_DISK_IMAGES (runtime identifiers, space separated: the runtimes the
# runner image mounts that way in every job), this waits until SIMULATOR_RUNTIME_SETTLE_SECONDS
# (default 750) have passed since the job first used simctl, while nothing is booted. Otherwise
# it returns at once. The first call in a job notes the time in a file (SIMULATOR_FIRST_USE_FILE,
# by default in the runner's temporary directory), so a later call, before a second attempt to
# prepare the Simulator, waits only for what is left. Call it before the job's first use of
# simctl, since the service starts then. Its own simctl call has a time limit.
set -euo pipefail

settle=${SIMULATOR_RUNTIME_SETTLE_SECONDS:-750}
poll=${SIMULATOR_RUNTIME_POLL_SECONDS:-30}
expected=${SIMULATOR_RUNTIMES_ON_DISK_IMAGES:-}
scripts=$(cd "$(dirname "$0")" && pwd)
first_use=${SIMULATOR_FIRST_USE_FILE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nope-simulator-first-use}
now() { date +%s; }
if [[ -s $first_use && $(cat "$first_use") =~ ^[0-9]+$ ]]; then
  started=$(cat "$first_use")
else
  started=$(now)
  echo "$started" >"$first_use" 2>/dev/null || true
fi

# The runtimes mounted from a plain disk image that aren't expected to be, one per line.
unsettled() {
  "$scripts/with-timeout.sh" 120 xcrun simctl runtime list -j 2>/dev/null | python3 -c '
import json, sys
expected = set(sys.argv[1].split())
try:
    images = json.load(sys.stdin)
except ValueError:
    sys.exit()
for image in images.values():
    mount = image.get("mountPath") or ""
    runtime = image.get("runtimeIdentifier") or ""
    if mount.startswith("/Library/Developer/CoreSimulator/Volumes/") and runtime not in expected:
        print(runtime + " (" + str(image.get("build")) + ") at " + mount)
' "$expected"
}

# Read twice, a few seconds apart: the service is still mounting when it has just started.
first=$(unsettled)
sleep "${SIMULATOR_RUNTIME_FIRST_LOOK_SECONDS:-5}"
first=$(printf '%s\n%s\n' "$first" "$(unsettled)" | sort -u | sed '/^$/d')
if [[ -z $first ]]; then
  echo "Simulator runtimes: mounted as expected"
  exit 0
fi
echo "::warning::Simulator runtime mounted from a plain disk image; waiting up to $settle seconds for the runner to remount it before booting a Simulator:"
echo "$first"
while (( $(now) - started < settle )); do
  sleep "$poll"
  state=$(unsettled)
  echo "After $(( $(now) - started )) seconds: ${state:-none mounted from a plain disk image}"
done
echo "Simulator runtimes: $(( $(now) - started )) seconds since the job first used simctl"
