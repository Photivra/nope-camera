# Security audit plan

Status: plan, 2026-11-12. No check below has been run against a release build yet. This page
lists every check the release audit (issue #1, step 4; AGENTS.md, "Before any release, a full
security audit must pass") runs before 1.0.0 and before every later release, how to run it, and
what counts as a pass. The project runs the audit itself.

Each check names the OWASP Mobile Application Security Verification Standard
([MASVS](https://mas.owasp.org/MASVS/), v2) control it maps to, and the Apple documentation it
relies on. Checks that need hardware say **Device**. Free, open-source or Apple tools only.

## How to use this page

1. Build the release candidate as an archive with the Release configuration, from a tagged
   commit (`xcodebuild archive -scheme NopeApp -configuration Release`).
2. Run every check in order on that archive and on the devices listed in the release notes:
   at least one iPhone with Bayer RAW on every lens, and one iPad.
3. Record each result in the audit report (an issue titled "Security audit: vX.Y.Z"): pass or
   fail, the evidence (command output, file, screenshot), the device and OS, and the commit.
4. Rank each failure: **Blocker** (breaks a promise in AGENTS.md "Honesty" or "No network, no
   analytics", or exposes photo contents, metadata, location or device identity), **Major**
   (weakens a defense without exposing data), **Minor** (hygiene). Every Blocker is fixed and
   re-tested before release. Major and Minor findings get an issue.
5. Complete the sign-off checklist at the end.

## Threat model

### What nope. protects

| Asset | Where it lives | Why it matters |
|---|---|---|
| Photo contents (pixels) | Memory during capture and development; the user's Photos library after saving | Can show people, places and documents |
| Metadata | The saved DNG, HEIF and JPEG files | Can reveal time, time zone, device, software version, and link photos together (`docs/PRIVACY.md`) |
| Location | Only if the user turns the location switch on: Core Location in memory, then the saved file | Reveals where the user was |
| Device identity | Maker notes, serial numbers, unique IDs, exact model; the signing certificate if it were reused | Links photos to one device or to each other |
| The signing key | A new Secure Enclave key per photo, discarded after signing | A reused or exported key would link photos, or let someone sign altered files |
| Settings | `UserDefaults` in the app container | Low sensitivity, but must hold no photo data or identifiers |

### Who the adversaries are

| Adversary | Capability | What they want |
|---|---|---|
| A recipient of a shared photo | Reads every byte of a file the user shares | Location, time, device, links to the user's other photos |
| A data broker or platform collecting many photos | Large sets of files from many sources | Link photos to one camera or person (metadata, signature fields, sensor noise) |
| A network observer | Sees traffic from the device | Learn that nope. is used, or anything about photos |
| A dependency or build-chain attacker | A compromised package, binary framework or GitHub Action | Add network code, collection, or a weak key |
| Someone with brief physical access to an unlocked or locked device | Reads the app container through backups or forensic tools | Leftover photos, thumbnails, logs |
| Someone who wants to fake a signed photo | Edits a nope. file | Make an altered file validate as unchanged |
| A curious contributor or a mistake in a pull request | Adds a log line, a temp file or a tag | Accidental leaks |

### Out of scope (disclosed on the Honesty screen, not fixed by the app)

What iOS and Photos do after a photo is saved (iCloud Photos, Enhanced Visual Search, on-device
analysis, sharing options, Share with App Developers, Siri), the sensor's noise pattern (PRNU),
what is visible in the picture, and a jailbroken or compromised device. See
`docs/research/privacy-claims.md` and `SECURITY.md`, "Scope".

## Checks

### 1. Supply chain: dependencies, pinned versions and licenses

MASVS-CODE-3. The only allowed dependencies are in `security/allowed-dependencies.txt`
(`c2pa-swift` and Apple's `swift-certificates`, `swift-asn1` and `swift-crypto`).

- **Run:**
  - `scripts/check-security.sh` (allowlist check against every `Package.resolved`).
  - Open each `Package.resolved` and confirm every pin has an exact `revision` and a `version`;
    in `Package.swift` and the Xcode project, every requirement is `.exact(...)` or a revision,
    never a range or branch.
  - For the C2PA binary framework (`C2PAC.xcframework`), confirm the `binaryTarget` has a
    `checksum`, and recompute it: `swift package compute-checksum C2PAC.xcframework.zip`.
  - Check each pinned version against the GitHub Advisory Database and
    [OSV](https://osv.dev) (search by package name and version; for the Rust core,
    `c2pa-rs` at the version the framework was built from, from its release notes).
  - Read each dependency's license at the pinned version and compare it with `THIRD_PARTY.md`.
  - GitHub Actions: every `uses:` in `.github/workflows/` is pinned to a full commit SHA
    (`grep -nE 'uses: [^@]+@[0-9a-f]{40}' .github/workflows/*.yml` matches every `uses:` line).
- **Pass:** no unlisted dependency; every pin exact; checksum matches; no known vulnerability
  that affects the code paths nope. uses (or a documented, reviewed exception); every license
  GPL-3.0-only compatible and recorded; every Action pinned by SHA.

### 2. Secrets in the repository and the binary

MASVS-CODE (supply chain), AGENTS.md "Keep the repository clean".

- **Run:**
  - Secret scan of the full history with an open-source scanner, for example
    `gitleaks detect --source . --log-opts="--all"`, and confirm GitHub secret scanning reports
    no open alerts.
  - `git log --all --name-only --format= | grep -iE '\.(p12|cer|mobileprovision|pem|key)$|Local\.xcconfig'`
    returns nothing.
- **Pass:** no credentials, certificates, provisioning profiles, private keys or team IDs in
  any commit.

### 3. Binary review

MASVS-CODE, MASVS-RESILIENCE (information in the binary). Run on the Release `.app` inside the
archive (`Products/Applications/NopeApp.app`).

- **Run:**
  - `strings -a NopeApp.app/NopeApp | grep -iE 'BEGIN (EC |RSA )?PRIVATE KEY|api[_-]?key|secret|token|password|/Users/|http://|https://'`
  - `strings -a NopeApp.app/NopeApp | grep -E 'NopeTagCheck|NopeCameraProbe|NopeSimulatedCamera|NopeArmDebugRun'`
    (Debug-only tools must not be in Release).
  - `nm -u NopeApp.app/NopeApp` and the same on every binary in `NopeApp.app/Frameworks/`,
    then search the undefined symbols for networking:
    `grep -E 'URLSession|NSURLConnection|nw_|CFSocket|CFStream|socket$|_connect$|getaddrinfo|SecTrust'`.
  - `otool -L` on every binary: no `Network.framework`, `WebKit.framework` or
    `CFNetwork.framework` load command.
  - `codesign -dv --verbose=4 NopeApp.app` and `codesign --verify --deep --strict NopeApp.app`.
- **Pass:** no secrets; no absolute build paths that name a person; no Debug-only tool strings;
  no networking symbols or frameworks in the app binary **or in any binary it links, including
  the C2PA library**; the signature verifies.
- **No networking code at all (maintainer's rule).** The shipped app must not link networking
  code, even code that is never called. There is no exception path: a networking symbol in any
  linked binary is a Blocker, and a dynamic proof (check 8) that it never runs doesn't replace
  this check. c2pa-rs has optional features that fetch remote manifests, OCSP responses and
  timestamps over HTTP; nope. builds it from source with every network feature off
  (`scripts/build-c2pa-lib.sh`, inputs pinned in `c2pa-lib/`) and vendors the Swift wrapper
  without its networking code (`Vendor/c2pa-swift`). Inspect the linked binary, not just the
  source:
  - `scripts/check-no-networking.sh NopeApp.app/NopeApp` on the release app binary (without
    `--allow-rust-std`), and on every other binary in the app bundle. It checks for Rust
    networking crates, socket imports and Apple's networking APIs, and fails on a linked
    CFNetwork or Network framework.
  - By hand as a cross-check: `xcrun nm --no-llvm-bc -u` on the app binary for `socket`,
    `connect`, `getaddrinfo`, `SSL_`, `nw_`, `CFHTTP` and `URLSession`, and `otool -L`.
  - Confirm the C2PA library checksum matches the pin, so the shipped library is the
    network-free build CI checked.

### 4. Entitlements

MASVS-PLATFORM, least privilege. Allowed keys are in `security/allowed-entitlements.txt`
(today only `com.apple.developer.locked-camera-capture`, for the lock-screen capture extension).

- **Run:**
  - `scripts/check-security.sh` (source `.entitlements` files).
  - On the signed archive, for the app and every extension:
    `codesign -d --entitlements - --xml NopeApp.app | plutil -p -`.
- **Pass:** the signed binary has only `application-identifier`,
  `com.apple.developer.team-identifier`, `get-task-allow` = false (distribution builds),
  `keychain-access-groups` only if Xcode adds its default, and the allowlisted keys. No
  iCloud, App Groups, associated domains, push, network extension, background modes or
  HealthKit. Any extra key is a Blocker until it is allowlisted by a reviewed pull request.
- **Apple docs:** [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements).

### 5. Info.plist: privacy strings and attack surface

MASVS-PLATFORM-1, MASVS-PRIVACY-1, MASVS-PRIVACY-3.

- **Run:** `plutil -p NopeApp.app/Info.plist` (and each extension's), plus the localized
  `InfoPlist.strings` in every `.lproj`.
- **Pass:**
  - Usage strings exist only for what the app uses: `NSCameraUsageDescription`,
    `NSPhotoLibraryAddUsageDescription`, and `NSLocationWhenInUseUsageDescription` only if the
    location switch ships. No `NSPhotoLibraryUsageDescription` (full library access), no
    microphone, contacts, tracking (`NSUserTrackingUsageDescription`), Bluetooth or local
    network strings.
  - Each string is accurate, says "nope.", and is translated in all 11 languages.
  - No `UIBackgroundModes`, `CFBundleURLTypes` (URL schemes), `CFBundleDocumentTypes`,
    `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, `NSAppTransportSecurity`
    exceptions, or `NSBonjourServices`.
  - `ITSAppUsesNonExemptEncryption` is `NO`. Export compliance answer: **No** non-exempt
    encryption (maintainer's decision, 2026-11-12): the app uses the operating system's
    cryptography only to sign photos (authentication and integrity) and encrypts no data. If the
    key is missing, that is a Minor finding (App Store Connect then asks for every build);
    if a release adds encryption of data, the answer must be reviewed again.
- **Apple docs:** [Requesting access to protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources),
  [`PHAccessLevel.addOnly`](https://developer.apple.com/documentation/photokit/phaccesslevel/addonly).

### 6. Privacy manifest and required-reason APIs

MASVS-PRIVACY-3. Apple requires a privacy manifest (`PrivacyInfo.xcprivacy`) that declares
tracking, tracking domains, collected data types and every use of a required-reason API, for the
app and for each third-party SDK it bundles
([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files),
[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)).

**Does nope. need one?** Yes. `App/NopeApp/PrivacyInfo.xcprivacy` exists and declares no
tracking, no tracking domains, no collected data and no required-reason APIs.

**Known gap (as of 2026-11-12), to fix before release:** Release code now uses two
required-reason APIs that the manifest doesn't declare: `@AppStorage` (`UserDefaults`) for the
manual controls setting in `App/NopeApp/NopeApp.swift`, and `ProcessInfo.systemUptime` to
throttle exposure readings in `Sources/NopeCapture/SystemCaptureHardware.swift`. The manifest
needs `CA92.1` and `35F9.1` (recheck the codes on Apple's page). Expected 1.0 use:

| Category | Expected 1.0 use | Reason code (recheck on Apple's page before submission) |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | Settings (manual controls today; switches, formats, master switch) | `CA92.1`: read and write data only the app itself uses |
| `NSPrivacyAccessedAPICategoryDiskSpace` | Only if the app checks free space before saving or shows an out-of-space message | `E174.1`: check space before writing files |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | Only if code reads creation or modification dates (for example to clean up temp files) | `C617.1`: timestamps of files in the app container |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `ProcessInfo.systemUptime` for the exposure readings throttle today; any idle timer that uses it or `mach_absolute_time()` | `35F9.1`: measure elapsed time inside the app |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | None expected | Not declared |

- **Run:**
  - Search Release code for the APIs Apple lists in each category, for example
    `grep -rnE 'UserDefaults|@AppStorage|systemUptime|mach_absolute_time|volumeAvailableCapacity|systemFreeSize|creationDate|modificationDate|contentModificationDate|\bstat\(|getattrlist' Sources App`,
    excluding `#if DEBUG` files, and add each hit to the table.
  - Check the C2PA package for its own `PrivacyInfo.xcprivacy`, and whether its Rust core
    reads file timestamps or disk space (`nm -u` for `stat`, `fstat`, `statfs`,
    `getattrlist`). If it does and ships no manifest, nope.'s manifest must cover it, or the
    package must add one.
  - Each extension target (lock-screen capture, widget controls) gets its own manifest if it
    ships code that uses a listed API.
  - In Xcode Organizer, select the archive and choose **Generate Privacy Report**; read the PDF.
  - `scripts/check-security.sh` (no tracking, no tracking domains).
- **Pass:** every required-reason API in the Release binary is declared with a correct code;
  nothing declared that isn't used; `NSPrivacyTracking` false, no tracking domains, no
  collected data types; the generated report matches; App Store Connect shows no missing-reason
  warning on upload.

### 7. No network: static proof

MASVS-NETWORK-1 and -2 (not applicable by design, so the check is that there is none),
AGENTS.md rule 4.

- **Run:**
  - `scripts/check-security.sh` (bans `URLSession`, `NWConnection`, `import Network`,
    `CFNetwork`, `WebKit` and analytics SDK names in app code).
  - `grep -rnE 'import (Network|WebKit|SafariServices)|URLSession|NWConnection|URLRequest|openURL|UIApplication\.shared\.open|Link\(' Sources App`:
    the only allowed hits are links that open in the browser (the privacy policy, the C2PA
    checker, the source code), which hand the URL to the system and don't fetch anything in
    the app.
  - The binary checks in check 3 (`nm -u`, `otool -L`) on the app and every framework.
- **Pass:** no networking API in source or binary; every `URL` in the app is a link opened by
  the system browser.

### 8. No network: dynamic proof (Device)

MASVS-NETWORK, MASVS-PRIVACY-1.

- **Run, three ways:**
  1. **Packet capture.** Connect the device to the Mac by cable, start a Remote Virtual
     Interface (`rvictl -s <device UDID>`), and capture everything:
     `sudo tcpdump -i rvi0 -k -w nope-audit.pcapng` (`-k` adds process metadata where macOS
     provides it). Exercise every feature for at least 10 minutes: permissions, every lens,
     every format, every switch, location on and off, signing on and off, the Honesty screen,
     settings, lock-screen capture, Control Center, Siri and Shortcuts. Stop with
     `rvictl -x <UDID>`. Open the file in Wireshark and filter by the app's process name; with
     no process metadata, compare against a baseline capture of the same length with nope.
     closed.
  2. **App Privacy Report.** Turn on Settings › Privacy & Security › App Privacy Report before
     the session, use the app as above, then read nope.'s entry
     ([App Privacy Report](https://support.apple.com/en-us/102188)).
  3. **Offline run.** With Airplane Mode on and Wi-Fi off, repeat the session. Every feature,
     including signing and the Honesty screen, works the same.
  - Optional: on the Simulator, `nettop -p <pid of NopeApp>` while running the UI tests.
- **Pass:** zero connections and zero DNS lookups attributable to nope. in the capture; App
  Privacy Report shows camera and photos (and location when on) access, and **no domains**
  under Network Activity; every feature works offline. Links opened in the browser appear under
  the browser, not nope.

### 9. Metadata: allowlist and fail-closed (Device and tests)

MASVS-PRIVACY-2, MASVS-STORAGE-2. `docs/PRIVACY.md` is the allowlist.

- **Run:**
  - The metadata unit tests: they assert the exact tag set of every format for each switch
    combination, and fail on any unexpected tag.
  - The fail-closed tests: inject an unexpected tag, IFD, XMP property and embedded block
    into a written file (with a fake writer); confirm the reader removes it or, when it can't,
    the photo is **not** saved and the user sees the plain message. Include a tag that a
    future iOS might add (an unknown tag ID).
  - The on-device tag check (`docs/TESTING.md`, "Tag check") on the release iOS version, on
    every test device.
  - For every format (DNG, HEIF, JPEG) and each switch combination, save from the release
    build, export the originals (Photos › Share › Options › All Photos Data, or Image Capture),
    and dump them: `exiftool -a -G1 -u -s <file>` and `swift scripts/dump-tags.swift <file>`.
    Compare against the allowlist.
  - Location off: no GPS IFD, no `{GPS}` dictionary, no XMP location in any file.
- **Pass:** every file contains only allowlisted items for its switches; no serial number,
  unique image ID, raw data ID, maker note (unless switched on), XMP `DocumentID` or
  `InstanceID` (other than the C2PA manifest's random one); the fail-closed tests pass;
  no location with the switch off.

### 10. Signing: key handling and signatures (Device and tests)

MASVS-CRYPTO-1, MASVS-CRYPTO-2, MASVS-PRIVACY-2. Design: `docs/research/c2pa-signing.md`.

- **Run:**
  - **Key creation:** read `Sources/NopeSigning/`: each photo creates
    `SecureEnclave.P256.Signing.PrivateKey()` with no persistence. Confirm there is no call to
    `dataRepresentation` that is stored or written, no Keychain API (`SecItemAdd`,
    `SecKeyCreateRandomKey` with a permanent tag), and no software (non-Secure Enclave) key
    path in a device build (the software key is compiled for the Simulator only; confirm the
    condition in the source and that the device binary has no software key path).
  - **Never exported:** the only data that leaves the signing code is the public key and the
    signature (`SignedData`). Grep for `dataRepresentation`, `rawRepresentation`,
    `x963Representation` on private keys: no hits.
  - **Per photo:** sign two photos and extract both manifests with the C2PA reference tool
    (`c2patool <file> --detailed`). The public keys, certificate serial numbers and instance
    IDs differ; the certificate subject and validity are identical and generic (no name,
    email, device or location); no timestamp when the date switch is off; the claim generator
    is the same for every user.
  - **Validity:** each format validates in `c2patool` as Valid with an untrusted signer
    (expected).
  - **Tamper:** change one pixel byte, one metadata byte, and one manifest byte in copies of a
    signed DNG, HEIF and JPEG; each fails validation.
  - **No homemade cryptography:** only CryptoKit and the C2PA library sign or hash.
- **Pass:** all of the above. A reused key, an exported key, an identifying certificate field,
  or a tampered file that validates is a Blocker.
- **Apple docs:** [`SecureEnclave.P256.Signing.PrivateKey`](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey),
  [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave).

### 11. Local data: files, file protection and leftovers (Device and Simulator)

MASVS-STORAGE-1, MASVS-STORAGE-2. Rule: photos go from memory to Photos; any temp file uses
complete file protection and is deleted at once (AGENTS.md, "Photos never linger").

- **Run:**
  - Code: every `write(to:` in Release code passes `.completeFileProtection` and is followed
    by deletion in a `defer`; `grep -rn 'write(to:\|FileManager\|temporaryDirectory' Sources App`.
  - After a session of 50 photos in every format, download the container (Xcode › Devices and
    Simulators › the app › Download Container, or `xcrun simctl get_app_container booted
    com.photivra.nope.dev data` on the Simulator) and list every file:
    `find <container> -type f -exec ls -la {} \;`.
  - Check file protection of anything left: `xattr -l` is not enough on a downloaded copy, so
    confirm in code and with a test that writes are protected.
  - App switcher snapshots: iOS stores a snapshot of the last screen in
    `Library/SplashBoard/Snapshots`. Check whether it shows the viewfinder or the last-photo
    thumbnail. If it does, that is a Major finding (MASVS-PLATFORM-3); the fix is to cover
    the viewfinder when the scene becomes inactive.
  - Backups: confirm nothing photo-related is in the container, so device backups carry only
    settings.
- **Pass:** after the session the container holds only `Library/Preferences/<bundle id>.plist`
  and system-managed folders, with no photo data, thumbnails, DNG/HEIF/JPEG files, reports or
  logs; snapshots show no photo content.

### 12. Settings storage (`UserDefaults`)

MASVS-STORAGE-2, MASVS-PRIVACY-2.

- **Run:** after using every setting, read the preferences file:
  `plutil -p <container>/Library/Preferences/<bundle id>.plist`.
- **Pass:** only the documented setting keys (switch states, formats, options), with Boolean
  or enum values. No photo data, metadata values, file names, dates of use, counters, device
  identifiers or the user's name and copyright text unless the user entered it for that switch.
  Debug-only keys (for example an armed debug run) never appear in a Release build.

### 13. Logging

MASVS-STORAGE-2. Rule: `Logger` only, every value private, never photo data or metadata.

- **Run:**
  - `scripts/check-security.sh` (bans `print`, `NSLog`, `debugPrint`).
  - `grep -rn 'Logger\|logger\.' Sources App`: every interpolated value has
    `privacy: .private` (or is a constant string).
  - **Device:** stream the device log in Console.app (filter subsystem `com.photivra.nope`)
    while exercising every feature, including errors (deny camera, fill storage, interrupt
    with a call).
- **Pass:** messages are constant strings or show `<private>` for values; no file paths,
  metadata, location, user text or image data.

### 14. Crash reporting and analytics

MASVS-PRIVACY-1.

- **Run:** confirm no crash-reporting or analytics framework in `Package.resolved`,
  `NopeApp.app/Frameworks/` or the source (`scripts/check-security.sh` bans the common names);
  no `MetricKit` subscriber (`MXMetricManager`) in Release code.
- **Pass:** none present. Apple's own crash reports, sent only if the user opts in to Share with
  App Developers, are Apple's collection and are disclosed on the Honesty screen.

### 15. Photos in memory

MASVS-STORAGE-2, AGENTS.md "Battery" (release RAW buffers as soon as each photo is saved).

- **Run (Device):** in Instruments, the Allocations and Leaks templates, take 30 photos in
  every format; mark generations between photos. Use Xcode's memory graph after the last
  save.
- **Pass:** RAW and developed buffers are freed after each save (memory returns to the
  baseline within one generation); no leaks of `AVCapturePhoto`, `CVPixelBuffer` or `Data`
  holding image bytes; only the "last photo" details the Honesty screen needs stay in memory,
  and they are gone after the app quits.

### 16. Permissions at run time (Device)

MASVS-PRIVACY-1, MASVS-PRIVACY-4.

- **Run:** on a reset device, install the release build and check every prompt: camera on
  first use; add-only Photos access on first save; location only when the user turns its
  switch on; no prompt for anything else. Check Settings › Privacy & Security for nope.'s
  entries, and that a library fetch with add-only access returns nothing.
- **Pass:** only those prompts, at those moments; with "Remove all optional details" on, the
  app never asks for location.

### 17. Inputs and attack surface

MASVS-PLATFORM-1, MASVS-PLATFORM-2, MASVS-CODE-4.

- **Run:** confirm in source and Info.plist: no web views, URL schemes, document types, file
  import, clipboard reads (`UIPasteboard`), drag-and-drop receivers or code loaded at run
  time. Any byte-level parser (the project's own tag reader) has fuzz tests, and every
  `Unsafe` use is in `security/allowed-unsafe.txt` (`scripts/check-security.sh`). App Intents
  parameters are validated by `NopeCore`.
- **Pass:** no untrusted input other than the camera, the user's own taps and App Intents.

### 18. Static analysis

MASVS-CODE-4.

- **Run:** CodeQL code scanning for Swift (weekly; read the latest results for the release
  commit); Xcode **Product › Analyze** on the Release configuration; the build with warnings as
  errors and strict concurrency.
- **Pass:** no open high or critical findings; no analyzer warnings.

### 19. App Store privacy label and privacy policy

MASVS-PRIVACY-3. The answers are in `docs/store/app-privacy-label.md`; the policy draft is
`docs/store/privacy-policy-draft.md`.

- **Run:** compare the App Store Connect answers and the published policy with the results of
  checks 6, 8, 9, 12 and 14.
- **Pass:** "Data Not Collected" is true for the release build and every dependency; the policy
  says nothing the checks don't support.
- **Apple docs:** [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/),
  [App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage).

### 20. Resilience

MASVS-RESILIENCE. The source is public and the app holds no secrets, so anti-tampering,
anti-debugging and obfuscation are not goals. The check is only that the release build is
distribution-signed with `get-task-allow` false (check 4).

## MASVS coverage

| MASVS group | Checks |
|---|---|
| STORAGE | 9, 11, 12, 13, 15 |
| CRYPTO | 10 |
| AUTH | Not applicable: no accounts or sign-in |
| NETWORK | 7, 8 |
| PLATFORM | 4, 5, 11 (snapshots), 17 |
| CODE | 1, 2, 3, 17, 18 |
| RESILIENCE | 3, 20 |
| PRIVACY | 5, 6, 8, 9, 10, 14, 16, 19 |

## Sign-off checklist

Copy this into the audit report issue for each release.

- [ ] 1. Dependencies allowlisted, pinned exactly, checksums verified, no known vulnerabilities, licenses recorded; Actions pinned by SHA
- [ ] 2. Full-history secret scan clean
- [ ] 3. Binary: no secrets, no Debug tools, no networking symbols in the app or any linked binary (no exceptions); signature verifies
- [ ] 4. Signed entitlements match the allowlist
- [ ] 5. Info.plist: only the needed usage strings, accurate in 11 languages; no background modes, URL schemes, file sharing or ATS exceptions; `ITSAppUsesNonExemptEncryption` = `NO`
- [ ] 6. Privacy manifest matches every required-reason API in the binary; Xcode privacy report reviewed
- [ ] 7. Static no-network proof
- [ ] 8. Packet capture, App Privacy Report and offline run: zero app traffic
- [ ] 9. Metadata dumps of every format and switch combination match the allowlist; fail-closed tests pass; tag check rerun on the release iOS version
- [ ] 10. New Secure Enclave key per photo, never exported; generic certificate; valid in the C2PA reference tool; tampered files fail
- [ ] 11. No photos, thumbnails, reports or logs left in the container; snapshots hide photo content
- [ ] 12. `UserDefaults` holds only documented settings
- [ ] 13. Logs private and free of photo data and metadata
- [ ] 14. No crash reporting, analytics or MetricKit
- [ ] 15. Photo buffers freed after each save
- [ ] 16. Only the expected permission prompts
- [ ] 17. No untrusted input surfaces; parsers fuzzed
- [ ] 18. CodeQL and Analyze clean
- [ ] 19. App Store privacy answers and privacy policy match the results
- [ ] 20. Distribution-signed, `get-task-allow` false
- [ ] Every Blocker fixed and re-tested; Major and Minor findings filed
- [ ] Accessibility release pass done (AGENTS.md, "Accessibility"); a failure blocks release
- [ ] Audit report linked from the release's `CHANGELOG.md` entry
- [ ] Maintainer sign-off: name, date, version, commit

## Sources

- OWASP [MASVS v2](https://mas.owasp.org/MASVS/) and the [MASTG](https://mas.owasp.org/MASTG/) iOS tests
- Apple: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files),
  [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api),
  [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements),
  [App privacy details](https://developer.apple.com/app-store/app-privacy-details/),
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
  [Encrypting your app's files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files),
  [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave),
  [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations),
  [App Privacy Report](https://support.apple.com/en-us/102188)
- `docs/PRIVACY.md`, `docs/research/privacy-claims.md`, `docs/research/c2pa-signing.md`, `SECURITY.md`
