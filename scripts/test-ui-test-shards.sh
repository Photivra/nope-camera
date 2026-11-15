#!/usr/bin/env bash
# Tests for scripts/ui-test-shards.sh: each case builds a small tree and checks pass or fail.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/ui-test-shards.sh"
failures=0

tests='import XCTest

final class FirstUITests: XCTestCase {
    func testOne() {}
    // func testCommentedOut() {}
    private func helper() {}
}

extension FirstUITests {
    @MainActor
    func testTwo() throws {}
}

final class SecondUITests: XCTestCase {
    func testThree() {}
}'

case_tree() { # case_tree "want" "name" "shard list" [mode args…]
  local want=$1 name=$2 shards=$3 d got
  shift 3
  d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts"
  printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
  printf '%s\n' "$shards" >"$d/scripts/ui-test-shards.txt"
  if "$script" "${@:-check}" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

all='# comment
1 FirstUITests/testOne
2 FirstUITests/testTwo

2 SecondUITests/testThree'

case_tree pass "every test in one shard" "$all"
case_tree fail "an empty list" "# no shards yet"
case_tree fail "a test in no shard" "1 FirstUITests/testOne
2 FirstUITests/testTwo"
case_tree fail "a test in two shards" "$all
1 FirstUITests/testTwo"
case_tree fail "a listed test that doesn't exist" "$all
1 FirstUITests/testGone"
case_tree fail "a commented-out test is not a test" "$all
1 FirstUITests/testCommentedOut"
case_tree fail "a test listed under the wrong class" "1 FirstUITests/testOne
2 SecondUITests/testTwo
2 SecondUITests/testThree"
case_tree fail "a gap in the shard numbers" "1 FirstUITests/testOne
3 FirstUITests/testTwo
3 SecondUITests/testThree"
case_tree fail "a bad shard number" "x FirstUITests/testOne
2 FirstUITests/testTwo
2 SecondUITests/testThree"
case_tree pass "arguments of a shard" "$all" args 2
case_tree fail "arguments of a shard that doesn't exist" "$all" args 3

# The workflow's shard matrices and job names must match the number of shards (2 here).
case_workflow() { # case_workflow "want" "name" "workflow"
  local want=$1 name=$2 workflow=$3 d got
  d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts" "$d/.github/workflows"
  printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
  printf '%s\n' "$all" >"$d/scripts/ui-test-shards.txt"
  printf '%s\n' "$workflow" >"$d/.github/workflows/build.yml"
  if "$script" check "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}
case_workflow pass "workflow runs every shard" 'jobs:
  a:
    name: ui-tests ${{ matrix.shard }}/2
    strategy:
      matrix:
        shard: [1, 2]'
case_workflow fail "workflow runs too few shards" 'jobs:
  a:
    name: ui-tests ${{ matrix.shard }}/2
    strategy:
      matrix:
        shard: [1]'
case_workflow fail "workflow job name has the wrong count" 'jobs:
  a:
    name: ui-tests ${{ matrix.shard }}/3
    strategy:
      matrix:
        shard: [1, 2]'

# The arguments name the target, class and test.
d=$(mktemp -d); mkdir -p "$d/App/NopeAppUITests" "$d/scripts"
printf '%s\n' "$tests" >"$d/App/NopeAppUITests/A.swift"
printf '%s\n' "$all" >"$d/scripts/ui-test-shards.txt"
got=$("$script" args 2 "$d" | tr '\n' ' ')
want="-only-testing:NopeAppUITests/FirstUITests/testTwo -only-testing:NopeAppUITests/SecondUITests/testThree "
if [[ $got == "$want" ]]; then echo "ok   argument text"; else echo "FAIL argument text: $got"; failures=$((failures + 1)); fi
rm -rf "$d"

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all UI test shard tests passed"
