#!/usr/bin/env bash
# Runs a command and ends it when it takes longer than a number of seconds:
#
#   scripts/with-timeout.sh <seconds> <command> [arguments…]
#
# It exits with the command's status, or with 124 after ending a command that ran out of time
# (the status GNU timeout uses; macOS has no timeout command). The CI scripts use it for every
# simctl call that prepares a Simulator: on the GitHub macOS runner such a call sometimes never
# returned, and the job ran to its limit without a test starting (docs/TESTING.md, "Preparing
# the Simulator has a time limit").
set -euo pipefail

[[ $# -ge 2 && $1 =~ ^[0-9]+$ ]] || { echo "usage: $0 <seconds> <command> [arguments…]" >&2; exit 2; }

exec python3 -c '
import subprocess, sys
seconds, command = int(sys.argv[1]), sys.argv[2:]
try:
    sys.exit(subprocess.run(command, timeout=seconds).returncode)
except subprocess.TimeoutExpired:
    print("error: no result after " + str(seconds) + " seconds: " + " ".join(command), file=sys.stderr)
    sys.exit(124)
except FileNotFoundError:
    print("error: " + command[0] + " not found", file=sys.stderr)
    sys.exit(127)
' "$@"
