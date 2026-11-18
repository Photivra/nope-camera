#!/usr/bin/env bash
# The UI tests run in CI as shards (docs/TESTING.md, "UI test shards"): fewer, larger jobs on the
# iPhone Simulator and on the iPad Simulator. Each test is listed in scripts/ui-test-shards.txt
# with its iPhone shard and its iPad shard; each device's shards are balanced by the test times
# measured on the CI runner for that device. scripts/run-ui-test-shard.sh runs one shard.
#
#   scripts/ui-test-shards.sh check [root]      every UI test is listed exactly once, every
#                                               listed test exists, each device's shards are
#                                               1…n, and build.yml's shard matrices and job
#                                               names match them
#   (each line of the list: iPhone shard, iPad shard, Class/test, seconds on the runner on
#   iPhone and on iPad, each with an "e" when estimated; # starts a comment)
#   scripts/ui-test-shards.sh args <iphone|ipad> <n> [root]
#                                               the xcodebuild -only-testing arguments of that
#                                               device's shard n (after the check)
#   scripts/ui-test-shards.sh count <iphone|ipad> [root]
#                                               the number of that device's shards
#   scripts/ui-test-shards.sh times [root]      each shard's listed test time in seconds
#
# Tests are found in App/NopeAppUITests/*.swift: each `func test…(` belongs to the last
# `class … : XCTestCase` or `extension …` declared above it in its file.
set -euo pipefail

usage() { echo "usage: $0 check [root] | args <iphone|ipad> <shard> [root] | count <iphone|ipad> [root] | times [root]" >&2; exit 2; }

mode=${1:-}
case $mode in
  check|times) root=${2:-.} ;;
  args) kind=${2:-}; shard=${3:-}; [[ $kind =~ ^(iphone|ipad)$ && $shard =~ ^[1-9][0-9]*$ ]] || usage; root=${4:-.} ;;
  count) kind=${2:-}; [[ $kind =~ ^(iphone|ipad)$ ]] || usage; root=${3:-.} ;;
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

# "<iPhone shard> <iPad shard> Class/test <iPhone seconds> <iPad seconds>" lines from the list,
# without comments and blank lines.
{ grep -vE '^[[:space:]]*(#|$)' "$list" || true; } | awk '{ print $1, $2, $3, $4, $5 }' >"$work/listed"

errors=0
fail() { echo "error: $*" >&2; errors=$((errors + 1)); }

while read -r iphone ipad name iphone_seconds ipad_seconds; do
  [[ $iphone =~ ^[1-9][0-9]*$ && $ipad =~ ^[1-9][0-9]*$ && -n $name
     && $iphone_seconds =~ ^[0-9]+e?$ && $ipad_seconds =~ ^[0-9]+e?$ ]] \
    || fail "bad line in ui-test-shards.txt: $iphone $ipad $name $iphone_seconds $ipad_seconds"
done <"$work/listed"

awk '{ print $3 }' "$work/listed" | sort >"$work/names"
while read -r name; do fail "$name is listed more than once"; done < <(uniq -d "$work/names")
while read -r name; do fail "$name is in no shard: add it to scripts/ui-test-shards.txt"; done < <(comm -23 "$work/found" <(sort -u "$work/names"))
while read -r name; do fail "$name is listed but not found in App/$target"; done < <(comm -13 "$work/found" <(sort -u "$work/names"))

# The number of a device's shards; they must be 1 to n without gaps.
shard_count() { # shard_count <column> <device name>
  local shards count
  shards=$(awk -v c="$1" '{ print $c }' "$work/listed" | sort -n | uniq)
  count=$(printf '%s\n' "$shards" | tail -1)
  [[ $shards == "$(seq 1 "${count:-0}")" ]] || fail "the $2 shards must be numbered 1 to n without gaps"
  echo "${count:-0}"
}
iphone_count=$(shard_count 1 iPhone)
ipad_count=$(shard_count 2 iPad)
# shard_count runs in a subshell, so its failures are counted again here.
for pair in "1 $iphone_count" "2 $ipad_count"; do
  set -- $pair
  [[ $(awk -v c="$1" '{ print $c }' "$work/listed" | sort -n | uniq) == "$(seq 1 "$2")" ]] || errors=$((errors + 1))
done

# The workflow's shard jobs: "name: ui-tests ${{ matrix.shard }}/n" runs the iPhone shards and
# "name: ui-tests-ipad ${{ matrix.shard }}/n" the iPad shards, each with "shard: [1, …, n]".
workflow="$root/.github/workflows/build.yml"
if [[ -f $workflow && $errors -eq 0 ]]; then
  while IFS='|' read -r name matrix; do
    if [[ $name == ui-tests-ipad\ * ]]; then count=$ipad_count device=iPad; else count=$iphone_count device=iPhone; fi
    want="[$(seq 1 "$count" | paste -sd, - | sed 's/,/, /g')]"
    [[ $name == *"}}/$count" ]] || fail "build.yml names a shard job '$name', but there are $count $device shards"
    [[ $matrix == "$want" ]] || fail "build.yml runs shards '$matrix' in '$name', but ui-test-shards.txt has $device shards $want"
  done < <(awk '
    /^    name:.*matrix\.shard/ { name = $0; sub(/^[[:space:]]+name:[[:space:]]*/, "", name) }
    /^[[:space:]]+shard:/ && name != "" { matrix = $0; sub(/^[[:space:]]+shard:[[:space:]]*/, "", matrix); print name "|" matrix; name = "" }
    END { if (name != "") print name "|" }
  ' "$workflow")
fi

if ((errors > 0)); then exit 1; fi

case $mode in
  check)
    echo "UI test shards checked: $(wc -l <"$work/found" | tr -d ' ') tests in $iphone_count iPhone and $ipad_count iPad shards"
    ;;
  count)
    if [[ $kind == ipad ]]; then echo "$ipad_count"; else echo "$iphone_count"; fi
    ;;
  times)
    awk '{ sub(/e$/, "", $4); sub(/e$/, "", $5); iphone[$1] += $4; ipad[$2] += $5 }
      END {
        for (i = 1; i in iphone; i++) printf "iPhone shard %d: %d s (%.0f min)\n", i, iphone[i], iphone[i] / 60
        for (i = 1; i in ipad; i++) printf "iPad shard %d: %d s (%.0f min)\n", i, ipad[i], ipad[i] / 60
      }' "$work/listed"
    ;;
  args)
    if [[ $kind == ipad ]]; then column=2 count=$ipad_count; else column=1 count=$iphone_count; fi
    ((shard <= count)) || { echo "error: there are $count $kind shards" >&2; exit 1; }
    awk -v s="$shard" -v c="$column" -v t="$target" '$c == s { print "-only-testing:" t "/" $3 }' "$work/listed"
    ;;
esac
