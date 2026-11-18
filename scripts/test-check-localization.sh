#!/usr/bin/env bash
# Tests for scripts/check-localization.sh: each case writes one catalog and checks pass or fail.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-localization.sh"
failures=0

# catalog "<comment>" "<english value>" "<translation>" "<state>" [option]
# The translation is written as Spanish (es) and as Latin American Spanish (es-419).
# A translation starting with "set:" is an App Shortcuts string set, its phrases separated by "|".
# A translation starting with "plural:" is a set of plural cases, "one=...|other=...".
# Options: "skip:<locale>" leaves a language out; "extra:<locale>" adds another language;
# "variant:<text>" gives es-419 its own text.
catalog() {
  python3 -I -c '
import json, sys
comment, english, value, state, option = sys.argv[1:6]
def localization(value):
    if value.startswith("set:"):  # an App Shortcuts string set: phrases separated by "|"
        return {"stringSet": {"state": state, "values": [v for v in value[4:].split("|")]}}
    if value.startswith("plural:"):  # plural cases: "one=...|other=..."
        cases = dict(case.split("=", 1) for case in value[7:].split("|"))
        return {"variations": {"plural": {form: {"stringUnit": {"state": state, "value": text}}
                                          for form, text in cases.items()}}}
    return {"stringUnit": {"state": state, "value": value}}
kind, _, argument = option.partition(":")
loc = {"en": {"stringUnit": {"state": "translated", "value": english}}}
for l in ["es", "es-419"] + ([argument] if kind == "extra" else []):
    if not (kind == "skip" and l == argument):
        loc[l] = localization(argument if kind == "variant" and l == "es-419" else value)
print(json.dumps({"sourceLanguage": "en", "version": "1.0",
                  "strings": {"key": {"comment": comment, "localizations": loc}}}))
' "$@"
}

# expect pass|fail "name" comment english value state [option] [overrides line]
# The overrides line, if any, is written to scripts/es-419-overrides.txt under the checked directory.
expect() {
  local want=$1 name=$2 d got; shift 2
  d=$(mktemp -d); catalog "$1" "$2" "$3" "$4" "${5:-}" >"$d/Localizable.xcstrings"
  if [[ -n ${6:-} ]]; then mkdir "$d/scripts"; printf '# A reason.\n%b\n' "$6" >"$d/scripts/es-419-overrides.txt"; fi
  if "$check" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

expect pass "complete catalog needing review" "Button title." "Allow" "Permitir" needs_review
expect pass "human-reviewed translation" "Button title." "Allow" "Permitir" translated
expect fail "missing translator comment" "" "Allow" "Permitir" needs_review
expect fail "missing Spanish" "Button title." "Allow" "Permitir" needs_review skip:es
expect fail "missing Latin American Spanish" "Button title." "Allow" "Permitir" needs_review skip:es-419
expect fail "a language that does not ship" "Button title." "Allow" "Permitir" needs_review extra:de
expect fail "new, unreviewed state" "Button title." "Allow" "Permitir" new
expect pass "name kept in translation" "Prompt." "nope. uses the camera." "nope. usa la cámara." needs_review
expect fail "name changed in translation" "Prompt." "nope. uses the camera." "Nope usa la cámara." needs_review
expect pass "placeholders kept, reordered" "Count." "%lld of %@" "%2\$@: %1\$lld" needs_review
expect fail "placeholder lost" "Count." "%lld of %@" "%lld" needs_review
expect fail "placeholder type changed" "Count." "%lld photos" "%@ fotos" needs_review
expect pass "phrase set needing review" "Siri phrase." "Take a photo with \${applicationName}" "set:Toma una foto con \${applicationName}|Saca una foto con \${applicationName}" needs_review
expect fail "phrase set with an empty phrase" "Siri phrase." "Take a photo" "set:Toma una foto|" needs_review
expect fail "phrase set with no phrases" "Siri phrase." "Take a photo" "set:" needs_review
expect fail "phrase set, new state" "Siri phrase." "Take a photo" "set:Toma una foto" new
expect fail "phrase set changes the name" "Siri phrase." "Open nope." "set:Abre nope.|Abre Nope" needs_review
expect fail "phrase without the app name parameter" "Siri phrase." "Take a photo with \${applicationName}" "set:Toma una foto con \${applicationName}|Toma una foto" needs_review
expect fail "phrase with a renamed parameter" "Siri phrase." "Switch to \${lens} in \${applicationName}" "set:Cambia a \${objetivo} en \${applicationName}" needs_review
expect pass "plural cases needing review" "Count." "%lld Saved" "plural:one=%lld guardado|other=%lld guardados" needs_review
expect fail "plural case with an empty value" "Count." "%lld Saved" "plural:one=%lld guardado|other=" needs_review
expect fail "plural cases, new state" "Count." "%lld Saved" "plural:one=%lld guardado|other=%lld guardados" new
expect fail "plural case changes the name" "Count." "%lld in nope." "plural:one=%lld in nope.|other=%lld in Nope" needs_review
expect fail "plural case loses the placeholder" "Count." "%lld Saved" "plural:one=Uno guardado|other=%lld guardados" needs_review
expect pass "listed regional wording" "Button title." "Settings" "Ajustes" needs_review variant:Configuración "Localizable.xcstrings\tkey"
expect fail "regional wording that is not listed" "Button title." "Settings" "Ajustes" needs_review variant:Configuración
expect fail "listed, but the same as Spanish" "Button title." "Settings" "Ajustes" needs_review "" "Localizable.xcstrings\tkey"
expect fail "listed string that does not exist" "Button title." "Settings" "Ajustes" needs_review "" "Localizable.xcstrings\tother key"
expect fail "regional wording changes the name" "Prompt." "Open nope." "Abre nope." needs_review "variant:Abre Nope" "Localizable.xcstrings\tkey"

# scripts/sync-es-419.sh: copies es to es-419, except for listed strings that have their own wording.
sync="$(cd "$(dirname "$0")" && pwd)/sync-es-419.sh"
# expect_sync "name" "<es-419 value after the sync>" option [overrides line]
expect_sync() {
  local name=$1 want=$2 d got; shift 2
  d=$(mktemp -d); catalog "Button title." "Settings" "Ajustes" needs_review "${1:-}" >"$d/Localizable.xcstrings"
  if [[ -n ${2:-} ]]; then mkdir "$d/scripts"; printf '%b\n' "$2" >"$d/scripts/es-419-overrides.txt"; fi
  "$sync" "$d" >/dev/null
  got=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["strings"]["key"]["localizations"]["es-419"]["stringUnit"]["value"])' "$d/Localizable.xcstrings")
  if [[ $got == "$want" ]] && "$check" "$d" >/dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}
expect_sync "sync fills in a missing es-419" "Ajustes" skip:es-419
expect_sync "sync replaces wording that is not listed" "Ajustes" variant:Configuración
expect_sync "sync keeps listed wording" "Configuración" variant:Configuración "Localizable.xcstrings\tkey"

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all localization check tests passed"
