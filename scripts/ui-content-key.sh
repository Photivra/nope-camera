#!/usr/bin/env bash
# Prints the content key of a commit's UI test inputs, for a proof from the owner's Mac
# (docs/TESTING.md, "When the GitHub UI runners are failing: a proof from the owner's Mac"):
#
#   scripts/ui-content-key.sh [<commit>]            the key (64 hex digits), default HEAD
#   scripts/ui-content-key.sh --inputs [<commit>]   the lines the key is the SHA-256 of
#
# The inputs are the git object ids of everything the UI tests build from or run with: the app
# and its tests, the package and its pinned dependencies, the configuration, the vendored and
# built-from-source libraries and the scripts. The workflow files and the documentation are not
# inputs, so a change to them alone keeps the key. A path the commit doesn't have counts as "-".
# Run it in the repository's top directory.
set -euo pipefail

mode=key
if [[ ${1:-} == --inputs ]]; then mode=inputs; shift; fi
[[ $# -le 1 ]] || { echo "usage: $0 [--inputs] [<commit>]" >&2; exit 2; }
rev=${1:-HEAD}
git rev-parse --verify --quiet "$rev^{commit}" >/dev/null || { echo "error: $rev is not a commit" >&2; exit 2; }

paths=(App Sources Tests Config Vendor Tools c2pa-lib scripts Package.swift Package.resolved)

inputs() {
  echo "nope-ui-content-key v1"
  local path id
  for path in "${paths[@]}"; do
    id=$(git rev-parse --verify --quiet "$rev:$path") || id=-
    echo "$path $id"
  done
}

if [[ $mode == inputs ]]; then inputs; exit 0; fi
if command -v sha256sum >/dev/null; then inputs | sha256sum | cut -d' ' -f1; else inputs | shasum -a 256 | cut -d' ' -f1; fi
