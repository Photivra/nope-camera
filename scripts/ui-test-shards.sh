#!/usr/bin/env bash
# The UI tests run in CI as shards (docs/TESTING.md, "UI test shards"). Each test is listed in
# scripts/ui-test-shards.txt with the shard it runs in; the shards are balanced by test time on
# the CI runner. scripts/run-ui-test-shard.sh runs one shard.
#
#   scripts/ui-test-shards.sh check [root]      every UI test is in exactly one shard, every
#                                               listed test exists, the shards are 1…n, and
#                                               build.yml's shard matrices run shards 1…n
#   (each line of the list: shard, Class/test, seconds on the CI runner, "est" when estimated;
#   # starts a comment)
#   scripts/ui-test-shards.sh args <n> [root]   the xcodebuild -only-testing arguments of shard n
#                                               (after the check)
#
# Tests are found in App/NopeAppUITests/*.swift: each `func test…(` belongs to the last
# `class … : XCTestCase` or `extension …` declared above it in its file.
set -euo pipefail

usage() { echo "usage: $0 check [root] | args <shard> [root]" >&2; exit 2; }

mode=${1:-}
case $mode in
  check) root=${2:-.} ;;
  args) shard=${2:-}; [[ $shard =~ ^[1-9][0-9]*$ ]] || usage; root=${3:-.} ;;
  *) usage ;;
esac

target=NopeAppUITests
tests_dir="$root/App/$target"
list="$root/scripts/ui-test-shards.txt"
[[ -d $tests_dir ]] || { echo "error: $tests_dir not found" >&2; exit 1; }
[[ -f $list ]] || { echo "error: $list not found" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Class/test for every test method in the sources.
for file in "$tests_dir"/*.swift; do
  awk '
    /^[[:space:]]*\/\// { next }
    match($0, /^(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
      n = split(substr($0, RSTART, RLENGTH), w, /[[:space:]]+/); cls = w[n]; next
    }
    match($0, /^extension[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
      n = split(substr($0, RSTART, RLENGTH), w, /[[:space:]]+/); cls = w[n]; next
    }
    match($0, /^[[:space:]]+func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(/) {
      name = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]+func[[:space:]]+/, "", name); sub(/[[:space:]]*\($/, "", name)
      if (cls == "") { print "error: " FILENAME ": " name " is outside a class" > "/dev/stderr"; exit 1 }
      print cls "/" name
    }
  ' "$file"
done | sort >"$work/found"

# "<shard> Class/test" lines from the list, without comments and blank lines.
{ grep -vE '^[[:space:]]*(#|$)' "$list" || true; } | awk '{ print $1, $2 }' >"$work/listed"

errors=0
fail() { echo "error: $*" >&2; errors=$((errors + 1)); }

while read -r number name; do
  [[ $number =~ ^[1-9][0-9]*$ && -n $name ]] || fail "bad line in ui-test-shards.txt: $number $name"
done <"$work/listed"

awk '{ print $2 }' "$work/listed" | sort >"$work/names"
while read -r name; do fail "$name is listed more than once"; done < <(uniq -d "$work/names")
while read -r name; do fail "$name is in no shard: add it to scripts/ui-test-shards.txt"; done < <(comm -23 "$work/found" <(sort -u "$work/names"))
while read -r name; do fail "$name is listed but not found in App/$target"; done < <(comm -13 "$work/found" <(sort -u "$work/names"))

shards=$(awk '{ print $1 }' "$work/listed" | sort -n | uniq)
count=$(printf '%s\n' "$shards" | tail -1)
[[ $shards == "$(seq 1 "${count:-0}")" ]] || fail "the shards must be numbered 1 to n without gaps"

# The workflow's shard matrices run the same shards.
workflow="$root/.github/workflows/build.yml"
if [[ -f $workflow && -n ${count:-} ]]; then
  matrix="[$(seq 1 "$count" | paste -sd, - | sed 's/,/, /g')]"
  while read -r line; do
    [[ $line == "shard: $matrix" ]] || fail "build.yml runs '$line', but ui-test-shards.txt has shards $matrix"
  done < <(grep -E '^[[:space:]]+shard:' "$workflow" | sed -E 's/^[[:space:]]+//')
  while read -r line; do
    [[ $line == *"}}/$count" ]] || fail "build.yml names a shard job '$line', but there are $count shards"
  done < <(grep -E '^    name:.*matrix\.shard' "$workflow" | sed -E 's/^[[:space:]]+name:[[:space:]]*//')
fi

if ((errors > 0)); then exit 1; fi

if [[ $mode == check ]]; then
  echo "UI test shards checked: $(wc -l <"$work/found" | tr -d ' ') tests in $count shards"
  exit 0
fi

((shard <= count)) || { echo "error: there are $count shards" >&2; exit 1; }
awk -v s="$shard" -v t="$target" '$1 == s { print "-only-testing:" t "/" $2 }' "$work/listed"
