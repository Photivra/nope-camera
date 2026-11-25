#!/usr/bin/env bash
# Prints the content key of a commit's UI test inputs, for a proof from the owner's Mac
# (docs/TESTING.md, "When the GitHub UI runners are failing: a proof from the owner's Mac"):
#
#   scripts/ui-content-key.sh [<commit>]            the key (64 hex digits), default HEAD
#   scripts/ui-content-key.sh --inputs [<commit>]   the lines the key is the SHA-256 of
#
# The inputs are the git object ids of everything the UI tests build from or run with: the tree
# ids of the app and its tests, the package and its pinned dependencies, the configuration and
# the vendored and built-from-source libraries ("-" for a path the commit doesn't have), and the
# blob id of every file under scripts/ except the four proof scripts (owner-mac-ui-proof.sh,
# check-owner-mac-proof.sh, test-owner-mac-proof.sh and this one). The workflow files, the
# documentation and the proof scripts are not inputs, so a change to them alone keeps the key.
# The lines are collected first and then hashed, so a failing git call never hashes part of them.
# Run it in the repository's top directory.
set -euo pipefail
mode=key
if [[ ${1:-} == --inputs ]]; then mode=inputs; shift; fi
[[ $# -le 1 ]] || { echo "usage: $0 [--inputs] [<commit>]" >&2; exit 2; }
rev=${1:-HEAD}
git rev-parse --verify --quiet "$rev^{commit}" >/dev/null || { echo "error: $rev is not a commit" >&2; exit 2; }

paths=(App Sources Tests Config Vendor Tools c2pa-lib Package.swift Package.resolved)
not_inputs='^scripts/(owner-mac-ui-proof|check-owner-mac-proof|test-owner-mac-proof|ui-content-key)\.sh$'

inputs() {
  echo "nope-ui-content-key v2"
  local path id
  for path in "${paths[@]}"; do
    id=$(git rev-parse --verify --quiet "$rev:$path") || id=-
    echo "$path $id"
  done
  git -c core.quotePath=false ls-tree -r --full-tree "$rev" -- scripts \
    | awk -F'\t' -v skip="$not_inputs" '$2 !~ skip { print $2, $1 }'
}

lines=$(inputs)
if [[ $mode == inputs ]]; then printf '%s\n' "$lines"; exit 0; fi
if command -v sha256sum >/dev/null; then printf '%s\n' "$lines" | sha256sum | cut -d' ' -f1; else printf '%s\n' "$lines" | shasum -a 256 | cut -d' ' -f1; fi
