#!/usr/bin/env bash
# Tests for scripts/coverage_gate.py: each case feeds a small llvm-cov summary and checks pass or fail.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
gate="$here/scripts/coverage_gate.py"
failures=0

expect() { # expect pass|fail "name" file lines-covered lines-total regions-covered regions-total
  local want=$1 name=$2 file=$3 d got
  d=$(mktemp -d); mkdir -p "$d/scripts" "$d/Sources/NopeCore"
  cp "$here/scripts/coverage-exclusions.txt" "$d/scripts/"
  mkdir -p "$d/Sources/NopeCapture" "$d/Sources/NopeSigning"
  touch "$d/Sources/NopeCapture/SystemCameraAuthorization.swift" "$d/Sources/NopeSigning/SecureEnclaveSigningKey.swift"
  mkdir -p "$d/$(dirname "$file")"; touch "$d/$file"
  json=$(printf '{"data":[{"files":[{"filename":"%s","summary":{"lines":{"covered":%s,"count":%s},"regions":{"covered":%s,"count":%s},"branches":{"covered":0,"count":0}}}]}]}' \
    "$d/$file" "$4" "$5" "$6" "$7")
  if python3 -I "$gate" "$d" NopeCore NopeCapture NopeSigning <<<"$json" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

expect pass "fully covered file" Sources/NopeCore/A.swift 10 10 4 4
expect fail "uncovered line" Sources/NopeCore/A.swift 9 10 4 4
expect fail "uncovered branch arm" Sources/NopeCore/A.swift 10 10 3 4
expect pass "excluded hardware adapter" Sources/NopeCapture/SystemCameraAuthorization.swift 0 8 0 3
expect pass "UI module is not gated" Sources/NopeUI/V.swift 0 10 0 4

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all coverage gate tests passed"
