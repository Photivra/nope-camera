#!/usr/bin/env bash
# Tests for scripts/check-security.sh: each case builds a small tree and checks pass or fail.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
check="$here/scripts/check-security.sh"
failures=0

new_tree() {
  local d; d=$(mktemp -d)
  cp -R "$here/security" "$d/security"
  echo "$d"
}

expect() { # expect pass|fail "name" dir
  local want=$1 name=$2 dir=$3 got
  if "$check" "$dir" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$dir"
}

d=$(new_tree); mkdir -p "$d/App"; printf 'import SwiftUI\nstruct A {}\n' >"$d/App/A.swift"
expect pass "clean Swift source" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let s = URLSession.shared\n' >"$d/App/A.swift"
expect fail "URLSession is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import WebKit\n' >"$d/App/A.swift"
expect fail "WebKit is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import AdjustSdk\n' >"$d/App/A.swift"
expect fail "Adjust SDK import is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'Adjust.trackEvent(event)\n' >"$d/App/A.swift"
expect fail "Adjust SDK call is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import Segment\n' >"$d/App/A.swift"
expect fail "Segment SDK import is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let busy = device.isAdjustingExposure || device.isAdjustingFocus\nlet t = AVSemanticSegmentationMatte.MatteType.hair\n' >"$d/App/A.swift"
expect pass "camera APIs containing Adjust or Segment are allowed" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'print("exif")\n' >"$d/App/A.swift"
expect fail "print is banned in app code" "$d"

d=$(new_tree); mkdir -p "$d/AppTests"; printf 'print("ok in tests")\n' >"$d/AppTests/T.swift"
expect pass "print is allowed in tests" "$d"

