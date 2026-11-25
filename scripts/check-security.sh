#!/usr/bin/env bash
# Fast security checks for every pull request (seconds, no build).
# - Banned code: networking, web views, analytics or ads SDKs, unguarded logging,
#   Unsafe pointer APIs outside allowlisted files.
# - Dependency, entitlement and privacy manifest allowlists.
# - Assistant entry points (issue #82): listed, gated, no indexing, links or schemas.
# - Debug tools: every Swift file in a DebugTools folder is one #if DEBUG block, and every
#   "-Nope…" launch argument is at least 16 bytes.
# Run from the repository root. Optional first argument: a directory to check instead.
set -euo pipefail

root="${1:-.}"
cd "$root"
fail=0
report() { echo "security: $1"; fail=1; }

# Source and config files, excluding tests, docs, scripts and this policy folder.
files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then git ls-files; else find . -type f | sed 's|^\./||'; fi |
    grep -E '\.(swift|kt|kts|java|m|mm|h|c|xml|gradle|plist|entitlements|xcprivacy)$' |
    grep -vE '(^|/)(Tests?|[A-Za-z]+Tests|test|androidTest|docs|scripts|security|\.github)/' || true
}

# 1. Banned code. The Adjust and Segment SDK names are matched as whole words, so camera APIs
#    such as isAdjustingExposure and semantic segmentation mattes aren't flagged.
#    StoreKit and the system review prompt are banned too: the app never asks for a rating; its
#    only App Store link is About's Rate or Review (docs/store/STORE-PAGE-PLAN.md, section 12).
#    Any import form (extra spaces, `import struct StoreKit.X`, `@preconcurrency`), the
#    Objective-C header, `canImport(StoreKit)` and `RequestReviewAction` count.
banned='URLSession|NSURLConnection|NWConnection|NWPathMonitor|import Network\b|CFNetwork|CFStream|import WebKit|WKWebView|SFSafariViewController|android\.permission\.INTERNET|java\.net\.|HttpURLConnection|okhttp|retrofit|android\.webkit|Firebase|Crashlytics|Sentry|Amplitude|Mixpanel|\bSegment\b|AppsFlyer|\b(Adjust|AdjustSdk|ADJConfig)\b|GoogleMobileAds|FBSDK|FacebookCore|TelemetryDeck|import[[:space:]]+([a-z]+[[:space:]]+)?StoreKit\b|<StoreKit/|canImport\(StoreKit\)|RequestReviewAction|requestReview|SKStoreReviewController|\bprint\(|\bNSLog\(|\bdebugPrint\('
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if hits=$(grep -nE "$banned" "$f"); then
    while IFS= read -r h; do report "banned API in $f:$h"; done <<<"$hits"
  fi
done < <(files)

# 2. Unsafe pointer APIs only in allowlisted files.
allowed_unsafe=$(grep -vE '^\s*(#|$)' security/allowed-unsafe.txt 2>/dev/null || true)
while IFS= read -r f; do
  [[ "$f" == *.swift && -f "$f" ]] || continue
  if grep -qE '\bUnsafe(Mutable)?(Raw)?(Buffer)?Pointer\b|unsafeBitCast' "$f" && ! grep -qxF "$f" <<<"$allowed_unsafe"; then
    report "Unsafe pointer API in $f (not in security/allowed-unsafe.txt)"
  fi
done < <(files)

# 3. Dependencies: Swift Package.resolved identities must be allowlisted.
allowed_deps=$(grep -vE '^\s*(#|$)' security/allowed-dependencies.txt 2>/dev/null || true)
while IFS= read -r resolved; do
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    grep -qxF "$id" <<<"$allowed_deps" || report "dependency '$id' in $resolved is not in security/allowed-dependencies.txt"
  done < <(grep -oE '"identity"[[:space:]]*:[[:space:]]*"[^"]+"' "$resolved" | sed -E 's/.*"([^"]+)"$/\1/')
