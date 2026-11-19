#!/usr/bin/env bash
# Tests for scripts/check-app-store-id.sh: each case writes a small AboutScreen.swift and checks
# pass or fail.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
check="$here/scripts/check-app-store-id.sh"
failures=0

expect() { # expect pass|fail "name" "declaration"
  local want=$1 name=$2 f got
  f=$(mktemp)
  printf 'struct AboutScreen {\n    %s\n}\n' "$3" >"$f"
  if "$check" "$f" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -f "$f"
}

expect pass "a numeric id" 'nonisolated static let appStoreID: String? = "1234567890"'
expect pass "a numeric id without nonisolated" 'static let appStoreID: String? = "1234567890"'
expect fail "no id" 'nonisolated static let appStoreID: String? = nil'
expect fail "an empty id" 'nonisolated static let appStoreID: String? = ""'
expect fail "an id that isn't digits" 'nonisolated static let appStoreID: String? = "id123"'
expect fail "no declaration" 'static let sourceAddress = "https://example.com"'

if "$check" /nonexistent/AboutScreen.swift >/dev/null 2>&1; then
  echo "FAIL a missing file (expected fail, got pass)"; failures=$((failures + 1))
else
  echo "ok   a missing file"
fi

if [[ $failures -ne 0 ]]; then echo "$failures app store id check test(s) failed"; exit 1; fi
echo "all app store id check tests passed"
