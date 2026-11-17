#!/usr/bin/env bash
# Tests for scripts/check-localization.sh: each case writes one catalog and checks pass or fail.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-localization.sh"
failures=0

# catalog "<comment>" "<english value>" "<translation>" "<state>" [skip-locale]
# A translation starting with "set:" is an App Shortcuts string set, its phrases separated by "|".
# A translation starting with "plural:" is a set of plural cases, "one=...|other=...".
catalog() {
  python3 -I -c '
import json, sys
comment, english, value, state, skip = sys.argv[1:6]
locales = ["ja","es","fr","de","ko","zh-Hant","zh-Hans","pt-BR","it","nl"]
loc = {"en": {"stringUnit": {"state": "translated", "value": english}}}
for l in locales:
    if l != skip:
        if value.startswith("set:"):  # an App Shortcuts string set: phrases separated by "|"
            loc[l] = {"stringSet": {"state": state, "values": [v for v in value[4:].split("|")]}}
        elif value.startswith("plural:"):  # plural cases: "one=...|other=..."
            cases = dict(case.split("=", 1) for case in value[7:].split("|"))
            loc[l] = {"variations": {"plural": {form: {"stringUnit": {"state": state, "value": text}}
                                                for form, text in cases.items()}}}
        else:
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
expect pass "phrase set needing review" "Siri phrase." "Take a photo" "set:Mach ein Foto|Nimm ein Foto auf" needs_review
expect fail "phrase set with an empty phrase" "Siri phrase." "Take a photo" "set:Mach ein Foto|" needs_review
expect fail "phrase set with no phrases" "Siri phrase." "Take a photo" "set:" needs_review
expect fail "phrase set, new state" "Siri phrase." "Take a photo" "set:Mach ein Foto" new
expect fail "phrase set changes the name" "Siri phrase." "Open nope." "set:nope. öffnen|Nope öffnen" needs_review
expect pass "plural cases needing review" "Count." "%lld Saved" "plural:one=%lld guardado|other=%lld guardados" needs_review
expect fail "plural case with an empty value" "Count." "%lld Saved" "plural:one=%lld guardado|other=" needs_review
expect fail "plural cases, new state" "Count." "%lld Saved" "plural:one=%lld guardado|other=%lld guardados" new
expect fail "plural case changes the name" "Count." "%lld in nope." "plural:one=%lld in nope.|other=%lld in Nope" needs_review

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all localization check tests passed"
