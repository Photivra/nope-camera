#!/usr/bin/env bash
# Fails if a built binary or library contains networking code (AGENTS.md, "No network, no
# analytics": iOS links no networking code). macOS only; needs Xcode's command line tools.
#
# Usage: scripts/check-no-networking.sh [--allow-rust-std] <file>...
#   <file>  a Mach-O binary, a static library (.a), or a .framework / .xcframework folder.
#   --allow-rust-std  for the C2PA static library only: ignore socket imports in Rust's standard
#                     library object (std-*.o). Rust's prebuilt std always contains std::net; the
#                     linker drops it from the app when nothing calls it, which the check of the
#                     linked app binary (run without this flag) proves.
#
# Checks, with `xcrun nm --no-llvm-bc -A` (plain nm can't read Rust's embedded bitcode):
#   1. no symbols from Rust networking crates: reqwest, hyper, hyper-util, rustls, h2, mio,
#      socket2, ureq, native-tls, tokio's net module;
#   2. no imports of socket functions (socket, connect, getaddrinfo, send, recv and relatives);
#   3. no references to Apple's networking APIs: NSURLSession, NSURLConnection, CFNetwork,
#      Network.framework (nw_*), and no linked CFNetwork or Network framework.
set -euo pipefail

allow_std=0
if [[ "${1:-}" == "--allow-rust-std" ]]; then allow_std=1; shift; fi
[[ $# -gt 0 ]] || { echo "usage: check-no-networking.sh [--allow-rust-std] <file>..."; exit 2; }

crates='(7reqwest|5hyper|10hyper_util|6rustls|2h2|3mio|7socket2|4ureq|10native_tls|5tokio3net)'
imports='_(socket|socketpair|connect|getaddrinfo|freeaddrinfo|gethostbyname|send|sendto|sendmsg|recv|recvfrom|recvmsg|bind|listen|accept)'
apple='(_OBJC_CLASS_\$_NSURLSession|_OBJC_CLASS_\$_NSURLConnection|_CFNetwork|_CFSocket|_CFStreamCreatePairWithSocketToHost|_nw_[a-z_]+)'

fail=0
binaries() { # Mach-O files inside a path
  if [[ -d "$1" ]]; then
    find "$1" -type f | sort
  else
    echo "$1"
  fi
}

for path in "$@"; do
  [[ -e "$path" ]] || { echo "networking: no such file: $path"; fail=1; continue; }
  while IFS= read -r file; do
    file "$file" | grep -qE 'Mach-O|ar archive' || continue
    symbols=$(xcrun nm --no-llvm-bc -A "$file" 2>/dev/null || true)
    [[ -n "$symbols" ]] || { echo "networking: no symbols read from $file"; fail=1; continue; }
    hits=$(grep -E "$crates" <<<"$symbols" | head -n 5 || true)
    if [[ -n "$hits" ]]; then
      echo "networking: Rust networking crate symbols in $file:"; echo "$hits"; fail=1
    fi
    undefined=$(grep -E " U ${imports}$" <<<"$symbols" || true)
    if [[ $allow_std -eq 1 ]]; then
      undefined=$(grep -vE '\(std-[0-9a-f]+\.std\.[0-9a-f]+-cgu\.[0-9]+\.rcgu\.o\)|:std-[0-9a-f]+\.std\.[0-9a-f]+-cgu\.[0-9]+\.rcgu\.o:' <<<"$undefined" || true)
    fi
    if [[ -n "$undefined" ]]; then
      echo "networking: socket imports in $file:"; echo "$undefined" | head -n 10; fail=1
    fi
    hits=$(grep -E " (U|T|S|D) ${apple}$" <<<"$symbols" | head -n 5 || true)
    if [[ -n "$hits" ]]; then
      echo "networking: Apple networking API references in $file:"; echo "$hits"; fail=1
    fi
    if otool -L "$file" 2>/dev/null | grep -qE '/(CFNetwork|Network)\.framework/'; then
      echo "networking: $file links CFNetwork or Network.framework"; fail=1
    fi
    echo "checked $file"
  done < <(binaries "$path")
done

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "no networking code found"
