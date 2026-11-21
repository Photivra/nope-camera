#!/usr/bin/env bash
# Tests for scripts/check-architecture.sh: each case builds a small tree and checks pass or fail.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-architecture.sh"
failures=0

case_tree() { # case_tree "want" "name" "path" "content"
  local want=$1 name=$2 path=$3 content=$4 d got
  d=$(mktemp -d); mkdir -p "$d/$(dirname "$path")"; printf '%s\n' "$content" >"$d/$path"
  if "$check" "$d" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

case_tree pass "core imports Foundation" Sources/NopeCore/A.swift "import Foundation"
case_tree fail "core imports SwiftUI" Sources/NopeCore/A.swift "import SwiftUI"
case_tree fail "core imports AVFoundation" Sources/NopeCore/A.swift "import AVFoundation"
case_tree fail "capture imports UIKit" Sources/NopeCapture/A.swift "import UIKit"
case_tree pass "capture imports AVFoundation" Sources/NopeCapture/A.swift "import AVFoundation"
case_tree fail "UI imports AVFoundation" Sources/NopeUI/V.swift "import AVFoundation"
case_tree fail "UI imports the signing module" Sources/NopeUI/V.swift "import NopeSigning"
case_tree pass "UI imports SwiftUI and NopeCore" Sources/NopeUI/V.swift "import SwiftUI
import NopeCore"
case_tree fail "attributed import is checked" Sources/NopeCore/A.swift "@preconcurrency import SwiftUI"
case_tree fail "symbol import is checked" Sources/NopeDevelop/A.swift "import struct SwiftUI.Color"
case_tree pass "signing imports C2PA and CryptoKit" Sources/NopeSigning/S.swift "import C2PA
import CryptoKit"
case_tree pass "signing imports the certificate packages" Sources/NopeSigning/S.swift "import X509
import SwiftASN1"
case_tree fail "signing imports UIKit" Sources/NopeSigning/S.swift "import UIKit"
case_tree pass "app target is unrestricted" Sources/NopeApp/App.swift "import SwiftUI
import AVFoundation"
case_tree fail "core reads Date()" Sources/NopeCore/A.swift "let started = Date()"
case_tree fail "core reads Date.now" Sources/NopeCore/A.swift "let started = Date.now"
case_tree fail "core passes Date.init" Sources/NopeCore/A.swift "let read: () -> Date = Date.init"
case_tree pass "core makes a fixed date" Sources/NopeCore/A.swift "let start = Date(timeIntervalSince1970: 0)"
case_tree pass "core names Date() in a comment" Sources/NopeCore/A.swift "    /// Never Date() here."
case_tree pass "the clock reads Date()" Sources/NopeCore/NopeClock.swift "let read = { Date() }"
case_tree pass "the interface reads Date.now" Sources/NopeUI/V.swift "let shown = Date.now"

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all architecture check tests passed"
