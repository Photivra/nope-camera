# Testing

Every change ships with tests (AGENTS.md, "Full test coverage"). This page says how to run them.
Local toolchain: Xcode 27.2 with the iOS 27.2 Simulator. The app supports iOS and iPadOS 26.0
and later, and its Apple Watch app watchOS 26.0 and later (issue #78).

## Quick checks (seconds, no build)

```sh
scripts/check-repo.sh
scripts/test-check-security.sh && scripts/check-security.sh
scripts/test-check-architecture.sh && scripts/check-architecture.sh
scripts/test-check-localization.sh && scripts/check-localization.sh
scripts/test-check-coverage.sh
scripts/test-dump-tags.sh   # macOS only: the tag dumper's TIFF walker
scripts/test-check-file-compat.sh
scripts/test-check-launch-screen.sh && scripts/check-launch-screen.sh   # add a built .app to check its Info.plist
scripts/test-check-app-store-id.sh
```

Before the release build, `scripts/check-app-store-id.sh` must pass: it fails while
`AboutScreen.appStoreID` is `nil`, and 1.0.0 ships with its Rate or Review row. It isn't run on
pull requests, because the id exists only once the app's App Store Connect record does
(`docs/SECURITY_AUDIT.md`, check 7).

`check-security.sh` reads tracked files only (`git ls-files`), so stage new files before running
it.

## The website

The public site (`docs/design/nope-site.md`) has its own build and checks, separate from the app's
CI: the `site` workflow (`.github/workflows/pages.yml`) runs them on pull requests that touch the
site or its sources, and before every publication.

```sh
(cd site && npm ci --ignore-scripts)   # once: the pinned Tailwind CLI and check tools
scripts/test-check-site.sh             # each build rule and check, with a passing and a failing case
scripts/check-site.sh --preview        # build, then every check; --static-only skips Chrome and Java
```

`check-site.sh` builds `_site/`, then runs `scripts/site_checks.py` (the site's promises, links,
search tags, truth rules and size budgets), the Nu HTML Checker (needs Java 11 or later; set `JAVA`
to use another one), a page load with axe-core in headless Chrome for every page in both themes at
1280 and 320 pixels (`site/checks/browser-checks.mjs`), and Lighthouse on the mobile profile with
the floors of the design, section 14.3 (`site/checks/lighthouse.mjs`). Everything runs against
`127.0.0.1`. Without `--preview` the build also refuses an unfinished policy; `--preview` skips only
that rule, and the policy's version and dates while it is unfinished (`docs/RELEASING.md`).

The `site build and checks` job is path-filtered, so it isn't a required status check: a pull
request that touches none of its paths never runs it and would wait for it forever. A change to a
string of `Sources/NopeUI/AccessibilitySettingsView.swift` runs it too, and fails it when a
sentence of the accessibility page is no longer one of that screen's strings, until
`site/content/accessibility.json` is updated to match.

Lighthouse's `robots-txt` audit is skipped: Lighthouse fetches `robots.txt` from inside the page,
and the site's Content-Security-Policy (`default-src 'none'`) blocks that fetch, so the audit
reports a CSP violation rather than anything about the file. `site_checks.py` checks the file's
lines instead.

**Manual pass of the site** (design, section 9: VoiceOver in Safari on iPhone and on a Mac,
keyboard only, 200% and 400% zoom, 320 px wide, both themes, print preview at Letter and A4):
not yet done. Record the date, devices and result here.

## Unit tests and coverage

The logic modules are tested with Swift Testing, against fakes of the hardware protocols:

```sh
xcodebuild test -scheme NopeKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' \
  -derivedDataPath DerivedData -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -Xllvm -instrprof-atomic-counter-update-all'
scripts/check-coverage.sh DerivedData
```

Keep the `OTHER_SWIFT_FLAGS` line (CI passes it too). Swift Testing runs tests in parallel, and
coverage counters are plain, non-atomic increments by default, so two threads running the same
code can lose a count. Swift's coverage data derives some regions by subtraction (for example the
`else` arm is the parent's count minus the `then` arm's), so a lost count in the parent can make
a region that ran show as 0. That is why the gate sometimes reported
`HEIFReader.swift: 134/135 regions` (issue #59), and `LensCatalog.swift: 36/37` in a local run
without the flag, though a test does run that code. `-instrprof-atomic-counter-update-all` makes
every counter update atomic (LLVM's `InstrProfiling` pass option, the same as Clang's
`-fprofile-update=atomic`), so the counts are exact; it changes only coverage builds. With it,
the unit tests and the gate passed 5 times in a row locally with 100% each time (2026-11-14).

`check-coverage.sh` requires 100% of lines and regions in `NopeCore`, `NopeCapture`,
`NopeDevelop` and `NopeSigning`. Swift's coverage data records each branch arm (each `switch`
case, each side of a ternary or `guard`) as a region and has no separate branch records, so
100% region coverage is how branch coverage is measured; branch records are checked too if a
future toolchain emits them.

The only files excluded are hardware adapters listed in `scripts/coverage-exclusions.txt`:

| File | Why it can't run in a unit test | Verified by |
|---|---|---|
| `Sources/NopeCapture/SystemCameraAuthorization.swift` | Requesting access shows a system prompt | On-device check |
| `Sources/NopeCapture/SystemCaptureHardware.swift` | The capture session, camera input and photo output need camera hardware | On-device check |
| `Sources/NopeCapture/SystemLiveView.swift` | The live analysis video output and the readout's key-value observations need a running camera | On-device check |
| `Sources/NopeCapture/PreviewRotation.swift` | `AVCaptureDevice.RotationCoordinator` needs a camera device | On-device check |
| `Sources/NopeSigning/SecureEnclaveSigningKey.swift` | The Simulator has no Secure Enclave (the key, its signing and `SecureEnclaveKeyProvider`) | On-device check |
| `Sources/NopeCapture/PhotoKitLibrary.swift` | Asking for add-only access shows a system prompt, and adding changes the person's library | On-device check |
| `Sources/NopeDevelop/CoreImageRAWRenderer.swift` | Core Image's RAW filter needs a real Bayer DNG; ImageIO and Core Image don't decode a hand-built one | On-device check |

Each excluded file is a thin wrapper; its logic lives in a tested file. For capture, the
decisions are in `LensCatalog` (which cameras and formats), `CapturePolicy` (every processing
switch), `PhotoSettingsFactory` (the photo settings) and `CaptureReadiness` (when to capture),
and `AVFoundationCaptureBackend` is tested against a fake `CaptureHardware`. For saving, the
decisions are in `PhotoKitMapping` (resource types and access), and `RAWDeveloper` and
`PhotoEncoder` are tested with a fake renderer.

### Metadata tests

- `MetadataPlanTests` asserts the exact tags each format may carry for all 8,192 switch
  combinations, signed and unsigned, against a hand-written table (`ExpectedTags`), and the
  exact ImageIO dictionary each file is written with.
- `MetadataReaderTests` covers the project's own tag reader: every TIFF directory in both byte
  orders, JPEG segments, HEIF boxes, items, properties and references, XMP, and every malformed
  case.
- `MetadataFailClosedFuzzTests` injects a simulated future system tag (`0xC7FF`) into every
  format and directory for random switch combinations, any tag off the allowlist, unexpected
  segments and items, and thousands of randomly damaged and random files (seeded, so runs are
  reproducible): every injected file is rejected and nothing crashes.
- `PhotoSaverTests` runs the whole save pipeline with fakes: nothing that fails the read-back
  reaches the library, and a signer that changes the RAW data is rejected.
- `ImageIOReadBackTests` and `RAWDeveloperTests` (`NopeDevelop`) encode real HEIF and JPEG files
  in the Simulator and read them back clean for the first-launch and all-on settings. `NopeUI` is not part of
the coverage gate: it is covered by UI tests and accessibility audits instead.

### RAW not saved without four TIFF fields (issue #65)

**How it was found.** On an iPhone 16 Pro Max (iOS 27.2.1), every Bayer RAW capture failed
("The photo wasn't taken. Try again.") with the default "Remove all optional details". Debug
runs on the device showed that `AVCapturePhoto.fileDataRepresentation(with:)` returned `nil`:
it needs `DateTime`, `Make`, `Model` and `Software` in the replacement metadata's `{TIFF}`
dictionary. Leaving out any one fails; an empty text for each works; `NSNull` doesn't.

**Tests.** `MetadataPropertiesTests.rawPropertiesAlwaysHoldTheFourTIFFFields` checks, for all
8,192 switch combinations, that a DNG's dictionary has the four keys, each the system's value
when its switch is on and empty when it is off, and that HEIF and JPEG don't get them.
`MetadataVerifierTests.emptyTIFFFieldsInADNGAreAcceptedInEveryEncoding` checks that the read-back
accepts every way a TIFF writer can store an empty text (one NUL, a count of 0, several NULs)
and the tag left out, and rejects a space, any text and a non-text value. Which encoding
AVFoundation writes is a device check (`docs/PRIVACY.md`, "Device checks").

### RAW pairs not saved (PhotoKit error 3300)

**How it was found.** On an iPhone 16 Pro Max (iOS 27.2.1, Debug build of 0.2.0), every photo
that saved a RAW together with a HEIF or JPEG failed with "Not saved: the photo library couldn't
add the photo. Try again.", on the 0.6× and 5× lenses, in manual mode. RAW only, JPEG only and
HEIF plus JPEG saved. The DNG itself, signed, is accepted.

**Cause (measured in the iOS 27.2 Simulator, 2026-11-15).** The app's own files (the fixtures of
the file compatibility matrix below) added to the Simulator's photo library through the app with
add-only access: a `PHAssetCreationRequest` with a `.photo` and an `.alternatePhoto` fails with
`PHPhotosErrorDomain` 3300 (`PHPhotosErrorChangeNotSupported`, "The change request is not
supported as configured") whenever the alternate is added from memory
(`addResource(with:data:options:)`): a DNG with a HEIF or a JPEG, in either order, with or
without type identifiers or matching file names, with any `originalResourceChoice`, and also with
read-write access. The shape in Apple's RAW capture article (the DNG from a file, the processed
copy from memory) fails the same way. The same pair succeeds when the alternate is added from a
file (`addResource(with:fileURL:options:)`), with or without `shouldMoveFile`, whether the main
file comes from memory or from a file. Single resources from memory succeed, which matches the
device. The Photos daemon logs "PhotoKit validation failed" before reading the files, so the file
contents aren't the cause. Apple's documentation doesn't state this rule.

**Fix.** `PhotoKitLibrary` adds each pair's alternate from a file and everything else from
memory (`PhotoKitMapping.Resource.addsFromFile`, `PhotoKitMapping.prepare(_:stage:)`). The file
is written by `ResourceStaging` (protected until the first unlock after the device starts,
so it can be written and read while the device is locked) under a random name in the app's
temporary directory, moved into the library (`shouldMoveFile`), and anything left is deleted as
soon as the change ends, whether or not it succeeded. If the file can't be written (for example,
before the first unlock after the device starts, or when storage is full), the pair is saved
as two photos from memory, so the photo is still saved. A failed change logs the error's domain
and code (and its underlying error's), and each request's resource types, marked private; the
person sees only the plain banner. A Debug build run from Xcode shows the private values in
Xcode's console (an assumption from developer reports, not from Apple's documentation).

