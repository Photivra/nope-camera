#!/usr/bin/env bash
# Tests the TIFF walker in scripts/dump-tags.swift against synthetic TIFF files built in memory
# (both byte orders, every pointer IFD, redaction, truncated and corrupt input). macOS only:
# the dumper uses ImageIO. Run from the repository root.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
swift "$here/dump-tags.swift" --self-test