done < <(find . -name Package.resolved -not -path './.build/*' 2>/dev/null)

# 4. Entitlements: every key must be allowlisted.
allowed_ent=$(grep -vE '^\s*(#|$)' security/allowed-entitlements.txt 2>/dev/null || true)
while IFS= read -r ent; do
  while IFS= read -r key; do
    grep -qxF "$key" <<<"$allowed_ent" || report "entitlement '$key' in $ent is not in security/allowed-entitlements.txt"
  done < <(grep -oE '<key>[^<]+</key>' "$ent" | sed -E 's|</?key>||g')
done < <(find . -name '*.entitlements' 2>/dev/null)

# 5. Privacy manifest: required once an Xcode project exists; no tracking, no tracking domains.
if find . -name '*.xcodeproj' -maxdepth 3 2>/dev/null | grep -q .; then
  manifests=$(find . -name PrivacyInfo.xcprivacy 2>/dev/null)
  [[ -n "$manifests" ]] || report "no PrivacyInfo.xcprivacy found"
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    tr -d ' \t\n' <"$m" | grep -q '<key>NSPrivacyTracking</key><false/>' || report "$m must declare NSPrivacyTracking false"
    if tr -d ' \t\n' <"$m" | grep -qE '<key>NSPrivacyTrackingDomains</key><array>[^<]*<string>'; then
      report "$m must not list tracking domains"
    fi
  done <<<"$manifests"
fi

# 6. Assistant entry points (issue #82): every App Intent, entity, query, App Shortcuts
#    provider and control is listed in security/assistant-entry-points.txt with its kind; a
#    gated intent's type calls the Assistant Access check (gate.answer) and requires an unlocked
#    device; results carry a sentence and at most a number; no URL scheme, search indexing,
#    donation, user activity or assistant schema exists. A conformance added in an extension
#    (`extension Name: AppIntent`) counts as a declaration of Name; its checks read the
#    extension's body.
entry_list=$(grep -vE '^\s*(#|$)' security/assistant-entry-points.txt 2>/dev/null || true)
entry_protocols='AppIntent|SetValueIntent|LiveActivityIntent|CameraCaptureIntent|AudioPlaybackIntent|ForegroundContinuableIntent|SnippetIntent|AppEntity|IndexedEntity|TransientAppEntity|EntityQuery|EntityStringQuery|EnumerableEntityQuery|EntityPropertyQuery|AppShortcutsProvider|ControlWidget'
entry_banned='NSUserActivity|CoreSpotlight|CSSearchableItem|IndexedEntity|IntentDonationManager|\.donate\(|onOpenURL|CFBundleURLTypes|@AssistantIntent|@AssistantEntity|@AssistantEnum|@AppIntent\(schema|@AppEntity\(schema|@AppEnum\(schema|ShowsSnippetView|OpensIntent|Transferable'
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if hits=$(grep -nE "$entry_banned" "$f" | grep -vE '^[0-9]+:[[:space:]]*//'); then
    while IFS= read -r h; do report "assistant entry point not allowed in $f:$h (docs/design/assistant-access.md, 7.4)"; done <<<"$hits"
  fi
  [[ "$f" == *.swift ]] || continue
  if hits=$(grep -nE 'ReturnsValue<' "$f" | grep -vE 'ReturnsValue<Int>'); then
    while IFS= read -r h; do report "an intent result other than a sentence and a number in $f:$h"; done <<<"$hits"
  fi
  while IFS= read -r decl; do
    [[ -z "$decl" ]] && continue
    line=${decl%%:*}; name=$(sed -E 's/^[0-9]+:[[:space:]]*(public |private |fileprivate |internal )?(final )?(struct|class|enum|actor|extension)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\4/' <<<"$decl")
    kind=$(awk -v n="$name" '$1 == n { print $2 }' <<<"$entry_list")
    if [[ -z "$kind" ]]; then report "$name in $f is not in security/assistant-entry-points.txt"; continue; fi
    if [[ "$kind" == takes-photos || "$kind" == changes ]]; then
      body=$(awk -v start="$line" 'NR >= start { print } NR > start && /^}/ { exit }' "$f")
      grep -q 'gate\.answer(' <<<"$body" || report "$name in $f doesn't run the Assistant Access check (gate.answer) in perform()"
      grep -q 'authenticationPolicy.*\.requiresAuthentication' <<<"$body" || report "$name in $f doesn't require an unlocked device (authenticationPolicy)"
    fi
  done < <(grep -nE "^[[:space:]]*(public |private |fileprivate |internal )?(final )?(struct|class|enum|actor|extension)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[^{]*\b($entry_protocols)\b" "$f" || true)
