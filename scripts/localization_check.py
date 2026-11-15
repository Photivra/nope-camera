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
            localization = localizations.get(locale, {})
            unit = localization.get("stringUnit")
            # App Shortcuts phrases (AppShortcuts.xcstrings) are string sets: one or more
            # phrases per language, all with the same state.
            string_set = localization.get("stringSet")
            if locale == "en" and unit is None and string_set is None:
                continue  # The key itself is the English text.
            values = [unit.get("value", "")] if unit is not None else (string_set or {}).get("values", [])
            state = (unit if unit is not None else string_set or {}).get("state")
            if not values or not all(value.strip() for value in values):
                failures.append(f"{path}: '{key}' has no {locale} translation")
                continue
            if state not in STATES:
                failures.append(f"{path}: '{key}' in {locale} has state '{state}'")
            if NAME in english and not all(NAME in value for value in values):
                failures.append(f"{path}: '{key}' in {locale} must keep the name '{NAME}' unchanged")

if failures:
    print("\n".join(f"localization: {failure}" for failure in failures))
    sys.exit(1)
print(f"localization checks passed ({len(sys.argv) - 1} catalogs)")
