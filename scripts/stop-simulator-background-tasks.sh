#!/usr/bin/env bash
# Stops the background task scheduler (dasd) of a booted Simulator, before UI tests run on it:
#
#   scripts/stop-simulator-background-tasks.sh <simulator identifier>
#
# A Simulator that boots for the first time has a list of the system's own background tasks to
# run, and its scheduler starts them a few minutes after boot: first a prewarm of the wallpaper
# gallery (about 25 wallpaper extensions and 20 Metal compiler processes on the iPhone
# Simulator), then Spotlight indexing, Health, Siri, Mail and other first-boot work. On the
# GitHub macOS runner (3 cores, 7 GB) the prewarm alone takes 2.1 to 2.8 minutes, and every
# test that failed with a timeout in build 44098207588 ran during it or the tasks after it
# (docs/TESTING.md, "The Simulator's background tasks on the runner"). On a developer's Mac the
# same prewarm takes about 15 seconds.
#
# The app has no background modes and schedules no background task, so no test needs the
# scheduler. It is removed from the Simulator's launchd until the Simulator boots again; a task
# another service asks for after that is refused and not run. Run this right after boot,
# before the scheduler starts the tasks.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <simulator identifier>" >&2; exit 2; }
udid=$1

# The scheduler's name in the Simulator's launchd: "system/…" on the iOS 27.2 Simulator, where
# launchctl also suggests "user/foreground/…".
loaded() {
  local service
  for service in system/com.apple.dasd user/foreground/com.apple.dasd; do
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
  echo "::warning::The background task scheduler of Simulator $udid is still loaded ($service); the tests run with it."
else
  echo "Background task scheduler on $udid stopped"
fi
