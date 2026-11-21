#!/usr/bin/env bash
# Tests for scripts/count-design-screens.py: each case builds a small docs/design/screens folder
# in a temporary tree and checks the printed counts, or that the script fails.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
count="$here/scripts/count-design-screens.py"
failures=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A tree with seven screens: three for iPhone (one a PNG without a mockup), two for iPad, one for
# the iPhone Duo and one for Apple Watch; plus a mockup without a PNG and a file that isn't a
# screen. Each PNG is 100 000 bytes, so the seven total 0.7 MB.
tree="$work/repo"
screens="$tree/docs/design/screens"
mkdir -p "$screens"
for name in camera viewer ipadding-camera ipad-camera bracket-ipad-card duo-inner-viewer watch-camera; do
  head -c 100000 /dev/zero >"$screens/$name.png"
  echo "<html></html>" >"$screens/$name.html"
done
rm "$screens/ipadding-camera.html"
echo "<html></html>" >"$screens/drawing-only.html"
echo "notes" >"$screens/README.txt"

expect() { # expect "name" "expected output" [arguments…]
  local name=$1 want=$2 got
  shift 2
  if got=$(python3 -I "$count" --root "$tree" "$@" 2>&1) && [[ $got == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"; echo "  expected: $want"; echo "  got:      $got"; failures=$((failures + 1))
  fi
}

expect_failure() { # expect_failure "name" [arguments…]
  local name=$1
  shift
  if python3 -I "$count" "$@" >/dev/null 2>&1; then
    echo "FAIL $name (expected the script to fail)"; failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

expect "every PNG is one screen, by the device in its name" \
  "7 screens: 3 iPhone, 2 iPad, 1 iPhone Duo, 1 Apple Watch
PNG files: 0.7 MB"
expect "a set left out" \
  "5 screens: 3 iPhone, 1 iPad, 1 iPhone Duo, 0 Apple Watch
PNG files: 0.5 MB" --leave-out watch- --leave-out bracket-
expect "only one set" \
  "2 screens: 0 iPhone, 1 iPad, 0 iPhone Duo, 1 Apple Watch
PNG files: 0.2 MB" --only watch- --only bracket-
expect "only one set, less a part of it" \
  "1 screen: 0 iPhone, 0 iPad, 0 iPhone Duo, 1 Apple Watch
PNG files: 0.1 MB" --only watch- --only bracket- --leave-out bracket-ipad-
expect "a prefix that matches nothing" \
  "0 screens: 0 iPhone, 0 iPad, 0 iPhone Duo, 0 Apple Watch
PNG files: 0.0 MB" --only nothing-
expect_failure "no screens folder" --root "$work/missing"
expect_failure "an empty prefix" --root "$tree" --leave-out ""

# The repository's own set: the script runs and counts at least one screen.
if got=$(python3 -I "$count" 2>&1) && [[ $got =~ ^[1-9][0-9]*\ screens: ]]; then
  echo "ok   the repository's screens"
else
  echo "FAIL the repository's screens: $got"; failures=$((failures + 1))
fi

if [[ $failures -ne 0 ]]; then echo "$failures design screen count test(s) failed"; exit 1; fi
echo "all design screen count tests passed"
