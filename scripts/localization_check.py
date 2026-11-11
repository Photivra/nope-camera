"""Checks String Catalogs given as arguments. Used by check-localization.sh."""
import json
import sys

LOCALES = ["en", "ja", "es", "fr", "de", "ko", "zh-Hant", "zh-Hans", "pt-BR", "it", "nl"]
STATES = {"translated", "needs_review"}
NAME = "nope."

failures = []
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        catalog = json.load(handle)
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("shouldTranslate") is False:
            continue
        if not entry.get("comment", "").strip():
            failures.append(f"{path}: '{key}' has no translator comment")
        localizations = entry.get("localizations", {})
        english = localizations.get("en", {}).get("stringUnit", {}).get("value", key)
        for locale in LOCALES:
            unit = localizations.get(locale, {}).get("stringUnit")
            if locale == "en" and unit is None:
                continue  # The key itself is the English text.
            if unit is None or not unit.get("value", "").strip():
                failures.append(f"{path}: '{key}' has no {locale} translation")
                continue
            if unit.get("state") not in STATES:
                failures.append(f"{path}: '{key}' in {locale} has state '{unit.get('state')}'")
            if NAME in english and NAME not in unit["value"]:
                failures.append(f"{path}: '{key}' in {locale} must keep the name '{NAME}' unchanged")

if failures:
    print("\n".join(f"localization: {failure}" for failure in failures))
    sys.exit(1)
print(f"localization checks passed ({len(sys.argv) - 1} catalogs)")
