#!/usr/bin/env bash
# Documentation checks (AGENTS.md, "Documentation is checked in CI").
# Usage: scripts/check-docs.sh <derived-data-path> [--write]
# 1. Builds the DocC documentation for every NopeKit module, with warnings as errors and
#    internal symbols included.
# 2. Fails if any public or internal symbol lacks its own DocC comment.
# 3. Exports the API as Markdown to docs/api/ and fails if it differs from the committed copy.
#    Pass --write to update docs/api/ instead of failing.
set -euo pipefail

derived="${1:?usage: check-docs.sh <derived-data-path> [--write]}"
mode="${2:-check}"
here="$(cd "$(dirname "$0")/.." && pwd)"
modules=(NopeCore NopeCapture NopeDevelop NopeSigning NopeUI)
cd "$here"

xcodebuild -quiet docbuild \
  -scheme NopeKit-Package \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  OTHER_DOCC_FLAGS="--warnings-as-errors" \
  OTHER_SWIFT_FLAGS='$(inherited) -symbol-graph-minimum-access-level internal'

graphs=$(mktemp -d)
trap 'rm -rf "$graphs"' EXIT
# One architecture is enough: the API is the same on every simulator architecture.
find "$derived/Build/Intermediates.noindex" -path '*/symbol-graph/swift/arm64-apple-ios-simulator/*' \
  -name '*.symbols.json' -exec cp {} "$graphs/" \;

out="$here/docs/api"
[[ "$mode" == "--write" ]] || out=$(mktemp -d)
python3 -I "$here/scripts/docs_tool.py" "$here" "$graphs" "$out" "${modules[@]}"

if [[ "$mode" != "--write" ]]; then
  if ! diff -ru "$here/docs/api" "$out"; then
    echo "docs: docs/api/ is out of date; run scripts/check-docs.sh <derived-data-path> --write"
    exit 1
  fi
  echo "docs/api/ matches the code"
fi
