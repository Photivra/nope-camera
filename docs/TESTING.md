# Testing

Every change ships with tests (AGENTS.md, "Full test coverage"). This page says how to run them.
Local toolchain: Xcode 27.2 with the iOS 27.2 Simulator. The app supports iOS and iPadOS 18.0
and later.

## Quick checks (seconds, no build)

```sh
scripts/check-repo.sh
scripts/test-check-security.sh && scripts/check-security.sh
scripts/test-check-architecture.sh && scripts/check-architecture.sh
scripts/test-check-localization.sh && scripts/check-localization.sh
scripts/test-check-coverage.sh
scripts/test-dump-tags.sh   # macOS only: the tag dumper's TIFF walker
```

`check-security.sh` reads tracked files only (`git ls-files`), so stage new files before running
it.

## Unit tests and coverage

The logic modules are tested with Swift Testing, against fakes of the hardware protocols:

```sh
xcodebuild test -scheme NopeKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' \
  -derivedDataPath DerivedData -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO
scripts/check-coverage.sh DerivedData
```

`check-coverage.sh` requires 100% of lines and regions in `NopeCore`, `NopeCapture`,
`NopeDevelop` and `NopeSigning`. Swift's coverage data records each branch arm (each `switch`
case, each side of a ternary or `guard`) as a region and has no separate branch records, so
100% region coverage is how branch coverage is measured; branch records are checked too if a
future toolchain emits them.

The only files excluded are hardware adapters listed in `scripts/coverage-exclusions.txt`:

| File | Why it can't run in a unit test | Verified by |
|---|---|---|
| `Sources/NopeCapture/SystemCameraAuthorization.swift` | Requesting access shows a system prompt | On-device check |
| `Sources/NopeSigning/SecureEnclaveSigningKey.swift` | The Simulator has no Secure Enclave | On-device check |

Each excluded file is a thin wrapper; its logic lives in a tested file. `NopeUI` is not part of
the coverage gate: it is covered by UI tests and accessibility audits instead.

## UI tests and accessibility audits

```sh
xcodebuild test -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' CODE_SIGNING_ALLOWED=NO
```

`NopeAppUITests` launches the app, runs `performAccessibilityAudit()` on the permission screen,
allows access, and audits the ready screen. Every new screen and state adds an audit.

## Documentation

```sh
scripts/check-docs.sh DerivedData          # check
scripts/check-docs.sh DerivedData --write  # update docs/api/ after changing a doc comment
```

It builds the DocC documentation with warnings as errors, fails if a public or internal symbol
has no DocC comment of its own, and fails if `docs/api/` doesn't match the code.

## Continuous integration

`.github/workflows/build.yml` runs on GitHub-hosted runners with the `xcode-27` image and Xcode
27.2 (the image's default is 27.1; the workflow selects 27.2 through `DEVELOPER_DIR` to match
the local toolchain). Jobs:

| Job | What it runs |
|---|---|
| `unit-tests` | Coverage gate tests, the tag dumper's TIFF walker test, NopeKit unit tests on the iOS 27.2 Simulator, the coverage gate |
| `ui-tests` | App build and the UI smoke test with accessibility audits |
| `docs` | `scripts/check-docs.sh` |

`.github/workflows/repo-checks.yml` (`repo-checks`) runs the quick checks above.

## On-device checks

Some behavior can only be checked on hardware. Before a release, on at least one iPhone and one
iPad:

- the camera permission prompt shows the localized `NSCameraUsageDescription`, and each answer
  leads to the right screen (`SystemCameraAuthorization`);
- a Secure Enclave key signs and verifies (`SecureEnclaveSigningKey`);
- the manual accessibility pass in AGENTS.md (VoiceOver, Voice Control, Switch Control, the
  largest text size).

The full release audit is in AGENTS.md, "Before any release, a full security audit must pass".

## Tag check (metadata dump from a real device)

