#!/usr/bin/env bash
# Release check: the app's App Store ID is set (docs/store/STORE-PAGE-PLAN.md, 12.2).
# The About screen's Rate or Review row is built from `AboutScreen.appStoreID` and hidden while
# it is nil, so a Release build without it ships no Rate or Review row. Run before cutting each
# release build (docs/SECURITY_AUDIT.md, check 7, and the sign-off checklist). It is not run on
# pull requests: the id exists only once the app's App Store Connect record does.
# Run from the repository root. Optional first argument: the AboutScreen.swift file to check.
set -euo pipefail

file="${1:-Sources/NopeUI/AboutScreen.swift}"
if [[ ! -f "$file" ]]; then echo "app store id: $file not found"; exit 1; fi
line=$(grep -E '^[[:space:]]*(nonisolated )?static let appStoreID: String\? = ' "$file" || true)
if [[ -z "$line" ]]; then echo "app store id: no 'static let appStoreID: String? = ...' in $file"; exit 1; fi
if grep -qE '= "[0-9]+"[[:space:]]*$' <<<"$line"; then
  echo "app store id set: $(sed -E 's/.*= "([0-9]+)".*/\1/' <<<"$line")"
  exit 0
fi
echo "app store id: AboutScreen.appStoreID in $file isn't a numeric id (found: ${line#*= })."
echo "Set it to the app's Apple ID from App Store Connect (App Information) before a release build;"
echo "without it the About screen has no Rate or Review row."
exit 1