d=$(new_tree); mkdir -p "$d/android"; printf '<uses-permission android:name="android.permission.INTERNET"/>\n' >"$d/android/AndroidManifest.xml"
expect fail "Android INTERNET permission is banned" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nimport SwiftUI\nenum Tool {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect pass "Debug tool wrapped in #if DEBUG" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf 'import SwiftUI\nenum Tool {}\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool without #if DEBUG" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum Tool {}\n#endif\nenum Leak {}\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with code after #endif" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#else\nenum Leak {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with #else in the #if DEBUG block" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#elseif !DEBUG\nenum Leak {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with #elseif in the #if DEBUG block" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#endif\nenum Leak {}\n#if DEBUG\nenum B {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with code between two #if DEBUG blocks" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '// A comment\n#if DEBUG\nenum A {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with a line before #if DEBUG" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool whose #if DEBUG block isn't closed" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nimport SwiftUI\n  #if os(iOS)\nenum A {}\n  #elseif os(watchOS)\nenum B {}\n  #else\nenum C {}\n  #endif\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect pass "Debug tool with nested conditions inside #if DEBUG" "$d"

# Debug tool bypasses: a directive followed by a comment or a parenthesis, and directives
# hidden in a block comment or a multi-line string. Each compiles `Leak` into Release.
d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#else//x\nenum Leak {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with #else followed by a line comment" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#else/**/\nenum Leak {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with #else followed by a block comment" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#elseif(!DEBUG)\nenum Leak {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with #elseif( in the #if DEBUG block" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\n/*\n#if X\n*/\nenum A {}\n#else\nenum Leak {}\n/*\n#endif\n*/\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with directives inside block comments" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nlet s = """\n#if X\n"""\n#else\nenum Leak {}\nlet t = """\n#endif\n"""\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "Debug tool with directives inside multi-line strings" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n  #if os(iOS)\nenum B {}\n  #endif // os\n#endif // DEBUG\n' >"$d/App/DebugTools/Tool.swift"
expect pass "Debug tool with #if( and #endif followed by comments" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n' >"$d/App/DebugTools/Tool.swift"
out=$("$check" "$d" 2>&1 || true); rm -rf "$d"
if [[ $(grep -c 'not closed' <<<"$out") == 1 ]]; then echo "ok   unclosed block reported once"; else echo "FAIL unclosed block reported once"; failures=$((failures + 1)); fi

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nenum A {}\n#else\nenum Leak {}\n#endif\n' >"$d/App/DebugTools/Tool.swift"
out=$("$check" "$d" 2>&1 || true); rm -rf "$d"
if grep -q '#else in the' <<<"$out" && ! grep -q 'not closed' <<<"$out"; then echo "ok   a stop at a line adds no end-of-file message"; else echo "FAIL a stop at a line adds no end-of-file message"; failures=$((failures + 1)); fi

# Debug launch arguments: 16 bytes or more, so the Release binary search can find them.
d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nlet a = "-NopeArmDebugRun"\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect pass "a 16-byte launch argument" "$d"

d=$(new_tree); mkdir -p "$d/App/DebugTools"; printf '#if DEBUG\nlet a = "-NopeProbeFront"\n#endif\n' >"$d/App/DebugTools/Tool.swift"
expect fail "a 15-byte launch argument" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let ok = args.contains("-NopeSimulatedPhone") || args.contains("-NopeTagCheck")\n' >"$d/App/A.swift"
expect fail "a short launch argument outside DebugTools, after a long one" "$d"

d=$(new_tree); mkdir -p "$d/AppUITests"; printf 'app.launchArguments = ["-NopeShort"]\n' >"$d/AppUITests/T.swift"
expect pass "launch arguments in tests aren't checked" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import StoreKit\n' >"$d/App/A.swift"
expect fail "StoreKit import is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import  StoreKit\n' >"$d/App/A.swift"
expect fail "StoreKit import with two spaces is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import struct StoreKit.SKOverlay\n' >"$d/App/A.swift"
expect fail "import struct from StoreKit is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import class StoreKit.SKStoreProductViewController\n' >"$d/App/A.swift"
expect fail "import class from StoreKit is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '@preconcurrency import StoreKit\n' >"$d/App/A.swift"
expect fail "@preconcurrency StoreKit import is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let a: RequestReviewAction? = nil\n' >"$d/App/A.swift"
expect fail "RequestReviewAction is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '#import <StoreKit/StoreKit.h>\n' >"$d/App/A.m"
expect fail "the StoreKit Objective-C header is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '#if canImport(StoreKit)\nenum A {}\n#endif\n' >"$d/App/A.swift"
expect fail "canImport(StoreKit) is banned" "$d"


d=$(new_tree); mkdir -p "$d/App"; printf '@Environment(\\.requestReview) private var requestReview\n' >"$d/App/A.swift"
expect fail "requestReview is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'SKStoreReviewController.requestReview()\n' >"$d/App/A.swift"
expect fail "SKStoreReviewController is banned" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '/// The app uses no StoreKit review request; Rate or Review is a plain link.\nimport SwiftUI\n' >"$d/App/A.swift"
expect pass "a comment naming StoreKit is allowed" "$d"

d=$(new_tree); mkdir -p "$d/AppTests"; printf 'import StoreKit\n' >"$d/AppTests/T.swift"
expect pass "StoreKit is allowed in tests" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let p: UnsafeRawPointer? = nil\n' >"$d/App/B.swift"
expect fail "Unsafe pointer outside the allowlist" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let p: UnsafeRawPointer? = nil\n' >"$d/App/B.swift"; echo "App/B.swift" >>"$d/security/allowed-unsafe.txt"
expect pass "Unsafe pointer in an allowlisted file" "$d"

d=$(new_tree); printf '{"pins":[{"identity":"c2pa-swift"}]}\n' >"$d/Package.resolved"
expect pass "allowlisted dependency" "$d"

d=$(new_tree); printf '{"pins":[{"identity":"c2pa-swift"},{"identity":"swift-certificates"},{"identity":"swift-asn1"},{"identity":"swift-crypto"}]}\n' >"$d/Package.resolved"
expect pass "C2PA with its Apple dependencies" "$d"

d=$(new_tree); printf '{"pins":[{"identity":"c2pa-swift"},{"identity":"some-analytics"}]}\n' >"$d/Package.resolved"
expect fail "dependency not on the allowlist" "$d"

d=$(new_tree); printf '<plist><dict><key>com.apple.developer.locked-camera-capture</key><true/></dict></plist>\n' >"$d/App.entitlements"
expect pass "allowlisted entitlement" "$d"

d=$(new_tree); printf '<plist><dict><key>com.apple.developer.networking.wifi-info</key><true/></dict></plist>\n' >"$d/App.entitlements"
expect fail "entitlement not on the allowlist" "$d"

d=$(new_tree); mkdir -p "$d/App.xcodeproj"
expect fail "Xcode project without a privacy manifest" "$d"

d=$(new_tree); mkdir -p "$d/App.xcodeproj"; printf '<plist><dict>\n<key>NSPrivacyTracking</key>\n<false/>\n<key>NSPrivacyTrackingDomains</key><array/>\n</dict></plist>\n' >"$d/PrivacyInfo.xcprivacy"
expect pass "privacy manifest with no tracking" "$d"

d=$(new_tree); mkdir -p "$d/App.xcodeproj"; printf '<plist><dict><key>NSPrivacyTracking</key><true/></dict></plist>\n' >"$d/PrivacyInfo.xcprivacy"
expect fail "privacy manifest declaring tracking" "$d"

d=$(new_tree); mkdir -p "$d/App.xcodeproj"; printf '<plist><dict><key>NSPrivacyTracking</key><false/><key>NSPrivacyTrackingDomains</key><array><string>t.example</string></array></dict></plist>\n' >"$d/PrivacyInfo.xcprivacy"
expect fail "privacy manifest listing a tracking domain" "$d"

# Assistant entry points (issue #82).
gated='struct TakePhotoIntent: AppIntent {\n    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication\n    func perform() async throws -> some IntentResult & ReturnsValue<Int> {\n        let a = await gate.answer(.takePhoto) {}\n    }\n}\n'
d=$(new_tree); mkdir -p "$d/App"; printf "$gated" >"$d/App/I.swift"
expect pass "a listed gated intent that runs the check and requires an unlock" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct SneakyIntent: AppIntent {\n    func perform() async throws -> some IntentResult { .result() }\n}\n' >"$d/App/I.swift"
expect fail "an intent not listed in assistant-entry-points.txt" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct TakePhotoIntent: AppIntent {\n    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication\n    func perform() async throws -> some IntentResult { await inbox.submit(.x) }\n}\n' >"$d/App/I.swift"
expect fail "a gated intent that skips the check" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct TakePhotoIntent: AppIntent {\n    func perform() async throws -> some IntentResult { await gate.answer(.takePhoto) {} }\n}\n' >"$d/App/I.swift"
expect fail "a gated intent without the unlock requirement" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct PhotoEntity: AppEntity {\n    let id: String\n}\n' >"$d/App/E.swift"
expect fail "an entity not listed" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct Sneaky {}\nextension Sneaky: AppIntent {\n    func perform() async throws -> some IntentResult { .result() }\n}\n' >"$d/App/I.swift"
expect fail "an intent declared in an extension and not listed" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct TakePhotoIntent {}\nextension TakePhotoIntent: AppIntent {\n    func perform() async throws -> some IntentResult { await inbox.submit(.x) }\n}\n' >"$d/App/I.swift"
expect fail "a gated intent declared in an extension that skips the check" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct TakePhotoIntent {}\nextension TakePhotoIntent: AppIntent {\n    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication\n    func perform() async throws -> some IntentResult & ReturnsValue<Int> {\n        let a = await gate.answer(.takePhoto) {}\n    }\n}\n' >"$d/App/I.swift"
expect pass "a listed gated intent declared in an extension" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'struct OpenCameraIntent: CameraCaptureIntent {\n    func perform() async throws -> some IntentResult { .result() }\n}\n' >"$d/App/I.swift"
expect pass "an intent that only opens a screen needs no check" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {}\n' >"$d/App/R.swift"
expect fail "an intent result that returns a file" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'let activity = NSUserActivity(activityType: "a")\n' >"$d/App/U.swift"
expect fail "a user activity" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf 'import CoreSpotlight\n' >"$d/App/S.swift"
expect fail "search indexing" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '.onOpenURL { _ in }\n' >"$d/App/L.swift"
expect fail "a URL handler" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '<key>CFBundleURLTypes</key>\n' >"$d/App/Info.plist"
expect fail "a URL scheme" "$d"

d=$(new_tree); mkdir -p "$d/App"; printf '@AppIntent(schema: .camera.startCapture)\nstruct S {}\n' >"$d/App/A.swift"
expect fail "an assistant schema" "$d"

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all security check tests passed"