The tag check lists every metadata tag in real files captured on an iPhone or iPad, so the
privacy list in [`PRIVACY.md`](PRIVACY.md) is based on what the device actually writes (issue
#1, step 2). It has two parts: a debug-only capture mode in the app, and a tag dumper that runs
on a Mac.

### What the capture mode does

The code is in `App/NopeApp/DebugTools/`, wrapped in `#if DEBUG`. It is compiled only in the
Debug configuration, and Release builds contain none of it. It runs only when the app is
launched with the `-NopeTagCheck` launch argument.

1. It asks for camera access (tap Allow once).
2. For each physical camera (rear wide, ultra wide, telephoto, and front; never a virtual
   multi-camera device) it configures a photo session as in
   [`research/capability-survey.md`](research/capability-survey.md), item 12: the `.photo`
   preset, `maxPhotoQualityPrioritization` and `photoQualityPrioritization` set to `.speed`,
   Apple ProRAW off, zoom 1.0, deferred delivery, constant color and distortion correction off,
   no flash. No location is requested and no GPS metadata is supplied.
3. It captures, per lens:
   - `<lens>-raw.dng`: a Bayer RAW-only capture, written with `fileDataRepresentation()`;
   - `<lens>-raw-stripped.dng`: the same RAW photo written with
     `fileDataRepresentation(with:)` and a customizer whose `replacementMetadata` removes
     `{MakerApple}`, `{GPS}` and every key whose name contains "SerialNumber" or "UniqueID"
     (the planned native removal path);
   - `<lens>-speed.heic`: a processed HEVC photo at `.speed` (`<lens>-speed.jpg` if the device
     offers no HEVC).

   A lens without a Bayer RAW format gets only the processed photo, and its report says so.
4. It writes `<lens>-report.json` for each lens (device model identifier, OS version, camera
   type and position, active format, RAW formats and whether each is Bayer, ISO, exposure and
   aperture ranges, iOS 27 aperture values, `maxBracketedCapturePhotoCount`, the photo output's
   processing switches, the requested and resolved photo settings, and `photo.metadata`), and a
   `summary.json`.

Lens names are `back-wide`, `back-ultrawide`, `back-telephoto`, `front-wide` and so on. Every
file goes to the app's `Documents/TagCheck/` folder, with complete file protection; each run
replaces the folder. The screen lists each step, and the same lines are logged with `Logger`
as private values.

Writing photos to the app's container is acceptable here only because this is a debug tool.
Release builds never write photos to the container: photos go from memory to Photos (AGENTS.md,
"Photos never linger").

### Running it

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your own team ID.
2. In Xcode, choose the `NopeApp` scheme and your device. In Product › Scheme › Edit Scheme ›
   Run, keep the Build Configuration at Debug, and under Arguments add `-NopeTagCheck` to
   "Arguments Passed On Launch". Run.
   From the command line, after installing a Debug build:
   ```sh
   xcrun devicectl device process launch --device <device-id> com.photivra.nope.dev -NopeTagCheck
   ```
3. Tap Allow, point the phone at a well-lit scene, and keep it still until the list says
   "Finished".
4. Keep the device unlocked (the files use complete file protection) and copy the folder to the
   Mac:
   ```sh
   xcrun devicectl device copy from --device <device-id> \
     --domain-type appDataContainer --domain-identifier com.photivra.nope.dev \
     --source Documents/TagCheck --destination TagCheckOutput
   ```
   `xcrun devicectl list devices` shows the device identifier.
5. Dump the tags:
   ```sh
   swift scripts/dump-tags.swift TagCheckOutput
   ```

### The tag dumper

`scripts/dump-tags.swift` uses only Foundation and ImageIO; it reads local files and never
uploads or fetches anything. For each DNG, TIFF, HEIC or JPEG file it prints:

- every ImageIO property dictionary (`CGImageSourceCopyPropertiesAtIndex`), including
  `{MakerApple}`, `{Exif}`, `{TIFF}`, `{DNG}`, `{GPS}` and `{IPTC}`, and every XMP tag
  (`CGImageSourceCopyMetadataAtIndex`, enumerated recursively);
- for DNG and TIFF, a walk of the file's TIFF structure: every entry's tag ID and name (TIFF
  6.0, EXIF 3.0 and DNG 1.7 names, "Unknown" otherwise), type, count and a short value preview,
  following SubIFDs, the EXIF IFD, the GPS IFD and the interoperability IFD.

It writes the same report as `tags-report.txt` and `tags-report.json` in the input folder, or
in the folder given with `--out`. `--redact` replaces serial numbers, unique IDs, owner names,
GPS values and maker note contents with `<redacted>`, for sharing a report.

**Never commit captured files or tag reports.** They contain the device's serial numbers and
unique IDs. `.gitignore` ignores `TagCheckOutput/` and `tags-report.*`; keep the output there.
Post only redacted reports, and only the tag lists, in issues and pull requests.

`scripts/test-dump-tags.sh` tests the TIFF walker against synthetic TIFF files built in memory:
both byte orders, every pointer IFD, redaction, and truncated, corrupt and looping input. It runs
in the `unit-tests` CI job.
