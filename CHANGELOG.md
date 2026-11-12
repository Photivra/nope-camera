# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [semantic versioning](https://semver.org).

## [Unreleased]

### Added
- C2PA Content Credentials signing (`NopeSigning`): `ContentCredentialsSigner` signs a DNG, HEIF or JPEG with a new P-256 key for every file (Secure Enclave on a device; a software key compiled for the Simulator only), an anonymous self-issued certificate, and a manifest with one `c2pa.created` action and "Photivra Nope Camera" as the claim generator and in the certificate name. Fully offline: no timestamp authority, OCSP, remote manifest or trust list. Validators report the file as valid and the signer as untrusted, which is expected. Not yet called by the app: the save pipeline comes next.
- `NopeCore` signing contract: `PhotoSigning`, `SignableFile`, `ContentCredentialsStore` (where each format keeps the manifest, for the read-back allowlist), `PhotoSigningError` and `SigningSettings` (signing on by default).
- Network-free C2PA library: c2pa-rs 0.92.0 built from source with every network feature off (`scripts/build-c2pa-lib.sh`, inputs pinned in `c2pa-lib/`, Rust 1.99.1), published as a checksummed release asset (`c2pa-lib-v0.92.0`); the c2pa-swift 0.1.0 wrapper vendored without its networking code (`Vendor/c2pa-swift`). CI rebuilds it on every pull request, checks its checksum against the pin, reviews every Rust crate's license with cargo-deny, and checks the library, a linked iOS binary and the app for networking code (`scripts/check-no-networking.sh`).
- Dependencies: swift-certificates 1.21.1, swift-asn1 1.7.4 and swift-crypto 4.5.2, pinned exactly; listed in `THIRD_PARTY.md`.
- Docs: `docs/PRIVACY.md`, "Content Credentials" (what a signature contains and what it adds to each format), and `docs/TESTING.md`, "Checking signatures".
- Stuck-camera detection: every RAW photo's pixel buffer is sampled (128 bytes), and a blank (zero-filled) photo is dropped. nope. restarts the camera once and retakes the photo; if it is still blank, the camera screen says "The camera isn't sending a picture." and disables the shutter. New strings in eleven languages (AI translations, needs review).
- Debug builds: a `blankPicture` simulated camera scenario with UI tests and accessibility audits.
- Capture core: `AVFoundationCaptureBackend` in `NopeCapture` finds the physical cameras only, publishes each lens's capabilities as plain values (Bayer RAW format, ISO and shutter ranges, aperture including the iOS 27 range, bracket count, photo sizes, magnification), and captures single-frame Bayer RAW (DNG), or the least-processed HEIF, labeled, on a lens without Bayer RAW. Photos are kept in memory only; nothing is saved yet.
- `NopeCore`: lens selection, capture, session status (interruptions by calls, other apps and multitasking, a pause at critical heat, runtime error recovery), capture status, capture events and an opaque viewfinder handle (`CameraPreviewSource`).
- Camera screen: live viewfinder (`AVCaptureVideoPreviewLayer`, supplied by the app target), RAW badge or no-RAW fallback badge, lens buttons with "No RAW" and the reason, a shutter that also works with the volume buttons and the Camera Control, and pause and capture messages, including "Captured (not saved yet: development build)". New strings in eleven languages (AI translations, needs review); honesty wording in `Honesty.xcstrings`.
- UI tests for every camera state with accessibility audits, the largest text size and right-to-left layout, using simulated camera scenarios (`-NopeSimulatedCamera`, Debug builds only).
- Rules for battery use and for Siri and Shortcuts control through App Intents.
- Metadata plan: every item that can be removed without breaking the photo is a user switch, including the exact camera model for RAW editors and lens correction instructions; required items are locked with plain explanations. A master switch, "Remove all optional details" (on by default), turns every optional item off at once; signing stays separate.
- Tag check results from the first device runs in `docs/PRIVACY.md`.
- Tag check: saves one live video frame per lens as a JPEG, records the decoded luminance of every file, shows the live view, and reports whether the output was prepared and ready before each capture.
- Metadata rule: allowlisted metadata only, verified on every save (fail closed), with tag checks on each new iOS release.
- Debug-only tag check (`-NopeTagCheck`, Debug builds only, not compiled into Release): captures a Bayer RAW DNG, a metadata-stripped DNG and a HEIF with each physical camera, with a JSON report per lens, for the device metadata dump (issue #1, step 2).
- Security check: the Adjust and Segment SDK names are matched as whole words, so camera APIs such as `isAdjustingExposure` are no longer flagged; new passing and failing cases.
- Tag check: waits for the camera to stream frames and for auto exposure, focus and white balance to settle (1 to 5 seconds) before capturing, and records the settle result, the exposure state at each capture and every supported maximum photo size. The first device run captured black frames.
- `scripts/dump-tags.swift`: a Mac tag dumper listing every ImageIO property, XMP tag and TIFF/DNG tag in a file, with a tested TIFF walker and a redaction option.
- App scaffold, version 0.1.0: the `NopeKit` Swift package (`NopeCore`, `NopeCapture`, `NopeDevelop`, `NopeSigning`, `NopeUI`) and the universal iPhone and iPad app (iOS and iPadOS 18 and later), with no camera features yet.
- `NopeCore` camera state machine, intents, device capabilities and the capture backend protocol, with a simulated backend for tests and development builds.
- Camera permission screens in eleven languages (AI translations marked "needs review"), "nope." as the Home Screen name, a privacy manifest with no tracking and no collected data, and no entitlements.
- Tests: Swift Testing unit tests with a 100% line and branch coverage gate for the logic modules, and a UI smoke test with accessibility audits.
- CI on GitHub-hosted macOS runners: unit tests and coverage, UI tests, and a DocC build with warnings as errors, documentation coverage and a Markdown API export in `docs/api/`.
- Localization checks for every String Catalog.
- Documentation: architecture, testing, privacy and building-an-interface guides.
- Repository setup: license documents, agent instructions, contribution and security policies, and repository checks.
- `llms.txt` index for language models, and documentation and readability rules for code.
- Security checks on every pull request: banned networking, web, SDK and logging APIs; dependency, entitlement and Unsafe allowlists; privacy manifest checks.
- Localization rules: eleven launch languages, String Catalogs, right-to-left readiness, AI translations to start, and human review required for honesty, privacy and store listing text.
- Accessibility rules: WCAG 2.2 AA and Apple's guidelines, every applicable App Store Accessibility Nutrition Label, eyes-free capture, and automated accessibility audits.
- Name and wordmark rules: "nope." when used alone, and the "nope." / "Photivra Nope Camera" lockup.
- Third-party license rule: check before use, keep every notice, follow each license's conditions (including the Adobe DNG notice and SF Symbols terms), no copying around a license.
- Font rule: only fonts that are free to use; the wordmark is Inter (SIL OFL) in outlines.
- Architecture rules: the interface is a replaceable layer over interface-free logic modules, with import boundaries checked in CI.
- Documentation rules: complete DocC documentation for every symbol, `NopeCore` documented as the interface contract, Markdown API export for agents, and documentation checks in CI.
- Research: C2PA signing with offline, per-photo keys, a device capability survey, and verified wording and sources for every privacy statement.

### Changed
- `NopeSigning`: `PerPhotoSigner`, `SignedData` and `SigningError` are replaced by `ContentCredentialsSigner` and `NopeCore.PhotoSigningError`; `PerPhotoSigningKey` now provides the certificate key instead of a DER public key.
- Architecture check: `NopeSigning` may also import `X509` and `SwiftASN1` (swift-certificates), to build each file's certificate.
- `Lens` describes its Bayer RAW format (`bayerRAWFormat`) instead of a flag, and carries its capabilities.

### Fixed
- The Debug tag check now captures through the app's own capture backend and its single session, switching lenses through the backend, with no session or video data output of its own. It no longer writes a metadata-stripped DNG or a preview frame.
- Testing docs: the blank frames in the first device runs came from a Mac viewing and controlling the phone's screen, which blanks the camera picture for apps other than Apple's Camera; stopping that session fixed them (docs/TESTING.md, "Black frames"). The tag check on 2026-11-12 produced real images on every lens and confirmed the exposure tags (docs/PRIVACY.md).
- Stopping the camera now tears the session down in order: `stopRunning()` on the session queue, then every input and output removed, before anything can start it again. The camera probe does the same.
- Black frames in the tag check: the capture setup now follows the documented order (switches and an explicit photo size committed before the session starts, zero shutter lag and responsive capture off, the output prepared for RAW, captures gated on `captureReadiness`, file types named). Both the app's backend and the tag check use it. To be confirmed on a device.
