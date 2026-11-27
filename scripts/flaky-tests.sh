#!/usr/bin/env bash
# Lists UI tests that both passed and failed in recent CI runs, from the per-test result files
# the UI test jobs upload (test-results-* artifacts, JSON Lines; docs/TESTING.md, "Flaky tests"):
#
#   scripts/flaky-tests.sh [-n <runs>] [-R <owner/repo>] [-b <branch>]
#       downloads the result artifacts of the last <runs> runs of the build workflow (default
#       20) with gh, which must be signed in, and reports on them
#   scripts/flaky-tests.sh --from <directory>
#       reports on the .jsonl files under a directory instead (already downloaded results)
#
# It prints four lists, each with counts: tests that were run once more after failing in a job
# (flaky when the retry passed; one retried in two or more runs needs an issue, docs/TESTING.md,
# "Flaky tests"), tests that passed and failed on the same commit (the test changed its result
# without the code changing), tests that passed and failed across the commits looked at, and
# tests that passed only in the second run after an infrastructure failure. A test's result in
# a job is its last attempt's; a test cut short by a dying Simulator and not run again
# ("interrupted") is counted apart from a failure.
set -euo pipefail

runs=20 repo= branch= from=
while [[ $# -gt 0 ]]; do
  case $1 in
    -n) runs=${2:?}; shift 2 ;;
    -R) repo=${2:?}; shift 2 ;;
    -b) branch=${2:?}; shift 2 ;;
    --from) from=${2:?}; shift 2 ;;
    *) echo "usage: $0 [-n <runs>] [-R <owner/repo>] [-b <branch>] | --from <directory>" >&2; exit 2 ;;
  esac
done

if [[ -z $from ]]; then
  command -v gh >/dev/null || { echo "error: gh is not installed" >&2; exit 1; }
  from=$(mktemp -d)
  trap 'rm -rf "$from"' EXIT
  list=(gh run list --workflow build.yml --limit "$runs" --json databaseId --jq '.[].databaseId')
  [[ -z $repo ]] || list+=(-R "$repo")
  [[ -z $branch ]] || list+=(--branch "$branch")
  while read -r id; do
    download=(gh run download "$id" --pattern 'test-results-*' --dir "$from/$id")
    [[ -z $repo ]] || download+=(-R "$repo")
    # A run without result artifacts (older, or still running) is left out.
    "${download[@]}" >/dev/null 2>&1 || true
  done < <("${list[@]}")
fi
[[ -d $from ]] || { echo "error: $from not found" >&2; exit 1; }

python3 - "$from" <<'PY'
import collections, json, pathlib, sys

rows = []
for path in sorted(pathlib.Path(sys.argv[1]).rglob("*.jsonl")):
    for line in path.read_text().splitlines():
        if line.strip():
            rows.append(json.loads(line))
if not rows:
    print("No per-test results found.")
    sys.exit()

# A test's result in one job of one run is its last attempt's.
final = {}
for row in sorted(rows, key=lambda r: r.get("attempt", 1)):
    final[(row.get("run_id"), row.get("run_attempt"), row.get("job"), row["test"])] = row

def device(row):
    job = row.get("job", "")
    return "iPad" if job.startswith("ui-tests-ipad") else "watch" if job.startswith("ui-tests-watch") else "iPhone"

by_commit = collections.defaultdict(collections.Counter)
overall = collections.defaultdict(collections.Counter)
commits, run_ids = set(), set()
for row in final.values():
    key = (row["test"], device(row))
    result = row["result"]
    # A second run after an infrastructure failure; older files have no retry field.
    if result == "passed" and row.get("attempt", 1) > 1 and row.get("retry", "infrastructure") == "infrastructure":
        overall[key]["passed on attempt 2"] += 1
    by_commit[key + (row.get("sha", ""),)][result] += 1
    overall[key][result] += 1
    commits.add(row.get("sha", "")); run_ids.add(row.get("run_id"))

def bad(counter):
    return counter["failed"] + counter["interrupted"]

def counts(counter):
    parts = [f"{counter[name]} {name}" for name in ("passed", "failed", "interrupted", "passed on attempt 2") if counter[name]]
    return ", ".join(parts)

# Tests run once more after a test failure, counted per run.
retried = collections.defaultdict(lambda: {"runs": set(), "passed": 0, "failed": 0})
for row in rows:
    if row.get("retry") == "test-failure":
        entry = retried[(row["test"], device(row))]
        entry["runs"].add(row.get("run_id"))
        entry["passed" if row["result"] == "passed" else "failed"] += 1

print(f"{len(final)} results of {len(overall)} tests from {len(run_ids)} run(s) on {len(commits)} commit(s)")
print()
print("Run once more after a test failure (flaky when the retry passed):")
for (test, kind), entry in sorted(retried.items(), key=lambda item: (-len(item[1]["runs"]), item[0])):
    parts = [f"{entry[name]} {label}" for name, label in (("passed", "passed on the retry"), ("failed", "failed on the retry too")) if entry[name]]
    issue = "; retried in 2 or more runs: needs an issue" if len(entry["runs"]) >= 2 else ""
    print(f"  {test} ({kind}): {len(entry['runs'])} run(s), {', '.join(parts)}{issue}")
if not retried:
    print("  none")
print()
print("Passed and failed on the same commit:")
same = sorted(((bad(c), key) for key, c in by_commit.items() if c["passed"] and bad(c)), reverse=True)
for _, (test, kind, sha) in same:
    print(f"  {test} ({kind}) at {sha[:7]}: {counts(by_commit[(test, kind, sha)])}")
if not same:
    print("  none")
print()
print("Passed and failed across these commits:")
across = sorted(((bad(c), key) for key, c in overall.items() if c["passed"] and bad(c)), reverse=True)
for _, (test, kind) in across:
    print(f"  {test} ({kind}): {counts(overall[(test, kind)])}")
if not across:
    print("  none")
print()
print("Passed only in the second run after an infrastructure failure:")
second = sorted(((c["passed on attempt 2"], key) for key, c in overall.items() if c["passed on attempt 2"]), reverse=True)
for count, (test, kind) in second:
    print(f"  {test} ({kind}): {count} time(s)")
if not second:
    print("  none")
PY
