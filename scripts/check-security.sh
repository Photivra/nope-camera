#!/usr/bin/env bash
# Fast security checks for every pull request (seconds, no build).
# - Banned code: networking, web views, analytics or ads SDKs, unguarded logging,
#   Unsafe pointer APIs outside allowlisted files.
# - Dependency, entitlement and privacy manifest allowlists.
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

# 1. Banned code.
banned='URLSession|NSURLConnection|NWConnection|NWPathMonitor|import Network\b|CFNetwork|CFStream|import WebKit|WKWebView|SFSafariViewController|android\.permission\.INTERNET|java\.net\.|HttpURLConnection|okhttp|retrofit|android\.webkit|Firebase|Crashlytics|Sentry|Amplitude|Mixpanel|Segment|AppsFlyer|Adjust|GoogleMobileAds|FBSDK|FacebookCore|TelemetryDeck|\bprint\(|\bNSLog\(|\bdebugPrint\('
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

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "security checks passed"
