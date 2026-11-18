"""Copies Spanish (es) to Latin American Spanish (es-419). Used by sync-es-419.sh: the root, then the catalogs."""
import copy
import json
import os
import sys

OVERRIDES = "scripts/es-419-overrides.txt"

root = sys.argv[1]
listed = set()
overrides_path = os.path.join(root, OVERRIDES)
if os.path.exists(overrides_path):
    with open(overrides_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line and not line.startswith("#"):
                catalog_path, _, key = line.partition("\t")
                listed.add((catalog_path, key))

changed = 0
for path in sys.argv[2:]:
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    catalog = json.loads(text)
    relative = os.path.relpath(path, root)
    before = changed
    for key, entry in catalog.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        if "es" not in localizations:
            continue
        # A listed string keeps its own es-419 wording; it only gets a copy when it has none yet.
        if (relative, key) in listed and "es-419" in localizations:
            continue
        if localizations.get("es-419") != localizations["es"]:
            localizations["es-419"] = copy.deepcopy(localizations["es"])
            entry["localizations"] = dict(sorted(localizations.items()))
            changed += 1
    if changed != before:
        # The layout Xcode writes: two-space indentation, " : " after each key, non-ASCII
        # characters as they are, and no newline at the end.
        output = json.dumps(catalog, indent=2, ensure_ascii=False, separators=(",", " : "))
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(output)
print(f"es-419 synced: {changed} string(s) copied from es")
