#!/usr/bin/env bash
# Tests for scripts/ui-content-key.sh, scripts/check-owner-mac-proof.sh and the checks and
# --dry-run of scripts/owner-mac-ui-proof.sh: each case builds a small repository and a stand-in
# for gh, and checks the result. Nothing is built, tested on a Simulator or posted.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
failures=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

expect() { # expect <want: pass|fail> <name> <command…>
  local want=$1 name=$2 got
  shift 2
  if "$@" >"$work/out" 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; sed 's/^/     /' "$work/out"; failures=$((failures + 1)); fi
}
expect_output() { # expect_output <name> <text>: the last command's output has the text
  if grep -qF -- "$2" "$work/out"; then echo "ok   $1"; else echo "FAIL $1 (no \"$2\" in the output)"; sed 's/^/     /' "$work/out"; failures=$((failures + 1)); fi
}

g() { git -C "$repo" -c user.name=Test -c user.email=test@example.com "$@"; }

# A repository with the UI test inputs, the scripts under test and the allow-list.
repo=$work/repo
mkdir -p "$repo/App" "$repo/Sources" "$repo/Tests" "$repo/Config" "$repo/scripts" "$repo/docs" "$repo/.github/workflows"
echo app >"$repo/App/A.swift"; echo src >"$repo/Sources/S.swift"; echo test >"$repo/Tests/T.swift"
echo cfg >"$repo/Config/Base.xcconfig"; echo pkg >"$repo/Package.swift"; echo '{}' >"$repo/Package.resolved"
echo doc >"$repo/docs/D.md"; echo 'name: build' >"$repo/.github/workflows/build.yml"
printf '# comment\nbshack  # the owner\n' >"$repo/.github/owner-mac-proof-allowed.txt"
cp "$here/ui-content-key.sh" "$here/check-owner-mac-proof.sh" "$here/owner-mac-ui-proof.sh" "$repo/scripts/"
echo '# stand-in' >"$repo/scripts/run-ui-test-shard.sh"
# Stand-in for scripts/ui-test-shards.sh: "check" passes; "count" prints FAKE_SHARDS, or fails
# when it is "fail".
cat >"$repo/scripts/ui-test-shards.sh" <<'EOF2'
#!/usr/bin/env bash
case $1 in
  check) exit 0 ;;
  count) [[ ${FAKE_SHARDS:-6} != fail ]] || exit 1; echo "${FAKE_SHARDS:-6}" ;;
esac
EOF2
chmod +x "$repo/scripts/ui-test-shards.sh"
git init -q "$repo"
g add -A && g commit -qm one
key() { (cd "$repo" && scripts/ui-content-key.sh "$@"); }

# --- scripts/ui-content-key.sh
k1=$(key)
expect pass "the key is 64 hex digits" bash -c "[[ $k1 =~ ^[0-9a-f]{64}$ ]]"
expect pass "the key is the same when run again" test "$(key)" = "$k1"
echo changed >"$repo/docs/D.md"; echo 'name: changed' >"$repo/.github/workflows/build.yml"
g commit -qam docs
expect pass "a docs and workflow change keeps the key" test "$(key)" = "$k1"
expect pass "a given commit's key" test "$(key HEAD~1)" = "$k1"
echo changed >"$repo/App/A.swift"; g commit -qam app
k2=$(key)
expect pass "an App change changes the key" test "$k2" != "$k1"
echo '# x' >>"$repo/scripts/run-ui-test-shard.sh"; g commit -qam script
k3=$(key)
expect pass "a scripts change changes the key" test "$k3" != "$k2"
for f in owner-mac-ui-proof check-owner-mac-proof ui-content-key; do echo '# x' >>"$repo/scripts/$f.sh"; done
echo '# x' >"$repo/scripts/test-owner-mac-proof.sh"; g add -A; g commit -qm "proof scripts"
expect pass "a change to a proof script keeps the key" test "$(key)" = "$k3"
mkdir -p "$repo/Vendor"; echo v >"$repo/Vendor/V.swift"; g add -A; g commit -qm vendor
expect pass "adding Vendor changes the key" test "$(key)" != "$k3"
g rm -q Package.resolved; g commit -qm resolved
expect_output_key() { key --inputs >"$work/out"; expect_output "$1" "$2"; }
expect_output_key "a missing path counts as -" "Package.resolved -"
expect fail "a commit that doesn't exist" key 0000000000000000000000000000000000000000
expect fail "two commits" key HEAD HEAD~1

# --- scripts/check-owner-mac-proof.sh
head_sha=$(g rev-parse HEAD)
key=$(key)
cat >"$work/gh" <<'EOF'
#!/usr/bin/env bash
# Stand-in for gh: prints $GH_STATUSES for the statuses call, fails with GH_FAIL set.
[[ -z ${GH_FAIL:-} ]] || exit 1
case "$*" in
  "api repos/Photivra/nope-camera/commits/$NOPE_HEAD_SHA/statuses?per_page=100") printf '%s' "$GH_STATUSES" ;;
  "api user --jq .login") echo "${GH_LOGIN:-bshack}" ;;
  "api repos/Photivra/nope-camera/commits/"*" --silent") [[ -z ${GH_NO_COMMIT:-} ]] ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/gh"