**Tests.** `PhotoKitRequestShapeTests` (`NopeCaptureTests`) checks every format combination
(RAW, HEIF, JPEG alone and in every combination, which is also every lens's processed fallback),
with each pairing: every request has one `.photo` first, from memory, and at most one
`.alternatePhoto`, from a file, only with a DNG as the main file; every file is saved exactly
once; only the alternate is staged; and when staging fails, each file is its own request.
Burst, bracket, interval, Astro and comparison frames go through the same `PhotoSaver` call, so
the same shapes. `ResourceStagingTests` checks the file names, contents and deletion. Checked by
hand in the iOS 27.2 Simulator on 2026-11-15 with the real `PhotoKitLibrary` and the fixtures
of six cases (first launch signed, every item on unsigned, ultra wide, telephoto, front camera
mirrored, a burst and an Astro frame): all 7 format combinations with both pairings saved, the
library held the DNG as `.photo` with the chosen copy as `.alternatePhoto` and the other copy
on its own, and no file was left in the temporary directory.

### Developed looks

The RAW renderer can't run on a hand-built DNG, so one test needs a real DNG and is skipped
unless it gets one. Never commit the file (`docs/TESTING.md`, "Tag check").

```sh
TEST_RUNNER_NOPE_TEST_DNG=/path/to/photo.dng xcodebuild test -scheme NopeKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' -only-testing:NopeDevelopTests
```

`DevelopedLookTests.flatIsLinearAndStandardHasACurve` renders the DNG at 0 and +1 EV in linear
Display P3: with the Flat look every mid-tone value doubles (no tone curve); with the Standard
look it doesn't. Run on 2026-11-12 in the iOS 27.2 Simulator with a DNG from the device tag
check: passed (on macOS 27 the median ratio was 2.01 for Flat and 2.51 for Standard).

The wording that the app turns off noise reduction, sharpening and local tone mapping for the
HEIF and JPEG copies rests on the RAW decoder settings the renderer sets (`NeutralDevelopment`).
Two tests cover them:

- `NeutralDevelopmentTests` (always runs) checks, with a fake decoder, that noise reduction
  (luminance and color), sharpening, detail, moiré reduction, local contrast and local tone
  mapping are set to 0 and lens correction is turned off wherever the decoder offers them, that
  settings it doesn't offer are left alone, and the tone curve of each look.
- `DevelopedLookTests.theDecoderKeepsTheNeutralSettings` (opt-in, with the DNG above) reads the
  same values back from Core Image's own `CIRAWFilter` after the renderer has set them. Run it on
  the iOS 26 and iOS 27 Simulators, since the decoder can differ between versions. Not yet run
  (no DNG on this branch's runs).

What a setting of 0 means is Apple's (`CIRAWFilter.h`); demosaicing itself smooths, and noise
reduction turned off means none is added. A device check compares one HEIF of a flat gray card with a
plain development of the same DNG (still to be done).

## File compatibility (issue #58)

Every file the app can save must open (AGENTS.md, "Every setting the device allows"). This has two
parts: an automated matrix of generated files, and a recorded table of manual checks in other
apps.

### The automated matrix

`FileCompatibilityTests` (`Tests/NopeSigningTests`) saves every format and setting the app
offers through the real save pipeline: `PhotoSaver` with `RAWDeveloper`, the system HEIF and
JPEG encoders, `ImageIOReadBack`, the metadata allowlist and `ContentCredentialsSigner` with the
Simulator's software key. Only the camera is replaced. No device files or anyone's photos are
used:

- the DNG is written by a test-only writer (`FixtureDNG`) from exactly the replacement metadata
  `MetadataPlan` builds for it, as AVFoundation does on a device, with generic camera and lens
  names;
- the RAW renderer is a stand-in that returns a flat 256 × 256, 16-bit Display P3 image with the
  DNG's own ImageIO properties, as `CoreImageRAWRenderer` does;
- the processed fallback HEIF and JPEG are written by the system encoder with the dictionary the
  capture backend gives AVFoundation.

The cases (260 files; `theMatrixCoversEveryOption` fails if an option is added without one):

| Group | Cases | Files |
|---|---|---|
| Metadata switch classes | first launch, each of the 13 items alone (with a name and copyright for "Your name and copyright", a location for "Location"), and every item on; each signed and unsigned | DNG, HEIF, JPEG |
| Lenses | ultra wide, wide, telephoto and front, every item on, signed | DNG, HEIF, JPEG |
| File options | each compression (system default, maximum, high, medium) × HEIF 8 and 10 bits × Display P3 and sRGB × Standard and Flat, signed | HEIF, JPEG |
| Processed fallback | HEIF and JPEG, first launch and every item on, signed and unsigned | HEIF or JPEG |
| Orientation | all eight orientations, as taken (wide) and mirrored (front); a mirrored fallback HEIF and JPEG | DNG, HEIF, JPEG |
| Location | on with a southern, western, below-sea-level location; on without an altitude; off with a location available | DNG, HEIF, JPEG |
| Series | bracket frames at −2, 0 and +2 EV, three burst frames, three Astro frames (10 s, ISO 3200), with exposure settings, date and sub-second time on | DNG, HEIF, JPEG |

Each saved file must:

- open in ImageIO as its own type (`com.adobe.raw-image`, `public.heic`, `public.jpeg`) with
  exactly one image;
- report the expected orientation: the system's, mirrored for a mirrored photo
  (`MetadataPlan.mirroredOrientation(_:)`), and 1 for a developed copy;
- report the expected bit depth (16 for the DNG, the chosen 8 or 10 for a developed HEIF, 10 for
  the fallback HEIF, 8 for JPEG), and for HEIF and JPEG decode at 256 × 256 in the chosen color
  space with an ICC profile (`ProfileName`);
- carry exactly its allowlisted tags: no read-back violation, and every non-empty value the plan
  wrote is in the file (compared with the project's tag reader: ImageIO doesn't report an empty
  `Make` in a DNG, or `OffsetTimeOriginal` in a DNG without `DateTimeOriginal`, though both are
  in the file; iOS 27.2 Simulator, 2026-11-14);
- when signed, validate with the C2PA library's reader: `Valid`, the hash assertion matches,
  and `signingCredential.untrusted` (the anonymous per-photo certificate) is the only failure;
  when unsigned, carry no manifest.

If a photo isn't saved at all, the test records each file's read-back violations.

**What it found.** With "Lens make and model" on and a HEIF or JPEG selected, no photo was
saved: ImageIO reports a DNG's `LensSpecification` and `LensModel` again under `{ExifAux}`, the
developed copy copied those keys, and ImageIO wrote them into the HEIF and JPEG as XMP
(`aux:LensInfo`, `aux:Lens`), which the read-back rejects. Fixed: a HEIF or JPEG never gets
`{ExifAux}` values (`MetadataPlan.isWritten(_:in:)`); the EXIF lens tags carry the same values.
Every other combination passed before the fix. Whether a camera DNG makes ImageIO report
`{ExifAux}` the same way is a device check below.

**What it can't show.** The DNG's layout comes from AVFoundation on a device, not from
`FixtureDNG`; ImageIO doesn't decode a hand-built DNG's pixels, so DNG colors, exposure and
editing are checked by hand; the Standard and Flat looks differ only in the rendered pixels,
which the stand-in renderer doesn't make (the looks are checked by "Developed looks" above); the lens correction opcodes and the contents of Apple's maker note come only from
the camera, so the fixtures have none (the maker note fixture is an opaque block).

### External validators

Run the tests with `TEST_RUNNER_NOPE_COMPAT_FIXTURES=<directory>` to also write every file there
with a `manifest.tsv` (name, format, signed, device-processed), then:

```sh
TEST_RUNNER_NOPE_COMPAT_FIXTURES=$PWD/compat-fixtures xcodebuild test -scheme NopeKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' \
  -only-testing:NopeSigningTests/FileCompatibilityTests
scripts/check-file-compat.sh compat-fixtures          # every validator that is installed
# The pinned, checksum-verified validators CI uses, in a directory of your choice:
PATH="$(scripts/install-file-validators.sh "$PWD/build/file-validators"):$PATH" \
  scripts/check-file-compat.sh --require "c2patool exiftool" compat-fixtures
```

`check-file-compat.sh` runs c2patool on every file (signed: `Valid` with
`signingCredential.untrusted` the only failure; unsigned: no manifest), `exiftool -validate` on
every file (errors fail, warnings are printed) and Adobe's `dng_validate` on every DNG when it is
installed. None of them is part of the app. c2patool and exiftool are maintainer-approved for CI
(`security/allowed-dependencies.txt`, `THIRD_PARTY.md`): `scripts/install-file-validators.sh`
downloads c2patool 0.28.4 (the project's universal macOS release asset) and exiftool 13.55 (the
latest production release, from SourceForge or CPAN), checks each against its pinned SHA-256
before unpacking it, and checks the installed versions. CI writes the fixtures in `unit-tests`,
and the `file-compat` job runs on every build with `--require "c2patool exiftool"`, so a missing
validator fails it. `dng_validate` isn't approved and doesn't run in CI. Updating a pin is a
reviewed change to the script, with the new checksum.
`scripts/test-check-file-compat.sh` tests the script with stand-in validators.

**Run locally on 2026-11-16** with `scripts/install-file-validators.sh` (c2patool 0.28.4,
exiftool 13.55) on the 280 fixtures of this branch: `check-file-compat.sh --require "c2patool
exiftool"` passed. c2patool reported every signed file `Valid` with `signingCredential.untrusted`
the only failure, and no manifest in any unsigned file; exiftool `-validate` reported no errors.
It printed warnings, which don't fail the check: on 106 of the JPEGs, "Missing required JPEG"
tags `YCbCrPositioning` (0x0213), `ComponentsConfiguration` (0x9101) and on 90 of them
`ColorSpace` (0xA001), on 19 `GPSVersionID` and on 6 `ExifVersion`; on 45 DNGs, "[minor] Invalid
date/time format for EXIF:ModifyDate" (the empty `DateTime` a DNG carries with Date and Time off,
issue #65). The JPEG tags are on the allowlist where they apply but ImageIO didn't write them;
the files open. Whether to supply them is a follow-up.

**Run locally on 2026-11-14** (Mac with macOS 27.2.1, iOS 27.2 Simulator), on the 260 files:
c2patool 0.29.0 (installed on the Mac by hand) reported every signed file `Valid` with
`signingCredential.untrusted` the only failure and found no manifest in any unsigned file; `sips`
on macOS opened every file as its type (62 DNG, 99 HEIC, 99 JPEG). exiftool and `dng_validate`
weren't installed, so they haven't been run on these files.

### Standard File Tags

The matrix saves every case with Standard File Tags on (the default) except `standardTagsOff`:
first launch and every item on, signed and unsigned, as RAW, HEIF and JPEG and as each processed
fallback, with the minimal set (`theMatrixCoversEveryOption` requires both states, for every
format and each fallback). `StandardFileTagsEncodingTests` encodes HEIF and JPEG in each color
space and checks what ImageIO keeps: every tag, except `ColorSpace` in a Display P3 JPEG, which
ImageIO drops; the read-back passes either way.

`exiftool -validate` on the 300 fixtures (iOS 27.2 Simulator, exiftool 13.55, 2026-11-16; no
errors in any file). **With them on:** HEIF and DNG files report no warnings; a DNG without its date
no longer reports "Invalid date/time format for EXIF:ModifyDate" (exiftool accepts the standard's
blank form, `    :  :     :  :  `, and reports the empty text); the GPS version, `ExifVersion` and
`ComponentsConfiguration` warnings are gone. Two remain on JPEGs, because ImageIO can't write
those tags (`docs/PRIVACY.md`, "Standard File Tags"): "Missing required JPEG IFD0 tag 0x0213
YCbCrPositioning" (106 JPEGs, all of them) and "Missing required JPEG ExifIFD tag 0xa001
ColorSpace" (90, the Display P3 ones). **With them off** (the `standardTagsOff` cases): the
minimal set's warnings, on JPEGs `YCbCrPositioning`, `ColorSpace`, `ComponentsConfiguration`,
`ExifVersion` (processed fallback) and `GPSVersionID` (with a location), and on DNGs the
`ModifyDate` format.

**Device checks:** with Standard File Tags on (the default) and the date off, a RAW is saved on
each lens and its `DateTime` is the 19-character blank date or empty (both pass the read-back;
note which); with it on and Location on, the HEIF, JPEG and DNG carry `GPSVersionID` 2.3.0.0; an
exiftool dump of a JPEG and a HEIF shows `ComponentsConfiguration`, `FlashpixVersion` and
`ColorSpace` as in `docs/PRIVACY.md`; the processed fallback keeps the system's own values where
it has them. With it off, the files match the earlier minimal set.

### Manual checks in other apps

Record each result with the file it was checked on (a photo taken on a device with the release's
build), the app and its version, the date, and what was seen: opens, orientation, colors and
exposure, metadata as in `docs/PRIVACY.md`, and the signature where the app shows it. Write only
what was observed; a cell stays "not yet checked" until someone checks it.

Files: **DNG** (each lens, signed), **DNG unsigned**, **HEIF 10-bit P3**, **HEIF 8-bit sRGB**,
**JPEG**, **Fallback** (a lens without Bayer RAW), **Mirrored** (front camera, Mirror Front
Camera on), **Series** (a bracket, burst or Astro frame).

Release 0.2.0:

| App | DNG | DNG unsigned | HEIF 10-bit P3 | HEIF 8-bit sRGB | JPEG | Fallback | Mirrored | Series |
|---|---|---|---|---|---|---|---|---|
| Photos on iPhone (including editing the RAW) | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| Photos on iPad | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| Photos on Mac (including editing the RAW) | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| Preview on Mac | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| RAW editor 1 (for example Lightroom) | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| RAW editor 2 (for example darktable or RawTherapee) | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| Google Photos | — | — | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| Windows Photos | — | — | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| Upload to a sharing site (for example iNaturalist, JPEG) | — | — | — | — | not yet checked | — | — | — |
| exiftool `-validate` on the device files | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |
| `dng_validate` on the device files | not yet checked | not yet checked | — | — | — | — | — | not yet checked |
| c2patool on the device files | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked | not yet checked |

"—" means the issue's matrix doesn't ask for that combination. If a file fails in an app, open an
issue; a setting whose files don't open is fixed or stops being offered.

**Device checks for this matrix:** with "Lens make and model" on, a RAW plus HEIF plus JPEG photo
is saved on each lens (the `{ExifAux}` fix above), and its HEIF and JPEG carry EXIF `LensModel`
and no XMP `aux:` properties (exiftool `-a -G1`).

## UI tests and accessibility audits

```sh
xcodebuild test -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=27.2' CODE_SIGNING_ALLOWED=NO
```

The same tests run on an iPhone and an iPad Simulator, one at a time (running both at once
stalled the test runner on the CI runner), in portrait and landscape (`XCUIDevice.orientation`).
The iPhone camera layout stays in portrait when the device turns, and its icons and text turn
upright; the tests check that the window stays portrait, the shutter stays below the picture,
and Settings rotates. On iPad the window rotates and the shutter is in the column beside the
picture. Running the iPhone tests on an iPhone SE (3rd generation) Simulator covers the
4.7-inch layout, where the lens row overlays the bottom of the picture.

The iPhone sideways tests turn the device with `turnSideways(_:to:mode:)`, which polls (every
0.2 seconds, for up to 10) until the camera shows the turned layout: the drive mode named on the
picture, turned to the new side. A turn the app never shows fails the test; it is not skipped,
so a sideways layout can't go untested while the run stays green. The one exception is the
iPhone Duo Simulator, whose outer display doesn't pass the turn to the app: the test is skipped
there, CI doesn't use it, and the turned layout is checked on a device ("iPhone Duo").

The night mode checks (`nonRedPixels`) count every sampled pixel that isn't red or black. On
iPad they leave out the window's bottom trailing corner (`windowCorner(_:)`, 40 points), where
iPadOS draws its window resize control: it is the system's, drawn outside the app's views where
night mode's red can't reach, and `persistentSystemOverlays(.hidden)` hides it only after a
delay. Everything else on the screen must be red or black.

Every test runs in the system's light setting, the Simulator's default, unless it sets dark
with `useAppearance(_:)`; `tearDown` waits (up to 30 seconds) until no photo is being saved,
closes the app, then restores portrait and, only if it changed, light. Settings, Presets, first run and the camera access screens
follow that setting, so their audits run in light; `testSettingsScreensPassAccessibilityAudits`, `testSettingsAtTheLargestTextSize`
and `testSettingsInRightToLeftLayout` set the dark setting, and
`testSettingsScreensPassAccessibilityAuditsInTheLightSetting` and
`testSettingsAtTheLargestTextSizeInTheLightSetting` audit every Settings screen in light,
contrast included (except on iPad, as for dark). `AppearanceUITests` samples the screenshot's
light share to check which screens are light and which dark, including a change of the setting
while Settings is open (the iPhone sheet follows it, the iPad popover keeps its setting until
it closes) and while only the camera shows, and that the camera's own sheets stay dark in the
light setting.

What we observed on the iOS 27.2 Simulator (Xcode 27.2), locally and on the runner: on a new
Simulator whose first change of the light or dark setting came from a test
(`XCUIDevice.appearance`), that change didn't apply, nor did any later one, from a test or from
`xcrun simctl ui <device> appearance`, until the Simulator booted again; the system's own
Settings app stayed light too, and the appearance tests failed on every CI shard (0.97 light
where dark was expected). On new Simulators whose first change came from simctl, every later
change applied, in each of our tries. The cause isn't known. `scripts/run-ui-test-shard.sh`
therefore switches the Simulator to dark and back with simctl before the tests, reads each
setting back and stops the shard if it didn't take, and `useAppearance(_:)` waits up to five
seconds for the device to report the new setting. On a new local Simulator, run
`xcrun simctl ui <device> appearance dark` and then `light` once before these tests (or boot it
again if a test changed the setting first).

The Apple Watch app (issue #63) has its own UI tests on the watch Simulator, with a simulated
phone (`-NopeSimulatedPhone ready|notSigned|notRunning|permissionDenied|unreachable|countdown`,
Debug builds only), because a UI test can't drive a paired iPhone:

```sh
xcodebuild test -project App/NopeCamera.xcodeproj -scheme NopeWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.2' CODE_SIGNING_ALLOWED=NO
```

They run the full accessibility audit in every state (ready, a signed and an unsigned result,
the camera not running, camera access declined, the phone not reachable, the countdown and its
cancel, the delay list, and the largest text size) with no exceptions. The audit flagged the
title "nope." as a label that isn't human-readable, so the watch screen has no title. The watch
tests aren't in the iPhone shard list; CI runs them in their own job.

`audit(_:)` in `NopeAppUITests.swift` runs every audit with these documented exceptions; every
other finding fails the test:

- an element cut by the window's edge (a form row below the fold), and a contrast finding with
  no element, which comes from such a row: the audit measures the clipped edge;
- the same for a row cut by the upper or lower edge of a popover (Settings on iPad). In build
  44098207588 `testSettingsAtTheLargestTextSize` failed on iPad with "Dynamic Type font sizes
  are partially unsupported" on the Choose Details header "In Each Photo", whose frame (695.5
  to 779 points down) ran 27 points past the popover's lower edge (752); the build before it
  passed with the same code in Settings. It wasn't reproduced locally;
- in `OverlayUITests`, a finding on text that was below the fold before the audit: the audit
  scrolls such text into view itself and measures it while the scroll view moves (on iPad at the
  largest text size it reported a manual control row 1,324 points down as low contrast at the
  place it scrolled it to);
- a Dynamic Type finding on text in the bottom fifth of the window: the audit enlarges the text
  past the edge and can't measure it (the same text styles are measured higher up elsewhere);
- the rules added with the 1.0.0 interface, each reviewed in the release code review (issue #79):
  - a "Text clipped" finding on an element in the bottom fifth of the list or popover that
    scrolls it. The finding's full text is "Text of this element may be clipped at larger
    Dynamic Type sizes": as for the Dynamic Type check above, the audit enlarges the text where
    it is and pushes a row at the lower edge past it. On HEIF and JPEG Copies scrolled to its
    end, the audit reported Restore Defaults and the footer under it in three audits in a row,
    on iPhone and in the iPad popover and night-mode sheet, while screenshots taken with each
    finding show both rows whole. A finding higher up fails;
  - a "Text clipped" finding with no element: it can't be placed or measured. The audit
    reported it on the Accessibility page, whose last row is at the lower edge (the recording
    shows every text whole), and on Details in Each Photo with the location notice at the
    largest text size;
  - on iPad, "Potentially inaccessible text" with no element while a popover is open. The
    audit reads the screen's text and reports text it can't match to an element; beside a
    popover it read the camera screen's text that the popover's edge cuts ("ff" and "e. in
    the Settings app." of "Camera Access Is Off" beside the Formats page, "Tint" of the live
    readout beside Viewfinder Overlays, in the failing runs' recordings). The Settings list
    with its search field passed the same check where no text was cut;
  - a contrast finding on a disabled control (the RAW row while it is the only format, the
    button gallery's disabled states, at the tokens' 40% opacity): WCAG 2.2, 1.4.3, exempts
    inactive user interface components from the contrast minimum;
  - in the scrolling camera layout, a contrast finding on a row partly under the pinned Q and
    shutter row (it runs from above the pinned row into it): the audit measures the part the
    pinned row covers. The pinned row's own buttons, and every row wholly above it, are checked;
  - in the button gallery's and the Photo Format sheet's contrast passes, a finding on a
    control cut by the window's edge, and in the sheet's pass one with no element: the same
    two rules as the first item of this list, in helpers that run the contrast check alone.
  - on the Photo Format sheet after it was scrolled, every "Text clipped" finding: the audit
    reported the Show Processed Marker explanation on iPhone and the switch's title in the iPad
    popover (184.5 points wide beside the switch at the default size) as text that may be
    clipped at larger sizes, while screenshots show both whole, the title also at the largest
    text size, where it wraps onto three lines;
  - on iPad, the Dynamic Type check of the Photo Format popover after it was scrolled, an open
    finding: at the largest text size the audit reported the Show Processed Marker switch's
    title, scrolled to the popover's top edge, as "Dynamic Type font sizes are unsupported",
    while the failing run's screenshot shows the title at the largest size. The same rows pass
    the check on iPhone (`testProcessedMarkerOnALensWithoutRAW`). At that size the popover (420
    points wide) shows about three words a line; whether the sheet should replace it at
    accessibility text sizes on iPad, as it does in night mode, is an open design question.
  Two rules of the integration were removed: clipped text of any element in the iPad popover
  after a scroll, and HEIF and JPEG Copies audited at its top only. The Restore Defaults row
  they covered was reported while it was below the fold: a row of a lazy list that isn't laid
  out yet reports a placeholder frame inside the list and reads as hittable, so the tests now
  scroll a Settings page to its end by what the screen shows
  (`scrollToTheEndOfTheSettingsPage`), and `auditSettingsScreens` audits the Copies page at its
  end too;
- the Settings screens at the default text size and right-to-left skip the Dynamic Type check:
  the iOS 27.2 Simulator reported system form section headers and footers as "partially
  unsupported" there, cause unknown; every Settings screen passes the full audit, Dynamic Type
  included, at the largest accessibility text size;
- a Dynamic Type finding on the Details in Each Photo footer "On: each photo keeps only what it
  needs to open. Off: choose each item below." and the header after it, "Location" (in 0.3.0,
  Choose Details and "In Each Photo"): the iPad runner's
  audit reports them although they grow at every text size, which
  `testChooseDetailsTextGrowsAtEveryTextSize` measures (see "Dynamic Type findings on the iPad
  runner");
- open iPad findings, on the manual accessibility pass: the lens buttons' "No RAW" caption in the
  iPad control column is reported as "Dynamic Type font sizes are partially unsupported",
  although it is visibly enlarged at the largest size and passes on iPhone; and the Settings and
  format popovers' section headers are reported as low contrast against the popover's material,
  and some of their rows as clipped text with no element, so those audits skip the contrast check
  and element-less clipped-text findings on iPad (they run both on iPhone), the Viewfinder
  Overlays screen in Settings included. The popover is translucent glass whatever its
  presentation background, so in night mode Settings and the format sheet open as sheets on
  iPad too (red on black needs an opaque background), and the last photo's details and the astro
  settings are sheets on iPad always (their audits run every check on iPad). The audits that
  skip contrast on iPad also skip Dynamic Type findings with no element: in the night-mode
  Settings sheet at the largest text size the audit reported one on the long Choose Details list
  (findings tied to a row still fail);
  three more iPad contrast findings with no visible cause (white text on near-black: the manual
  dial over a white or yellow picture, and the format chip and the failure banner in the scrolling
  layout at the largest text size) are skipped on iPad in `testControlsOverWhiteAndYellowFrames`,
  `testLargestTextSize` and `testBlankPictureAtTheLargestTextSize`, which run every check on
  iPhone;
- `testSpaceTakesAPhoto` is skipped on iPad, an open finding: on the iPad Simulator the Space
  bar reached the focused button instead of the Camera menu's command, and no photo was taken; it
  passes on iPhone. The device check below covers a hardware keyboard on iPad;
- the press-and-hold step of `testTapToFocusLocksWithTheButtonAndUnlocksWithThePill` is skipped
  on iPad, an open finding: on the iPad Simulator the test's 1.2-second press arrived as a tap
  (the focus square moved to the pressed point, unlocked), at the center and off it; it passes
  on iPhone. The device check below covers press and hold on iPad;
- two findings from the 1.0.0 integration, each set aside on one text in one test (an owner
  decision; 2026-11-18, iOS 27.2 Simulator; `isApprovedAuditException` in
  `NopeAppUITests.swift`). The recordings show both texts whole, so both are taken to be false
  findings of the audit; before each release they are checked by hand on an iPad at the
  largest text size (see "On-device checks"). Every other finding on these screens, and every
  finding on these texts in other tests, still fails:
  - `testAssistantAccessPageAtTheLargestTextSize`, on the iPad Air 11-inch (M4) only: "Dynamic
    Type font sizes are partially unsupported" and "Text clipped" on the Assistant Access
    switch's explanation ("Lets Siri, Shortcuts…", in the row `settings.assistantAccess.switch`). In the 720-point popover the
    explanation runs past the list's lower edge and is reached by scrolling. Scrolled fully into
    view, shown whole in the recording, a taller popover (1000 points) and Settings as a sheet
    were each tried: the audit reported the same two findings every time, as it does for the
    switch's title on the iPhone and the iPad Pro, which the test already sets aside. No layout
    change was kept;
  - the Settings audits that walk every page, in night mode
    (`testNightModeSettingsScreensPassAccessibilityAudits`, and the same audit at the largest
    text size and right to left) and in the system appearance
    (`testSettingsScreensPassAccessibilityAudits` and `…InTheLightSetting`): "Text clipped" on
    the Accessibility page's "Pinching to switch lenses is optional. The lens buttons do the
    same.", matched by its text. Reported on the iPad Air 11-inch (M4) in the night mode audit,
    and on the iPhone 18 Pro in all four but the largest text size; the iPhone recording shows
    it whole on two lines too.
    The recording shows the sentence whole on two lines, inside the frame the audit reports;
- a fourth finding from the 1.0.0 integration, set aside after it was measured (an owner
  decision on the third code review, 2026-11-19; `isMeasuredGridStyleFinding` in
  `OverlayUITests.swift`): in `testOverlaySettingsAtTheLargestTextSize`, on the iPhone 18 Pro
  Simulator with iOS 27.2, "Dynamic Type font sizes are partially unsupported" on the "Grid
  Style" text (`settings.overlays.gridStyle`, the inline picker's label, drawn as its section's
  title). `testGridStyleTextGrowsAtEveryTextSize` measures it at each size from Large to the
  largest: 52, 54, 56, 59, 63.7, 69.7, 78, 86.3 and 93.3 points high, 370 wide, taller at every
  step (on the iPad Air 11-inch (M4) Simulator, in the popover: 52 to 93.5 points, 440 wide),
  so the finding is taken to be a false one. Only that finding, on that text, in that test
  is skipped; the measuring test keeps checking that it grows, and a screenshot at the largest
  size is attached to its result;
- a third finding from the 1.0.0 integration is fixed, not set aside:
  `testFirstStartAtTheLargestTextSizeAndRightToLeft` reported a contrast finding on the
  "Ultra Wide" lens row, which the first start's plate covered at the largest text size on iPad.
  The scrolling layout now waits to draw everything that scrolls until the first start ends
  (docs/design/LAUNCH-SCREEN.md, 13), so nothing is under the plate and the test's audit runs
  with no finding set aside;
- on an iPhone held sideways, clipped-text and contrast findings on SwiftUI nodes the audit
  can't tie to an element: it measures turned text in its unturned frame. The same views pass
  every check in portrait; the turned layout is on the manual accessibility pass below;
- on an iPhone held sideways, a contrast finding on turned text itself (an element taller than
  it is wide). The format chip turned over the Simulator's dark gray picture failed the contrast
  check although its pixels are white text on a 20% gray capsule (12.6:1, measured in the
  failing screenshot); the same chip passed turned over a black and over a white picture, and
  unturned over the same gray on iPad. Every other finding on a turned element still fails.

The Simulator has no camera, so `NopeAppUITests` launches Debug builds with
`-NopeSimulatedCamera <scenario>` (`App/NopeApp/DebugTools/SimulatedCameraLaunch.swift`), which
swaps in `SimulatedCaptureBackend` and simulated save steps (`SimulatedSaving.swift`; nothing
touches the Simulator's photo library). Release builds ignore the argument. The scenarios and what
each test checks, with `performAccessibilityAudit()` in every state:

| Scenario | Test |
|---|---|
| `allow` | First-run screen (three statements, Continue); camera ready with the format chip ("single-frame RAW, RAW + HEIF") and the wide lens selected; no thumbnail before the first photo; the shutter gives the last-photo slot "Saved and signed." (a simulated signer stands in for the real one, which `NopeSigningTests` cover); the telephoto (no RAW) turns the format status into the "Processed" marker; full auto shows only the default controls (no Settings button on the stacked camera); the camera flip; the format status's sheet, read-only on a lens without RAW; Q, the quick menu (closes on the shutter and on Q; Settings opens from its foot); signing off is stated after each photo without a warning chip; landscape on iPhone (layout fixed, Settings rotates) and iPad (column); the first run at the largest text size and right-to-left |
| `allow`, `signingFails`, `noRAW` | The last photo (issues #36, #53): after a save the thumbnail is a button named "Last Photo" with a simulated picture; a tap opens the Last Photo viewer, whose Photo Details opens "What's in This Photo", which lists the files, signature (signed, or "Not signed" with the reason), processing (the fallback's "processed by the phone's camera"), the details left out with "Off in Settings", and the timings, at the default and largest text sizes and right-to-left; tapping the thumbnail opens the viewer and not another app, and its Open in Photos brings the Photos app to the front; with `manual` and a bracket, each frame is its own page of the viewer |
| `manual`, `noRAW`, `signingFails` with `-NopeSimulatedSaveSettings` and `-NopeSimulatedFileTags` | What's in This Photo in the 1.0.0 design (`PhotoDetailsUITests.swift`, `docs/design/BUILD-SPEC.md` 3.15; the summary card of issue #118): the summary's head and its four rows, each one element with exact words, in order, a warning row beginning with "Warning"; with the default settings the simulated camera's 1/60 s and ISO 100 and the lens marked "Not in the files"; the group headings in order; Files with "lossless", Display P3 and "One photo: the RAW with its HEIF"; each disclosure row opens and closes (In the Files open at first); the processed fallback's warning, distortion and "didn't change this file's picture" lines and no RAW Sensor Data; the three signature states; the location "Hidden" until Show Value, hidden again after reopening, "nothing to write" and "Off in Settings"; the Every Tag page (groups, a tag's value and setting, search, Show Hidden Values); the value hidden again after the app leaves the screen and returns; audits at the default and largest text sizes, right to left, in night mode (no non-red pixel), sideways and on iPad. `-NopeSimulatedSaveSettings <base64>` (debug builds) writes the save settings JSON, Base64-encoded so the arguments domain still reads the launch's other arguments, into the emptied UI test settings store; `-NopeSimulatedFileTags full` (or `fullNoLocation`) makes the simulated read-back return realistic tags, each only where the current settings' allowlist allows it |
| `noRAW` | A device without RAW (wide and front, no Bayer RAW): the "Processed" marker ("Processed: no RAW on this lens, HEIF" for VoiceOver) and the HEIF fallback in the viewfinder description, portrait and landscape, default and largest text sizes; Space takes a photo |
| `multitasking` | iPad Split View, Slide Over or Stage Manager: "The camera works only when nope. fills the screen.", shutter disabled |
| `-NopeSimulatedViewfinder white` or `yellow` | The camera with a photo, the manual readout and an open dial over a pure white and a pure yellow picture |
| `-NopeSimulatedViewfinderImage <path>` | The simulated picture is the still at that path on the Mac (HEIF, JPEG or PNG), shown whole on black, for store screenshots taken on the Simulator (`SimulatedViewfinderImage.swift`; `ViewfinderStillUITests.swift` checks a white still replaces the gray). Only the picture changes: the histogram, focus peaking and zebras still measure the simulated frame, so screenshots with those overlays on don't describe the still. Use only a photo taken with the app and saved unedited |
| `-NopeSimulatedAppStoreID <digits>` | An App Store ID, so About shows its Rate or Review row (`RateOrReviewUITests.swift`): a link with its App Store header and footer, last on the page; found by search ("rating", "feedback"); audited at the default and largest text sizes, right to left and in night mode (no non-red pixel). Without it the row and its search entry are absent, as in a build with no id. The link is never tapped: the Simulator has no App Store |
| `metadataRejected` | Every file carries a simulated future system tag: "Not saved: nope. couldn't confirm that the photo holds only the details you chose."; also at the largest accessibility text size |
| `photosDenied` | Adding to Photos isn't allowed: the "isn't allowed to add photos" banner with Open Settings |
| `signingFails` | The signer fails: the photo is saved unsigned, the last-photo slot and the "Not Signed" chip say "Saved. Not signed: the signature couldn't be created.", shutter still enabled; also right-to-left, with the bottom row mirrored |
| `signedFileRejected` | Every signed file fails the read-back: the unsigned files are saved, the last-photo slot and the "Not Signed" chip say "Saved. Not signed: the signed file didn't pass the check.", shutter still enabled |
| `interrupted` | The "in use by another app or a call" message, shutter disabled; also at the largest accessibility text size |
| `hot` | The "cool down" message, shutter disabled |
| `captureFails` | The capture failure banner: Try Again, Dismiss |
| `noRAW`, `signingFails`, `allow`, `firstSaveOnly` | The Last Photo viewer (`PhotoViewerUITests.swift`; docs/design/BUILD-SPEC.md, 3.14): a tap on Last Photo opens it on the newest photo with the status and caption facts in the photo's VoiceOver value; Close, Escape and a swipe down close it; swipes and the arrow keys page, oldest first; the three status variants; double tap and pinch zoom with the preview hint (the simulated read-back reports HEIF and JPEG at 4032 × 3024, larger than the 30 × 40 simulated preview); tap hides and shows the controls; Photo Details and Open in Photos; a photo from a running interval series gives New Photo; with `firstSaveOnly` (the first photo is saved, every later save fails) the Photo Not Saved chip, which closes the viewer to the banner; after the background the viewer is closed and shows "Preview Not Kept"; Space closes it and takes no photo; the largest text size, right to left, night mode (no pixel other than red or black), iPhone sideways, iPad in both orientations, and `-NopeSimulatedLockScreenCamera` (no Open in Photos and no previews, as in the Lock Screen camera, so each photo shows "No Preview" and never "has released this one") |
| `blankPicture` | Every photo is blank: after the shutter, one automatic restart and retry, then "The camera isn't sending a picture.", the blank-picture capture message, shutter disabled |
| `denied`, `noCamera` | The access-off screen with Open Settings, and the no-camera screen |
| `allow`, `denied` | Settings, opened from Q on the stacked camera and from the Settings button elsewhere: Settings, Formats, HEIF and JPEG Copies (top and bottom), Details in Each Photo (top and bottom), Accessibility, Honesty (top and bottom), About and the license text, each audited at the default size, at the largest accessibility text size and in right-to-left layout; the format rule (the last format can't be turned off), the HEIF and JPEG Copies row ("Not Saved" with RAW only, otherwise the look) and the privacy rules (the master switch on and signing off by default, one item on makes it "Custom", locked items read "Locked"); `SettingsUITests.swift` covers the root rows, search, Show Processed Marker and the presets' More menu |

UI test launches store settings in their own `UserDefaults` suite, emptied at each launch
(`SimulatedCameraLaunch.settingsStore()`), so every test starts from the defaults and the real
settings are never touched.
| `manual` (with `-NopeSettings.showsManualControls YES`) | Manual controls: hidden without the option; the Manual Controls button ("On" or "Off"); the readout row; a dial with the lens's range, Auto, − and +; "All Auto" from the row's last button; exposure compensation blocked in M; the ultra wide's fixed aperture; Pro Tools (no Interval or Bracketing section) and a 3-frame bracket from the drive strip; the lock pill after AE-L, which unlocks; the Manual Controls button turns manual controls off; interval progress and Stop from the drive strip; clean view from Q; the list at the largest text size; right-to-left |
| `manual`, `dimManual`, `astro`, `manualFirstSaveOnly` | Bracket on the drive strip (`BracketUITests.swift`): the word in full auto and its card (no more than an eighth of the picture), Bracket Settings (Frames, Step, Order, Start Delay, The Frames, the Honesty sentence), the order and frame count on the card and in The Frames, the limited frames in dim light (`dimManual`: ISO 3200 at 1/4 s), the start delay counting down and cancelled by Cancel and the shutter, the saving and saved cards (`astro`: half a second per save), the Bracket group of What's in This Photo, no Bracket on the front camera, a bracket that stops part-way as the first capture (`manualFirstSaveOnly`: the first save works, later ones fail) shows the frame saved on Last Photo and opens the viewer on it; audited at the default and largest text sizes, right to left, in night mode (all red; on iPad the window corner control the system draws is skipped, and Bracket Settings' audit skips the element-less "Potentially inaccessible text" finding for camera text cut by the page sheet's edge, as beside a popover), sideways and on iPad |
| `allow` (clean view) | The no-RAW chip stays visible in clean view |
| `allow` (light and flash) | The Light switch turns the light on with its pill ("25%"), which stays through a photo and in clean view, changes the brightness and turns the light off; the Flash menu and its pill; the light hides the flash pill; no Light or Flash on the ultra wide |
| `lightUnavailable` | The system refuses the light: the "Light Unavailable" warning, cleared by turning Light off |
| `manual` (Astro and night mode, `AstroNightModeUITests`) | Astro turns night mode on; leaving it for Single turns night mode off again; night mode the person turned off and on again in Q while Astro was on, night mode on before Astro (`-NopeSettings.isNightModeOn YES`), and Keep Night Mode After Astro (`-NopeSettings.keepsNightModeAfterAstro YES`) each stay on; the Keep Night Mode After Astro row right after Night Mode, off by default, found by a keyword; audited at the default and largest text sizes, right to left and in night mode. A relaunch, which keeps night mode as it was, can't be tested here (each launch empties the settings): `AstroNightModeTests` covers it |
| `burst` | Burst (docs/design/BURST.md, `BurstUITests`): each photo takes 0.4 s and each save 0.5 s, so a tap ends before a second photo. The idle card ("Fast burst", Start Burst) covers no more than a quarter of the picture; a tap saves one photo and shows no summary; holding the shutter (`press(forDuration:)`) saves three or more and leaves the summary with the measured rate; sliding off the shutter stops the burst; Start Burst, Stop Burst and the shutter; the speed menu (Fast, Slow) and the shutter's value "Burst, fast." or "Burst, slow."; the summary until a lens change; at the largest text size, right to left, in night mode (no pixel that isn't red), sideways and on iPad. XCUITest can't read the screen while a press lasts, so "Release to stop" is covered by the unit tests of the card |
| `allow`, `signingFails`, `photosDenied` with `-NopeSettings.isNightModeOn YES` | Night mode from Q and at launch: the camera with a photo, a warning and the light, at the largest text size, and every Settings screen (default, largest, right-to-left); a screenshot check finds no white, green or blue pixel outside the viewfinder and the status bar; the viewfinder stays white (natural) by default and turns red with Red Viewfinder |

In right-to-left layout the viewfinder, which `CameraScreen` draws behind the interface, was
placed from the wrong edge: beside the control column (iPad) it sat a column's width to the left
of the picture's frame, under the column, and left a black strip at the picture's right edge.
The warning chips ("Location On", "Not Signed") then crossed the picture's edge, and in build
44075379089 their contrast audit failed on iPad in `testLocationWarningInRightToLeftLayout` and
`testCameraRightToLeftWithAPhotoAndWarnings` (the failing run's screen recording shows the
strip). `testViewfinderFillsThePictureRightToLeft` checks, with a yellow viewfinder, that it
covers the picture's frame to both side edges and nothing outside it.

`testPhotosAccessDeniedIsExplained` failed once on the iPad runner (build 44075379089): the
shutter was pressed and no failure banner came. The app's output in the result bundle has, at
that moment, "onChange(of: CaptureStatus) action tried to update multiple times per frame": the
simulated save fails at once, so the capture status changed several times within one frame, and
SwiftUI ran the camera view's `onChange` action once and dropped the rest, the failure with
them. A small SwiftUI program that changes an observed value three times in one frame shows the
same message, and `onChange(of:)` and `task(id:)` both missed the last value in 12 of 180
rounds, while a loop that waits for the change with `withObservationTracking` and then reads
the value missed none. The camera view now records capture results with such a loop
(`recordCaptureResults()`), so a failure or a save is shown however fast it comes.

At the largest text sizes the screen scrolls, and the audit ignores a contrast issue only for an element that runs past the screen edge (it measures the clipped edge); every other issue still fails (`auditScrollingScreen`).

`testBlankPictureAtTheLargestTextSize` failed intermittently on CI with "Contrast failed" on
the status text (issue #59). The failing runs audited right after the status text appeared,
while the blank-picture retry could still change the screen, and before the screen had stopped
scrolling. The test now waits for the final state ("isn't sending a picture"), scrolls to the
top, and audits only once the layout has stopped moving: the shutter's frame must read the same
twice in a row, half a second apart (`waitUntilStill`), instead of a fixed pause. Issues are
judged after the audit rather than inside its handler (querying the app from the handler can
make the audit time out), and an issue fails the test when two more audits of the same screen
report it again (see "Dynamic Type findings on the iPad runner" below).
It could not be made to fail locally before or after the change (10 runs, 4 of them with every
CPU core busy); after it, it passed 3 times in a row with the whole UI suite.

`CaptureReadinessTests` use a 600-second timeout: the ready answer comes on a fixed read, so the
timeout only has to be longer than any CI runner can take (with 5 seconds, `waitsUntilReady`
failed intermittently while the other tests kept every thread busy).

Right-to-left layout is tested with `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`
(Apple's right-to-left pseudo-language: English text in a mirrored layout). Long text is tested
with `-NSDoubleLocalizedStrings YES` (Apple's double-length pseudo-language: every string is
shown twice), in `testQuickMenuLongLanguage` on the phone and `testDoubleLengthText` on the
watch, each also right to left. These stand in for long and right-to-left languages while the
app ships in English only (issue #86).
In Night Mode, Settings and the Every Tag page show the app's own red search field instead of
the system's (issues #88 and #98): iOS draws the system field as gray glass outside the app's
views, where the red filter can't reach it, and `testNightModeSettingsScreensPassAccessibilityAudits`
found 879 sampled pixels that weren't red or black with it. `NightSearchUITests.swift` checks
that the red field has no non-red pixel at rest, with results and with no result (keyboard
closed), and outside the keyboard's frame while the keyboard is open; that it finds rows by name
and keyword, clears and cancels; that a search is kept when Night Mode changes from outside
Settings (`-NopeSimulatedNightModeSwitch <seconds>[,<seconds>…]`, debug builds, switches Night
Mode as Siri or Control Center do); and the audits at the largest text size and right to left.
`testSettingsRedesignInNightMode` checks that the system field returns, with the Night Mode row
still in view, when Night Mode is turned off.

Keep Screen On (issue #97) is tested with shorter times and a known brightness:
`-NopeKeepScreenOnSeconds <dim>,<lowPowerDim>,<limit>` and `-NopeSimulatedBrightness <0…1>`
(debug builds, `SimulatedScreen`). `KeepScreenOnUITests.swift` checks the row, the dimming and
the Brighten Screen cover, that nothing dims under a sheet or while Battery Low shows, search,
a preset round trip, and that a series doesn't dim a screen already at 10% or darker (issue
#99). XCTest can't read the idle timer; `KeepScreenOnTests` covers it with a fake screen and
clock.
Every new screen and state adds an audit.

### Space between the camera's rows (issue #116)

`CameraSpacingUITests.swift` measures the camera's layout from the frames the accessibility tree
reports (rounded to about half a point, so each check allows 1 point):

- `testCameraRowsShareTheSpareHeight` (iPhone): in full auto, with manual controls on, sideways
  both ways, right to left and in night mode, the picture is the window's width and 4:3 and
  doesn't move; every target in the lens row, the drive strip and the shutter row is at least
  44 points and at least 8 points from the next row's targets; the gap between the lens row and
  the drive strip is the one the spare height gives (`CameraLayout.rowGap(spareHeight:)`); and
  on the screen sizes in `docs/design/finish-1.0.md`, section 1.3, the picture's top edge and the
  gap match the table. Each case is recorded in the result bundle with its measurements and a
  screenshot ("spacing …" attachments).
- `testCameraColumnGivesTheShutterRoom` (iPad): Q and Last Photo are 16 points from the shutter
  in a window at least 600 points tall, in portrait and landscape, right to left and in night
  mode; the picture is 4:3 and beside the column.
- `CameraShellTests` checks the rule itself for each screen size of the design, with the
  safe-area insets measured on the iOS 27.2 Simulators.

Run them on the smallest iPhone (iPhone SE, 3rd generation: the rows overlay the picture), a
6.1 to 6.3-inch iPhone (iPhone 16 or 17), the largest (iPhone 17 Pro Max) and an iPad. Within
the drive strip the targets touch, and within the lens group they are 4 points apart
(`NopeSpace.xxs`), as the design specifies; the 8-point rule is between rows.

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
| `unit-tests` | Coverage gate tests, the tag dumper's TIFF walker test, NopeKit unit tests on the iOS 27.2 Simulator (they also write and upload the file compatibility fixtures), the coverage gate |
| `ui-build` | Builds the app and the UI tests once (`build-for-testing`) and uploads the test run and the apps |
| `ui-tests 1/6` … `6/6` | The UI tests with accessibility audits on the iPhone 18 Pro Simulator, one shard per job (`test-without-building`) |
| `ui-tests-ipad 1/5` … `5/5` | The same tests in five shards on the iPad Air 11-inch (M4) Simulator, except `testSourceCodeIsAnHTTPSLink`: on iPad the About screen's source link isn't found in the Settings popover, an open finding |
| `ui-tests`, `ui-tests-ipad` | Pass only when every iPhone (iPad) shard passed; these are the required status checks |
| `file-compat` | The pinned c2patool and exiftool (`scripts/install-file-validators.sh`) on the fixtures from `unit-tests`; both are required (see "File compatibility") |
| `ui-tests-watch 1/1` | The Apple Watch app's UI tests with accessibility audits on the Apple Watch Series 12 (46mm) Simulator (`NopeWatch` scheme) |
| `ui-tests-watch 1/1 (second runner)` | The same, only when the first job's runner was lost before the job ended |
| `ui-tests-watch` | Passes when the watch tests passed on the first runner or on the second; the required status check |
| `unit-tests (iOS 26)` | The NopeKit unit tests on an iPhone 17 Pro Simulator with iOS 26.5 (no coverage gate: `unit-tests` has it) |
| `ui-tests 1/6 (iOS 26)` | The first iPhone UI test shard on the same iOS 26.5 Simulator, from the `ui-build` build, with `scripts/run-ui-test-shard.sh` and `SIMULATOR_OS=26.5` |
| `ui-tests-watch (watchOS 26)` | The watch UI tests on an Apple Watch Series 11 (46mm) Simulator with watchOS 26.5 |
| `oldest-os` | Passes when the three iOS and watchOS 26 jobs passed |
| `docs` | `scripts/check-docs.sh` |

`.github/workflows/repo-checks.yml` (`repo-checks`) runs the quick checks above.

The jobs above the `oldest-os` rows use the iOS 27.2 and watchOS 27.2 Simulators. The app
supports iOS, iPadOS and watchOS 26 and 27 (issue #78). The `xcode-27` image has no iOS 26 or
watchOS 26 Simulator runtime, and the `macos-26` image, which has them, has no Xcode 27, which
the app needs (it uses iOS 27 APIs behind `#available(iOS 27, *)` checks). So the three iOS
and watchOS 26 jobs run on the `xcode-27` image and first add the runtime they need with
`scripts/add-simulator-runtime.sh <iOS|watchOS> 26.5 <device type> <name>`: when the runtime
isn't installed it downloads Apple's with `xcodebuild -downloadPlatform <platform>
-buildVersion 26.5 -architectureVariant arm64` (once more if that fails), then creates the
Simulator when it isn't there, and prints its identifier. Its simctl calls each have a
two-minute limit and are tried once more; when both tries fail it says so and fails the step. 26.5 (iOS 23F77, watchOS 23T570) is
the newest 26.x runtime in Apple's Simulator runtime index as of 2026-11-18; the version is
`OLDEST_OS` in `build.yml`. The runtimes (8.5 GB for iOS, 4 GB for watchOS) aren't cached:
they don't fit the repository's cache, so each of those jobs downloads one (about 10 minutes,
counted in their time limits). The iPhone 17 Pro and Apple Watch Series 11 are used because
the iPhone 18 Pro and Apple Watch Series 12 Simulators need the 27 runtimes; the watch app runs
with a simulated phone, so the watch needs no paired iPhone. Checked locally on 2026-11-19
with the 26.5 runtimes: the watch UI tests passed on an Apple Watch Series 11 (46mm) with
watchOS 26.5, and on an iPhone 17 Pro with iOS 26.5 the first start, Honesty and focus fade
tests passed. On iOS 26.5 the Simulator reports a SwiftUI `Link` in the About form as a button,
not a link (on iOS 27.2 the same build reports a link), so `app.links[…]` didn't find the
privacy policy or source code link and `testSourceCodeIsAnHTTPSLink` and
`testPrivacyPolicyIsAnHTTPSLink` failed there. Each of the three About links now adds the link
trait and removes the button trait (`.accessibilityAddTraits(.isLink)` and
`.accessibilityRemoveTraits(.isButton)`; adding the link trait alone leaves a button on 26.5),
and both tests, with the Rate or Review link tests, pass on iOS 26.5 and 27.2 (checked locally
on 2026-11-19). Whether VoiceOver on an iOS 26 device says "link" is a device check below. With
the deployment target at
26.0, the compiler also rejects any API newer than iOS or watchOS 26 that isn't behind an
`#available` check. Running on a version 26 device is part of the on-device checks below.

### UI test shards

By the listed times the UI suite takes about 512 minutes of test time on the iPhone Simulator
and 534 on the iPad Simulator on the GitHub macOS runner (about twice as long as on a recent
Mac, so CI limits are sized from runner times, never from local ones). About four fifths of
those times are estimates (`e`, twice a local time), so the runner is expected to measure
less. CI runs it in six iPhone shards and five iPad shards, each its own job:

| Job | Tests (listed times) | With about 7 minutes of setup | Limit |
|---|---|---|---|
| `ui-tests 1/6` … `6/6` | 84 to 90 minutes each | 91 to 97 minutes | 130 minutes |
| `ui-tests-ipad 1/5` … `5/5` | 106 to 109 minutes each | 113 to 116 minutes | 160 minutes |
| `ui-tests 1/6 (iOS 26)` | 84 minutes | 101 minutes, with the runtime download | 140 minutes |
| `ui-tests-watch` | 2 minutes | 13 minutes, with its build | 45 minutes |
| `ui-tests-watch (watchOS 26)` | 2 minutes | 23 minutes, with the runtime download | 70 minutes, with room for the runtime wait |

The 1.0.0 merges (device feedback, Honesty, the first start's plate) brought the listed times
to 122 minutes for each of four iPhone shards and 171 for each of three iPad shards, past the
limits, so 1.0.0 runs six iPhone and five iPad shards, rebalanced from the listed times, with
the limits raised to fit them.

Before that, the 1.0.0 interface had added about 75 UI tests, listed with estimates, and with
three iPhone and two iPad shards an iPad shard came to 124 of its 130 minutes with setup, so a
fourth iPhone shard and a third iPad shard were added. The limits leave room for the wait for a runtime remount (up to 12.5 minutes, see "Simulator
runtime disk images on the runner") and for one second run of unfinished tests after an
infrastructure failure. Until build 44149517211 there were eight shards per device; with fewer,
larger jobs, fewer jobs per build boot a Simulator (12 with the iOS 26 shard, against 17), and the runner's Simulator
failures start in the minutes after a job's first use of the Simulator.

`scripts/ui-test-shards.txt` lists every UI test as `<iPhone shard 1-6> <iPad shard 1-5>
Class/test <seconds>e <seconds>e`: its iPhone shard, its iPad shard and its time in seconds on
the runner on each device, or, with an `e`, an earlier or estimated time
(twice the local time for a new test) until the runner has measured it. Each device's shards
are balanced by its own times (longest test first, into the shard with the least time so
far). To rebalance, take the times from the per-test result files (see "Flaky tests") or from
the `Test Case … passed (n seconds)` lines of the shard jobs' logs; `scripts/ui-test-shards.sh
times` prints each shard's total.

`scripts/ui-test-shards.sh args <iphone|ipad> <n>` prints the `-only-testing` arguments of that
device's shard n, and `count <iphone|ipad>` the number of its shards.
`scripts/ui-test-shards.sh check`, in `repo-checks`, fails when a test in `App/NopeAppUITests` is
listed for no shard or twice, when a listed test doesn't exist, or when the shard matrices or
job names in `build.yml` don't match either device's shards, so a new test can't be skipped
silently: add it to the shard with the least time on each device, with twice its local time
and an `e`.

Each shard job runs `scripts/run-ui-test-shard.sh`: it boots the Simulator and waits until it
has booted (`simctl bootstatus -b`), switches it to dark and back with simctl (so the tests'
changes of the light or dark setting apply, see "UI tests and accessibility audits"), installs the
app and launches it once, then runs the shard. Both scripts first stop the Simulator's
background task scheduler (`scripts/stop-simulator-background-tasks.sh`, see "The Simulator's
background tasks on the runner" below) and its push service (`scripts/stop-simulator-push.sh`,
see "The Simulator's push service on the runner" below). The watch job does the same with `scripts/prepare-simulator.sh` before
`test-without-building`, and names the watch Simulator by the identifier the script prints: on
the runner its name also matches the iPhone it is paired with, and `build-for-testing` stopped
with "multiple devices matched" (`xcodebuild test` had accepted the name). in the 0.3.0 run its first test failed to launch the watch app within
XCTest's limit (301 s) and the next failed to terminate that launch; the watch app hadn't
changed since its last passing run. In build 44075379089 the first watch test again failed to
launch the app ("Timed out while launching application via Xcode", 170 s) and the other seven
passed: the watch's system app answered the test runner at once, but `xcodebuild` started the
launch two minutes later, while it was booting the iPhone Simulator paired with the watch (it
boots that iPhone for a watch test run). `scripts/prepare-simulator.sh` now boots the paired
iPhone too, beside the watch, and waits for both, and it fails if the app can't be launched
once (it ignored a failed launch before). The boots are started before the build
(`--start`, which waits for nothing) and waited for in the test step (see "Preparing the
Simulator has a time limit" below).
In the first sharded CI run, two shards failed before any test started ("The test runner crashed
while preparing to run tests", after 7 to 9 minutes of "Testing started"), and the first test of
two others failed to launch the app within its time limit; both happened on a Simulator the test
runner had to boot itself. Such a run, in which the test runner failed before any test started (any "… while preparing to
run tests" error, including "Test crashed with signal term while preparing to run tests", which
ended an iPad shard of build 43786103024 after its Simulator took five minutes to boot), is an
infrastructure failure and is run again once; a test that failed is never run again (see
"Infrastructure and test failures" below). `scripts/test-ui-test-shards.sh` tests the scripts.

On the runner the tests wait for state rather than assume speed: a new launch waits until the
previous run of the app has exited (`launchAfterThePreviousRunExits()`; a launch right after
`terminate()` sometimes waited out XCTest's minute for a process ID), a tap on the viewfinder
waits until the camera runs, and a value is awaited with a predicate instead of read once. When
an accessibility audit can't finish within XCTest's fixed time ("Audit failed to complete in
time", error -56; XCTest has no setting for it), `performCompleteAccessibilityAudit` runs the same
checks again as one smaller audit per type, so every check still runs. In the second sharded run
the app showed no crash report, and the spindump XCTest took at a failed launch shows the app's
main thread idle in its run loop with 0.014 s of CPU in 75 s while its threads waited to run: the
runner, not the app, was stalled.

#### The Simulator's push service on the runner

In build 44075379089 UI tests failed on six jobs with a different timeout each ("Failed to
terminate", "Timed out while evaluating UI query", "Audit failed to complete in time", "Timed out
while launching application via Xcode"), as in the builds before it. The Simulator system logs in
the failed jobs' result bundles (`xcrun xcresulttool export diagnostics`, then `log show
--archive …/system.logarchive`) show the same thing on every one, iPhone, iPad and watch: the
Simulator's push service (`apsd`) connects to Apple's push server, can't get its device
certificate ("Could not get certificate from simulator with error … Client is not supported"),
closes the connection and connects again at once, without a pause, from boot to the end of the
job: about 500 connections a minute, each with a TLS handshake and a certificate check in
`trustd`, and 1,200 to 1,800 log lines a second (1.77 million lines from `apsd` in the 25 minutes
of one iPhone shard; 312,000 of the 408,000 lines the watch Simulator logged during its failed
launch). On a developer's Mac the same Simulator's `apsd` logged 97 lines in two minutes and
no such error. How much of the runner's three cores this takes wasn't measured.

The timeouts themselves were the whole Simulator standing still, not the app: in the iPhone
shard whose `testPresetsInRightToLeftLayout` timed out on a query, the app answered the test
runner's accessibility requests the whole time, about 17 log lines a second instead of the
usual 230, and in the same two minutes the push service's own reconnects fell from about 700 a
minute to 50. The app showed no crash report or hang in any failed job.

The app has no push notifications and makes no network request, so `scripts/stop-simulator-push.sh`
removes the service from the Simulator's launchd (`launchctl bootout`) after boot; it comes back
when the Simulator boots again. The script first prints how often the service gave up its
connection in the last minute, so each job's log shows whether its runner was affected. No test,
audit or limit changed.

#### The Simulator's background tasks on the runner

In build 44098207588, with the push service stopped, one test timed out in each of six shards
(iPad 1, 3, 5 and 7, iPhone 4 and 5): "Failed to terminate", "does not have a process ID"
after a launch, and a query that took 283 seconds. Two of them ran on Simulators whose push
service had reported no dropped connection. Each failed test ran within ten minutes of its
Simulator's boot, and the Simulator system logs show what ran then: the Simulator's background
task scheduler (`dasd`) started `com.apple.springboard.posterboardupdate.prewarm`, PosterBoard's
prewarm of the wallpaper gallery, which took 127 to 158 seconds, and then the other first-boot
tasks (Spotlight indexing, Health, Siri, Mail and Maps migrations, about 100 in all). Prewarm
and failed test, by the logs' times (UTC):

| Shard | Prewarm | Failed test |
|---|---|---|
| iPad 1 | 14:51:26 to 14:53:48 | 14:50:27 to 14:53:53, terminate failed at 14:53:51 |
| iPad 3 | 14:17:10 to 14:19:48 | 14:16:38 to 14:22:22, stalled from 14:17:29 |
| iPad 5 | 15:15:46 to 15:17:53 | 15:15:59 to 15:19:49 |
| iPad 7 | 14:24:38 to 14:26:55 | 14:24:44 to 14:26:59 |
| iPhone 4 | 15:39:01 to 15:41:16 | 15:39:05 to 15:41:17 |
| iPhone 5 | 14:27:31 to 14:29:39 | 14:27:57 to 14:32:40 |

The spindump XCTest took during the failed launch on iPhone shard 5 (14:29:15) shows the runner
(3 cores, 7 GB) with all three cores busy and short of memory: 25 wallpaper extension processes
and 23 Metal compiler processes of the prewarm, 958 processes in all, and 3.1 of the 7.1 CPU
seconds sampled spent in the kernel, 1.4 of them in its memory compressor and 1.4 reading the
Simulator's disk image. The app had launched (the Simulator reported its process ID six seconds
after the request), and the test runner didn't learn of it for four minutes.

The app has no background modes and schedules no background task, so
`scripts/stop-simulator-background-tasks.sh` removes the scheduler from the Simulator's launchd
(`launchctl bootout`) right after boot, before it starts the tasks; it comes back when the
Simulator boots again. Checked on two new iPad Simulators on a Mac: the one left alone ran the
prewarm (14 seconds there) and about 100 tasks in its first seven minutes, the one with the
scheduler stopped ran none, and services that asked for a task were refused without retrying
in a loop (about 240 log lines in six minutes). No test, audit or limit changed.

#### Simulator runtime disk images on the runner

The failures that ended a Simulator in builds 44124454610 and 44149517211 have one cause, shown
by the disk image service's log (`simdiskimaged.log`) in the 14 result bundles we have from
builds 44098207588, 44124454610 and 44149517211, all on runner image `xcode-27-arm64`
20261104.0337.1. When a job first uses the Simulator, the
service mounts each runtime's disk image. On every runner two of them (watchOS 27.0 and tvOS
27.0) fail to mount the usual way ("Cryptex mount failed … Code=2") and are mounted from a plain
disk image under `/Library/Developer/CoreSimulator/Volumes`; from 147 to 716 seconds after its
start the service tries to mount them again and unmount the first mount, which mostly fails and
leaves things as they were. On two of the 14 runners another runtime failed too at the start
("Disk image operation failed with error code 153"), and those are the two jobs whose Simulator
host process (`SimLaunchHost`) crashed:

| Job | Mount that failed at the start | What followed |
|---|---|---|
| 44124454610, iPad shard 1 | xrOS 27.0 | remounted at +427 s; host process crashed at about +432 s; the first test was cut short |
| 44149517211, iPhone shard 8 | xrOS 27.0 and iOS 27.2, the runtime under test | iOS 27.2 unmounted and remounted at +535 to +550 s; host process crashed three times from +543 s; then "The iOS 27.2 simulator runtime is not available" |

In the 12 other bundles only the two usual runtimes were on plain disk images and the host
process didn't crash. Two more jobs without a result bundle fit the times: iPad shard 8 of
44124454610 ("server died" at about +320 s) and iPad shard 4 of 44149517211, where stopping the
background task scheduler took 9.6 minutes and the install ended with "server died" at about
+707 s; its retry ran into a second loss of the Simulator in the first test and the job's
35-minute limit. Their cause is assumed, not shown.

`scripts/wait-for-simulator-runtimes.sh` runs before a Simulator is booted in the shard and
watch jobs and, before its tests, in `unit-tests (iOS 26)`. It counts from the job's first use
of simctl, which it notes in a file (`SIMULATOR_FIRST_USE_FILE`) when it is the first; in the
three iOS and watchOS 26 jobs that first use is `scripts/add-simulator-runtime.sh`, which notes
the time before its own first simctl call, ten minutes of download earlier, so the later wait
counts from when the disk image service started. It reads `xcrun simctl runtime list -j`. When a runtime other than the two usual ones
(`SIMULATOR_RUNTIMES_ON_DISK_IMAGES` in `build.yml`) is mounted under
`/Library/Developer/CoreSimulator/Volumes`, it waits until 750 seconds have passed, with nothing
booted, so the remounting is over before a Simulator runs: in the bundles the last unmount came
716 seconds after the service started, with nothing later in logs that run to 1,772 seconds.
On other runners it returns at once. The job limits leave room for the wait; no test's time
limit changed. That the wait is enough rests on
those logs: a runner whose runtime under test never mounts the usual way hasn't been seen
through a whole job. Open: a runtime the 26 jobs download is itself mounted from a disk image;
if the runner mounts it under `/Library/Developer/CoreSimulator/Volumes` by design, the wait
would take its full 12.5 minutes in each of those jobs (not seen yet; the job limits allow for
it). After the first run on the runner, add the 26.5 runtime identifiers to
`SIMULATOR_RUNTIMES_ON_DISK_IMAGES` if they are mounted that way in every job.

#### A Simulator that dies on the runner

In build 44124454610 two iPad shards lost their Simulator. In shard 1 the first test stopped at
"Setting up automation session", the test runner was ended ("Test crashed with signal term"),
`xcodebuild` started it again and the other 12 tests passed, but the shard failed on the test
that was cut short. In shard 8 `simctl install` ended with "Mach error -308 (ipc/mig) server
died" before any test ran. Shard 1's result bundle shows the cause: the runner image mounts
some Simulator runtime disk images twice, and a few minutes into the job the Simulator's disk
image service (`simdiskimaged.log`) unmounted the duplicates (tvOS 27.0 at 17:39:46, watchOS
27.0 at 17:39:58; "Image is a duplicate of existing image … preferring cryptex variant").
A minute later the Simulator's host process, under which every booted Simulator runs, crashed
while unloading a library from an unmounted image (`SimLaunchHost.arm64`, 17:41:07,
`EXC_BAD_ACCESS`, `KERN_MEMORY_ERROR` in `dlclose`), and the Simulator's own processes ended
with it (17:41:07 to 17:41:15). "Simulator runtime disk images on
the runner" above has what the two crashes share. Shard 8 uploaded no result bundle, so its
cause is assumed, not shown, to be the same.

This is outside the app and the tests, so such a run is an infrastructure failure and its
unfinished tests are run again once (next section). The first version of that second run,
used in build 44149517211, ran only the tests that had started and had no result: in iPhone
shard 4 the host process crashed in the first test, `xcodebuild` ended the whole run, the one
test cut short ran again and passed, and the job passed although 17 of its 18 tests had never
run. The second run now takes every test without a result, and
`scripts/test-ui-test-shards.sh` has that case.

#### Preparing the Simulator has a time limit

In build 44222358365 the watch job stopped in its step "Find and boot the watch Simulator and
its paired iPhone", which ran `scripts/prepare-simulator.sh`: the step started at 02:35:01 and
never ended, the job was cancelled 55 minutes after it started (its limit was 45), the later
steps stayed pending, and no log exists for the job. That is how a job looks whose runner
stopped answering; which command was running isn't known. That step booted two Simulators
with nothing limiting how long a `simctl` call may take, and it was outside the
infrastructure classification. (In build 44149517211 one `simctl` step of an iPad shard had
taken 9.6 minutes.)

Now every `simctl` call that prepares a Simulator runs under `scripts/with-timeout.sh`, in the
shard jobs and the watch job: 180 seconds to start a boot, 600 to finish it, 180 and 300 to
stop the scheduler and the push service, 300 to install the app, 120 to launch it. A call that
runs out of time fails the preparation, which is an infrastructure failure and is done once
more (next section). The watch job starts both boots before its build without waiting for them
(`prepare-simulator.sh --start`) and waits for them, with those limits, in its test step
(`scripts/run-watch-ui-tests.sh`), so a boot that fails or never finishes is classified and
tried again like any other. Installing the watch app is tried up to three times: on a Mac,
right after the watch and its iPhone had booted, the pairing service removed the app while it
was being installed ("Client appconduitd … requested uninstall") and the next install went
through.

#### A runner that is lost

A time limit inside the job doesn't help when the runner itself is lost, as it may have been
in build 44222358365: nothing in the job runs any more. For the watch tests there is
therefore a second job, `ui-tests-watch 1/1 (second runner)`. The first job's last step notes
that the job ended on its runner (it runs whatever the job's result); the second job runs
only when the first didn't pass and that note is missing. A job that ended on its runner with
a test failure or an infrastructure failure is not run again this way. The required check
`ui-tests-watch` passes when either job passed. The iPhone and iPad shard jobs have no such
second job yet; a lost runner there fails the build.

#### Infrastructure and test failures

`scripts/ui-test-run-lib.sh`, used by the shard jobs and the watch job, classifies a failed
run from its `xcodebuild` log:

- **Test failure:** a test failed with a result (`Test Case '…' failed`). It is never run
  again, whatever else happened in the run. A test that was cut short with no sign that the
  Simulator died (the test runner crashed or was ended) counts as a test failure too.
- **Infrastructure failure:** no test failed with a result, and no test started, or the
  Simulator's host process left a new crash report (`SimLaunchHost*.ips` in
  `~/Library/Logs/DiagnosticReports`), or the log has "simulator runtime is not available" or
  "(ipc/mig) server died". Failing to boot the Simulator or install the app counts as one.

After an infrastructure failure the job reboots the Simulator and runs once more, in the same
job, the tests that have no result yet (the finished ones are passed to `xcodebuild` as
`-skip-testing`); a second infrastructure failure fails the job as one. There is one second
run per job at most, and no workflow-level rerun, so no passed job or test is repeated. The
first run's result bundle is kept and uploaded as `…-interrupted.xcresult`.

The job summary on GitHub names the classification ("ui-tests 2/4: Passed", "Test failure" or
"Infrastructure failure"), says whether a second run happened, and lists the tests that failed
or were cut short.

#### Flaky tests

Each shard job and the watch job uploads its per-test results as an artifact
(`test-results-ui-tests-<n>`, `test-results-ui-tests-ipad-<n>`, `test-results-ui-tests-watch`,
kept 30 days): a JSON Lines file with one line per test and run of it, holding `test`
(Class/test), `result` (`passed`, `failed`, `skipped`, or `interrupted` for a test that
started and has no result), `seconds`, `attempt` (2 for the second run after an infrastructure
failure), `job`, `device`, `shard`, `runner_image`, `run_id`, `run_attempt` and `sha` (the
pull request's head commit).

```sh
scripts/flaky-tests.sh                 # the last 20 runs of the build workflow, with gh
scripts/flaky-tests.sh -n 50 -b main   # more runs, one branch
scripts/flaky-tests.sh --from results  # result files already downloaded
```

It lists, with counts, the tests that passed and failed on the same commit, the tests that
passed and failed across the commits looked at, and the tests that passed only in the second
run after an infrastructure failure.

#### Dynamic Type findings on the iPad runner

In build 44124454610 two iPad tests failed with "Dynamic Type font sizes are partially
unsupported" on text that the failing runs' screen recordings show whole, wrapped and not cut,
at the largest size, and smaller at the smaller sizes the audit switches through:
`testSettingsAtTheLargestTextSize` on the Choose Details footer "On: each photo keeps only what
it needs to open. Off: choose each item below." (frame 30, 428.5, 440 × 267, inside the Settings
popover), and `testLastPhotoDetailsAtTheLargestTextSize` on the Files row title "HEIF" (frame
40, 355.5, 111.5 × 63.5). On a Mac the audit reports no Dynamic Type finding on either screen,
also with every core busy.

`audit(_:)` writes each Dynamic Type issue, and each issue no rule ignores, to the test log
("Audit round n: …", with the type, the element's label and frame, the window's frame and
whether a rule ignored it). In build 44149517211 those lines show what the iPad runner's audit
does: its first pass over a screen at the largest text size reported findings no rule ignores
in five tests (ten findings, nine of them Dynamic Type: the same Choose Details footer in both
Settings tests, five Files rows of the last photo's details, two texts of the compare view),
and the second audit of the same screen three seconds later reported none of them, so all five
tests passed. No iPhone shard had such a finding. The two failures of build 44124454610 were
runs where the second audit still reported one row; in the details test it was a row the first
audit hadn't reported.

The audit's findings on these screens therefore change from one audit to the next while the
screen doesn't. An issue now fails the test when the audit reports it three times in a row: in
the first audit and again in each of two more audits of the same screen (the same type on an
element with the same label). A finding that is real is reported every time and still fails.
Why the runner's first audit reports them isn't known.

In build 44209365138 one finding did pass that rule: in `testNightModeSettingsScreensAtTheLargestTextSize`
on iPad, where Settings is a sheet, all three audits of Choose Details reported the master
switch's footer ("On: each photo keeps only what it needs to open. Off: choose each item
below.", 548 × 167 points) and the header after it ("In Each Photo", 548 × 83.5) as "Dynamic
Type font sizes are partially unsupported"; these are the two texts of the earlier popover
failures. Both are a system `Form` section's footer and header with no font, size limit or line
limit of the app's own. Measured on the iPad Simulator in night mode at each of the nine text
sizes from the default to the largest, each grows at every step (footer height 30, 50, 54.5,
59, 68.5, 77.5, 129.5, 147.5, 167 points; header 40.5, 43, 45.5, 47.5, 53.5, 59.5, 68, 76.5,
83.5), and at the largest size they measure what the runner's audit reported. So the finding
is the audit's, not the layout's. The audit no longer fails on a Dynamic Type finding on these
two texts (by label, `measuredDynamicTypeLabels`), and `testChooseDetailsTextGrowsAtEveryTextSize`
checks what the audit was asked instead, on iPhone and iPad: both texts and the master switch's
title are larger at every text size than at the size before.

#### Audits that don't finish

In build 44185929631 two tests failed with "Audit failed to complete in time" (XCTest's error
-56): `testComparisonShotShowsBothPicturesAndTheirDetails` on iPhone and
`testLastPhotoDetailsAtTheLargestTextSize` on iPad. Both failed in the audit that follows a
scroll (`audit(_:afterScrolling: true)`), in its first pass, so the rule about repeated audits
played no part. XCTest gives an audit 15 seconds. On a Mac the compare test failed the same way
six times out of six: on the compare details, scrolled to the identifier row, the whole audit
ran into the 15 seconds and so did the contrast check alone (the same list's audit before the
scroll took two seconds); `performCompleteAccessibilityAudit`, which runs one audit per check
after such a timeout, has nothing smaller than one check to fall back to. On the iPad runner
the audit of the last photo's details after a scroll had taken about ten seconds when it passed
(build 44149517211).

After a scroll every contrast finding is ignored (see `audit(_:)` above: the rows are
contrast-checked before scrolling), and so are the contrast or Dynamic Type findings of a test
that skips that check. `audit(_:)` and `auditScrollingScreen(_:)` now leave a check whose every
finding is ignored out of the audit, so the slowest check doesn't run where its result was
thrown away; what fails a test is unchanged. With that the compare test passes on a Mac (three
of three runs on iPhone, two of two on iPad). When an audit does time out,
`performCompleteAccessibilityAudit` writes to the test log how long it ran and how long each
check then took alone, which XCTest's error doesn't say. Why the contrast check doesn't finish
on that part of the compare details isn't known.

#### Contrast findings set aside by measurement

An owner decision of 2026-11-19, from a code review of 1.0.0. The contrast audit of the
iOS 26.5 Simulator reported text that screenshots show far above the minimum: the "Guides"
header of Viewfinder Overlays (`testOverlaySettingsAndProTools`), black on `#EFEFF3`, about
18:1, reported in every run on iOS 26.5 and in none on iOS 27.2.

The rule: every audit goes through `performCompleteAccessibilityAudit`
(`UITestSupport.swift`), which, for each contrast finding on an element that exists and lies
wholly in the window, takes a screenshot of the element's frame and measures its contrast
(`MeasuredContrast` in `MeasuredContrast.swift`): the frame's most common color is the
background, and the foreground is the color that at least 0.5% of the frame's pixels reach
(nine pixels at least); the ratio is the WCAG 2.2 contrast of the two. The finding is set aside
only when the measured ratio is **7:1 or more**, WCAG 2.2's enhanced level for text (1.4.6). A
finding measured below 7:1, one on an element that isn't wholly in the window, one with no
element, and every finding of another type go on to the test's own rules as before, so text that
is really low in contrast still fails.

Each finding set aside is written to the test log as "Contrast finding set aside", with the
finding, the element's label, identifier and frame, the measured ratio and the iOS version, and
the element's screenshot is attached to the test result under the same ratio and version. A
finding measured and kept is logged as "Contrast finding kept" with its ratio.
`MeasuredContrastTests` checks the measurement on drawn images: the WCAG formula's fixed points
(21:1 for white on black, 5.25:1 for the night red on black), the background found by count, and
that a few stray pixels can't raise the result.

Night mode's form rows are not set aside this way: the night red is 5.0:1 on their
`#1C0000` (`NopeColor.nightRowUnderMultiply`), below 7:1, so they pass the audit on their own
or fail. Until 2026-11-19 they were `#2C0000` in sheets (4.74:1), which the iOS 26.5 audit reported
as "Contrast nearly passed" (`testProcessedMarkerAtTheLargestTextSizeRightToLeftAndNightMode`,
`testProcessedMarkerOnALensWithoutRAW`).

#### Continue on the first-run screen (open)

In build 44149517211 two tests at the largest text size failed the same way, once each:
`testPresetsAtTheLargestTextSize` (iPhone shard 5) and `testLandscapeAtTheLargestTextSize` (iPad
shard 3). The test tapped Continue on the first-run screen and the camera didn't come within
ten seconds; the hierarchy and the screen recording at the failure still show the first-run
screen. The Simulator's log shows the touch reaching the app (touch down and up 71 ms apart,
then the app's own event dispatch lines), and the steps before the tap took as long as in runs
that passed. Neither ran during a remount of the runtime disk images (19 and 13 minutes into
their jobs). Both tests passed in the two builds before with the same app code, and in 25 local
runs of each on an iPhone Simulator the step worked every time; the camera model received one start request
per launch in a local check. The cause isn't known, and nothing was changed for it.

To run one shard locally, with a Simulator named as in CI:

```sh
xcodebuild build-for-testing -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
scripts/run-ui-test-shard.sh 1 "iPhone 18 Pro" DerivedData/Build/Products ui-tests.xcresult
```

### Siri and Shortcuts in the UI tests

XCTest can't speak to Siri or run a shortcut, so Debug builds take
`-NopeSimulatedShortcut <request>`: a number for Take Photo with that delay in seconds,
`burst<count>` for Take Photo with a count, `bracket<count>` for Take Bracket (darkest first;
`bracket<count>-metered` or `bracket<count>-brightest` for another order),
`lens-ultraWide` for Switch Lens, `preset-factory` for Apply Preset or `interval` for Start
Interval Shooting; several requests separated by commas are sent one after another, and the last
one's answer is shown (`interval,lens-ultraWide` asks for a lens while a series runs). The app sends
the request through the Assistant Access check and the same `ShortcutInbox` the intents use
(`AssistantGate`, issue #82) and shows what Siri would say. Access is off by default, so
`ShortcutUITests` launch with `-NopeSettings.assistantAccess YES -NopeSettings.assistantAsk never`;
`-NopeSimulatedAssistantAnswer cancel` cancels the question that Every Action and Only Before a
Photo ask (it is confirmed otherwise). `AssistantAccessUITests.swift` covers the Settings page
(off and on, Ask First while off, the largest text size, right to left, night mode all red with
the iPad window corner excluded, search, the Lock Screen camera's read-only row) and the requests
through the check: every action refused while access is off with the refusal card and its count,
a cancelled question, the camera's hint and the This Session list, and the tip after five
confirmations. At the largest text size the audit's Dynamic Type check reports the page's switch
title, "Assistant Access", as "partially unsupported" or "Text clipped" on the iPhone and iPad Simulators (iOS 27.2)
wherever it is drawn; that one finding is set aside there, and
`testAssistantAccessTitleGrowsAtEveryTextSize` measures the switch's row growing at all nine
text sizes instead. The check, the session record, the stored settings and presets that keep the
Privacy settings are unit tested in `AssistantAccessTests`. Before Assistant Access, the request
went straight to the inbox, as described here:
(`ShortcutUITests`: a delay with the countdown, a cancelled countdown, no camera access, a burst
of three, a bracket in full auto, a bracket taken brightest first, a lens switch, and a lens switch refused during a series). The Interval drive mode is covered by
`testIntervalShootingFromTheDriveMenuInFullAuto` and the sheet's audits at the largest text size
and right-to-left; a series that stops after a time by `IntervalTimeUITests.swift` (the Stop
After picker, the hours and minutes, "At most", the check that the interval is shorter than the
time, the idle and running cards, audited at the default and largest text sizes, right to left
and in night mode). The request logic (counts, lenses, the light, interval shooting,
requests without a camera screen) is unit tested in `ShortcutTests`; a timed series (its end on
the monotonic clock, a change of the device's time, pausing, ending early, presets and the
duration of Start Interval Shooting) in `IntervalTimeTests`, with a `FakeClock` passed as the
model's `NopeClock`.

## Launch screen

The design and the reasons are in `docs/design/LAUNCH-SCREEN.md`; the build is described in
`docs/ARCHITECTURE.md`, "Launch screen".

Automated:
- `scripts/check-launch-screen.sh [<built .app>]` checks that the `LaunchBackground` color set has
  one color, opaque sRGB black, with no appearance variant; that `LaunchMark.svg` is byte for
  byte `docs/design/launch-mark.svg`, rendered as the original, and that its three paths are the
  icon's (`AppIcon.icon/Assets`) in the icon's colors; and, given a built app, that its Info.plist
  has exactly `UIColorName`, `UIImageName` and `UIImageRespectsSafeAreaInsets` (false) in
  `UILaunchScreen`, `UIStatusBarStyleLightContent`, and no launch storyboard, and (on macOS) that
  the compiled asset catalog holds both assets. `scripts/test-check-launch-screen.sh` has a
  passing and a failing case for each. The repository checks run both on every pull request; the
  `ui-build` job checks the app it builds.
- `LaunchHandOffUITests.swift` launches the `slowStart` scenario, whose camera stays starting
  until the app first goes to the background, and checks the first start: one element
  "Starting the camera…", no spinner, the mark's frame 78 × 54 points, centered across the window
  and 3 points above its center (within a point, from the screenshot's pixels), the picture
  black outside it, the screen black and the status bar's content white in the light
  appearance, red only in night mode, the audit, the largest text size and right to left (in the
  dark appearance); then that the indicator ends when the camera runs and stays gone after the
  background and a lens change, and that first run ends it; and that the shutter and Q are
  there under the indicator, whole, inside the window and usable (`testFirstStartKeepsTheControlsWhole`,
  on the iPhone and the iPad, at the default and the largest text size). At the largest text
  size (the scrolling layout, LAUNCH-SCREEN.md, 13) `testFirstStartAtTheLargestTextSizeAndRightToLeft`
  also checks that the lens rows don't exist during the first start, that Take Photo and Quick
  Menu exist, are whole and can be pressed, that no button intersects the indicator, that the
  audit passes with no finding set aside, and that the rows exist and the indicator is gone once
  the camera runs.
- `FirstStartTests` (NopeCore) covers `CameraModel.isFirstStart`; `StartIndicatorTests` (NopeUI)
  the mark's geometry and colors, and the arithmetic of the rule that leaves out the words and
  the plate where they would come within `NopeSpace.s` (12 points) of the pinned row
  (`StartIndicator.wordsFit(plateExtent:roomBelowCenter:)`). The UI tests can't make a window
  that short, so that case is check 11 below.

A UI test can't capture the launch screen: iOS draws it before the app runs. On the Simulator
it can be held for a screenshot:

```sh
xcrun simctl erase <device>          # or a new device: see "Kept launch screens" below
xcrun simctl boot <device>
xcrun simctl ui <device> appearance light
xcrun simctl install <device> <path>/nope.app
xcrun simctl launch --wait-for-debugger <device> com.photivra.nope.dev
xcrun simctl io <device> screenshot launch.png
xcrun simctl terminate <device> com.photivra.nope.dev
```

`--wait-for-debugger` holds the launch screen: the app's process is stopped (state `T` in `ps`)
before its first line of code, and the launch screen stayed up for as long as it was held (23
seconds, the longest tried, on an iPhone 17 Pro Simulator with iOS 27.2, 2026-11-18). Measured
that day with this method, in the light and the dark appearance, on an iPhone 17 Pro, an iPhone
SE (3rd generation) and an iPad Pro 13-inch (M5) in portrait, all iOS 27.2: every pixel outside
the mark, the status bar and the home indicator band was `#000000`; the status bar's content was
white; the mark's lit pixels were 78 × 54 points, centered across and 3 points above the
screen's center, unscaled, in `#EDEDEE` and `#40C8E0`; and the app's first start
(`-NopeSimulatedCamera slowStart`) drew the mark in the same pixels and colors. So the
`UILaunchScreen` image is placed as the design asks and the launch storyboard of the design's
section 6.2 isn't needed.

Kept launch screens: on the Simulator `simctl uninstall` and a new install did not replace the
launch screen iOS had kept from the previous build (the old period color still showed); erasing
the device did. Erase the device, or use a new one, before checking a changed launch screen.

Colors: Xcode's asset compiler reads an SVG's colors as Display P3 and stores the launch image in
sRGB. With the icon's `#40C8E0` written in the SVG the launch screen's period was `#00CBE4`; the
SVG therefore writes the period as `#6AC5DD`, the Display P3 value of sRGB `#40C8E0`, and the
launch screen shows `#40C8E0` (measured as above). `#EDEDEE` is the same in both spaces.

By hand, once for each release and again when a file of the design's section 6 changes (record
the results here):
1. Each Simulator check above also on the iPad in landscape and in Split View, and on the iPhone
   Duo closed and open.
2. A recording of a launch in the light appearance, stepped through frame by frame: no frame
   between the launch screen and the camera is lighter than the launch screen, and the mark is in
   the same pixels until it fades.
3. On an iPhone, an iPad and an iPhone Duo: a cold start (restart, wait a minute, open) and a
   start from the app switcher, in the light and the dark appearance, recorded, and filmed at
   240 frames a second for a single bright frame. Note how long the launch screen and the first
   start last.
4. On an iPhone, starting the app held sideways, both ways round: the mark stays upright and in
   place, with no turn that can be seen. If a turn shows, option A ships.
5. Night Mode on, the app opened in a dark room: nothing white but the status bar and the mark
   before the red camera; the mark turns red in one frame and doesn't move.
6. The Lock Screen camera, with Night Mode off and on: what iOS shows before the extension's first
   frame; nothing brighter than black, then red from the first frame in Night Mode, and the
   indicator for its first start.
7. Smart Invert and Classic Invert: the launch screen and the first frame agree. If iOS inverts
   one and not the other, option A ships.
8. First run on a fresh install, in each appearance: the mark, then the statements, nothing in
   between (black to white once in the light appearance, as decided).
9. After an update: install release 0.3.0, open it, install the new build over it, open it, and
   record whether the old launch screen is shown once.
10. The Home Screen icon is still the Icon Composer icon now that the app has an asset catalog.
11. At the largest text size, in a window too short for the words (an iPad in Stage Manager or
    Split View at its smallest height, or the 4.7-inch iPhone with `-NopeSimulatedCamera
    slowStart`): the first start shows the mark alone, with no words and no plate, at the
    window's center; VoiceOver still reads "Starting the camera…"; the pinned row is drawn and
    nothing else is until the camera runs. In a taller window the words and the plate show.

## What was tested on real hardware

The real hardware for the 1.0.0 checks is an iPhone 16 Pro Max (iOS 27.2.1) and an iPad Air
(5th generation). Everything else, including other iPhone and iPad models, iOS and iPadOS 26
and the Apple Watch app, was tested only in Apple's Simulator, which has no real camera. The only
recorded device result so far is the debug tag check on the iPhone 16 Pro Max (2026-11-11 and
2026-11-12, "Tag check" below); the release save path is still to be checked on a device.

Known limits that no available device can close before release:

- Whether any value of the locked details (the color matrices, the as-shot white balance, the
  black and white levels) differs between two devices of the same model. Only one unit of each
  model has been available, so the app doesn't say these values can't identify a device.
- What a real iPhone camera writes on iOS 26, and whether photos save there.
- Pairing, reach, timing and transport of a real Apple Watch, and the Live Activity on the watch.
- Lenses on other iPhone models: which have RAW, fixed-focus ultra wide lenses, RAW buffer layouts.

The app and the store listing make no "tested" or "verified" claims; this section, the README's
requirements and the App Review notes (`docs/store/README.md`) say what was tested. Update this
section with each release.

## On-device checks

Some behavior can only be checked on hardware. Before a release, on at least one iPhone and one
iPad, with at least one device (or, where hardware isn't needed, a Simulator) on iOS or iPadOS 26
and one on 27, the oldest and newest supported versions (issue #78):

- the camera permission prompt shows the localized `NSCameraUsageDescription`, and each answer
  leads to the right screen (`SystemCameraAuthorization`);
- at the largest text size, the texts whose audit findings are set aside (see "UI tests and
  accessibility audits") show whole, with nothing cut off: on an iPad the Assistant Access
  switch's explanation ("Lets Siri, Shortcuts…", Settings › Privacy › Assistant Access) and, in
  night mode, the Accessibility page's "Pinching to switch lenses is optional. The lens buttons
  do the same."; on an iPhone, the "Grid Style" title in Settings › Viewfinder Overlays;
- a Secure Enclave key signs and verifies (`SecureEnclaveSigningKey`), and a DNG, HEIF and JPEG
  saved on the device validate with c2patool (below) as `Valid` with only
  `signingCredential.untrusted` failing;
- capture (`SystemCaptureHardware`): every physical lens appears with the right label; the
  viewfinder shows the scene; the shutter, the volume buttons and the Camera Control each take
  a photo and the last-photo slot appears with a teal seal; a lens
  without Bayer RAW turns the format chip amber; a phone call or another camera app shows the interruption message, and
  the camera comes back afterwards; and the tag check (below) shows exposed frames;
- saving (`PhotoKitLibrary`, `SystemCaptureHardware`, `CoreImageRAWRenderer`): the add-only
  prompt appears once and declining it shows the "isn't allowed to add photos" banner, whose
  Open Settings opens the app's page in the Settings app; a RAW
  plus HEIF appears as one photo in Photos with the RAW as the original; RAW plus HEIF, RAW plus
  JPEG, and RAW plus HEIF plus JPEG with each "Paired with RAW" choice are saved on the wide, 0.6×
  and 5× lenses, in full auto and manual, and in the Lock Screen camera while locked (see "RAW
  pairs not saved (PhotoKit error 3300)"); after these photos the app's container holds no photo
  file (Xcode › Devices and Simulators › Download Container); every saved file passes
  the read-back (`docs/PRIVACY.md`, "Device checks") and an exiftool dump matches the tables in
  `docs/PRIVACY.md`;
- last photo and its details (`ImageIOThumbnailer`, `PhotoDetails`, `openPhotosApp`): after a
  RAW + HEIF, a RAW-only, a RAW + JPEG and a no-RAW photo, the thumbnail shows the photo upright
  in portrait and landscape (time how long a RAW-only thumbnail takes: it decodes the DNG);
  tapping it opens the Last Photo viewer; the viewer's Open in Photos opens Photos, where the new
  photo is the newest item (the `photos-redirect://` URL opens Photos, not a chosen asset; Apple
  documents no way to open one asset, and the URL itself isn't documented by Apple); the
  VoiceOver actions on the thumbnail offer Open in Photos and Photo Details; for each photo, the details match `exiftool -a -G1 -s` of the files exported
  from Photos as originals: pixel size (`ImageWidth`/`ImageHeight` for the DNG, the image size
  for HEIF and JPEG), `BitsPerSample`, `CFAPattern`, `BlackLevel`, `WhiteLevel`, opcode lists,
  `ExposureTime`, `ISO`, `FNumber`, `FocalLength`, `ExposureCompensation`, `WhiteBalance`, the
  file sizes, and the tag list; RAW clipping (`RAWClippingMeter`) shows numbers, not "Not
  measured", on every lens (record each lens's `CVPixelBufferGetPixelFormatType`, width, height
  and bytes per row against the DNG's `ImageWidth`, `ImageLength`, `ActiveArea` and
  `BitsPerSample`, and whether the buffer's values are shifted), a frame with a bare bulb or the
  sun shows clipped highlights and a lens-cap frame clipped shadows (record both shares), and taking a RAW photo is no slower than before by more than the time the count
  takes (Time Profiler, `clipping(of:dng:)`); with signing on, c2patool shows the same claim generator and
  description; the timings look plausible;
- manual controls (`SystemCaptureHardware`), on each lens of each test device, with manual
  controls turned on: see "Manual controls on a device" below;
- rotation (`PreviewRotation`, `AppDelegate`, `DeviceOrientation`): on an iPhone 16 Pro Max in
  both landscape orientations, mounted on a tripod, the camera layout stays put while the chip,
  pills, warnings, banners, readouts and buttons turn upright and nothing collides; Settings and
  the format sheet rotate and the camera returns to its layout when they close; on an iPad Air in
  all four orientations the interface rotates with the controls in the trailing column; with the
  rear and front cameras the viewfinder is upright and not stretched, and each saved DNG's
  Orientation tag (read with `scripts/dump-tags.swift`) shows it upright (the developed HEIF and
  JPEG are rendered upright and carry Orientation 1); Split View or Stage Manager shows the
  multitasking pause; a hardware keyboard's Space bar takes a photo; pressing and holding the
  picture locks focus and exposure;
- contrast over real scenes: the chip, pills, warnings, banner, dial, thumbnail and shutter ring
  stay readable against a white wall and a yellow surface, with and without Reduce Transparency
  and Increase Contrast; the haptic on a good save is light;
- viewfinder overlays: see "Viewfinder overlays on a device" below;
- the manual accessibility pass in AGENTS.md (VoiceOver, Voice Control, Switch Control, the
  largest text size), including the turned icons and text on an iPhone held sideways, the failure
  banner taking VoiceOver focus, and the low-priority "Saved and signed" announcement;
- hardware shutter (issue #37), on an iPhone 16 Pro Max: volume up, volume down and a Camera
  Control press each take one photo on release; while the camera is paused (another app using
  it) the volume buttons change the volume; note what a press does with Settings open; the
  AirPods camera remote, where available, behaves the same;
- self-timer (issue #39): 3 s and 10 s count down with a light haptic each second and, with
  VoiceOver, each number spoken; pressing the shutter, a volume button or Cancel Timer stops it
  without a photo; Instruments shows no CPU work during the countdown beyond the running camera;
- burst (issue #46; docs/design/BURST.md, 5.7), on each lens for RAW, RAW + HEIF and HEIF:
  holding the on-screen shutter, a volume button or the Camera Control takes the first photo on
  the press and photos until it is released, stopping within one photo of the release; a tap
  takes one photo; sliding the finger off the shutter stops the burst; Start Burst runs one until
  the shutter or Stop Burst; record the frames per second (below, "Burst rate"); every saved
  frame passes the read-back and is its own photo in Photos; memory stays flat over three bursts
  of 50 frames at 12 MP and at 48 MP (Instruments, Allocations); the picture between photos stays
  live (record any stutter); focus and exposure follow a moving subject in full auto and hold with
  AE/AF lock; the light tap for each photo is felt and the shutter sound follows the system;
  leaving the app during a burst saves every photo and the Live Activity counts them; with
  VoiceOver, a double tap takes one photo, a double tap and hold a burst, and the action Start
  Burst one with no hold; with Voice Control ("Tap Start Burst", "Tap Stop Burst") and Switch
  Control a burst starts and stops with no hold; record the heat level after three bursts of 50; memory stays flat
  once 20 frames hold Last Photo previews (`SessionPhotos`);
- Last Photo viewer (`PhotoViewer.swift`; BUILD-SPEC.md, 3.14): with real photos, the opening
  and closing motion (a fade with a short zoom; the system zoom transition isn't used, because
  its swipe down also closed a zoomed photo), the swipe down to close (and that it doesn't close
  a zoomed photo), double tap and pinch up to the preview's pixels with the hint, and a pinch
  back to fit (a synthesized pinch in left the photo zoomed in the iOS 27.2 Simulator, so the UI
  test returns to fit with a double tap), paging through 20 or more photos (the 21st shows the
  fallback at its 156-pixel thumbnail, at most 160 points), and a portrait and a landscape
  photo; Escape (a synthesized Escape didn't reach the viewer's command in the iOS 27.2
  Simulator, so no UI test covers it) and the VoiceOver scrub close it; the volume buttons and
  the Camera Control close the viewer and take no photo, and the next press takes one (decision
  V1); a photo from Apple Watch while the viewer is open gives New Photo; the app switcher's
  snapshot shows no photo, for the viewer, for Photo Details opened from the camera and for
  Photo Details opened over the viewer (they rely on `scenePhase` inside a full-screen cover and
  inside a sheet, which no UI test can see; a privacy claim in `docs/PRIVACY.md`, so record the
  device, iOS version and date here before each release); Reduce Motion fades the viewer and crossfades pages; night mode draws
  the photo red; VoiceOver (the photo's value, the adjustable paging, the actions, Escape, focus
  back on Last Photo), Voice Control ("Close", "Photo Details", "Open in Photos", "New Photo"),
  Switch Control and Full Keyboard Access; the Lock Screen camera's viewer has no Open in
  Photos and shows "No Preview" for each photo (it makes no previews); Photo Details' Files row
  shows 10-bit for a 10-bit HEIF copy (unit-tested in `PhotoDetailsTests`; the simulated files
  have no 10-bit HEIF); the iPhone Duo fold pair (`duo-fold-viewer`): the viewer stays open on the same photo;
- Last Photo previews (`SessionPhotos`, `ImageIOPreviewer`): on the oldest and newest supported
  iPhone and an iPad, for RAW, RAW + HEIF and HEIF, record the time the preview adds to each
  save (Instruments, Time Profiler), the size of a 3072-pixel preview at JPEG quality 0.9 and
  whether it shows artifacts when zoomed in, and the app's memory with 20 previews held and
  with the viewer open (three decoded pages); after going to the background and back, and with
  Xcode's Simulate Memory Warning, every preview is released;
- storage and battery warnings (issue #44): see "Low storage" below; at 3% battery or less,
  unplugged, "Battery Low" shows (not at 4%) and is announced, and it goes away when the device
  is plugged in; Low Power Mode changes the explanation;
- interval shooting screen (issue #48): during a series the screen doesn't lock and is dimmed;
  a tap brightens it while the series continues; the brightness and auto-lock come back when the
  series ends, is stopped, or the app goes to the background, and after the camera screen closes.
- interval shooting that stops after a time: Stop After Time, 0 hours 5 minutes, 30 s apart:
  the card shows "n photos taken · 5 min left" counting down by minutes and the series ends by
  itself after about 5 minutes; start again and leave the app for 2 minutes: back in the app,
  the series continues with about 2 minutes less left (the time keeps running while paused);
  start again, leave for longer than the time: back in the app the series ends at once without
  another photo, and the Live Activity said "Paused: n photos taken · m:ss left" and counted down
  while away.

### Open device checks named by the third code review of 1.0.0

Each item below is a statement the app or its documents make that rests on iOS behavior no one
has recorded yet. None has been run. Record each result with the date, the device and the iOS
version in the section named, or list it in the changelog as not yet checked:

- **Assistant Access** ("Assistant Access on a device" below): that
  `authenticationPolicy = .requiresAuthentication` makes iOS ask for an unlock before
  `perform()` (check 5, and check 11 for Siri on a locked phone), and which of the two checks
  refuses on a locked phone: iOS's unlock, or the app's own fallback
  (`isProtectedDataAvailable`, which lags a lock by some seconds and is always true on a device
  without a passcode); that `requestConfirmation` shows and speaks its question from an intent
  started in the background mode (check 2); that a refused or cancelled request never opens the
  app, and that `continueInForeground` opens it after Confirm (check 1); and that the preset
  picker in the Shortcuts app lists no saved names while access is off (`PresetQuery`, check 13).
- **Focus bracketing** ("Bracketing on a device"): D5 to D7 (`focusSettleSeconds` of 0.1 s, the
  0.02 tolerance, whether a frame taken right after the handler is sharp where planned), and D11
  (exposure and white balance hold across the frames on each lens).
- **Keep Screen On** ("Keep Screen On and the Night Mode search field on a device"): checks 1 to
  3 and 7 of `docs/design/keep-screen-on.md`, section 11 (the idle timer after the limit,
  Auto-Brightness while dimmed, the brightness put back after each way out, VoiceOver with the
  cover); also whether a brightness set in Control Center while dimmed is kept.
- **Pinch** ("Pinch to switch lenses on a device"): the thresholds, a pinch that continues while
  the camera restarts for its first step, and that two fingers are never taken for a tap, a lock
  or a clean-view swipe.
- **Device feedback** ("Device feedback for 1.0.0"): C1 and C2 (the close-up detector and the
  Ultra Wide advice; for C1 also a tripod and a still close subject, where readings may stop),
  S1 to S5 (the stabilization signal and the 2-stop allowance, both provisional), and F1 to F7
  (the fade, Voice Control's "Tap Lock" in time, Full Keyboard Access focus through
  `@FocusState`).
- **Rate or Review** (once `AboutScreen.appStoreID` is set): tapping the row on About opens the
  App Store at the app's write-review page on an iPhone and an iPad, and the app stays as it
  was. The `?action=write-review` form is unverified until it can be opened for a live app, so
  check it after the first release; on a TestFlight build, note only that the App Store opens
  (it doesn't take reviews for a TestFlight build). With App Privacy Report on, the tap adds no
  domain under the app (`docs/SECURITY_AUDIT.md`, check 8). From the Lock Screen camera, if About
  is offered there, the link needs the device unlocked first, as the other two do.
- **About links on iOS 26**: on an iPhone with iOS 26, VoiceOver reads each of the three About
  links (Privacy Policy, the source code address, Rate or Review) as "link", not "button". The
  iOS 26.5 Simulator reported them as buttons until the button trait was removed; this checks
  the fix where VoiceOver speaks.
- **Opening Photos**: the `photos-redirect://` address, which Apple doesn't document, now has two
  entry points, the viewer's Open in Photos and the camera's Open Photos (P1 under "Device
  feedback for 1.0.0"). Record that each opens the Photos app; the app ignores the result of the
  call, so if a future iOS stops opening the address, both buttons would do nothing without a
  message.

### Open device check named by the fourth code review of 1.0.0

- **A HEIF copy saves on iOS 26.** The iOS 26.5 Simulator's ImageIO reader reports a top-level
  `Headroom` key on every HEIF the app writes, which the read-back now allows in a HEIF only
  (`MetadataPlan.heifDerivedImageIOKeys`, `docs/PRIVACY.md`, "ImageIO's own keys"). On an iPhone
  with iOS 26, take a photo with RAW + HEIF and with the processed fallback (HEIF), and record
  that each HEIF saves to Photos and that the read-back reports no other key. Not run.

### The viewer and What's in This Photo on a device (1.0.0)

Device checks added by the last viewer and details changes for 1.0.0. Not run.

- **The shown page zooms after a long series** (issue #102). Start an interval series of more
  than 100 photos, open the viewer on the oldest photo while it runs, and leave it until that
  photo is dropped from the session (the session keeps 100). The viewer moves to the newest
  photo; double tap and pinch zoom it. `PhotoViewerTests.theShownPageFollowsTheFallbackWhenItsPhotoIsDropped`
  covers the rule; no UI test runs a series that long.
- **Memory in the viewer** (issue #103). The viewer now decodes each of its three pages at the
  size it fills on the screen, and the page shown at the preview's full 3072 pixels only while
  it is zoomed in. By arithmetic (not measured), a 4:3 photo upright on a 402-point page at 3
  pixels per point decodes at 1206 × 1608 pixels (about 7.8 MB) instead of 2304 × 3072 (about
  28 MB), so three pages hold about 23 MB instead of 85 MB. With 20 photos taken, record the
  app's memory (Xcode's memory gauge, or Instruments, Allocations) on the camera, with the
  viewer open on a middle photo, zoomed in, and after a swipe to the next photo, on this build
  and on the build before the change, on the smallest and largest supported iPhone and an iPad.
  Check by eye that a fitted page is as sharp as before and that a zoomed page turns sharp
  within a moment. The simulated previews of the UI tests are 30 × 40 pixels, so the Simulator
  can't show it; `PhotoViewerTests.pagesDecodeAtTheirFittedSizeAndTheZoomedPageAtFull` covers
  the sizes asked for.
- **The viewer's status lines wrap** (issue #110). At the largest text size, with a processed
  photo of a lens without RAW and signing on but failed ("Processed · HEIF" and "Not signed"),
  open the viewer on the smallest supported iPhone and on an iPad in the narrowest window it
  allows (a resized window or Slide Over): each line wraps inside the window and nothing runs
  past its edge. `PhotoViewerTests.stackedStatusLinesWrapInANarrowWindow` measures the lines at
  160 points; the status is hidden from VoiceOver (its words are in the photo's value), so a UI
  test can't read its frame. `testViewerLargestText` runs on the iPhone SE (3rd generation)
  Simulator for the 4.7-inch width.
- **The summary card of What's in This Photo** (issue #118). With VoiceOver, swipe through the
  card for a RAW photo with signing off, a processed photo of a lens without RAW, a photo that
  could not be signed and a photo with the location kept: the head is read once ("RAW (DNG)",
  the lens and time, the pixel size and file size), then each row once and in order, its second
  line with it, and a warning row begins with "Warning". At the largest text size the symbol
  column grows and each row wraps under its own first word; right to left (the pseudo-language)
  the symbols are on the right; in Night Mode everything is red and a warning is told by its
  triangle and words; on an iPad the card fills the sheet's width and says "Processed by this
  iPad". Compare with the figures `summary-*` in `docs/design/screens`.

### Lock Screen, Control Center, Siri and Shortcuts on a device

Issues #42 and #62. Assumptions to confirm: the capture extension needs no entitlement, can add
to Photos with the add-only access granted in the app, and can create a Secure Enclave key while
the device is locked (if it can't, photos are saved unsigned and the "Not Signed" chip says so).

- Control: add "Open nope." in Control Center, on the Lock Screen and to the Action button;
  each opens the camera; unlocked, it opens the app.
- Locked: the camera opens without unlocking; a photo is saved to Photos (RAW plus HEIF by
  default), signed, and passes the read-back; the thumbnail opens the photo's details, not
  Photos; Settings changes made there don't change the app's settings; the volume buttons take a
  photo; first use before the app was ever opened (camera and Photos prompts) behaves sensibly.
  Settings: see "Shared settings" below.
- Siri on the iPhone: "Take a photo with nope." takes a photo and Siri says "Photo saved and
  signed."; "Take a photo in 10 seconds with nope." shows and speaks the countdown; with camera
  access off, Siri says how to turn it on. From an Apple Watch through Siri, the same phrases.
- Siri while the iPhone is locked: "Take a photo with nope." asks to unlock before opening the
  app. "Open the camera in nope.": record whether Siri opens the Lock Screen camera, asks to
  unlock, or refuses (not documented by Apple; docs/ARCHITECTURE.md).
- Siri, other phrases: "Switch to Ultra Wide in nope." (and a lens the device lacks), "Turn on
  the light in nope." and "Turn off the light in nope." (the light comes on and goes off; with
  the app closed, turning it off says the light is off without opening the app), "Start interval
  shooting in nope." with Manual Controls off (the series runs in full auto; Manual Controls stay
  off) and on (the photos use the manual settings; the screen dims), "Stop interval shooting in
  nope.", and "Take a bracket with nope." in full auto and with a bracket chosen on the drive
  strip (three photos at different exposures; the strip's bracket and Manual Controls are
  unchanged afterwards; on the front camera Siri says the lens can't take it).
- Shortcuts: Take Photo with a custom delay, each lens (a missing lens says so) and Number of
  Photos 5 (five separate photos, no "Burst stopped" announcement), Switch Lens, Turn On and Turn
  Off the Light, Start Interval Shooting with Seconds Between Photos and Number of Photos, and
  with Duration in Minutes (the series stops after that time; with an interval as long as the
  duration or longer, the action says the time between photos must be shorter), Stop
  Interval Shooting, Take Bracket with 5 and 7 Photos, each Step and each Order (7 on a lens that
  takes fewer says so), and Set Night Mode on and off, with the app closed and with it open (the
  screen turns red at once).
- Siri does not mistake "Turn on the light in nope." for a HomeKit request.
- Shortcuts settings actions: Set Focus Range to Close-Up, Far Focus and No Limit (the Close-Up
  or Far Focus pill shows and goes; a lens without a range limit says so); Set Photo Size Largest
  and Standard on a lens with a choice (Settings > Photo Size shows it; the next photo's size
  changes) and on a Bayer RAW lens (says there is one size); Set Fast Shutter and Set Face
  Detection with the app closed (Settings shows the new value when the app opens). Apply
  Preset: the picker lists Factory Defaults and the saved presets (a renamed preset shows its new
  name, a deleted one is gone); with the app closed it opens, applies the preset (lens, values
  and settings), says it can be undone in Presets, and Presets shows Undo; with a preset that has
  Location on and access declined, it says some settings couldn't be applied; the light stays
  off.
- Check in each language that ships (English only in 1.0.0) that Siri accepts the phrases.

### Assistant Access on a device (issue #82)

The design's assumptions (`docs/design/assistant-access.md`, section 14). Each is an assumption
until it is confirmed in Apple's documentation for iOS 26 and 27 and on a device; record the
result, the device and the iOS version here. A check that fails changes the design (the column
"If it doesn't hold"), not the wording. None has been run yet.

| # | Check on a device | If it doesn't hold | Result |
| --- | --- | --- | --- |
| 1 | A gated intent starts in the background and moves to the foreground only after the check and the question (`supportedModes` `[.background, .foreground(.dynamic)]`, `continueInForeground`): with access off, "Take a photo with nope." answers without opening the app; a cancelled question doesn't open it either; after Confirm, `continueInForeground` opens it | Go back to `openAppWhenRun`: the app opens, then refuses or asks | Not run |
| 2 | `requestConfirmation`, from an intent started in the background mode, shows and speaks the question, the line under it ("You can change this in nope. › Settings › Privacy.") and the custom buttons (Take Photo, Switch Lens, Apply Preset, Cancel) in Siri and in Shortcuts, before the app opens, and throws on Cancel | The app's own card on the camera (design, 5.5); drop the line if only it fails | Not run |
| 3 | An unattended Shortcuts automation stops at the question and doesn't run the action | Every Action and Only Before a Photo must refuse when no person can answer | Not run |
| 4 | After Cancel, Siri and Shortcuts show "Cancelled. Nothing changed." | No answer; nothing is claimed | Not run |
| 5 | `authenticationPolicy = .requiresAuthentication` makes Siri ask for an unlock for every gated action, on the Lock Screen, through headphones and in a car; the app's own check (protected data unavailable) answers "Unlock this device to use nope.'s actions. Nothing changed." if a request still arrives locked. Record which of the two refuses on a locked phone: the app's fallback (`isProtectedDataAvailable`) lags a lock by some seconds and is always true without a passcode | The check refuses while the device is locked, by the app's own test (built) | Not run |
| 6 | A result can carry one button that runs Open Assistant Access (Open Settings in the off answer). Not built: the off answer is the sentence alone, which names the path; the Open Assistant Access action exists in Shortcuts | Keep the sentence alone | Not run |
| 7 | Camera-domain assistant schemas: what exists on iOS 26 and 27, and whether a conforming intent still runs `perform()` and can ask for confirmation. None is adopted | No schema is adopted | Not run |
| 8 | The system doesn't record or suggest the app's actions unless the app donates them (the app donates nothing) | State what the system does on the Honesty screen; point to the system's Siri settings for the app | Not run |
| 9 | Siri on Apple Watch, headphones, a car or a speaker can't run the phone's actions around the check; the headphone remote's volume press stays a shutter button | Any path found gets the same check before release | Not run |
| 10 | iPhone Mirroring: whether the camera runs, and whether any control can be operated from the Mac | State it as a limit | Not run |
| 11 | Siri on a locked phone: the photo action requires unlocking | Release blocker | Not run |
| 12 | The camera stops when the app leaves the screen, and the system's camera indicator shows whenever it runs. Only after this is recorded may the page and the Honesty screen say "No photo is taken while nope. is not on screen" (decision 19) | Release blocker | Not run |
| 13 | With access off, the system lists the app's actions and phrases and nothing else about the app; the Apply Preset picker lists only Factory Defaults | State what is listed | Not run |

Also on a device: the manual accessibility pass with VoiceOver, Voice Control and Switch Control
over the Assistant Access page, a refused request, a question answered by voice and by touch,
and the camera's hint; each gated action from Siri and Shortcuts with access off (the off answer,
nothing changes, the refusal card the next time the camera is shown), with Every Action (the
question names the values the action runs with), with Only Before a Photo and with Never; Apply
Preset through Shortcuts with a preset that has Location and signing on while both are off (they
stay off; the answer says privacy settings weren't applied); a saved shortcut that names a
saved preset while access is off; and a shortcut saved before 1.0.0 (it answers that access is
off until it is turned on).

### Live Activity on a device

Issue #64. Turn on Settings › Camera › Live Activity first. Assumptions to confirm: the activity
starts when a run starts in the foreground, the update sent as the app leaves reaches the system,
and the time iOS gives to finish saving is enough for a burst's frames.

- Interval series: start one (10 photos, 10 s), go to the Home Screen: the Dynamic Island and the
  Lock Screen show "Paused: n of 10 photos taken. Open nope. to continue."; tapping the activity
  opens the app and the series continues; going out again and pressing Stop ends the series and
  the activity at once, and the app shows the series stopped.
- Burst: hold the shutter in burst mode, go to the Home Screen while it saves: "Saving: n of m
  photos saved", then "Photos saved: m" with "Signed." (or the unsigned line with signing off),
  gone two minutes later; every frame is in Photos.
- Astro: leave during the frames: the frames pause and the activity shows "Paused: n of N
  frames. Open nope. to continue." with Stop; coming back counts the start delay down again and
  the run continues from frame n + 1 (the frame cut short by leaving is taken again); Stop from
  the Lock Screen ends the run with every frame taken saved. Leave during the start delay: the
  run starts paused and begins after the delay on return. A call during a run pauses it the same
  way. Check that a frame cut short by leaving doesn't end the run as failed (the interruption
  may arrive after the frame fails).
- Self-timer: start a 10 s timer and lock the phone: the timer is cancelled and the activity says
  "Stopped. No photo taken."; no photo is taken when the app is opened again.
- In the foreground no activity is visible, and with the switch off none starts. Night mode shows
  it red on black. VoiceOver reads the compact, expanded and Lock Screen layouts; larger text sizes
  stay readable.
- With Live Activities turned off for nope. in the Settings app, the switch isn't offered.
- Network capture during these checks shows no traffic (`docs/SECURITY_AUDIT.md`, check 8).

### Clock and interval series on a device (issues #105, #106, #107, #122, #123, #125)

Pending verification. On the release build, on an iPhone, with Settings › Camera › Live Activity
on. The rules are unit tested with a fake clock (`IntervalTimeTests`, `IntervalScheduleTests`,
`DriveTests`, `LiveActivityTests`, `NopeClockTests`); these checks confirm them against the
system's clocks.

- Timed series and the device's clock (#106): start a 10-minute series (Interval, Stop After:
  Time, 10 s apart) and time it with a stopwatch on another device. After 3 minutes turn off
  Settings › General › Date & Time › Set Automatically and set the time an hour forward; after
  5 minutes set it two hours back. Expected: the series still ends 10 minutes after it began, the
  card's time left follows the stopwatch, and a photo is still taken every 10 seconds. Turn Set
  Automatically back on afterwards.
- A failed last photo (#105): start a series of 3 photos, 30 s apart, and before the third
  photo make saving fail (turn off the app's Photos access in the Settings app, or fill the
  storage). Expected: the camera says why the photo wasn't saved, and the card and the Live
  Activity end as Stopped, never Finished.
- Start to start (#123): with Manual Controls on, set the shutter to 2 s and an interval series
  of 10 photos every 10 s. Expected: "Takes 10 photos, starting one every 10 seconds." under the
  rows; the photos' times (Photos › Info, or the camera's own photo details) are 10 s apart, the
  card reads "Next photo in 8s" just after each save, and the series ends about 92 s after it
  started. Then set the shutter to 15 s: before Start, "The shutter time is longer than the
  interval, so photos follow one another."; while it runs, the card says "Each photo takes longer
  than the interval" instead of the countdown, VoiceOver announces it once, and no photo is taken
  twice (ten photos, each starting as the one before is saved). Check the line in Night Mode (red
  only), at the largest text size and right to left.
- Self-timer (#122): start a 10 s timer and a stopwatch together, five times, once with Low
  Power Mode on. Record each time to the shutter sound (or the haptic) and the numbers shown.
  Expected: about 10 s each time, with no drift from one run to the next; a number may be
  skipped only if the phone was held up for more than a second.
- Live Activity and the device's clock (#125): start the 10-minute timed series above, go to the
  Lock Screen, and set the time an hour forward and then back as above. Expected: after each change
  the activity's time left is right again at once, and its counts still update.

### Shared settings, the Night Mode control and the Lock Screen camera on a device

Issue #42. Assumptions to confirm: cross-process delivery of the settings change signal (a
Darwin notification) between the app and `NopeControls`; that `NopeControls` may write
`OpenCameraIntent`'s app context (Apple documents the app and the capture extension); and that
the Lock Screen camera reads the app context quickly enough not to be ended for having no camera
view.

- Signing: a device build with automatic signing registers `group.<bundle identifier>` for the
  app and `NopeControls`; `codesign -d --entitlements - --xml` on each shows exactly that one App
  Group, and none on `NopeCaptureExtension`.
- Upgrade: install 0.2.0, change several settings (formats, a detail, signing off, night mode
  on), install this build over it: the settings are kept.
- Control: add Night Mode in Control Center and on the Lock Screen. It shows the app's state;
  turning it on with the app open turns the app red at once (also while Control Center covers the
  app); with the app in the background or closed, the app is red when opened. Turning night mode
  on or off in the app (Settings, Q or the Set Night Mode shortcut) updates the control.
- Lock Screen camera: with night mode on, RAW plus HEIF plus JPEG, a detail on and signing off
  in the app, lock the device and open "Open nope.": the camera opens red, without a white flash,
  and its photo has those formats, that detail and no signature. Change night mode from the
  Night Mode control on the Lock Screen, then open the camera again: it follows. A setting
  changed in the Lock Screen camera doesn't change the app's. With the Location switch on in the
  app, a photo from the Lock Screen camera has no location.
- After these checks the App Group's preferences file holds only `NopeSettings.` keys, the
  migration key and the saved presets, `NopePresets.saved` (`docs/SECURITY_AUDIT.md`, check 12).

### Settings presets on a device

Issue #72. The rules are unit-tested (`SettingsPresetsTests`, `CameraSetupTests`) and the screens
UI-tested on the Simulator; on a device, confirm the parts the simulated camera can't show:

- Save a preset on the telephoto with manual ISO and shutter, a 10 s timer and RAW + JPEG; apply
  Factory Defaults (wide lens, full auto, single, RAW + HEIF, saved presets still listed), then
  the preset: the lens switches once without a frozen or black viewfinder, the values and timer
  are back, and the next photo has those formats.
- A preset with Location on, applied after location access was declined in Settings: Location
  stays off, the notice says so, and no prompt appears; with access not yet asked, the system
  prompt appears once.
- A preset with the astro helper on, applied in daylight: the helper is on with the preset's
  frame count and delay, and night mode follows the preset.
- From Q in night mode: the presets sheet is red on black and VoiceOver reads each preset
  and the result after applying. Undo returns the lens and values.
- After applying a preset, open the Lock Screen camera: it uses the applied formats and night
  mode (the copy is handed over after every change).

### Apple Watch on a device (issue #63)

Needs an iPhone with the app installed from Xcode (the watch app is embedded and installs on the
paired Apple Watch through the Watch app, or automatically if that setting is on). Unverified
assumptions to confirm: a watch command reaches the iPhone app while it is open and unlocked,
`WCSession.isReachable` follows the watch app being open, and replies arrive within a second.
Run these checks with the watch on watchOS 26 and on watchOS 27 (issue #78), on a device or, for
what needs no hardware, the watchOS Simulator.

- Pairing: the watch app appears on the paired watch, named "nope."; it opens to "Camera ready"
  while the camera is open on the iPhone.
- Shutter: Take Photo saves a photo on the iPhone (RAW plus HEIF by default, signed); the watch
  says "Saved and signed" with a haptic; with signing off, "Saved, not signed" in amber.
- Delays: 3 and 10 seconds start the iPhone's own self-timer (its countdown shows and speaks on
  the iPhone); the watch shows "Photo in 3 seconds" and counts down with a light haptic each
  second; Cancel Timer on the watch stops it and nothing is taken; cancelling on the iPhone shows
  "Timer cancelled. No photo taken." on the watch.
- Nothing taken when the camera isn't available: with the iPhone app in the background, closed,
  or with Settings open over the camera, the watch says "Camera not available. Open nope. on your
  phone." and Take Photo is disabled; opening the app later takes no photo. With camera access
  declined, the watch says so. With the iPhone out of range or off, "Can't reach your phone".
- A photo whose result the watch missed (lower the wrist during the countdown): raising it shows
  the result.
- VoiceOver on the watch reads the status, the shutter and the delay, and announces each
  countdown second and the result; the largest text size keeps every control reachable by
  scrolling.
- App Privacy Report on the iPhone lists no domain for the app after these checks.
- iPad: the app runs as before (WatchConnectivity isn't supported there and stays off).

### Low storage

`PhotoSizeEstimate` uses upper bounds that are assumptions until measured: 2 bytes a pixel for
Bayer RAW, 1 for HEIF, 2.5 for JPEG, and 1 MB a file. On each test device, save a RAW + HEIF and a
RAW + HEIF + JPEG photo with each lens, compare the file sizes in Photos with the estimate, and
record them here. Then fill the device until fewer than 25 photos fit and check that "Storage
Low" shows about the right number, that "Storage Full" shows before a save would fail, and that a
burst stops with "Burst stopped: storage is full." before it fails.

### Burst rate

Not measured yet. The app shows only the rate it measures from the burst that is running, and
Slow is worded "up to 2 a second"; no rate is stated as a property of a device until it is
recorded here. On each test device, for each lens, at each Photo Size, for RAW, RAW + HEIF,
RAW + HEIF + JPEG and HEIF, with signing on and off:

- hold the shutter at Fast for a 20-photo burst and record the photos a second (the summary
  card's rate, checked against the photos' capture times);
- record the time to take one photo and the time to save it (Photo Details, "Taking the Photo",
  and a signpost around the save), which decide whether a deeper saving buffer is worth building
  (docs/design/BURST.md, decision 4: only if taking is at least one and a half times as fast as
  saving on the main lens at 12 MP);
- at Slow, check that no two photos start less than 0.5 s apart and that Slow is slower than
  Fast. Where Fast measures under about 3 a second, the app stops offering Slow on that lens for
  the session (`DriveModel.slowBurstMinimumFastRate`); check the Burst menu then has only Fast.

### Headphones as a remote shutter on a device (issue #81)

Pending verification; nothing here is claimed in the store listing until it is checked. The app
handles hardware buttons only through `onCameraCaptureEvent` (AVKit), so anything the system
delivers as a capture event works without app code. From Apple's sources:
- AirPods with the H2 chip send stem clicks as primary capture events from iOS 26; apps that
  already use the capture event interaction get it with no change, and the system plays a default
  tone for an AirPods click (WWDC25 session 253, "Enhancing your camera experience with capture
  controls"). The person picks the click type in the AirPods settings ("Remote Camera Capture").
  The SDK header says AirPods Camera Control is not available in the European Union
  (`AVCaptureEventInteraction.h`, `defaultCaptureSoundDisabled`).
- Wired EarPods: Apple's documentation doesn't say whether their volume buttons send capture
  events to third-party apps. Record what happens.
- Siri through AirPods uses the same App Shortcuts as Siri on the iPhone.

Steps, on an iPhone with iOS 26 or later, with the app open on the camera screen (unlocked):
- AirPods Pro 2, AirPods Pro 3 or AirPods 4: in the AirPods settings, choose a click type under
  remote camera capture (record the section's exact name); press the stem once: one photo is saved (signed only if signing is on in Settings), and the tone plays; press and
  hold: record whether it takes one photo or, in Burst, a burst until released.
- Repeat with Drive set to 3 s and 10 s (the self-timer starts; a second press cancels it), Burst,
  an interval series (a press starts and stops it, as the volume buttons do) and the astro helper
  (a press starts the countdown); each behaves as the volume buttons do.
- With the camera paused (another app using the camera) and with Settings open: record what a
  stem press does; it must not take a photo while the camera isn't running.
- Wired EarPods (Lightning or USB-C): press volume up and volume down on the cord in the same
  modes; record whether each takes a photo or changes the volume.
- Siri through AirPods ("Hey Siri" or press and hold the stem, as set): "Take a photo with
  nope." and "Take a photo in 10 seconds with nope." with the app open and with it closed, the
  iPhone unlocked; Siri says the photo was saved, and whether it was signed (signing is off by default) Record what happens while the iPhone is
  locked (Siri asks to unlock, as on the iPhone).
- Record the device, AirPods model and firmware, iOS version and region with the results.

### Flash, light and night mode on a device

- the Light and Flash controls appear on each rear lens that has them and never on the front
  camera; record which lenses report a torch and which flash modes on each test device;
- light on at 10%, 25% and 100%: it stays on, without blinking, through framing, focusing,
  single RAW (DNG) photos, RAW + HEIF, a bracket and an interval series, and the photos are
  lit by it; a Bayer RAW photo with Flash On and Auto fires the flash, is saved and passes the
  read-back (`docs/PRIVACY.md`, "Device checks"); does Flash On keep a locked focus (capability
  survey, question 6)?
- the light turns off when the app goes to the background, on a phone call or another camera
  app, on a lens without a light, and at a critical heat level; warm the device and check the
  "Light Unavailable" warning and that a lower level can be chosen;
- a Light request before the camera is ready (issue #75): force-quit the app, open it, and turn
  the Light on as soon as the switch shows, before the picture appears; the switch stays on and
  the light comes on once the camera has started (or "Light Unavailable" shows), and it is never
  silently off. Repeat 10 times from a cold start, and also right after switching lenses and
  right after changing the Photo Size; record any try where the switch went back to off with no
  light and no warning;
- night mode at night: no white or blue element in the app's own screens (camera, tray, pills,
  manual controls, Pro Tools, the format sheet, Settings and every detail screen, warning
  popovers); list what the system still draws (status bar, menus, alerts); the app never changes
  the screen's brightness; the real viewfinder keeps its colors by default and is red with Red
  Viewfinder; energy with the red viewfinder on (Instruments);
- night mode and Red Viewfinder switch at once from Q and from Settings › Screen, with the
  live picture never freezing, going black or restarting (Instruments Hangs: no hang on the
  switch; the 0.2.0 build rebuilt the preview layer each time).

### Manual controls on a device

The rules are unit-tested against a scripted backend; these checks cover the hardware calls.
Do each on every lens (ultra wide, wide, telephoto, front) of each test device, in RAW and, on a
lens without RAW, in the fallback:

- the grid shows only what the lens supports: "n/a" or "Fixed" where the lens can't, the
  aperture adjustable only on a variable-aperture lens (iOS 27), S and I only on iOS 27;
- ISO and shutter at both ends of the lens's range, and a long exposure (1 s where offered):
  the viewfinder changes and the DNG's `ExposureTime` and `ISOSpeedRatings` match the set
  values (`.speed` keeps them, `AVCaptureDevice.h`);
- S and I: the camera adjusts the other value and the meter stays near 0;
- exposure compensation in P, S and I changes brightness; blocked in M;
- manual focus from Closest to Far moves the focus, and autofocus comes back with Auto; AF-L
  holds focus;
- white balance: each preset, 2500 K and 10,000 K, and tint ±150 are accepted without an
  exception (gains limited to `maxWhiteBalanceGain`), and the DNG's as-shot neutral changes;
- metering: spot and whole frame (iOS 26) change the exposure of a high-contrast scene;
- AE-L holds exposure when the phone points elsewhere;
- a bracket of 3 (and 5 or 7 where `maxBracketedCapturePhotoCount` allows) returns that many
  separate DNGs with the planned exposures, and no frame is blank;
- interval shooting: 3 photos 5 s apart; Stop ends it; leaving the camera screen ends it;
- switching lenses and an interruption: the manual settings are applied again afterwards;
- "All Auto" and turning the option off return the camera to continuous auto;
- readings: the meter and the Auto values update while manual controls are on; with them off
  the readings still arrive (for full auto's aids) but aren't shown, and nothing is observed
  once the camera screen closes (Instruments: no key-value observation callbacks);
- with VoiceOver: each slot adjusts by swiping up and down, and the eyes-free shutter (volume
  buttons, Camera Control) still works with manual controls on and in clean view.

### File options, pairing, mirroring and location

The rules are unit-tested; every file option combination is encoded and read back on the
Simulator (`FileOptionsEncodingTests`). On a device:

- **File options** (issue #57): with each compression, HEIF bit depth and color space, a RAW plus
  HEIF plus JPEG photo is saved, opens in Photos and a RAW editor, and the HEIF's depth and both
  copies' color profile (exiftool `ProfileDescription`) match the choice;
- **Copy Size** (issue #57): with Half Size and Quarter Size, the HEIF and JPEG open in Photos at
  half (2016 × 1512 from a 12 MP RAW) and a quarter of the RAW's width and height, the RAW is
  unchanged, and exiftool's `ExifImageWidth` and `ExifImageHeight` match the copy;
- **Focus on Faces** (issues #57 and #80; Face Detection before 1.0.0): on a fresh install it is off; with it off, autofocus
  and exposure stay on the center (or the tapped point) with a face in the frame, on the wide
  and the front camera; turned on, they follow a face in the frame in full auto, as before;
  nothing in the files changes either way. Installing over a build that stored Focus on Faces
  on keeps it on;
- **Far Focus** (issue #57): with manual controls on, Far Focus in Q, on each rear lens:
  autofocus ignores a near subject (a hand or a branch close to the lens) and keeps the far scene
  sharp; Close-Up then replaces it and back; the live readout's focus range shows the limit;
- **Photo Size** (issue #57): on a device with a lens without Bayer RAW that reports more than
  one size (the Debug tag check lists each lens's `supportedMaxPhotoDimensions`), each size saves
  a processed photo of that size that opens in Photos; record the lenses and sizes. On a lens
  with Bayer RAW, confirm the RAW is 12 MP whatever `maxPhotoDimensions` is (the reason the
  choice isn't offered there);
- **Paired with RAW** (issue #50): with RAW, HEIF and JPEG selected, Photos shows two items: the
  RAW paired with the chosen copy, and the other copy on its own; note how Photos labels the
  paired item and which copy it shows and shares by default, for each choice;
- **Mirror Front Camera** (issue #45): see `docs/PRIVACY.md`, "Device checks";
- **Location** (issue #43): turning Location on shows the system prompt with the localized
  `NSLocationWhenInUseUsageDescription`; Allow turns the switch on and shows "Location On"; Don't
  Allow leaves it off with the explanation and Open Settings; a photo then carries the location
  (`docs/PRIVACY.md`, "Device checks"); location services stop (the status bar arrow goes) when
  the camera is interrupted, the app goes to the background or Location is turned off; with
  Precise Location off, the approximate location is written; Instruments shows no location
  activity with Location off.

### Processing disclosure and new defaults on a device (issue #80)

The defaults, Factory Defaults and preset decoding are unit-tested (`NopeSettingsTests`,
`SettingsPresetsTests`); the marker, its note and the switch are UI-tested with the simulated
cameras (`ProcessedMarkerUITests.swift`). What the camera reports about distortion correction
can only be checked on hardware. On each device available (record the model and iOS version):

- **Fresh install:** Settings shows Formats "RAW (DNG)", Sign Each Photo off and Focus on Faces
  off; the first photo says "Saved. Not signed: signing is off in Settings." and Photos gets one
  DNG; Factory Defaults returns to the same values. Installing over an earlier build keeps the
  formats, signing and Focus on Faces the person had stored.
- **Which lenses have no Bayer RAW:** run the Debug tag check (`-NopeTagCheckRun`, "Tag check"
  below) and record, for each physical camera, whether it gives Bayer RAW.
- **Marker and note:** on each lens without Bayer RAW (for example an iPad's cameras, or a
  front camera without RAW), "Processed: No RAW on This Lens" shows before the first photo and
  in clean view; tapping it shows the note. Record its distortion line for each such lens: "lets
  apps turn it off" is `isGeometricDistortionCorrectionSupported` true, "doesn't let apps turn
  it off" false. Settings › Screen › Show Processed Marker appears only on such a device; turning it
  off hides the marker and nothing else.
- **Distortion correction actually applied:** for each lens without Bayer RAW, take the same
  scene with straight lines near the frame's edges (a door frame or a grid) with the app and
  with the system Camera app. With the Live Camera Readout on (Settings › Camera › Viewfinder
  Overlays), check whether its "Processing Off" line includes "Lens distortion fix" while that
  lens is in use (it reads `isGeometricDistortionCorrectionEnabled` after the app turned it
  off: "All" includes it). A lens that reports the switch but whose line leaves the fix out, or
  whose photos are visibly corrected (curved lines
  straightened, a narrower field of view than its RAW on the same device, where it has one),
  keeps correction on even when the app turns it off: record it, so the note's wording for that
  lens can be changed by a reviewed pull request.
- **What's in This Photo:** for a processed fallback photo, the Processing section shows the
  same distortion line as the note; a RAW photo shows none. For a RAW + HEIF photo with every
  detail on and with every detail off, compare each value of the 1.0.0 groups with
  `exiftool -a -G1 -s` of the files exported from Photos as originals: the exposure values
  (`FocalLengthIn35mmFormat`, `ExposureMode`, `ExposureProgram`, `MeteringMode`,
  `BrightnessValue`, `MaxApertureValue`, `SubjectArea`), the lens and camera names, the DNG's
  `ActiveArea`, `DefaultCropOrigin`, `DefaultCropSize`, `Compression`, `DNGVersion`,
  `BaselineExposure` and `AsShotNeutral`, the date and location values, and that each Every Tag
  page lists exactly the file's tags; with Exposure Settings off, the shutter and ISO marked
  "Not in the files" match the camera's readout for that photo; with a RAW, a HEIF and a JPEG,
  Photos shows the pairing the Files group states. With a location shown after Show Value, open
  the app switcher: the sheet's snapshot is covered and shows no value (a UI test can't query the
  app while its scene is inactive; it checks that the value is hidden again on return). Check VoiceOver, Voice Control and Switch
  Control on the flows in `docs/design/ACCESSIBILITY.md` ("What's in This Photo").

### Viewfinder overlays on a device

The geometry, level, analysis and rate rules are unit-tested; these checks cover the hardware
(`SystemLiveView`, `PreviewRotation.previewAngle`, `MotionGravitySource`):

- grid: each style in portrait and both landscape orientations; the spiral keeps its place
  relative to the horizon when the phone turns; lines stay visible over white, yellow and dark
  scenes;
- level: the bar matches a real horizon (or a spirit level) within about 1 degree in portrait
  and both landscape orientations; pointing straight down shows the top-down level;
  Instruments shows no motion updates while the level is off, and none added by the tap;
- level tap (`docs/design/level-haptic.md`, section 10; the rule is unit-tested in
  `LevelTapTests`, the path and wording by the `testLevel…` UI tests with
  `-NopeSimulatedGravity becomesLevel`):
  1. iPhone: the tap can be felt in the hand, in portrait and on its side, with and without a
     case, and can't be mistaken for the saved-photo tap. If it can't be felt, switch
     `NopeHaptic.levelTap` to `.rigidFallback` (one line in `DesignTokens.swift`; the
     fallback, `.impact(flexibility: .rigid, intensity: 0.6)` from the design's section 3, is
     built and unit-tested) and repeat. Open until done: until this check is recorded, the tap
     may not be felt;
  2. one tap per entry; none while held; none within 1 second of the last; none when Level is
     switched on while level;
  3. with System Haptics off in iOS Settings: no tap; with Low Power Mode on: record what the
     system does;
  4. no tap during a 1 second or longer exposure, a bracket, a burst, a countdown, an interval
     series or Astro; a photo taken as the device comes level is as sharp as one taken with
     Level off;
  5. Lock Screen camera: record whether the tap plays;
  6. iPhone Duo: outer display, inner display and half-open; record what the level reads
     half-open;
  7. iPad: no tap and no error; with VoiceOver on, "Level" is spoken;
  8. VoiceOver on iPhone: "Level" is spoken once per entry and doesn't cut off "Saved." or a
     countdown second;
- focus peaking: on the rear and front cameras, in portrait and landscape (and every iPad
  orientation), the highlight sits on the in-focus edges, not mirrored or turned; a small
  subject 5 to 15 cm away in front of a busy background shows sharp when focused (issue #51),
  and the highlight stays on the same edges with the 3× focus magnifier on;
- histogram: a bright window flags clipped highlights and a dark corner clipped shadows; the
  thresholds (`Histogram.highlightThreshold`, `shadowThreshold`, `clippedShare`) and
  `FocusPeakingMap.minimumEdge` look right on real scenes;
- captures unchanged: with peaking and the histogram on, a DNG and its HEIF from the same scene
  match ones taken with them off (dimensions, exposure, the metadata dump), and Bayer RAW is still
  offered on every lens that had it;
- rate and energy: with Instruments (Energy Log, Time Profiler), the analysis runs at most four
  times a second (two in Low Power Mode), the video output is gone from the session when every
  live aid is off, and the energy impact with them on is recorded in the release notes;
- live camera readout: the values match the saved files' EXIF (ExposureTime, ISOSpeedRatings,
  FNumber, ExposureBiasValue); the processing line reads "All" in RAW; the near focus limit and
  the torch show when another feature turns them on; with Keep Readout in Clean View on, the
  readout stays in clean view and keeps updating, and with it off clean view hides it.

### Comparison shot on a device (issue #55)

The rules (which photos are comparison shots, that only the app's files reach the library, failure
handling, the metadata grouping and masking) are unit-tested with a scripted backend; the UI tests
audit the compare view at the default and largest text sizes, right-to-left and in night mode.
On the iPhone 16 Pro Max, record:

- the time between the two photos (the compare view's "started … after nope.'s"), on the wide,
  ultra wide and telephoto lenses and the front camera, in good and low light;
- that the phone-processed side visibly shows the phone's processing (tone, noise reduction,
  sharpening, multi-frame fusion in low light), and the app's side matches the saved photo;
- that only the app's files appear in Photos after several comparison shots, and that a following
  photo with Compare off has the same DNG tags and image data as before (the output's maximum
  prioritization is back at `.speed`): run the tag check after a comparison shot;
- memory in Xcode's memory gauge or Instruments: it rises while the compare view is open and
  returns to the camera's level when Done is pressed;
- the app switcher shows the hidden-contents cover, not the photos;
- with the flash set to On, whether the second photo fires the flash again and how long it
  waits for it;
- App Privacy Report after a session of comparison shots: no network activity for the app;
- the masked values in Details (maker notes, `ImageUniqueID`, any serial number) and whether iOS
  adds location to the phone's file (it shouldn't: the app supplies none).

### Focus, exposure and close-up aids on a device

The rules (point handling, the lock, the fast shutter limit and its hysteresis, the hint and the
close-up trigger) are unit-tested against a scripted backend; these checks cover the hardware
calls and the assumptions. Do them on every lens of the test iPhone (16 Pro Max) and the iPad:

- tap to focus: the focus square appears where tapped and the camera focuses and exposes there,
  in portrait and with the iPhone turned, on the front camera too (its preview is mirrored; the
  point must still match); moving the phone returns focus to the center; a lens without a focus
  point (some front cameras) only re-exposes;
- press and hold (and the Lock button) lock focus and exposure: they stay when the phone points
  elsewhere; the AE/AF pill and the button unlock; VoiceOver's Focus on Center and Lock Focus
  and Exposure actions do the same, and the lock change is announced;
- exposure compensation in full auto: Q's Exposure dial brightens and darkens the
  viewfinder over the lens's range, the pill resets it, and the DNG's `ExposureBiasValue` follows
  (with exposure settings kept);
- fast shutter: on each lens in bright light the DNG's `ExposureTime` is no slower than
  1/(2 × focal length) (wide about 1/50, ultra wide about 1/26, 5× about 1/240), and no slower
  than 1/500 or 1/1000 with Freeze Motion; in dim light the shutter gets slower than that only
  when ISO is at the lens's highest; the focal lengths computed from the field of view match
  Apple's published ones within a few millimeters;
- the steady hint, "Hold it steady or use a tripod.": checks S1 to S5 under "Device feedback
  for 1.0.0" below;
- manual controls: a manual shutter is never changed, and shows no steady hint; P mode isn't
  limited;
- the hint after a mode change: in dim light with the hint showing, turn Manual Controls on (the
  hint goes and stays away), set a slow shutter, then turn them off; turn Astro on and off; switch lenses; in a bright scene
  the hint must be gone within about a second of each change (the first readings after a slow
  exposure are ignored while their shutter is more than a quarter stop longer than full auto's
  limit, an assumption to check: record the first reported shutters after leaving Astro). While
  Astro is on the hint doesn't show. In a dark scene it comes back from the new readings;
- Close-Up: a small subject 5 to 15 cm away in front of a busy background focuses with Close-Up
  on and a tap, and the pill turns it off;
- close-up hint: check C1 under "Device feedback for 1.0.0" below; it never switches by itself,
  and Dismiss hides it until the lens changes;
- the magnifier enlarges the viewfinder around the focus point and the saved photo isn't
  zoomed (its dimensions and field of view are the same);
- energy: with the camera screen open in full auto, readings arrive at most four a second
  (Instruments), and nothing is observed after leaving the camera screen.

### Device feedback for 1.0.0

The changes of `docs/design/device-feedback-1.0.md` are unit-tested (`CloseUpDetectorTests`,
`SteadyHintTests`, `AutoValueTests`, `ManualControlSupportTests`, `DeviceFeedbackTests`) and
UI-tested (`DeviceFeedbackUITests`, `FocusBracketUITests`) against the simulated camera; these
checks cover the hardware and the provisional values. Checks S1, S2 and F1 gate release 1.0.0:
the values they set are provisional in the code until then. Record results here, with the
device and iOS version; record no distance.

The Last Photo spot (section 1):

- **P1** On iPhone 16 Pro Max and an iPad, on the iOS version released with 1.0.0: Open Photos
  opens the Photos app from the camera, from a cold start and after a relaunch.
- **P2** What Photos shows when opened this way, so no wording promises more.
- **P3** Take a photo, quit the app, open it: Open Photos is there; take a photo: the thumbnail
  replaces it.
- **P4** The Lock Screen camera before its first photo: the spot is empty and nothing there can
  be pressed.
- **P5** iPhone Duo: fold and unfold with Open Photos showing.

Use the Whole Range (section 2):

- **W1** Night mode on an iPad, Bracket Settings as a sheet at its regular width: the check mark
  and the words are easy to read in a dark room.
- **W2** VoiceOver reads "Use the Whole Range, button" with another range set, and "Selected,
  Use the Whole Range, In use, button" with the whole range.

Close-up focus (section 3 and the detector):

- **C1** On 1× and 5×, a subject nearer than the lens can focus brings up the hint, and About
  Close-Up Focus opens the entry. The detector's thresholds are provisional
  (`CloseUpDetector`): lens position 0.05 or less, for 2 of the last 2.5 seconds, with a search
  seen within 4 seconds. Record when the hint comes (or doesn't) for a subject the lens can't
  focus on and one at its closest focus, and whether readings keep arriving while the lens rests
  at its nearest position (the reading throttle now sends the last reading once things settle,
  and `isAdjustingFocus` is observed).
- **C2** On iPhone 16 Pro Max, 0.6× focuses nearer than 1× and 5×, so "try the Ultra Wide lens"
  is good advice there. Also record whether each lens reports `minimumFocusDistance` (not −1):
  where both report it, the hint offers the Ultra Wide lens only if it focuses closer; where one
  doesn't, it is still offered. No distance is recorded in the app.

"Hold it steady or use a tripod." (section 4):

- **S1** On iPhone 16 Pro Max, an iPad and one iPhone with an unstabilized lens: the value of
  `AVCapturePhotoOutput.isLensStabilizationDuringBracketedCaptureSupported` with each lens
  attached (`Lens.reportsStabilization`). If no usable signal is found, the allowance stays at 0
  for every lens (decision 16).
- **S2** For each lens of iPhone 16 Pro Max, handheld, a flat target with fine text: ten photos at
  each shutter from the handheld rule to 3 stops slower, one stop apart, by two people. The
  allowance for that lens is the slowest step at which at least eight of ten are sharp at 100%.
  Set `AutoShutter.stabilizationAllowance` (now 2 stops, provisional) from the result.
- **S3** Walking between a bright and a dim room on each lens: the hint does not flicker (the
  half-stop `AutoShutter.returnMargin` and the 2-second minimum).
- **S4** An evening indoors on each lens, Manual Controls off: note when the hint shows, beside
  the system camera in the same light.
- **S5** Manual Controls on, Shutter on Auto and set to 1 s: no hint.

The focus square and Lock (section 5):

- **F1** Beside the system camera on iPhone 16 Pro Max: three seconds
  (`NopeMotion.focusAidLinger`, provisional) is long enough to press Lock with one hand and short
  enough to be out of the way. Adjust within 2 to 5 seconds.
- **F2** VoiceOver on: the square and Lock stay; focus on Lock is never lost; the viewfinder's
  actions work after a tap.
- **F3** Switch Control with automatic scanning at its slowest: Lock can be reached.
- **F4** Voice Control: "Tap Lock" in time; "Long press Viewfinder" locks.
- **F5** iPad with a keyboard: Tab to Lock holds it (read through SwiftUI's focus state, an
  assumption).
- **F6** Touch and hold after the fade locks at the held point.
- **F7** On a tripod with a still subject: after the fade, focus and exposure stay at the tapped
  point.

### Astro helper on a device

The rules (starting exposure, the run, its stop conditions) are unit-tested against a scripted
backend, and the screens with UI tests; these checks need the iPhone 16 Pro Max at night on a
tripod (issue #60):

- record each rear lens's `activeFormat.maxExposureDuration` and ISO range for the RAW format
  here (the Astro Settings sheet shows the shutter and ISO it set); the helper offers no lens
  without manual focus or Bayer RAW;
- focus at lens position 1 (the far end): is a bright star sharp, or does it need fine-tuning
  with Magnify and the Focus control? Lens position isn't calibrated to a distance (AVFoundation,
  `lensPosition`), so record the result per lens;
- whether the highest ISO is a useful starting point or should be lower (owner decision);
- a run of 20 frames with a 10 second start delay: every frame is a separate Bayer RAW (DNG)
  photo that passes the read-back and is signed, the frames open in a stacking application, and
  the time per frame beyond the shutter (read-out and saving) is recorded here;
- the screen stays awake and dims during the run; the light can't be turned on; night mode
  (natural and red viewfinder) with the magnifier on enlarges the real viewfinder;
- the run stops when storage is nearly full and at 10% battery unplugged (`AstroModel.stopBatteryLevel`,
  an assumption), and every frame taken before is saved.
- night mode: off before Astro, on with it, and off again after choosing another drive mode, after
  switching to a lens without Astro; after the app is closed during Astro and opened again it is
  still on, and leaving Astro later doesn't turn it off; on before Astro, or changed with the Control Center or Lock Screen control while Astro is on, it
  stays as it is; with Keep Night Mode After Astro on, it stays on.

Issue #108, the night mode record and the Lock Screen camera: with night mode off, turn Astro
on in the app (night mode turns on), lock the phone, open the Lock Screen camera and take a
photo, then unlock and return to the app, and leave Astro: night mode turns off. Repeat with the
app closed by the system in between (it then keeps night mode on, as after any relaunch).

### Bracketing on a device

Exposure bracketing on the drive strip (docs/design/BRACKETING.md, section 9). The plan, the
order, the progress and each photo's place are unit-tested against a scripted backend
(`BracketDriveTests.swift`), and the screens with UI tests (`BracketUITests.swift`); these checks
need each back lens of each supported iPhone, and gate release 1.0.0 (D4 is optional):

- **D1** each order (Darkest First, Metered First, Brightest First) with 3, 5 and 7 frames where
  the lens allows: the saved files' exposure times and ISO, in the order they were saved, match
  The Frames in Bracket Settings. Decides whether Order ships.
- **D2** a bracket in full auto, in bright and in dim light: the frames are planned from the
  camera's reading at the press of the shutter (the files' exposures centre on the metered one).
  Decides the footer under The Frames.
- **D3** the limited-frame mark: at the longest shutter and highest ISO (Manual Controls, or dim
  light), the frame taken has the offset The Frames states ("+2 EV, not +4"). Decides the mark's
  wording.
- **D4** (optional) whether the per-frame delegate calls arrive while later frames are still being
  exposed. Decides whether "Taking 3 frames" could count frames; not needed to ship.

Focus bracketing (issue #90; docs/design/BRACKETING.md, sections 8 and 9) is unit-tested against a
scripted backend (`CameraModelFocusBracketTests.swift`, `FocusBracketSettingsTests.swift`) and its
screens with UI tests (`FocusBracketUITests.swift`). The build uses provisional values that these
checks replace: a reported position counts as at its plan within 0.02 (`FocusFramePlace.tolerance`)
and each photo waits 0.1 seconds after the handler (`CameraModel.focusSettleSeconds`). Closest
Focus of This Lens is not shown until D5 confirms it for a lens. At the largest text size the
accessibility audit reports the texts of Bracket Settings' Type row ("Type", and its value
"Exposure" or "Focus") as "Dynamic Type font sizes are partially unsupported" or "Text clipped" in
some runs and not others, on the iPhone and the iPad Simulator, in every form of the row tried,
while each is one whole line at the largest size's line height; the audit skips those findings
(`measuredTypeRowLabels`) and `testFocusBracketAtTheLargestTextSize` measures the row instead.
The device checks gate release 1.0.0:

- **D5** `isLockingFocusWithCustomLensPositionSupported` and `minimumFocusDistance` for each lens,
  and the real closest focus measured with a ruler. Decides which lenses offer Focus and whether
  Closest Focus of This Lens is shown for a lens.
- **D6** for positions 0 to 1 in steps of 0.05: the position reported after the handler, twice in
  each direction. Decides the tolerance and whether a direction rule is needed.
- **D7** the time from the request to the handler, and whether a photo taken at once after it is
  sharp where expected (a slanted ruler); the same with a wait of 50, 100 and 200 ms. Decides the
  wait, and go or no-go for the feature on a lens.
- **D8** the time for each frame of a 12-frame series at 12 MP and at 48 MP, with a RAW and with a
  RAW and a HEIF. Nothing is shown; decides whether the limit of 50 frames stands.
- **D9** a 20-frame series over the whole range on a slanted ruler: whether the sharp zones of
  neighboring frames overlap, by lens and step. Decides the default frame count.
- **D10** the shift of the picture's scale between the two ends of the range. Decides the tripod
  advice wording.
- **D11** exposure and white balance read from each file of a series in changing light: constant
  (acceptance criterion 4).
- **D12** battery and heat over a 50-frame series; the pause and continue on a call. Decides the
  stop rules.
- **D13** the frames of one series stacked in two stacking programs: they load and align. No
  program is named in the app.

Record the device, lens, iOS version and the result of each check here.

### The lens while the camera is busy on a device (issue #96)

The rule (`CameraModel.canChangeLens`) is unit tested with a simulated backend that holds a photo
in flight (`LensWhileBusyTests`), and the disabled lens controls with UI tests
(`LensWhileBusyUITests`, `ShortcutUITests`). What only a device shows
(docs/design/lens-while-busy.md, section 7):

- a 1/60 s photo: the lens row does not blink. A 10 s exposure (manual shutter): the row dims
  after about half a second and returns when the photo is saved;
- a lens press during a long exposure, a burst and an interval series: nothing changes, and the
  photo or series ends normally with one lens;
- the capture backend's own check: the rule (`CapturePolicy.cameraToCapture`, a plan made for
  lens A with lens B attached, a stopped session or no camera takes no photo) is unit-tested in
  `CapturePolicyTests`; that `SystemCaptureHardware` calls it before a photo, a bracket and the
  comparison shot needs camera hardware. It is not reachable from the interface any more; a
  debug build that sends `.selectLens` during a long exposure should end that photo with
  "camera not running" rather than lose it silently or raise an exception;
- VoiceOver reads "dimmed" and, during a series, the hint "The camera is taking photos. Try
  again when it's done."; focus stays on a control that becomes dimmed. Switch Control and Full
  Keyboard Access skip the dimmed controls. The Large Content Viewer still shows a dimmed lens
  button;
- night mode in the dark: the dimmed outline is still visible and clearly weaker than the lens in
  use.

### Keep Screen On and the Night Mode search field on a device (issues #88, #97, #98, #99)

Not yet checked on a device. Before the wording ships, run the device checks of
`docs/design/keep-screen-on.md`, section 11 (the idle timer back on after the limit, Auto-Lock
set to Never, Auto-Brightness while dimmed, the brightness restored after each way out, touches
everywhere on the camera screen, Low Power Mode, the Lock Screen camera left alone, VoiceOver with
the cover, energy with Instruments for the Honesty page, 10% in daylight and in the dark), and of
`docs/design/night-search-field.md`, section 9 (the field, cursor and selection red; what the
dark keyboard's bar still shows with autocorrection off; selection handles, the magnifier and the
edit menu; dictation, a hardware keyboard and Escape; the two fields' heights when Night Mode
changes and the iPad popover becoming the sheet; VoiceOver with both fields; the largest text size
on the smallest iPhone). Also: a series (interval or Astro) with the screen already at 10% or
darker shows no Brighten Screen cover (issue #99), and Every Tag in What's in This Photo shows the
red field in Night Mode (issue #98).

### Dim After on a device (issue #119)

Not yet checked on a device. Dim After (Settings › Screen, under Keep Screen On) is covered by
`KeepScreenOnTests` with a fake screen and clock (each choice, Never, Low Power Mode and the
serious heat level, Battery Low, the limit, an unknown stored value, presets and Factory
Defaults) and by `KeepScreenOnUITests.swift` (the row, the menu, the note for each choice,
Never not dimming, search, the largest text size, right to left and Night Mode, with audits).
In the UI tests `-NopeKeepScreenOnSeconds <dim>,<lowPowerDim>,<limit>` gives every choice but
Never the same `<dim>`. The Simulator has no Low Power Mode or heat, so these need a phone,
with Keep Screen On on and the camera showing:

1. Each choice, 1, 2 and 5 minutes, against a stopwatch: the Brighten Screen cover comes at
   that time after the last touch or photo, and not before.
2. Never for 30 minutes without a touch: the screen keeps its brightness, and Auto-Lock applies
   at 30 minutes. Note the battery level and how warm the phone feels (or the thermal state in
   Xcode's energy gauge) before and after. This is the evidence for the note "Never uses more
   battery and can warm the phone." in the Honesty review.
3. Never with Low Power Mode on: the screen dims after 30 seconds.
4. Never while the phone is hot (the serious thermal state, for example after a long 4K video
   in the Camera app in the sun, read in Xcode's energy gauge): the screen dims after
   30 seconds. Record how the state was reached.
5. Never during an interval series and an Astro run: the screen still dims at once when the
   series starts.
6. VoiceOver reads the note with the row, and with Never also the cost; changing the choice
   doesn't move focus. With Reduce Motion on, the dimming still fades as Keep Screen On's does.

### Burst Limit setting on a device (issue #121)

The setting alone (Settings › Camera › Burst Limit) is covered by `NopeSettingsTests`,
`SettingsPresetsTests`, `BurstLimitSearchTests` and `BurstLimitSettingUITests.swift` (the row,
the menu, search, a preset round trip, the largest text size, right to left and Night Mode, with
audits). On a phone: the row with VoiceOver (the explanation read with it, the value read as
"Off" or the number) and Voice Control ("Burst Limit"); and the choice made in the app reaches
the Lock Screen camera's Settings. The burst that stops at the limit has its own device check
with the shutter work (Burst Limit 10: a tap, a hold, a second press at photo 4, with each kind
of button).

### Pinch to switch lenses on a device (issue #95)

The step logic, where a pinch is used, the settling and the setting are unit tested
(`LensPinchTests`, `LensPinchSearchTests`), and the gesture with the simulated backend's one,
two and three rear lenses in `LensPinchUITests` (`XCUIElement.pinch(withScale:velocity:)`). The
values below are starting values from docs/design/pinch-lens.md, marked as device-tuning values
in the code; tune them here and record what was tried:

| Value | Start | Where |
| --- | --- | --- |
| First step | scale 1.25 spreading, 0.80 pinching | `LensPinch.firstSpreadStep`, `firstPinchStep` |
| Each further step | factor 1.35 | `LensPinch.furtherStep` |
| Return margin | 10% | `LensPinch.returnMargin` |
| Settle time | 0.25 s | `LensPinchSwitcher.settleSeconds` |

What only a device shows (docs/design/pinch-lens.md, section 11):

- the thresholds with one hand and with two, on the smallest and the largest iPhone and on an
  iPad: a short pinch moves one lens, a long one passes further lenses, a brush of a second
  finger moves none, and a hand resting at a threshold doesn't flip between lenses;
- the time a lens switch takes for each pair of lenses (record it here); the picture changes when
  the next camera has started and is never drawn enlarged in between;
- a long pinch across three lenses restarts the camera once, not for each lens passed;
- one haptic tick for each step, also in clean view, and none at an end of the range;
- a pinch that ends cancels a pending hold: no AE/AF lock, no tap focus and no clean-view swipe;
- an inward pinch on an iPad held upright: on the iPad Simulator in portrait no simulated inward
  pinch reached the picture, so the UI tests turn the iPad to landscape first;
- a trackpad pinch on iPad, and AssistiveTouch's pinch;
- the iPhone Duo on both displays; folding during a pinch keeps the lens the camera has;
- the label with Increase Contrast and Reduce Transparency (solid black backing), in Night Mode
  (red on black) and sideways (upright);
- VoiceOver: a pinch isn't delivered while it is on; the lens buttons still change the lens.

### iPhone Duo (foldable) on a device

The layout rule is unit-tested at the Duo's measured sizes (`CameraLayoutTests`), and the
layouts, folding and unfolding were checked on the iPhone Duo Simulator (iOS 27.2). In the
Simulator, Device Hub's Closed, Partially Open and Open buttons fold and unfold the device (no
`simctl` command does); `xcrun devicectl device orientation set --device <udid> <orientation>`
turns it. After a fold, UI test queries wait about a minute for the app to idle, so a UI test
can't fold the device; no UI test covers folding, and no CI job runs on the Duo. The Simulator
has no camera, so these checks need a real iPhone Duo:

- the outer display: the stacked layout in portrait, upright icons and text with the phone on
  its side, the bands over the picture's bottom, and the status bar strip not covering a control;
- the inner display held like a book and turned: the column layout, the interface turning with
  the phone, the preview and the saved photos upright (`AVCaptureDevice.RotationCoordinator`,
  with the inner display's own orientation), and the level's horizon and the grid's spiral in
  the right place (they assume the interface is portrait; on the inner display and on iPad the
  interface turns);
- folding and unfolding with the live view open, during a self-timer, an interval series and an
  astro run: whether the capture session is interrupted (`AVCaptureSession.wasInterruptedNotification`,
  and its reason), whether the scene leaves the foreground, and that the run continues or pauses
  and continues as it says; the self-timer is cancelled only if the app really leaves the
  foreground; record what happens here;
- folding with the phone on its side returns the outer display to portrait; the half-open
  (Partially Open) posture: what the system shows and whether the camera keeps running;
- the lens row lists only the cameras the Duo reports (expected: ultra wide, wide and front, no
  telephoto), each with Bayer RAW, and a RAW plus HEIF photo is saved on each;
- which camera the inner display uses for selfies (the rear cameras or a front camera), and
  whether the front camera changes when folding;
- the system camera handoff: the "Open nope." control and the Lock Screen camera
  (`NopeCaptureExtension`) on each display, and opening the app from the Lock Screen camera
  after unfolding.

The full release audit is in AGENTS.md, "Before any release, a full security audit must pass".

## The C2PA library and the networking check

`NopeSigning` links the C2PA library built from source with every network feature off
(`c2pa-lib/README.md`). SwiftPM downloads the published, checksummed build. To build it yourself
and test against your build, which is what CI does on every pull request:

```sh
scripts/build-c2pa-lib.sh build/c2pa-lib-work      # needs rustup; prints the checksum
mkdir -p build/c2pa-lib && (cd build/c2pa-lib && unzip -q ../c2pa-lib-work/C2PAC.xcframework.zip)
export NOPE_C2PA_LIB_FROM_SOURCE=1                  # then run any xcodebuild command below
scripts/check-c2pa-lib-licenses.sh build/c2pa-lib-work
scripts/check-no-networking.sh --allow-rust-std build/c2pa-lib/C2PAC.xcframework
```

CI's `c2pa-lib` job also builds `Tools/NopeSigningLinkCheck` and the app in Release for a device
and runs `scripts/check-no-networking.sh` on both, with no exceptions; for the app it checks the
app binary, both extension binaries (`NopeCaptureExtension`, `NopeControls`, which also draws
the Live Activity) and the embedded Apple Watch app (`Watch/NopeWatch.app/NopeWatch`).

## Checking signatures

The unit tests in `Tests/NopeSigningTests` sign synthetic DNG, HEIF and JPEG files with a
software key and validate them with the C2PA library's reader, offline: the hash binding and
claim signature are valid, the only failure is `signingCredential.untrusted`, and a one-bit
change in the image data or in the claim makes the file invalid. They also check that signing
adds only the Content Credentials store (`docs/PRIVACY.md`, "Content Credentials").

They also open every signed file in ImageIO, as Photos and other apps do: it must report the
file's own type (`com.adobe.raw-image`, `public.heic` or `public.jpeg`) with exactly one image
(`signedFileOpensInImageIOAsItsTypeWithOneImage`, and `ReadBackTests` runs the app's own
`ImageIOReadBack`). The synthetic DNG is 256 × 256 pixels because ImageIO doesn't recognize the
same DNG as a DNG at 200 × 200 or smaller (macOS 27, 2026-11-14), and a test needs an unsigned
DNG that ImageIO opens to show the signed one still does.

### Signed DNG and ImageIO

**How it was found (issue #66).** On an iPhone 16 Pro Max (iOS 27.2.1) with every metadata item
on, the RAW and HEIF passed the read-back before signing, but after signing the DNG,
`CGImageSourceCreateWithData` reported `public.tiff` with 0 images instead of
`com.adobe.raw-image`, so the read-back rejected it and nothing was saved.

**Cause.** The C2PA library's own DNG writer (c2pa-rs 0.92.0) writes a new IFD0, the old tags
plus tag 52545, at the end of the file and points the header at it; the old IFD0 stays in the
file unreferenced. Reproduced on a Mac with c2patool 0.28.6, on a camera DNG and on the
synthetic one: ImageIO reports `public.tiff` for the signed file. On the camera DNG, moving IFD0
to the end of the file is enough to cause it, with no store at all, and inserting tag 52545 into
IFD0 where it is keeps `com.adobe.raw-image` (macOS 27, 2026-11-14).

**Fix.** The app inserts the entry into IFD0 in place and appends the store
(`DNGManifestSlot`), then signs with the C2PA library's data-hash workflow: a placeholder store
of the final size, the hash over the file with the store excluded, and the signed store written
over the placeholder (`ContentCredentialsSigner.embedInDNG`). The tests check that every value in
every directory is unchanged after the insertion, in both byte orders, with IFD0 first or last,
SubIFDs, EXIF, GPS and interoperability directories, a chained IFD1 and SHORT offsets, plus 400
seeded random layouts and damaged files (`DNGManifestSlotTests`), and
`theLibrarysOwnDNGWriterMakesAFileImageIOCantOpenAsDNG` records the library's behavior, so a
library update that changes it is noticed. Checked by hand on 2026-11-14: c2patool 0.28.6
reports `Valid` for the signed synthetic DNG, HEIF and JPEG files of every kind from the tests
(`assertion.dataHash.match` for the DNG and JPEG, `assertion.bmffHash.match` for the HEIF), with
`signingCredential.untrusted` the only failure, and ImageIO on macOS 27 opens each as its own
type with one image. A DNG from the camera is signed this way only on a device (`docs/PRIVACY.md`,
"Device checks").

**Safety net.** If a signed file still fails the read-back for any reason, `PhotoSaver` saves
the unsigned file, which passed the read-back first, and the status says "Saved. Not signed: the
signed file didn't pass the check." An unreadable file is never saved.

### Checking a signed file by hand

To check a signed file by hand, use [c2patool](https://github.com/contentauth/c2patool) on a Mac
(a local tool only; it isn't a project dependency):

```sh
c2patool photo.dng             # the manifest and its validation report
c2patool photo.dng --detailed  # also the claim and the hash exclusions
```

Expect `"validation_state": "Valid"`, with `signingCredential.untrusted` as the only failure.
The anonymous per-photo certificate isn't on any trust list; that is by design.

The software key is compiled only for the Simulator. To confirm it isn't in a device build:

```sh
xcodebuild build -scheme NopeKit-Package -destination 'generic/platform=iOS' \
  -configuration Release -derivedDataPath DerivedData-device CODE_SIGNING_ALLOWED=NO
nm "$(find DerivedData-device/Build/Products/Release-iphoneos -name NopeSigning.o)" | grep -c Simulator   # 0
```

## Tag check (metadata dump from a real device)

The tag check lists every metadata tag in real files captured on an iPhone or iPad, so the
privacy list in [`PRIVACY.md`](PRIVACY.md) is based on what the device actually writes (issue
#1, step 2). It has two parts: a debug-only capture mode in the app, and a tag dumper that runs
on a Mac.

### Each new iOS and iPadOS version

The read-back fails closed for a tag a new iOS version adds, but nothing fails closed for a new
processing switch. On each iOS and iPadOS beta and major release, as well as the tag check below,
read the new SDK's `AVCapturePhotoSettings.h`, `AVCapturePhotoOutput.h`, `AVCaptureDevice.h` and
`CIRAWFilter.h` for any new processing, fusion, distortion correction or RAW decoder setting, and
check that `ProcessingSwitches.leastProcessing` and `NeutralDevelopment` set each one to its
least-processing value.

### What the capture mode does

The code is in `App/NopeApp/DebugTools/` (`TagCheckScreen.swift`, `TagCheckRunner.swift`,
`TagCheckReport.swift`), wrapped in `#if DEBUG`. It is compiled only in the Debug
configuration, and Release builds contain none of it. It runs only when the app is launched
with the `-NopeTagCheckRun` launch argument, or from an armed run (below).

The tag check drives the app's own capture backend (`AVFoundationCaptureBackend`) through the
`CaptureBackend` API only, the same instance the camera screen would use. It creates no capture
session, input or output of its own, and adds no video data output: the one session belongs to
`SystemCaptureHardware` in `NopeCapture`. So the files are exactly what the app captures, with
the backend's processing switches (`CapturePolicy`), photo settings (`PhotoSettingsFactory`),
setup order and blank-picture check.

1. It asks for camera access if it hasn't been decided (tap Allow once).
2. It asks the backend for the lenses (`deviceCapabilities()`): every physical camera, never a
   virtual multi-camera device.
3. For each lens, through the backend:
   - `startSession` with a Bayer RAW request switches to the lens (the backend replaces the
     camera input inside one configuration on the same session); after 2 seconds, so
     continuous auto exposure, focus and white balance can converge, `capturePhoto` takes a
     RAW-only DNG;
   - `startSession` with `CaptureRequest(lens:format:)` and the lens's processed fallback
     re-prepares the photo output for HEIF on the same running camera; after 0.5 seconds,
     `capturePhoto` takes the `.speed` HEIF (JPEG if the lens has no HEVC).

   A lens without a Bayer RAW format gets only the processed photo, and its report says so.
   The screen shows the backend's own viewfinder (its preview layer) while the lenses run.
4. At the end it calls `stopSession()`, which stops the session and tears it down in order
   (below) before the summary is written.
5. It writes, per lens, `<lens>-raw.dng`, `<lens>-speed.heic` and `<lens>-report.json` (device
   model identifier, OS version, the lens's published capabilities, and for each file the
   format, size, dimensions, the exposure duration and ISO read before the capture, every
   ImageIO property dictionary of the file and its decoded `luminance`), and a `summary.json`.
   A capture the backend rejected as blank is reported as `failed: blankPicture`.

Earlier versions also wrote a metadata-stripped DNG (`fileDataRepresentation(with:)`), one live
video frame per lens and `AVCapturePhoto.metadata`. They needed their own session per lens
with an extra video data output, which is what left the camera service stuck (see "Black
frames"), so they were removed. The tag dumper reads the same metadata from the files.

Lens names are `back-wide`, `back-ultrawide`, `back-telephoto`, `front-wide` and so on. Every
file goes to the app's `Documents/TagCheck/` folder, with complete file protection; each run
replaces the folder. The screen lists each step, and the same lines are logged with `Logger`
as private values. No location is requested and no GPS metadata is supplied.

Writing photos to the app's container is acceptable here only because this is a debug tool.
Release builds never write photos to the container: photos go from memory to Photos (AGENTS.md,
"Photos never linger").

### Running it

**Check first that no Mac is viewing the phone's screen** (no viewing icon in the Dynamic
Island): while one is, every app other than Apple's Camera gets blank frames (see "Black
frames").

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your own team ID.
2. Install a Debug build. Open the app normally from the Home Screen once and check that the
   viewfinder shows the scene.
3. Launch the tag check. In Xcode: Product › Scheme › Edit Scheme › Run, keep the Build
   Configuration at Debug, add `-NopeTagCheckRun` to "Arguments Passed On Launch", and run. From the
   command line:
   ```sh
   xcrun devicectl device process launch --device <device-id> --terminate-existing \
     com.photivra.nope.dev -- -NopeTagCheckRun
   ```
   Arguments after the bundle ID must follow `--`; without it `devicectl` parses `-Nope...` as
   its own options and does not launch the app.
4. Point the phone at a well-lit scene, and keep it still until the list says "Finished".
5. Keep the device unlocked (the files use complete file protection) and copy the folder to the
   Mac:
   ```sh
   xcrun devicectl device copy from --device <device-id> \
     --domain-type appDataContainer --domain-identifier com.photivra.nope.dev \
     --source Documents/TagCheck --destination TagCheckOutput
   ```
   `xcrun devicectl list devices` shows the device identifier.
6. Open the app normally again and check that the viewfinder still shows the scene.
7. Dump the tags:
   ```sh
   swift scripts/dump-tags.swift TagCheckOutput
   ```

### Checking that frames are exposed

Every file is decoded on the device (`CIRAWFilter` for DNGs, `CIImage` otherwise) and
measured. In each `<lens>-report.json`, `captures.<file>.luminance` has:

- `meanLuma`, `minLuma`, `maxLuma`: Rec. 709 luma of the sRGB-encoded image, 0 to 1;
- `looksBlack`: the mean is below 0.01;
- `looksFlat`: the whole image is within one 8-bit step, a constant fill;
- `maxRed`, `maxBlue` and `looksZeroFilled`: a zero-filled YCbCr buffer decodes as a green
  field with no red or blue anywhere, which can pass the mean test.

The status list and `summary.json` say "done, but the image looks black or flat" for such a
file. For a lit scene, expect all three flags to be `false`, a `meanLuma` well above 0.01 and a
`maxLuma` above `minLuma`, and the HEIF's `{Exif}` `ExposureTime` and `ISOSpeedRatings` not 0.
The thresholds are tool settings, not platform values.

### Black frames

**Symptom.** On an iPhone 16 Pro Max (iOS 27.2.1), every tag check run produced zero-filled
buffers on every lens and output: the Bayer DNGs were a constant fill (all 16 tiles identical,
the lossless-JPEG data one repeated byte, decoded mean exactly 0), the 15 KB `.speed` HEIFs
decoded to a green field (a zero YCbCr buffer) with no `ExposureTime` or ISO, and every
sampled luma byte of the video data output frames was 0. At the same time the session reported
running, frames arrived at the exposure's rate, `captureReadiness` was `.ready`, and auto
exposure metered the room normally (for example 1/60 s, ISO 134, −0.06 EV).

**Cause (confirmed 2026-11-12).** A Mac was viewing and controlling the phone's screen. While
such a session runs, the Dynamic Island shows a purple screen-and-person icon, and Settings
shows "“MacBook Pro” is viewing and controlling this iPhone" with a **Stop Session** button.
During the session, every app other than Apple's Camera got blank frames, including other
camera apps from the App Store, while the session ran normally and auto exposure followed
the room. Tapping **Stop Session** brought the app's live viewfinder back at once, with no code
change and no restart, and the next tag check produced real images on every lens. The session
started while the phone was connected to the Mac for development builds; which Mac feature
starts it has not been isolated. No Apple documentation found describes the blanking.

**Before any camera test on a device:** check that the Dynamic Island shows no viewing icon.
If it does, tap it, then **Stop Session**. Stopping it also unpairs the Mac; plug the phone in
again and tap **Trust** to install builds.

**Earlier diagnosis, now superseded.** Before the cause was found, the blank frames were blamed
on the old tag check's pipeline (a separate `AVCaptureSession` per lens, an extra
`AVCaptureVideoDataOutput`, and a bare `stopRunning()`), because a phone restart sometimes
seemed to clear them. That was not confirmed: after a restart, the main-branch build, a fresh
bundle identifier and a session with none of the app's settings were all blank while the viewing
session ran. The changes below are kept because they are simpler and safer, not because they
fixed the blank frames.

**Changes kept from the earlier diagnosis.**

- The tag check now uses the app's backend and its single session (above). It builds no
  sessions and no video data output.
- Teardown is strictly sequential everywhere a session stops: `SystemCaptureHardware.stop()`
  and the probe call `stopRunning()` on the session's own serial queue, which "is synchronous
  and blocks until the receiver has completely stopped running" (`AVCaptureSession.h`), then
  remove every input and output in one configuration, and only then return. The backend's
  `stopSession()` awaits that, so nothing configures or starts the session while it is
  stopping. The backend never creates a second session.
- **Stuck-camera detection** in the real backend. After every capture, `SystemCaptureHardware`
  reads 128 bytes (two adjacent bytes at 64 evenly spaced places) from the photo's pixel
  buffer, and `PictureCheck` (tested) calls it blank when they are all equal: a sensor readout
  always has noise, a zero or constant fill never does. `AVFoundationCaptureBackend` then
  drops the photo and throws `CaptureError.blankPicture`. `CameraModel` stops and restarts the
  session once and retakes the photo; if that is blank too, it moves to
  `SessionStatus.noPicture`, which the camera screen shows as "The camera isn't sending a
  picture." with the shutter disabled (another lens
  tries again). The check runs on the photo, not on preview frames: the backend has no video
  data output, and adding one to the pipeline under suspicion, and processing frames ahead of
  need, was ruled out. `AVCapturePhoto.pixelBuffer` is documented as `nil` for compressed
  formats, so a HEIF or JPEG photo (a lens without Bayer RAW) isn't checked and counts as a
  picture. That the RAW-only DNG capture does carry its pixel buffer is an assumption from the
  documentation, not yet confirmed on a device; if it is `nil`, the check is skipped, never
  falsely triggered. The restart-and-retry logic and the message are unit- and UI-tested
  (`CameraModelTests`, the `blankPicture` scenario); the trigger itself can only be seen on a
  phone that delivers blank frames.

### Debug runs for diagnosis

These Debug-only tools stay for future diagnosis. **Before a run, check that no Mac is viewing
the phone's screen** (above), and open the app normally first to check the viewfinder: a run while
the camera picture is blanked gives blank frames whatever the pipeline, and proves nothing.

- `-NopeCameraProbe` runs the simplest pipeline from Apple's sample flow
  ([Setting up a capture session](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session),
  [AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)):
  its own session with the `.photo` preset, `AVCaptureDevice.default(for: .video)`, a
  full-screen preview layer, a video data output and one default HEVC photo, then the same
  sequential teardown. The app's backend never starts in that launch. It writes
  `probe-report.json`, `probe-frame.jpg` and `probe-photo.heic` to `Documents/TagCheck/`, with
  the app and scene activation state, authorization, `isInterrupted`, every interruption or
  runtime-error notification, `isSuspended`, multitasking camera access, the exposure state,
  the photo's `{Exif}`, the decoded luminance and the raw luma-plane bytes of the frame.
  `-NopeProbeNoVideoOutput` leaves out the video data output; `-NopeProbeFrontCamera` uses the front
  camera.
- `-NopeArmDebugRun tagcheck` (or `probe`) only stores the run and shows a message. The next
  launch from the Home Screen performs it once and clears it.

Pass every argument after `--`, for example
`xcrun devicectl device process launch --device <device-id> --terminate-existing com.photivra.nope.dev -- -NopeCameraProbe -NopeProbeFrontCamera`.

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
