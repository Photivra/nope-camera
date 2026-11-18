#!/usr/bin/env bash
# Copies each string's Spanish (es) translation to Latin American Spanish (es-419) in every
# String Catalog, except for the strings listed in scripts/es-419-overrides.txt, which keep their
# own es-419 wording. Run it after adding or changing a Spanish translation: iOS does not fall
# back from es-419 to es for a missing string, so es-419 must hold every string
# (scripts/check-localization.sh checks it).
# Optional first argument: a directory to sync instead of the repository root.
set -euo pipefail

root="${1:-.}"
here="$(cd "$(dirname "$0")" && pwd)"
find "$root" -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0 |
  xargs -0 python3 -I "$here/localization_sync.py" "$root"