done < <(files)

# 7. Debug tools (UI-test scenarios, the simulated viewfinder still, the tag check): every Swift
#    file in a DebugTools folder is one `#if DEBUG` block, so none of it is compiled into Release.
#    The first non-blank line is `#if DEBUG` and the last is its `#endif`; nothing else is at
#    depth 0, and the outer block has no `#else` or `#elseif`, whose branch would be compiled into
#    Release. Conditions nested inside the block are allowed. A directive is `#if`, `#elseif`,
#    `#else` or `#endif` followed by anything but a letter, digit or underscore (`#else//x`,
#    `#elseif(!DEBUG)`). A file with a block comment or a multi-line string fails, since a
#    directive inside one can't be told from a real one. CI also checks the Release binaries
#    for their launch arguments (section 8).
while IFS= read -r f; do
  [[ "$f" == */DebugTools/*.swift && -f "$f" ]] || continue
  if ! problem=$(awk '
    /^[[:space:]]*$/ { next }
    index($0, "/*") || index($0, "\"\"\"") {
      print "line " NR " has a block comment or a multi-line string"; failed = 1; exit 1
    }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      seen++
      if (seen == 1) {
        if (line != "#if DEBUG") { print "the first line is not #if DEBUG"; failed = 1; exit 1 }
        depth = 1; next
      }
      if (depth == 0) { print "line " NR " is outside the #if DEBUG block"; failed = 1; exit 1 }
      if (line ~ /^#if([^A-Za-z0-9_]|$)/) { depth++; next }
      if (line ~ /^#(else|elseif)([^A-Za-z0-9_]|$)/) {
        if (depth == 1) { print "line " NR " has " line " in the #if DEBUG block"; failed = 1; exit 1 }
        next
      }
      if (line ~ /^#endif([^A-Za-z0-9_]|$)/) { depth--; next }
    }
    END {
      if (failed) exit 1
      if (seen == 0) { print "the file is empty"; exit 1 }
      if (depth != 0) { print "the #if DEBUG block is not closed"; exit 1 }
    }
  ' "$f"); then
    report "$f is a Debug tool but isn't one #if DEBUG ... #endif block: $problem"
  fi
done < <(files)

# 8. Debug launch arguments are long enough to be found in a binary. Optimized Swift keeps a
#    string literal of 15 UTF-8 bytes or fewer inside the instructions, not in the string
#    section, so `strings` can't print it and CI's Release search (`-Nope[A-Z]`,
#    .github/workflows/build.yml) would miss it. Every "-Nope…" literal in app code is at least
#    16 bytes, which makes that search cover every launch argument.
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    literal=${hit#*:}; literal=${literal#\"}; literal=${literal%\"}
    bytes=$(LC_ALL=C awk -v s="$literal" 'BEGIN { print length(s) }')
    if (( bytes < 16 )); then
      report "launch argument \"$literal\" in $f:${hit%%:*} is $bytes bytes; use 16 or more so the Release binary search can find it"
    fi
  done < <(grep -noE '"-Nope[^"\\]*"' "$f" || true)
done < <(files)

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "security checks passed"
