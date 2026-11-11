#!/usr/bin/env bash
# Localization checks for every String Catalog (AGENTS.md, "Localization").
# Each string must have a translator comment and a non-empty value in all eleven launch
# languages, marked "translated" or "needs_review"; a string containing the name "nope." keeps
# it unchanged in every language.
# Optional first argument: a directory to check instead of the repository root.
set -euo pipefail

root="${1:-.}"
here="$(cd "$(dirname "$0")" && pwd)"
find "$root" -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0 |
  xargs -0 python3 -I "$here/localization_check.py"
