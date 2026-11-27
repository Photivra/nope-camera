#!/usr/bin/env bash
# Runs the whole UI suite on the owner's Mac and, only when every part passes, posts the
# "ui-tests (owner Mac)" commit status that the `ui-tests`, `ui-tests-ipad` and `ui-tests-watch`
# checks accept in place of their GitHub shards (docs/TESTING.md, "When the GitHub UI runners are
# failing: a proof from the owner's Mac"). A fallback: the GitHub shards remain the default.
#
#   scripts/owner-mac-ui-proof.sh [--dry-run]
#
# Run it in a clean checkout of the commit to prove, pushed to GitHub, with Xcode 27.2 and the
# iOS and watchOS 27.2 Simulators. It refuses a tree with changes or untracked files, checks that
# the gh login is listed in .github/owner-mac-proof-allowed.txt and that GitHub has the commit,
# then in a new detached worktree of the commit (so ignored local files such as
# Config/Local.xcconfig don't take part) runs, one after another, with build.yml's scripts and
# devices (and the published C2PA library):
#   0. scripts/ui-test-shards.sh check, and reads the iPhone and iPad shard counts;
#   1. xcodebuild build-for-testing of the NopeApp scheme for the iPhone 18 Pro Simulator;
#   2. every iPhone shard on the iPhone 18 Pro Simulator (scripts/run-ui-test-shard.sh);
#   3. every iPad shard on the iPad Air 11-inch (M4) Simulator, without the test the iPad jobs skip;
#   4. the NopeWatch build and its UI tests on the Apple Watch Series 12 (46mm) Simulator
#      (scripts/run-watch-ui-tests.sh).
# It stops at the first failure, leaving the worktree and its result bundles for inspection. A
# test that failed and passed when run once more, alone (scripts/ui-test-run-lib.sh), doesn't
# stop it: such tests are listed as flaky at the end and counted in the status's description.
# Unlike build.yml it builds against the published C2PA library that Package.swift pins by
# checksum, not one built from source (the c2pa-lib job checks that they are the same).
# When all pass it posts the status on the commit, with the content key of its UI test inputs
# (scripts/ui-content-key.sh) in the description, and removes the worktree.
#
# --dry-run does the checks, prints the steps and the status it would post, and stops: it runs
# no build or test and posts nothing.
#
# Environment: NOPE_PROOF_REPO (default Photivra/nope-camera), NOPE_PROOF_DIR (the worktree,
# default a new directory under TMPDIR), NOPE_GH (the gh command, default gh).
set -euo pipefail

dry_run=
case ${1:-} in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "usage: $0 [--dry-run]" >&2; exit 2; }

repo=${NOPE_PROOF_REPO:-Photivra/nope-camera}
gh=${NOPE_GH:-gh}
context="ui-tests (owner Mac)"
iphone="iPhone 18 Pro"
ipad="iPad Air 11-inch (M4)"
simulator="platform=iOS Simulator,name=$iphone,OS=27.2"
watch="platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.2"
ipad_skip=-skip-testing:NopeAppUITests/NopeAppUITests/testSourceCodeIsAnHTTPSLink

root=$(git rev-parse --show-toplevel)
cd "$root"
if [[ -n $(git status --porcelain) ]]; then
  echo "error: the working tree has changes or untracked files; commit or stash them first:" >&2
  git status --short >&2
  exit 1
fi
sha=$(git rev-parse HEAD)
key=$(scripts/ui-content-key.sh HEAD)

login=$("$gh" api user --jq .login) || { echo "error: gh couldn't read the signed-in login (gh auth login)" >&2; exit 1; }
if ! git show "HEAD:.github/owner-mac-proof-allowed.txt" 2>/dev/null | sed 's/#.*//' | tr -d ' \t' \
    | grep -ixF -- "$login" >/dev/null; then
  echo "error: $login is not listed in .github/owner-mac-proof-allowed.txt, so CI wouldn't accept the proof" >&2
  exit 1
fi
"$gh" api "repos/$repo/commits/$sha" --silent 2>/dev/null \
  || { echo "error: $repo has no commit $sha; push it first" >&2; exit 1; }

description="iPhone, iPad and watch UI tests passed; key $key"
work=${NOPE_PROOF_DIR:-${TMPDIR:-/tmp}/nope-owner-mac-proof-${sha:0:12}}

