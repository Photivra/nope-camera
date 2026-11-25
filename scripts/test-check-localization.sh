#!/usr/bin/env bash
# Tests for scripts/check-localization.sh: each case writes one catalog and checks pass or fail.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-localization.sh"
failures=0

# catalog "<comment>" "<english value>" "<state>" [extra-locale]
# An empty English value leaves the entry without one: the key is the English text.
# A value starting with "set:" is an App Shortcuts string set, its phrases separated by "|".
# A value starting with "plural:" is a set of plural cases, "one=...|other=...".
# An extra locale gets a copy of the English value, as a translation that must not be there.
catalog() {
  python3 -I -c '
import json, sys
comment, value, state, extra = sys.argv[1:5]
def localization(value):
    if value.startswith("set:"):  # an App Shortcuts string set: phrases separated by "|"
        return {"stringSet": {"state": state, "values": [v for v in value[4:].split("|")]}}
    if value.startswith("plural:"):  # plural cases: "one=...|other=..."
        cases = dict(case.split("=", 1) for case in value[7:].split("|"))
        return {"variations": {"plural": {form: {"stringUnit": {"state": state, "value": text}}
                                          for form, text in cases.items()}}}
    return {"stringUnit": {"state": state, "value": value}}
loc = {}
if value:
    loc["en"] = localization(value)
if extra:
    loc[extra] = localization(value or "Text")
entry = {"comment": comment}
if loc:
    entry["localizations"] = loc
print(json.dumps({"sourceLanguage": "en", "version": "1.0", "strings": {"key": entry}}))
' "$@"
}

expect() { # expect pass|fail "name" comment english state [extra-locale]
  local want=$1 name=$2 d got; shift 2
  d=$(mktemp -d); catalog "$1" "$2" "$3" "${4:-}" >"$d/Localizable.xcstrings"
  if "$check" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

expect pass "key is the English text" "Button title." "" translated
expect pass "English value that differs from the key" "Button title." "Allow" translated
expect pass "English value needing review" "Button title." "Allow" needs_review
expect fail "missing translator comment" "" "Allow" translated
expect fail "missing translator comment, key only" "" "" translated
expect fail "a language that does not ship" "Button title." "Allow" translated es
expect fail "a language that does not ship, key only" "Button title." "" translated de
expect fail "new, unreviewed state" "Button title." "Allow" new
expect fail "blank English value" "Button title." " " translated
expect pass "phrase set" "Siri phrase." "set:Take a photo|Take a picture" translated
expect fail "phrase set with an empty phrase" "Siri phrase." "set:Take a photo|" translated
expect fail "phrase set with no phrases" "Siri phrase." "set:" translated
expect fail "phrase set, new state" "Siri phrase." "set:Take a photo" new
expect pass "plural cases" "Count." "plural:one=%lld Photo|other=%lld Photos" translated
expect fail "plural case with an empty value" "Count." "plural:one=%lld Photo|other=" translated
expect fail "plural cases, new state" "Count." "plural:one=%lld Photo|other=%lld Photos" new

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all localization check tests passed"
