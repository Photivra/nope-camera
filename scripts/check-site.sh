#!/usr/bin/env bash
# Builds the public site and runs every check of docs/design/nope-site.md, 14.3, on this machine.
# Nothing here calls an outside service: the pages are served on 127.0.0.1, and the only network
# use is installing the pinned tools beforehand (`npm ci --ignore-scripts` in site/).
#
#   scripts/check-site.sh [--preview] [--static-only] [--no-build] [--out DIR]
#
#   --preview      build and check with the policy's draft markers allowed (a [bracketed] item,
#                  "draft"), and its version and dates unchecked while those markers remain.
#                  Every other rule runs. For a local look and for pull requests only; a
#                  publishing run never uses it.
#   --static-only  only the standard-library checks (scripts/site_checks.py): no Chrome or Java.
#   --no-build     check an existing build instead of building first.
#
# Needs: Python 3, Node (site/.nvmrc) with site/node_modules, Google Chrome (or CHROME_PATH) for
# the page-load, axe and Lighthouse checks, and Java 11 or later (or JAVA) for the Nu HTML Checker.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
out="$here/_site"
preview=()
static_only=0
build=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview) preview=(--preview) ;;
    --static-only) static_only=1 ;;
    --no-build) build=0 ;;
    --out) out="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift ;;
    *) echo "usage: scripts/check-site.sh [--preview] [--static-only] [--no-build] [--out DIR]" >&2; exit 2 ;;
  esac
  shift
done

if [[ $build -eq 1 ]]; then
  python3 scripts/build-site.py --out "$out" ${preview[@]+"${preview[@]}"}
fi

echo "== site checks (promises, links, search, truth, size)"
python3 scripts/site_checks.py ${preview[@]+"${preview[@]}"} "$out"
[[ $static_only -eq 1 ]] && exit 0

[[ -d site/node_modules ]] || { echo "site/node_modules is missing: run npm ci --ignore-scripts in site/" >&2; exit 1; }

echo "== HTML validation (Nu HTML Checker)"
java="${JAVA:-java}"
"$java" -jar site/node_modules/vnu-jar/build/dist/vnu.jar --errors-only --skip-non-html "$out"
echo "HTML validation passed"

echo "== page load and accessibility (headless Chrome, axe-core)"
node site/checks/browser-checks.mjs "$out"

echo "== Lighthouse (mobile, median of three runs)"
node site/checks/lighthouse.mjs "$out" 3

echo "all site checks passed${preview[*]:+ (preview: not for publishing)}"