echo "Commit:      $sha ($repo)"
echo "Content key: $key"
echo "gh login:    $login"
echo "Worktree:    $work"
echo "Steps:       build-for-testing NopeApp; every iPhone shard on $iphone; every iPad shard on $ipad;"
echo "             build-for-testing NopeWatch and its UI tests on the watch Simulator"
echo "Then posts:  gh api repos/$repo/statuses/$sha -f state=success -f context=\"$context\" -f description=\"$description\""
if [[ -n $dry_run ]]; then
  echo "Dry run: nothing was built, tested or posted."
  exit 0
fi

# sed reads all of xcodebuild's output: with pipefail, head would end it early and stop the script (141).
version=$(xcodebuild -version | sed -n 1p)
[[ $version == "Xcode 27.2" ]] || { echo "error: CI uses Xcode 27.2, this is $version (select it with xcode-select or DEVELOPER_DIR)" >&2; exit 1; }

[[ ! -e $work ]] || { echo "error: $work exists; remove it (git worktree remove --force) or set NOPE_PROOF_DIR" >&2; exit 1; }
git worktree add --detach "$work" "$sha"
cd "$work"
trap 'echo "error: the proof stopped at a failure; nothing was posted. The worktree is $work" >&2' ERR
export NOPE_HEAD_SHA=$sha
# The shards run as build.yml runs them: on iOS 27.2, with the published C2PA library (pinned by
# checksum in Package.swift) and the default result files.
unset SIMULATOR_OS NOPE_C2PA_LIB_FROM_SOURCE NOPE_TEST_RESULTS NOPE_CRASH_REPORTS
# The Simulator runtimes are already in use on this Mac: no first-use settling wait.
export SIMULATOR_RUNTIME_SETTLE_SECONDS=0
mkdir -p results

step() { echo; echo "==> $*"; "$@"; }

# The counts are read into variables and checked: a failing command substitution inside (( ))
# would end the loop at once without stopping the script (bash 3.2, even with set -e).
step scripts/ui-test-shards.sh check
iphone_shards=$(scripts/ui-test-shards.sh count iphone) || iphone_shards=
ipad_shards=$(scripts/ui-test-shards.sh count ipad) || ipad_shards=
if [[ ! $iphone_shards =~ ^[1-9][0-9]*$ || ! $ipad_shards =~ ^[1-9][0-9]*$ ]]; then
  trap - ERR
  echo "error: the shard counts couldn't be read; nothing was posted. The worktree is $work" >&2
  exit 1
fi

step xcodebuild build-for-testing -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination "$simulator" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
step scripts/check-launch-screen.sh DerivedData/Build/Products/Debug-iphonesimulator/nope.app

for (( shard = 1; shard <= iphone_shards; shard++ )); do
  step scripts/run-ui-test-shard.sh "$shard" "$iphone" DerivedData/Build/Products "results/ui-tests-$shard.xcresult"
done
for (( shard = 1; shard <= ipad_shards; shard++ )); do
  step scripts/run-ui-test-shard.sh "$shard" "$ipad" DerivedData/Build/Products "results/ui-tests-ipad-$shard.xcresult" "$ipad_skip"
done

udid=$(scripts/prepare-simulator.sh --find "$watch" | sed -n 's/^udid=//p' | sed -n 1p)
[[ -n $udid ]] || { echo "error: no watch Simulator for $watch" >&2; false; }
step xcodebuild build-for-testing -project App/NopeCamera.xcodeproj -scheme NopeWatch \
  -destination "id=$udid" -derivedDataPath DerivedData-watch CODE_SIGNING_ALLOWED=NO
step scripts/run-watch-ui-tests.sh "$watch" DerivedData-watch results/ui-tests-watch.xcresult

trap - ERR
# The tests that failed once and passed when run once more: listed, and counted in the status.
flaky=$(scripts/ui-test-run-lib.sh --flaky results/*-results.jsonl)
if [[ -n $flaky ]]; then
  count=$(grep -c . <<<"$flaky")
  echo
  echo "Run once more after a test failure ($count), recorded as flaky in results/*-results.jsonl:"
  echo "$flaky"
  description="iPhone, iPad and watch UI tests passed, $count after a retry; key $key"
else
  echo
  echo "No test needed a retry."
fi
[[ $(scripts/ui-content-key.sh HEAD) == "$key" ]] || { echo "error: the worktree's content key changed; nothing was posted" >&2; exit 1; }
"$gh" api "repos/$repo/statuses/$sha" -f state=success -f context="$context" -f description="$description" --silent \
  || { echo "error: every test passed but the status couldn't be posted; nothing was posted. The worktree is $work" >&2; exit 1; }
echo
echo "Posted \"$context\" (success) on $sha with content key $key."
cd "$root"
git worktree remove --force "$work"
