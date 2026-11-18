"""Checks String Catalogs. Used by check-localization.sh: the root directory, then the catalogs."""
import json
import os
import re
import sys

# The launch languages: English (the development language) and Spanish.
LOCALES = ["en", "es"]
# Latin American Spanish. iOS reads each string from one language's table only and does not fall
# back to "es" for a string missing from "es-419" (it would show the English), so every string
# has an "es-419" value: the "es" value, except for the strings listed in OVERRIDES.
VARIANT = "es-419"
VARIANT_BASE = "es"
OVERRIDES = "scripts/es-419-overrides.txt"
STATES = {"translated", "needs_review"}
NAME = "nope."
# printf-style specifiers ("%@", "%lld", "%1$@") and App Intents parameters ("${lens}").
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(@|lld|ld|d|f)|(\$\{\w+\})")


def variation_units(localization):
    """Every string unit under a localization's variations (plural or device), at any depth."""
    units = []
    for cases in localization.get("variations", {}).values():
        for case in cases.values():
            if "stringUnit" in case:
                units.append(case["stringUnit"])
            units.extend(variation_units(case))
    return units


def placeholders(text):
    """The placeholders of a string, in a fixed order, without their positions."""
    return sorted(first or second for first, second in PLACEHOLDER.findall(text))


def read_overrides(root):
    """The (catalog path, key) pairs listed in the overrides file, or an empty set without one."""
    listed = set()
    path = os.path.join(root, OVERRIDES)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.rstrip("\n")
                if line and not line.startswith("#"):
                    catalog, _, key = line.partition("\t")
                    listed.add((catalog, key))
    return listed


root = sys.argv[1]
overrides = read_overrides(root)
seen_overrides = set()
failures = []
for path in sys.argv[2:]:
    with open(path, encoding="utf-8") as handle:
        catalog = json.load(handle)
    relative = os.path.relpath(path, root)
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("shouldTranslate") is False:
            continue
        if not entry.get("comment", "").strip():
            failures.append(f"{path}: '{key}' has no translator comment")
        localizations = entry.get("localizations", {})
        english = localizations.get("en", {}).get("stringUnit", {}).get("value", key)
        for locale in sorted(set(localizations) - set(LOCALES) - {VARIANT}):
            failures.append(f"{path}: '{key}' has a {locale} translation; only {', '.join(LOCALES + [VARIANT])} ship")
        for locale in LOCALES + [VARIANT]:
            localization = localizations.get(locale, {})
            unit = localization.get("stringUnit")
            # App Shortcuts phrases (AppShortcuts.xcstrings) are string sets: one or more
            # phrases per language, all with the same state.
            string_set = localization.get("stringSet")
            if "variations" in localization:
                # Plural (or device) variations: every case needs a value and a reviewed state.
                units = variation_units(localization)
                if not units or not all(u.get("value", "").strip() for u in units):
                    failures.append(f"{path}: '{key}' has no {locale} translation")
                elif not all(u.get("state") in STATES for u in units):
                    failures.append(f"{path}: '{key}' in {locale} has a variation that is not translated or needs_review")
                elif NAME in english and not all(NAME in u["value"] for u in units):
                    failures.append(f"{path}: '{key}' in {locale} must keep the name '{NAME}' unchanged")
                elif not all(placeholders(u["value"]) == placeholders(english) for u in units):
                    failures.append(f"{path}: '{key}' in {locale} must keep the placeholders of the English")
                continue
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
            # A placeholder that is lost or renamed is never filled in; in a Siri phrase a
            # missing ${applicationName} also stops the phrase from being registered.
            if not all(placeholders(value) == placeholders(english) for value in values):
                failures.append(f"{path}: '{key}' in {locale} must keep the placeholders of the English")
        if VARIANT in localizations and VARIANT_BASE in localizations:
            differs = localizations[VARIANT] != localizations[VARIANT_BASE]
            if (relative, key) in overrides:
                seen_overrides.add((relative, key))
                if not differs:
                    failures.append(f"{path}: '{key}' is listed in {OVERRIDES} but its {VARIANT} equals {VARIANT_BASE}")
            elif differs:
                failures.append(f"{path}: '{key}' in {VARIANT} differs from {VARIANT_BASE} but is not listed in {OVERRIDES}")

for catalog_path, key in sorted(overrides - seen_overrides):
    failures.append(f"{OVERRIDES}: '{key}' is not a string of {catalog_path}")

if failures:
    print("\n".join(f"localization: {failure}" for failure in failures))
    sys.exit(1)
print(f"localization checks passed ({len(sys.argv) - 2} catalogs)")
