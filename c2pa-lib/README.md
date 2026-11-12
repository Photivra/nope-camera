# The network-free C2PA library

nope. signs photos with the C2PA library (c2pa-rs, through its C interface) and links no
networking code at all (AGENTS.md, "No network, no analytics"). The library's prebuilt Apple
release contains an HTTP client (reqwest, hyper, rustls, h2, tokio networking) and socket code,
so nope. builds its own copy from source with every network feature off, and publishes it here.

## What is built

- **Source:** c2pa-rs at the tag and commit in `versions.env` (`c2pa-v0.92.0`, the version
  c2pa-swift v0.1.0 is written for). The tag must resolve to the pinned commit, or the build
  stops.
- **Features:** `c2pa-c-ffi` with `--no-default-features --features rust_native_crypto,file_io`.
  Off: `http` (reqwest, rustls, webpki-roots), `add_thumbnails` and OpenSSL. `c2pa_c_ffi.patch`
  also removes `c2pa/fetch_remote_manifests`, which `c2pa-c-ffi` otherwise always turns on.
- **Lockfile:** `Cargo.lock` (c2pa-rs doesn't publish one), used with `cargo build --locked`.
- **Toolchain:** Rust 1.99.1, pinned in `rust-toolchain.toml`, installed with the official
  rustup installer (`https://sh.rustup.rs`).
- **Targets:** `aarch64-apple-ios` (devices), `aarch64-apple-ios-sim` and `x86_64-apple-ios`
  (Simulator), as one `C2PAC.xcframework`, with c2pa-swift's header patch and module map.
- **Reproducibility:** paths are remapped out of the binary, the xcframework's `Info.plist` is
  sorted, and the zip has fixed timestamps and sorted entries. Builds on a Mac and on a GitHub
  runner give the same checksum; CI rebuilds it on every pull request and fails if the checksum
  differs from the pin in `Package.swift`.

The Swift wrapper is vendored separately, without its networking code
(`Vendor/c2pa-swift/README.md`).

## Build it

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none
scripts/build-c2pa-lib.sh build/c2pa-lib-work            # prints the SwiftPM checksum last
mkdir -p build/c2pa-lib && (cd build/c2pa-lib && unzip -q ../c2pa-lib-work/C2PAC.xcframework.zip)
NOPE_C2PA_LIB_FROM_SOURCE=1 xcodebuild test -scheme NopeKit-Package ...   # use the local build
```

Without `NOPE_C2PA_LIB_FROM_SOURCE=1`, SwiftPM downloads the published asset and checks it
against the pinned checksum.

## Proving there is no networking code

`scripts/check-no-networking.sh` lists every symbol with `xcrun nm --no-llvm-bc -A` (plain `nm`
can't read the bitcode Rust embeds) and fails on any symbol from reqwest, hyper, hyper-util,
rustls, h2, mio, socket2, ureq, native-tls or tokio's net module; any imported socket function
(`socket`, `connect`, `getaddrinfo`, `send`, `recv` and relatives); any reference to
`NSURLSession`, `NSURLConnection`, CFNetwork or Network.framework; or a linked CFNetwork or
Network framework. The `c2pa-lib` CI job runs it on:

1. **the library**, with `--allow-rust-std`: Rust's prebuilt standard library is one object file
   that always contains `std::net`, so its socket imports are ignored there, and only there;
2. **an iOS executable that links `NopeSigning`** (`Tools/NopeSigningLinkCheck`, Release, dead-code
   stripping on, symbols kept): it calls the signer, so everything signing can reach is linked;
   no exceptions;
3. **the app** (Release, device): no exceptions.

Results on 2026-11-12 (Mac, Xcode 27.2, Rust 1.99.1):

| Binary | reqwest / hyper / rustls / h2 / mio / socket2 symbols | Socket imports |
|---|---|---|
| Upstream prebuilt `C2PAC` (c2pa-swift 0.0.16, device slice) | 4,647 / 1,739 / 4,338 / 2,407 / 462 / 245 | `socket`, `connect`, `getaddrinfo`, `send*`, `recv*`, `bind`, `listen`, `accept` |
| This build, `C2PAC` (device slice) | 0 / 0 / 0 / 0 / 0 / 0 | Only in Rust's `std` object (`std::net`) |
| `NopeSigningLinkCheck` (Release, device, 103,893 symbols, 13,118 from c2pa) | 0 | None; no `std::net` symbol is linked |

## Licenses

`scripts/check-c2pa-lib-licenses.sh` runs cargo-deny 0.20.2 with `deny.toml`: every crate
compiled into the library must have a license compatible with GPL-3.0-only, and the network
crates above are banned from the graph. `CRATES.md` lists every compiled crate with its version
and license, and CI fails if it is out of date. The crates' license texts must ship in the app's
Licenses screen.

## Publishing

The library is published as a release asset of this repository, under its own tag namespace
(`c2pa-lib-v<c2pa-rs version>`, not the app's `v*` tags):

1. CI's `c2pa-lib` job builds it, checks it (networking, licenses, checksum) and uploads it as the
   `C2PAC.xcframework` artifact.
2. A maintainer downloads that artifact from the run and creates the release with it:

   ```sh
   gh run download <run-id> -n C2PAC.xcframework
   swift package compute-checksum C2PAC.xcframework.zip   # must equal Package.swift's checksum
   gh release create c2pa-lib-v0.92.0 C2PAC.xcframework.zip --target <commit> \
     --title "C2PA library 0.92.0 (network-free)" --notes-file <notes>
   ```

## Updating

Change `versions.env` (tag and commit), regenerate `Cargo.lock` (`cargo generate-lockfile` in the
patched checkout), check that `c2pa_c_ffi.patch` still applies, update the vendored wrapper to
the matching c2pa-swift release, run both scripts (`--write` for `CRATES.md`), and update the
checksum and tag in `Package.swift`. Review the c2pa-rs and c2pa-swift changelogs, and record the
review in the pull request.
