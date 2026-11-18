#!/usr/bin/env bash
# Stops the push notification service (apsd) of a booted Simulator, before UI tests run on it:
#
#   scripts/stop-simulator-push.sh <simulator identifier>
#
# On the GitHub macOS runner the Simulator's push service can't get its device certificate
# ("Could not get certificate from simulator … Client is not supported"), drops its connection
# to the push server and connects again at once, without a pause: about 500 connections a
# minute and more than a thousand log lines a second for as long as the Simulator runs, on the
# iPhone, iPad and watch Simulators alike (the system logs of the failed shards of build
# 44075379089). On a developer's Mac it gets the certificate and stays connected. The app has no
# push notifications and makes no network request, so no test needs the service; stopping it
# takes that load off the runner. The service is removed from the Simulator's launchd until
# the Simulator boots again, so nothing starts it again during the tests.
#
# The script prints how often the service gave up its connection in the last minute, so a
# run's log shows whether the Simulator was affected.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <simulator identifier>" >&2; exit 2; }
udid=$1

drops=$(xcrun simctl spawn "$udid" log show --last 1m --style compact \
  --predicate 'process == "apsd" AND eventMessage CONTAINS "Could not get certificate from simulator"' 2>/dev/null \
  | grep -c "Could not get certificate" || true)
echo "Push service on $udid: gave up its connection $drops time(s) in the last minute"

# The service's name in the Simulator's launchd: "system/…" on the iOS 27.2 Simulator, where
# launchctl also suggests "user/foreground/…".
loaded() {
  local service
  for service in system/com.apple.apsd user/foreground/com.apple.apsd; do
    if xcrun simctl spawn "$udid" launchctl print "$service" >/dev/null 2>&1; then
      echo "$service"
      return
    fi
  done
  return 1
}

if service=$(loaded); then
  xcrun simctl spawn "$udid" launchctl bootout "$service" 2>&1 | grep -v "Please switch to" || true
fi
# Not stopping it leaves the tests as they were, so it is reported and the run goes on.
if service=$(loaded); then
  echo "::warning::The push service of Simulator $udid is still loaded ($service); the tests run with it."
else
  echo "Push service on $udid stopped"
fi
