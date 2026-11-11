#!/usr/bin/env bash
# Repository checks: required documents, license text, and sign-off on pull request commits.
set -euo pipefail

fail=0
for f in LICENSE NOTICE TRADEMARKS.md CONTRIBUTING.md SECURITY.md THIRD_PARTY.md CHANGELOG.md AGENTS.md CLAUDE.md README.md; do
  if [[ ! -s "$f" ]]; then echo "missing or empty: $f"; fail=1; fi
done

if ! head -n 3 LICENSE | grep -q "GNU GENERAL PUBLIC LICENSE" || ! head -n 3 LICENSE | grep -q "Version 3"; then
  echo "LICENSE is not the GPLv3 text"; fail=1
fi

if ! grep -q "@AGENTS.md" CLAUDE.md; then echo "CLAUDE.md must import AGENTS.md"; fail=1; fi

# Sign-off: every commit in the range BASE..HEAD needs a Signed-off-by trailer.
if [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]]; then
  while read -r sha; do
    if ! git show -s --format=%B "$sha" | grep -q "^Signed-off-by: "; then
      echo "commit $sha has no Signed-off-by trailer"; fail=1
    fi
  done < <(git rev-list "$BASE_SHA..$HEAD_SHA")
fi

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "repository checks passed"