status() { # status <state> <login> <key> [created at] [context]
  printf '{"id":1,"state":"%s","context":"%s","description":"iPhone, iPad and watch UI tests passed; key %s","created_at":"%s","creator":{"login":"%s"}}' \
    "$1" "${5:-ui-tests (owner Mac)}" "$3" "${4:-2026-11-24T10:00:00Z}" "$2"
}
check() { # check <shards result> <statuses JSON>
  (cd "$repo" && GH_STATUSES=$2 NOPE_GH="$work/gh" GITHUB_REPOSITORY=Photivra/nope-camera \
    NOPE_HEAD_SHA=$head_sha GITHUB_STEP_SUMMARY="$work/summary" scripts/check-owner-mac-proof.sh ui-tests "$1")
}
valid=$(status success bshack "$key")
other=$(printf '%064d' 7)

expect pass "shards passed, no status needed" check success "[]"
expect_output "it says the shards passed" "passed on GitHub's runners"
expect fail "shards failed, no status" check failure "[]"
expect_output "it says there is no status" "no \"ui-tests (owner Mac)\" status"
expect pass "shards failed, a valid proof" check failure "[$valid]"
expect_output "it says the proof passed" "passed with a proof from the owner's Mac"
expect pass "the job summary says which path passed" grep -qF "passed with a proof from the owner's Mac" "$work/summary"
expect pass "shards cancelled, a valid proof" check cancelled "[$valid]"
expect fail "shards cancelled, no proof" check cancelled "[]"
expect fail "shards skipped, no proof" check skipped "[]"
expect fail "a proof for other content" check failure "[$(status success bshack "$other")]"
expect_output "it names the key that differs" "is not this commit's $key"
expect fail "a proof by a login not in the list" check failure "[$(status success someone "$key")]"
expect pass "a login in another case" check failure "[$(status success BShack "$key")]"
expect fail "a pending proof" check failure "[$(status pending bshack "$key")]"
expect fail "a newer failure withdraws the proof" check failure "[$(status failure bshack "$key" 2026-11-24T11:00:00Z),$valid]"
expect pass "a newer success after a failure" check failure "[$(status failure bshack "$key" 2026-11-24T09:00:00Z),$valid]"
expect fail "a success with another context" check failure "[$(status success bshack "$key" "" other)]"
expect fail "a description without a key" check failure '[{"id":1,"state":"success","context":"ui-tests (owner Mac)","description":"passed","created_at":"x","creator":{"login":"bshack"}}]'
expect fail "a response that isn't JSON" check failure "not json"
export GH_FAIL=1; expect fail "gh fails" check failure "[$valid]"; unset GH_FAIL
expect fail "no head commit" bash -c "cd '$repo' && GITHUB_REPOSITORY=Photivra/nope-camera NOPE_HEAD_SHA= NOPE_GH='$work/gh' scripts/check-owner-mac-proof.sh ui-tests failure"
expect fail "usage" bash -c "cd '$repo' && scripts/check-owner-mac-proof.sh ui-tests"

# --- scripts/owner-mac-ui-proof.sh (checks and --dry-run only)
proof() { (cd "$repo" && NOPE_GH="$work/gh" NOPE_PROOF_DIR="$work/proof-tree" scripts/owner-mac-ui-proof.sh "$@"); }
expect pass "dry run on a clean tree" proof --dry-run
expect_output "it prints the status it would post" "gh api repos/Photivra/nope-camera/statuses/$head_sha -f state=success -f context=\"ui-tests (owner Mac)\" -f description=\"iPhone, iPad and watch UI tests passed; key $key\""
expect_output "it says nothing was posted" "Dry run: nothing was built, tested or posted."
expect pass "the dry run made no worktree" test ! -e "$work/proof-tree"
echo dirty >>"$repo/App/A.swift"
expect fail "a changed file" proof --dry-run
expect_output "it says the tree has changes" "the working tree has changes"
g checkout -q -- App/A.swift
touch "$repo/App/New.swift"
expect fail "an untracked file" proof --dry-run
rm "$repo/App/New.swift"
export GH_LOGIN=someone; expect fail "a login not in the list" proof --dry-run; unset GH_LOGIN
export GH_NO_COMMIT=1; expect fail "a commit GitHub doesn't have" proof --dry-run; unset GH_NO_COMMIT
expect fail "an unknown option" proof --post

# Past the dry run, with a stand-in xcodebuild that only reports its version: shard counts that
# can't be read stop the proof before any build, and nothing is posted.
mkdir -p "$work/bin"
cat >"$work/bin/xcodebuild" <<'EOF2'
#!/usr/bin/env bash
[[ $1 == -version ]] || { echo "xcodebuild stand-in: no build in these tests" >&2; exit 1; }
echo "Xcode 27.2"
EOF2
chmod +x "$work/bin/xcodebuild"
real_proof() { (cd "$repo" && PATH="$work/bin:$PATH" NOPE_GH="$work/gh" NOPE_PROOF_DIR="$work/proof-tree-$FAKE_SHARDS" scripts/owner-mac-ui-proof.sh); }
for FAKE_SHARDS in fail 0 x; do
  export FAKE_SHARDS
  expect fail "shard count \"$FAKE_SHARDS\" stops the proof" real_proof
  expect_output "it says the counts couldn't be read ($FAKE_SHARDS)" "the shard counts couldn't be read; nothing was posted"
  cp "$work/out" "$work/proof-out"
  expect fail "no build ran and nothing was posted ($FAKE_SHARDS)" grep -qE "xcodebuild stand-in|Posted" "$work/proof-out"
done
unset FAKE_SHARDS
git -C "$repo" worktree prune

if [[ $failures -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "all owner Mac proof tests passed"
