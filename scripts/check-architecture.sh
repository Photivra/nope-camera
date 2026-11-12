#!/usr/bin/env bash
# Module import boundaries (AGENTS.md, "Architecture: interface separate from logic").
# Each module under Sources/ may import only the modules and frameworks in its allowlist.
# Optional first argument: a directory to check instead of the repository root.
set -euo pipefail

root="${1:-.}"
cd "$root"
fail=0

# Module name -> allowed imports (space separated). Swift standard modules are always allowed.
allowed_for() {
  case "$1" in
    NopeCore)    echo "Foundation" ;;
    NopeCapture) echo "NopeCore Foundation AVFoundation Photos CoreMedia CoreVideo" ;;
    NopeDevelop) echo "NopeCore Foundation CoreImage ImageIO CoreGraphics UniformTypeIdentifiers" ;;
    NopeSigning) echo "NopeCore Foundation CryptoKit Security C2PA X509 SwiftASN1" ;;
    NopeUI)      echo "NopeCore Foundation SwiftUI" ;;
    *)           echo "*" ;;
  esac
}
always="Swift Observation os"

[[ -d Sources ]] || { echo "architecture checks passed (no Sources yet)"; exit 0; }

while IFS= read -r f; do
  module=$(echo "$f" | cut -d/ -f2)
  allowed=$(allowed_for "$module")
  [[ "$allowed" == "*" ]] && continue
  while IFS= read -r imp; do
    name=$(echo "$imp" | sed -E 's/^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+(struct|class|enum|protocol|func|var|let|typealias)?[[:space:]]*([A-Za-z0-9_]+).*/\3/')
    if ! grep -qw -- "$name" <<<"$allowed $always"; then
      echo "architecture: $f imports $name, which $module may not import"; fail=1
    fi
  done < <(grep -E '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "$f" || true)
done < <(find Sources -name '*.swift' -type f | sort)

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "architecture checks passed"
