#!/usr/bin/env bash
# Coverage gate for the logic modules (AGENTS.md, "Full test coverage").
# Usage: scripts/check-coverage.sh <derived-data-path>
# Reads the coverage profile from an `xcodebuild test -enableCodeCoverage YES` run of the
# NopeKit-Package scheme, and fails unless every line and region in NopeCore, NopeCapture,
# NopeDevelop and NopeSigning is covered, except the files in scripts/coverage-exclusions.txt.
# Swift's coverage mapping records each branch arm as a region and emits no separate branch
# records, so the region check is the branch check; branch records are also checked if present.
set -euo pipefail

derived="${1:?usage: check-coverage.sh <derived-data-path>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
modules=(NopeCore NopeCapture NopeDevelop NopeSigning)

profile=$(find "$derived/Build/ProfileData" -name Coverage.profdata | head -n 1)
[[ -n "$profile" ]] || { echo "coverage: no Coverage.profdata under $derived"; exit 1; }

objects=()
for m in "${modules[@]}"; do
  o=$(find "$derived/Build/Products" -name "$m.o" | head -n 1)
  [[ -n "$o" ]] || { echo "coverage: no object file for $m"; exit 1; }
  objects+=("$o")
done

args=("${objects[0]}")
for o in "${objects[@]:1}"; do args+=(-object "$o"); done

xcrun llvm-cov export -summary-only -instr-profile "$profile" "${args[@]}" |
  python3 -I "$here/scripts/coverage_gate.py" "$here" "${modules[@]}"
