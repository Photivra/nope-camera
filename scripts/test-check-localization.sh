#!/usr/bin/env bash
# Tests for scripts/check-localization.sh: each case writes one catalog and checks pass or fail.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-localization.sh"
failures=0

# catalog "<comment>" "<english value>" "<translation>" "<state>" [skip-locale]
catalog() {
  python3 -I -c '
import json, sys
comment, english, value, state, skip = sys.argv[1:6]
locales = ["ja","es","fr","de","ko","zh-Hant","zh-Hans","pt-BR","it","nl"]
loc = {"en": {"stringUnit": {"state": "translated", "value": english}}}
for l in locales:
    if l != skip:
        loc[l] = {"stringUnit": {"state": state, "value": value}}
print(json.dumps({"sourceLanguage": "en", "version": "1.0",
                  "strings": {"key": {"comment": comment, "localizations": loc}}}))
' "$@"
}

expect() { # expect pass|fail "name" comment english value state [skip]
  local want=$1 name=$2 d got; shift 2
  d=$(mktemp -d); catalog "$1" "$2" "$3" "$4" "${5:-}" >"$d/Localizable.xcstrings"
  if "$check" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

expect pass "complete catalog needing review" "Button title." "Allow" "Erlauben" needs_review
expect pass "human-reviewed translation" "Button title." "Allow" "Erlauben" translated
expect fail "missing translator comment" "" "Allow" "Erlauben" needs_review
expect fail "missing a launch language" "Button title." "Allow" "Erlauben" needs_review ko
expect fail "new, unreviewed state" "Button title." "Allow" "Erlauben" new
expect pass "name kept in translation" "Prompt." "nope. uses the camera." "nope. nutzt die Kamera." needs_review
expect fail "name changed in translation" "Prompt." "nope. uses the camera." "Nope nutzt die Kamera." needs_review

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all localization check tests passed"
