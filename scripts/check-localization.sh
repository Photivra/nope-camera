#!/usr/bin/env bash
# Localization checks for every String Catalog (AGENTS.md, "Localization").
# The app ships in English only. Each string must have a translator comment and no translation
# into another language; an English value that differs from the key (and every plural case,
# where it has plural variations) must be non-empty and marked "translated" or "needs_review".
# Optional first argument: a directory to check instead of the repository root.
set -euo pipefail

root="${1:-.}"
here="$(cd "$(dirname "$0")" && pwd)"
find "$root" -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0 |
  xargs -0 python3 -I "$here/localization_check.py"
