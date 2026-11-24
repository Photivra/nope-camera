#!/usr/bin/env bash
# Decides a required UI check of .github/workflows/build.yml (`ui-tests`, `ui-tests-ipad`,
# `ui-tests-watch`) from its shards' result (docs/TESTING.md, "When the GitHub UI runners are
# failing: a proof from the owner's Mac"):
#
#   scripts/check-owner-mac-proof.sh <check name> <shards result>
#
# It passes when the shards' result is "success". Otherwise it passes only with a valid proof:
# the newest commit status with the context "ui-tests (owner Mac)" on the commit NOPE_HEAD_SHA
# (for a pull request, its head commit) is a success, was created by a login listed in
# .github/owner-mac-proof-allowed.txt, and its description ends with "key <content key>" equal to
# the key of the checked-out commit (scripts/ui-content-key.sh). For a pull request the
# checked-out commit is the merge with the base branch, so a proof made before the base branch
# changed a UI test input doesn't match. A newer status with that context and another state
# withdraws an earlier proof. Either way it says in the job summary which path passed, or why
# the check failed.
#
# Environment: GITHUB_REPOSITORY (owner/name), NOPE_HEAD_SHA, GH_TOKEN for gh (statuses: read),
# GITHUB_STEP_SUMMARY (optional), NOPE_GH (the gh command, default gh; the tests use a stand-in).
# Run it in the repository's top directory.
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <check name> <shards result>" >&2; exit 2; }
check=$1 shards=$2
scripts=$(cd "$(dirname "$0")" && pwd)
context="ui-tests (owner Mac)"
allowed_file=.github/owner-mac-proof-allowed.txt

say() { printf '%s\n' "$@" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"; }
fail() { say "### $check: failed" "" "The shards' result is \`$shards\` and there is no valid proof from the owner's Mac: $1" ""; exit 1; }

if [[ $shards == success ]]; then
  say "### $check: passed on GitHub's runners" "" "Every shard passed." ""
  exit 0
fi

repo=${GITHUB_REPOSITORY:-}
sha=${NOPE_HEAD_SHA:-}
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "GITHUB_REPOSITORY isn't set."
[[ $sha =~ ^[0-9a-f]{40}$ ]] || fail "NOPE_HEAD_SHA isn't a commit id."
[[ -f $allowed_file ]] || fail "$allowed_file is missing."
key=$("$scripts/ui-content-key.sh" HEAD) || fail "the content key couldn't be computed."

statuses=$("${NOPE_GH:-gh}" api "repos/$repo/commits/$sha/statuses?per_page=100") \
  || fail "the commit statuses of $sha couldn't be read."

# Prints "ok <login> <created at>" for a valid proof, or "no <reason>".
verdict=$(python3 -I -c '
import json, re, sys
context, key, allowed_file = sys.argv[1:4]
try:
    statuses = json.loads(sys.stdin.read())
except ValueError:
    print("no the statuses response is not JSON"); sys.exit()
if not isinstance(statuses, list):
    print("no the statuses response is not a list"); sys.exit()
allowed = set()
for line in open(allowed_file):
    line = line.split("#", 1)[0].strip()
    if line:
        allowed.add(line.lower())
mine = [s for s in statuses if isinstance(s, dict) and s.get("context") == context]
if not mine:
    print("no there is no \"" + context + "\" status on the commit"); sys.exit()
newest = max(mine, key=lambda s: (s.get("created_at") or "", s.get("id") or 0))
login = ((newest.get("creator") or {}).get("login") or "")
if newest.get("state") != "success":
    print("no the newest \"" + context + "\" status is " + str(newest.get("state"))); sys.exit()
if login.lower() not in allowed:
    print("no the newest \"" + context + "\" status was created by " + (login or "nobody") + ", who is not in " + allowed_file); sys.exit()
match = re.search(r"key ([0-9a-f]{64})$", newest.get("description") or "")
if not match:
    print("no the newest \"" + context + "\" status has no content key"); sys.exit()
if match.group(1) != key:
    print("no its content key " + match.group(1) + " is not this commit\x27s " + key); sys.exit()
print("ok " + login + " " + str(newest.get("created_at")))
' "$context" "$key" "$allowed_file" <<<"$statuses")

case $verdict in
  ok\ *)
    read -r _ login created <<<"$verdict"
    say "### $check: passed with a proof from the owner's Mac" "" \
      "The shards' result is \`$shards\`. The \`$context\` status on $sha, created by $login at $created, is a success for content key $key, this commit's (scripts/check-owner-mac-proof.sh)." ""
    ;;
  *) fail "${verdict#no }." ;;
esac
