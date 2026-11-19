#!/usr/bin/env bash
# Tests the site's build rules and checks (scripts/build-site.py, scripts/site_checks.py): each
# rule gets a passing and a failing case. Needs site/node_modules for the Tailwind CLI.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/test_check_site.py
