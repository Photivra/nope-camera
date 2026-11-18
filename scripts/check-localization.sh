#!/usr/bin/env bash
# Localization checks for every String Catalog (AGENTS.md, "Localization").
# Each string must have a translator comment and a non-empty value in English, Spanish (es) and
# Latin American Spanish (es-419), and in no other language (in every plural case, where it has
# plural variations), marked "translated" or "needs_review". A string keeps the name "nope." and
# its placeholders unchanged in every language. es-419 equals es except for the strings listed in
# scripts/es-419-overrides.txt, which must differ.
# Optional first argument: a directory to check instead of the repository root.
set -euo pipefail

root="${1:-.}"
here="$(cd "$(dirname "$0")" && pwd)"
find "$root" -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0 |
  xargs -0 python3 -I "$here/localization_check.py" "$root"
