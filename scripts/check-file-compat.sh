#!/usr/bin/env bash
# Runs the external file validators on the compatibility fixtures (issue #58, docs/TESTING.md,
# "File compatibility"). The fixtures are written by the unit tests
# (Tests/NopeSigningTests/FileCompatibilityTests.swift) when they run with
# TEST_RUNNER_NOPE_COMPAT_FIXTURES=<directory>; that directory holds the files and manifest.tsv
# (name, format, signed, device-processed).
#
# Usage: scripts/check-file-compat.sh [--require "c2patool exiftool dng_validate"] <directory>
#
# Each validator runs only if it is on PATH; none is a project dependency. --require names the
# ones that must be present (CI passes the maintainer-approved list), so a missing one fails.
#   c2patool      every signed file: validation_state Valid, signingCredential.untrusted the only
#                 failure; every unsigned file: no manifest
#   exiftool      exiftool -validate on every file: no errors (warnings are printed)
#   dng_validate  Adobe's DNG SDK validator on every DNG: exit 0 and no "*** Error"
set -euo pipefail

required=""
if [[ "${1:-}" == "--require" ]]; then
  required="${2:-}"
  shift 2
fi
dir="${1:?usage: check-file-compat.sh [--require \"tools\"] <fixtures directory>}"
manifest="$dir/manifest.tsv"
[[ -f "$manifest" ]] || { echo "file-compat: no manifest.tsv in $dir"; exit 1; }

fail=0
ran=0
for tool in $required; do
  case "$tool" in
    c2patool|exiftool|dng_validate) ;;
    *) echo "file-compat: unknown validator $tool"; fail=1; continue ;;
  esac
  command -v "$tool" >/dev/null || { echo "file-compat: required validator $tool isn't installed"; fail=1; }
done

# c2patool prints the manifest store as JSON; this prints "<state> <failure codes>", or
# "none" when the file has no manifest.
c2pa_summary() {
  python3 -c '
import json, sys
try:
    report = json.load(sys.stdin)
except ValueError:
    print("none")
    sys.exit(0)
failures = report.get("validation_results", {}).get("activeManifest", {}).get("failure", [])
print(report.get("validation_state"), ",".join(sorted({f["code"] for f in failures})))
'
}

while IFS=$'\t' read -r name format signed _; do
  file="$dir/$name"
  [[ -f "$file" ]] || { echo "file-compat: $name is in the manifest but missing"; fail=1; continue; }
  if command -v c2patool >/dev/null; then
    ran=1
    summary=$(c2patool "$file" 2>/dev/null | c2pa_summary || true)
    expected=$([[ "$signed" == true ]] && echo "Valid signingCredential.untrusted" || echo "none")
    [[ "$summary" == "$expected" ]] || { echo "c2patool: $name: $summary (expected $expected)"; fail=1; }
  fi
  if command -v exiftool >/dev/null; then
    ran=1
    report=$(exiftool -validate -warning -error -a -s "$file" 2>&1 || true)
    if grep -qE '^Error|^Validate +: .*[1-9][0-9]* Errors?' <<<"$report"; then
      echo "exiftool: $name:"; echo "$report"; fail=1
    elif grep -q '^Warning' <<<"$report"; then
      echo "exiftool: $name (warnings):"; grep '^Warning' <<<"$report"
    fi
  fi
  if [[ "$format" == raw ]] && command -v dng_validate >/dev/null; then
    ran=1
    if ! report=$(dng_validate "$file" 2>&1) || grep -q '\*\*\* Error' <<<"$report"; then
      echo "dng_validate: $name:"; echo "$report"; fail=1
    fi
  fi
done < "$manifest"

if [[ $fail -ne 0 ]]; then exit 1; fi
if [[ $ran -eq 0 ]]; then
  echo "file-compat: no validator installed; nothing checked"
else
  echo "file-compat checks passed ($(wc -l < "$manifest" | tr -d ' ') files)"
fi
