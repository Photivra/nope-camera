"""Reads `llvm-cov export -summary-only` JSON on stdin and enforces 100% coverage.

Arguments: the repository root, then the module names to check. Used by check-coverage.sh.
"""
import json
import os
import sys

root, modules = sys.argv[1], sys.argv[2:]
with open(os.path.join(root, "scripts/coverage-exclusions.txt"), encoding="utf-8") as handle:
    excluded = {line.strip() for line in handle if line.strip() and not line.startswith("#")}

failures = []
for path in sorted(excluded):
    if not os.path.isfile(os.path.join(root, path)):
        failures.append(f"exclusion lists a missing file: {path}")

totals = {module: [0, 0, 0, 0] for module in modules}
reported = set()
for entry in json.load(sys.stdin)["data"][0]["files"]:
    path = os.path.relpath(os.path.realpath(entry["filename"]), os.path.realpath(root))
    parts = path.split(os.sep)
    if len(parts) < 3 or parts[0] != "Sources" or parts[1] not in modules:
        continue
    reported.add(path)
    if path in excluded:
        print(f"excluded  {path}")
        continue
    summary = entry["summary"]
    lines, regions, branches = summary["lines"], summary["regions"], summary["branches"]
    total = totals[parts[1]]
    total[0] += lines["covered"]; total[1] += lines["count"]
    total[2] += regions["covered"]; total[3] += regions["count"]
    for name, item in (("lines", lines), ("regions", regions), ("branches", branches)):
        if item["covered"] < item["count"]:
            failures.append(f"{path}: {item['covered']}/{item['count']} {name} covered")

for module in modules:
    for dirpath, _, names in os.walk(os.path.join(root, "Sources", module)):
        for name in names:
            path = os.path.relpath(os.path.join(dirpath, name), root)
            if name.endswith(".swift") and path not in reported and path not in excluded:
                print(f"no code   {path} (declarations only)")

for module, (lc, lt, rc, rt) in totals.items():
    print(f"{module}: lines {lc}/{lt}, regions (branch arms) {rc}/{rt}")

if failures:
    print("\n".join(f"coverage: {failure}" for failure in failures))
    sys.exit(1)
print("coverage checks passed: 100% of lines and regions")
