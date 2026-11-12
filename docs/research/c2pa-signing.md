# Research: C2PA signing with offline, per-photo keys

Status: research spike, 2026-11-11. No code. Facts are marked **confirmed** (from the source or the spec) or **inference** (to verify in code or on a device).

## Summary

The design works with the official library. Each photo is signed with a fresh Secure Enclave key, fully offline. Validators report the file as **valid**: unchanged since signing, with a correct signature. They also report the signer as **untrusted or unknown**, because an anonymous per-photo certificate can't chain to a trust-list root. That is expected, and it matches the planned wording: the signature proves the file hasn't changed, not who took it.

## Library

- **Confirmed:**
  - Swift package `C2PA` from [contentauth/c2pa-swift](https://github.com/contentauth/c2pa-swift), which `contentauth/c2pa-ios` now points to.
  - It wraps c2pa-rs through a prebuilt `C2PAC.xcframework`.
  - License: MIT or Apache-2.0 (GPLv3-compatible).
  - Latest release v0.0.16 (2026-10-27): maintained, but pre-1.0.
  - Minimum iOS 16.
- **Confirmed:** `Package.swift` also depends on Apple's `swift-certificates`, `swift-asn1` and `swift-crypto` (Apache-2.0). The dependency allowlist must name these as part of the C2PA dependency.
- **To measure:** the size it adds to the shipped app. The release archive holds every architecture slice, so its size isn't representative.

## Signing with a Secure Enclave key

- **Confirmed:**
  - The signer is `Signer(algorithm: .es256, certificateChainPEM:, tsa: URL? = nil, sign: (Data) throws -> Data)`, a callback, so the private key never leaves the Secure Enclave.
  - Signing goes through `Builder.sign(format:source:destination:signer:)`.
  - The library also offers `SecureEnclaveSigner` and `CertificateManager` helpers.
- **Inference:** the callback returns a DER-encoded ES256 signature. With CryptoKit, that is `SecureEnclave.P256.Signing.PrivateKey.signature(for:).derRepresentation`. The callback fits one-use keys better than the tag-stored helper does.

## Formats

- **Confirmed:** c2pa-rs supports DNG (`image/x-adobe-dng`), TIFF, HEIF/HEIC and JPEG ([supported formats](https://github.com/contentauth/c2pa-rs/blob/main/docs/supported-formats.md)).
- **Inference, to test:**
  - The signature binds the exact file bytes, so any later rewrite breaks it: edits in Photos, export, or re-encoding.
  - Test on real Bayer DNGs from AVFoundation.
  - Use the correct file extension, because the library detects the format from it.

## Certificates and trust

- **Confirmed** (C2PA specification 2.2):
  - **Certificate (§5.2.3, §14.4–14.5):** the signer uses an X.509 v3 certificate. It must not be a CA certificate, and it needs `digitalSignature` key usage and a specific extended key usage: the C2PA signing EKU `1.3.6.1.4.1.62558.2.1`, with `emailProtection` suggested for compatibility.
  - **Validation states (§14.3):** Well-Formed ⊂ Valid ⊂ Trusted. "Trusted" requires a chain to a trust-list root.
  - **Untrusted signers (§15.7):** they produce `signingCredential.untrusted`.
  - **No anonymous mode:** the spec has no provision for ephemeral or anonymous signers.
- **Confirmed** (c2pa-rs `certificate_profile.rs`): a self-signed certificate is rejected only if it is also a CA. A self-signed, non-CA leaf passes the certificate checks, but it is never Trusted.
- **Options:**
  1. **Self-signed leaf per photo, signed by the Secure Enclave key.** Recommended.
  2. **A throwaway software root and intermediate per photo** (`CertificateManager.createSelfSignedCertificateChain`), discarded after signing. The fallback if self-signed leaves are tightened.
  3. ~~An app-embedded intermediate~~. Rejected: the key can be extracted to sign fakes "as the app", and it still wouldn't be on a trust list.
- **Validator display (partly inference):**
  - c2patool reports the manifest as Valid, with `signingCredential.untrusted`.
  - The Content Credentials Verify site shows an "unknown source".
  - Hash binding is still checked and reported.

## Timestamps

- **Confirmed:**
  - `tsa: nil` is supported.
  - With no timestamp, validators check the certificate against the current time (§15.8.2). A manifest without a timestamp stops validating when the certificate expires (§10.3.2.5.1).
  - The claim has no required time field.
- **Design:**
  - Give the leaf a long, fixed validity period (for example 2000–2099). The same range for every photo avoids leaking the capture time.
  - When the date switch is off, omit `when` on actions.
  - **To verify:** whether c2pa-rs adds a timed `c2pa.created` action on its own.

## Privacy

- **Confirmed (§10.2):** `instanceID` and `claim_generator_info.name` are required.
- **Design:** nothing in a manifest may identify the user or device, or link photos together.
  - A generic claim generator name and version, the same for every user.
  - A random UUID for each instance ID.
  - Identical, generic certificate subject fields, with no email or location.
  - A random serial number.
  - No assertions about the creator, location or device.

## Recommended design

For each photo:
1. Create a `SecureEnclave.P256.Signing.PrivateKey`.
2. Build a generic, self-signed, non-CA leaf with the C2PA EKU and a fixed validity of 2000–2099.
3. Sign the DNG, HEIF and JPEG separately with `Signer(algorithm: .es256, certificateChainPEM:, tsa: nil, sign:)`.
   - **Manifest contents:** a `c2pa.created` action with the camera-capture digital source type, and no time when the date is off.
4. Discard the key.

**User-facing wording:** "Content Credentials prove this file hasn't been changed since nope. saved it. They don't prove who took it. Viewers show the signer as unrecognized, because each photo is signed anonymously."

## Open risks

- Some viewers may present "untrusted" as a warning.
- Anyone can make an identical-looking anonymous signature, so this proves integrity, not origin.
- Photos edits and re-encoding by sharing apps remove or break the signature.
- The pre-1.0 API may change.
- The transitive dependencies are Apple's own Swift packages.
- Binary size is unmeasured.
- If self-signed leaves are restricted later, fall back to option 2.

## Implementation findings (2026-11-12)

Checked while building `NopeSigning` with c2pa-swift 0.0.16 (c2pa-rs 0.91.7), on synthetic files, with the library's reader and c2patool 0.28.6:

- **Confirmed:** the signer callback accepts a DER-encoded ES256 signature from CryptoKit.
- **Confirmed:** a self-issued, non-CA leaf works, but c2pa-rs also requires an authority key identifier on it (`certificate_profile.rs`); without one, signing fails with "the certificate is invalid". The leaf carries subject and authority key identifiers derived from its own one-use key.
- **Confirmed:** validators report `Valid` with `signingCredential.untrusted` as the only failure, for DNG, HEIF and JPEG; a one-bit change in the image data gives `assertion.dataHash.mismatch` (DNG, JPEG) or `assertion.bmffHash.mismatch` (HEIF).
- **Confirmed:** c2pa-rs adds no time to the `c2pa.created` action when none is given, and no timestamp when timestamping is off.
- **Confirmed:** c2pa-rs appends its own entry (`org.contentauth.c2pa_rs` and its version) to the claim generator information.
- **Confirmed:** the prebuilt `C2PAC.xcframework` contains an HTTP client (reqwest) for remote manifests, OCSP and timestamps. nope. turns every fetch off, allows no network host, and gives the library an HTTP resolver that refuses every request; a test makes the library attempt a fetch and checks the resolver is called and refuses it. The client code is still linked into the binary.

### Networking code in the C2PA library (2026-11-12)

Decision (maintainer, 2026-11-12): the shipped app must not link any networking code, even code that is never called. Checked against c2pa-swift 0.0.16:

- **Confirmed, prebuilt binary.** `C2PAC.xcframework` (iOS device slice) is a static archive of 1,315 Rust objects built from c2pa-rs 0.91.7. Apple's `nm` can't read the embedded LLVM bitcode, so symbols were listed with `xcrun nm --no-llvm-bc -A C2PAC` (231,057 lines). Mangled-name matches: `7reqwest` 4,647, `5hyper` 1,739, `10hyper_util` 1,498, `6rustls` 4,338, `2h2` 2,407, `5tokio` 3,704, `3mio` 462, `7socket2` 245, `4http` 2,158; `4ureq` 0, `10native_tls` 0. Undefined (imported) socket functions: `_socket`, `_connect`, `_bind`, `_listen`, `_accept`, `_send`, `_sendto`, `_sendmsg`, `_recv`, `_recvfrom`, `_recvmsg`, `_getaddrinfo`, `_freeaddrinfo`.
- **Confirmed, build features** (`c2pa_c_ffi/Cargo.toml` at tag `c2pa-v0.91.7`): `default = ["c2pa/openssl", "http", "add_thumbnails"]`, with `http = ["c2pa/http_reqwest", "c2pa/http_reqwest_blocking"]` (reqwest, rustls, webpki-roots). The FFI also always enables `c2pa/fetch_remote_manifests`, `file_io` and `pdf`, and depends on `tokio` (`rt`, `rt-multi-thread`) on every native target. The workspace depends on the `c2pa` crate with `default-features = false`. The release assets for 0.91.7 have one build per target triple and no variant without HTTP.
- **Confirmed, Swift wrapper.** c2pa-swift's own Swift sources use `URLSession` in `C2PAContext.swift` (an HTTP resolver initializer) and `WebServiceSigner.swift`.
- **Inference, not yet built:** c2pa-rs's FFI could be built for the iOS targets with `--no-default-features` and a crypto feature only (`c2pa/openssl` or `rust_native_crypto`), without `http`. Whether it compiles with `fetch_remote_manifests` still on, and whether the `c2pa_http_resolver_create` and `c2pa_context_builder_set_http_resolver` exports c2pa-swift calls remain, is untested. The Swift wrapper would also need its two networking files removed (a fork or vendored copy).
- **Decided (maintainer, 2026-11-12):** build it ourselves, in this repository's CI, and publish it as a checksummed release asset; vendor the wrapper without its networking code; use the latest stable, reviewed versions.

### Network-free build (2026-11-12)

Built as described in `c2pa-lib/README.md`: c2pa-rs `c2pa-v0.92.0` (commit `83eba34`), `--no-default-features --features rust_native_crypto,file_io`, with `c2pa/fetch_remote_manifests` removed by a one-line patch, Rust 1.99.1, `cargo build --locked`.

- **Confirmed:** it compiles without `http` and without `fetch_remote_manifests`, and the C interface keeps every function the c2pa-swift 0.1.0 wrapper calls (checked against the generated `c2pa.h`). All NopeSigning tests pass against it.
- **Confirmed, dependency graph** (`cargo tree`, iOS targets, these features): no reqwest, hyper, rustls, h2, mio, socket2, ureq, native-tls or webpki-roots; cargo-deny's ban list passes. `tokio` (runtime only, no `net` feature), `http` (types) and `url` (parsing) remain; none opens a connection.
- **Confirmed, symbols** (`xcrun nm --no-llvm-bc -A`): the library has 0 symbols from those crates. Its only socket imports are in Rust's standard library object, which always contains `std::net`. An iOS executable that links NopeSigning and calls the signer (Release, dead-code stripping, symbols kept; 103,893 symbols, 13,118 of them from c2pa) has no socket imports and no `std::net` symbol: the linker drops them because nothing calls them.
- **Confirmed, reproducible:** two builds in different folders gave the same SwiftPM checksum (`9e2ddfe5…0bb9`), and a CI build on a GitHub runner gave the same file-for-file; the libraries match byte for byte, and `scripts/build-c2pa-lib.sh` sorts the xcframework's `Info.plist`, which `xcodebuild -create-xcframework` writes in no fixed order. CI rebuilds it and compares with the pin.
- **Confirmed, licenses:** cargo-deny 0.20.2 passes with only GPL-3.0-only-compatible licenses allowed; 262 crates, c2pa-rs's own two included, are compiled in (`c2pa-lib/CRATES.md`).
- **Changelog review:** c2pa-rs 0.92.0 removes deprecated APIs (the wrapper 0.1.0 is updated for them), passes the signing context to timestamp requests (unused here), adds OCSP stapling (unused: OCSP is off and the library has no HTTP), and adds the built-in EKUs by default. c2pa-swift 0.1.0 migrates to the 0.92 C API, releases the signer callback box when creation fails, and reports stream write errors. Nothing changes nope.'s manifests: the tests and c2patool results are unchanged.
- **To measure:** the app size it adds once the app links `NopeSigning`. The static archive for one device architecture is about 250 MB unstripped (71 MB stripped); the linker keeps only what is used.

## Sources

- [contentauth/c2pa-swift](https://github.com/contentauth/c2pa-swift): README, `Package.swift`, `Signer.swift`, `SecureEnclaveSigner.swift`, `CertificateManager.swift`, release v0.0.16
- [contentauth/c2pa-rs](https://github.com/contentauth/c2pa-rs): `sdk/src/crypto/cose/certificate_profile.rs`, `docs/supported-formats.md`
- [C2PA specification 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html): §§5.2.3, 10.2, 10.3.2.5.1, 14.3–14.5, 15.7–15.9
- [Trust lists](https://opensource.contentauthenticity.org/docs/conformance/trust-lists) and [known certificate list](https://opensource.contentauthenticity.org/docs/verify-known-cert-list)
- [contentauth/c2pa-ios#109](https://github.com/contentauth/c2pa-ios/issues/109): Secure Enclave signer and timestamps
