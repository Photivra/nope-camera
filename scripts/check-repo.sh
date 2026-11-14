#!/usr/bin/env bash
# Repository checks: required documents, license text, and sign-off on pull request commits.
set -euo pipefail

fail=0
for f in LICENSE NOTICE TRADEMARKS.md CONTRIBUTING.md SECURITY.md THIRD_PARTY.md CHANGELOG.md AGENTS.md CLAUDE.md README.md llms.txt; do
  if [[ ! -s "$f" ]]; then echo "missing or empty: $f"; fail=1; fi
done

if ! head -n 3 LICENSE | grep -q "GNU GENERAL PUBLIC LICENSE" || ! head -n 3 LICENSE | grep -q "Version 3"; then
  echo "LICENSE is not the GPLv3 text"; fail=1
fi

if ! grep -q "@AGENTS.md" CLAUDE.md; then echo "CLAUDE.md must import AGENTS.md"; fail=1; fi

# llms.txt: every relative link must point to a file in the repository.
while read -r target; do
  if [[ ! -e "$target" ]]; then echo "llms.txt links to a missing file: $target"; fail=1; fi
done < <(grep -oE '\]\([^)#]+\)' llms.txt | sed -E 's/^\]\((.*)\)$/\1/' | grep -vE '^[a-z]+://')

# Sign-off: every commit in the range BASE..HEAD needs a Signed-off-by trailer.
if [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]]; then
  while read -r sha; do
    if ! git show -s --format=%B "$sha" | grep -q "^Signed-off-by: "; then
      echo "commit $sha has no Signed-off-by trailer"; fail=1
    fi
  done < <(git rev-list "$BASE_SHA..$HEAD_SHA")
fi

# Private test deployments: no host name containing "staging" in tracked files (AGENTS.md rule 6).
host_pattern='[a-z0-9-]*''staging''[a-z0-9-]*([.][a-z0-9-]+)*[.](com|dev|app|net|org|io)([^a-z0-9-]|$)'
if hits=$(git grep -n -I -i -E "$host_pattern" -- . ':!scripts/check-repo.sh' 2>/dev/null) && [[ -n "$hits" ]]; then
  echo "private test deployment host names found (AGENTS.md rule 6):"; echo "$hits"; fail=1
fi

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "repository checks passed"
