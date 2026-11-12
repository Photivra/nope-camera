#!/usr/bin/env bash
# Builds the network-free C2PA library (C2PAC.xcframework) from c2pa-rs source.
# See c2pa-lib/README.md for why and how; every input is pinned in c2pa-lib/.
#
# Usage: scripts/build-c2pa-lib.sh <work-dir>
#   <work-dir>  an empty or reusable folder for the c2pa-rs checkout and build output.
# Output: <work-dir>/C2PAC.xcframework.zip and its SwiftPM checksum on the last line.
#
# Requires macOS with Xcode, git, and rustup on PATH (the toolchain in
# c2pa-lib/rust-toolchain.toml is installed by rustup on first use).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
work="${1:?usage: build-c2pa-lib.sh <work-dir>}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
# shellcheck source=../c2pa-lib/versions.env
. "$here/c2pa-lib/versions.env"

src="$work/c2pa-rs"
out="$work/out"

# 1. The exact c2pa-rs commit. A reused checkout is reset, so local edits never leak in.
if [[ ! -d "$src/.git" ]]; then
  git init -q "$src"
  git -C "$src" remote add origin "$C2PA_RS_REPOSITORY"
fi
git -C "$src" fetch -q --depth 1 origin "refs/tags/$C2PA_RS_TAG"
git -C "$src" checkout -q --force FETCH_HEAD
git -C "$src" clean -q -fdx -e target
actual=$(git -C "$src" rev-parse HEAD)
if [[ "$actual" != "$C2PA_RS_COMMIT" ]]; then
  echo "c2pa-lib: $C2PA_RS_TAG is $actual, expected $C2PA_RS_COMMIT"; exit 1
fi

# 2. Pinned inputs: the network-free feature patch, the lockfile and the toolchain.
git -C "$src" apply "$here/c2pa-lib/c2pa_c_ffi.patch"
cp "$here/c2pa-lib/Cargo.lock" "$src/Cargo.lock"
cp "$here/c2pa-lib/rust-toolchain.toml" "$src/rust-toolchain.toml"

# 3. Build each target. --locked fails if Cargo.lock doesn't match; the path remap keeps the
#    work folder out of the binary.
export IPHONEOS_DEPLOYMENT_TARGET
export RUSTFLAGS="--remap-path-prefix=$src=/c2pa-rs --remap-path-prefix=$HOME=/home"
for target in $C2PA_TARGETS; do
  echo "==> cargo build $target"
  (cd "$src" && cargo build --locked --release -p c2pa-c-ffi --target "$target" \
    --no-default-features --features "$C2PA_FEATURES")
done

# 4. One framework per platform: the device, and the Simulator (both architectures in one
#    library). The header is patched as c2pa-swift's own framework build does: Swift can't name
#    a forward-declared struct, so the two opaque handles get empty bodies.
rm -rf "$out"
mkdir -p "$out"
make_framework() { # make_framework <dir> <library>
  local fw="$1/C2PAC.framework"
  mkdir -p "$fw/Headers" "$fw/Modules"
  cp "$2" "$fw/C2PAC"
  sed -e 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' \
    -e 's/typedef struct C2paStream C2paStream;/typedef struct C2paStream { } C2paStream;/g' \
    "$src/target/aarch64-apple-ios/release/c2pa.h" >"$fw/Headers/c2pa.h"
  printf 'framework module C2PAC {\n    header "c2pa.h"\n    export *\n}\n' >"$fw/Modules/module.modulemap"
  cat >"$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>C2PAC</string>
    <key>CFBundleIdentifier</key>
    <string>com.photivra.nope.C2PAC</string>
    <key>CFBundleName</key>
    <string>C2PAC</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${C2PA_RS_TAG#c2pa-v}</string>
    <key>CFBundleVersion</key>
    <string>${C2PA_RS_TAG#c2pa-v}</string>
    <key>MinimumOSVersion</key>
    <string>${IPHONEOS_DEPLOYMENT_TARGET}</string>
</dict>
</plist>
PLIST
}
make_framework "$out/device" "$src/target/aarch64-apple-ios/release/libc2pa_c.a"
mkdir -p "$out/simulator"
lipo -create "$src/target/aarch64-apple-ios-sim/release/libc2pa_c.a" \
  "$src/target/x86_64-apple-ios/release/libc2pa_c.a" -output "$out/simulator/libc2pa_c.a"
make_framework "$out/simulator" "$out/simulator/libc2pa_c.a"
rm "$out/simulator/libc2pa_c.a"

xcodebuild -quiet -create-xcframework \
  -framework "$out/device/C2PAC.framework" \
  -framework "$out/simulator/C2PAC.framework" \
  -output "$out/C2PAC.xcframework"

# xcodebuild lists the two libraries in no fixed order; sort them so the file is the same on
# every build.
python3 -I - "$out/C2PAC.xcframework/Info.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    info = plistlib.load(f)
info["AvailableLibraries"].sort(key=lambda library: library["LibraryIdentifier"])
with open(path, "wb") as f:
    plistlib.dump(info, f, sort_keys=True)
PY

# 5. Zip with fixed timestamps and sorted entries, without extra attributes.
find "$out/C2PAC.xcframework" -exec touch -h -t 200001010000 {} +
rm -f "$work/C2PAC.xcframework.zip"
(cd "$out" && find C2PAC.xcframework -print | LC_ALL=C sort | zip -q -X -@ "$work/C2PAC.xcframework.zip")

# Per-file hashes, to compare two builds when their checksums differ.
(cd "$out" && find C2PAC.xcframework -type f | LC_ALL=C sort | xargs shasum -a 256)
echo "==> $work/C2PAC.xcframework.zip"
swift package compute-checksum "$work/C2PAC.xcframework.zip"
