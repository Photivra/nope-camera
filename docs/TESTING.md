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
```

`check-security.sh` reads tracked files only (`git ls-files`), so stage new files before running
it.

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
- the Settings screens at the default text size and right-to-left skip the Dynamic Type check:
  the iOS 27.2 Simulator reported system form section headers and footers as "partially
  unsupported" there, cause unknown; every Settings screen passes the full audit, Dynamic Type
  included, at the largest accessibility text size;
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
| `allow`, `signingFails`, `noRAW` | The last photo (issues #36, #53): after a save the thumbnail is a button named "Last Photo" with a simulated picture; its long-press menu offers Open in Photos and Photo Details; "What's in This Photo" lists the files, signature (signed, or "Not signed" with the reason), processing (the fallback's "processed by the phone's camera"), the details left out with "Off in Settings", and the timings, at the default and largest text sizes and right-to-left; tapping the thumbnail brings the Photos app to the front; with `manual` and a bracket, the details' Photo picker shows each frame |
| `noRAW` | A device without RAW (wide and front, no Bayer RAW): the "Processed" marker ("Processed: no RAW on this lens, HEIF" for VoiceOver) and the HEIF fallback in the viewfinder description, portrait and landscape, default and largest text sizes; Space takes a photo |
| `multitasking` | iPad Split View, Slide Over or Stage Manager: "The camera works only when nope. fills the screen.", shutter disabled |
| `-NopeSimulatedViewfinder white` or `yellow` | The camera with a photo, the manual readout and an open dial over a pure white and a pure yellow picture |
| `metadataRejected` | Every file carries a simulated future system tag: "Not saved: nope. couldn't confirm that the photo holds only the details you chose."; also at the largest accessibility text size |
| `photosDenied` | Adding to Photos isn't allowed: the "isn't allowed to add photos" banner with Open Settings |
| `signingFails` | The signer fails: the photo is saved unsigned, the last-photo slot and the "Not Signed" chip say "Saved. Not signed: the signature couldn't be created.", shutter still enabled; also right-to-left, with the bottom row mirrored |
| `signedFileRejected` | Every signed file fails the read-back: the unsigned files are saved, the last-photo slot and the "Not Signed" chip say "Saved. Not signed: the signed file didn't pass the check.", shutter still enabled |
| `interrupted` | The "in use by another app or a call" message, shutter disabled; also at the largest accessibility text size |
| `hot` | The "cool down" message, shutter disabled |
| `captureFails` | The capture failure banner: Try Again, Dismiss |
| `blankPicture` | Every photo is blank: after the shutter, one automatic restart and retry, then "The camera isn't sending a picture.", the blank-picture capture message, shutter disabled |
| `denied`, `noCamera` | The access-off screen with Open Settings, and the no-camera screen |
| `allow`, `denied` | Settings, opened from Q on the stacked camera and from the Settings button elsewhere: Settings, Formats, HEIF and JPEG Copies (top and bottom), Details in Each Photo (top and bottom), Accessibility, Honesty (top and bottom), About and the license text, each audited at the default size, at the largest accessibility text size and in right-to-left layout; the format rule (the last format can't be turned off), the HEIF and JPEG Copies row ("Not Saved" with RAW only, otherwise the look) and the privacy rules (the master switch on and signing off by default, one item on makes it "Custom", locked items read "Locked"); `SettingsUITests.swift` covers the root rows, search, Show Processed Marker and the presets' More menu |

UI test launches store settings in their own `UserDefaults` suite, emptied at each launch
(`SimulatedCameraLaunch.settingsStore()`), so every test starts from the defaults and the real
settings are never touched.
| `manual` (with `-NopeSettings.showsManualControls YES`) | Manual controls: hidden without the option; the Manual Controls button ("On" or "Off"); the readout row; a dial with the lens's range, Auto, − and +; "All Auto" from the row's last button; exposure compensation blocked in M; the ultra wide's fixed aperture; Pro Tools (no Interval section) and a 3-frame bracket; the lock pill after AE-L, which unlocks; the Manual Controls button turns manual controls off; interval progress and Stop from the drive strip; clean view from Q; the list at the largest text size; right-to-left |
| `allow` (clean view) | The no-RAW chip stays visible in clean view |
| `allow` (light and flash) | The Light switch turns the light on with its pill ("25%"), which stays through a photo and in clean view, changes the brightness and turns the light off; the Flash menu and its pill; the light hides the flash pill; no Light or Flash on the ultra wide |
| `lightUnavailable` | The system refuses the light: the "Light Unavailable" warning, cleared by turning Light off |
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
make the audit time out), and a failing audit is repeated once after the layout settles again.
It could not be made to fail locally before or after the change (10 runs, 4 of them with every
CPU core busy); after it, it passed 3 times in a row with the whole UI suite.

`CaptureReadinessTests` use a 600-second timeout: the ready answer comes on a fixed read, so the
timeout only has to be longer than any CI runner can take (with 5 seconds, `waitsUntilReady`
failed intermittently while the other tests kept every thread busy).

Right-to-left layout is tested with `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`.
Every new screen and state adds an audit.

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
| `ui-tests 1/8` … `8/8` | The UI tests with accessibility audits on the iPhone 18 Pro Simulator, one shard per job (`test-without-building`) |
| `ui-tests-ipad 1/8` … `8/8` | The same shards on the iPad Air 11-inch (M4) Simulator, except `testSourceCodeIsAnHTTPSLink`: on iPad the About screen's source link isn't found in the Settings popover, an open finding |
| `ui-tests`, `ui-tests-ipad` | Pass only when every iPhone (iPad) shard passed; these are the required status checks |
| `file-compat` | The pinned c2patool and exiftool (`scripts/install-file-validators.sh`) on the fixtures from `unit-tests`; both are required (see "File compatibility") |
| `ui-tests-watch` | The Apple Watch app's UI tests with accessibility audits on the Apple Watch Series 12 (46mm) Simulator (`NopeWatch` scheme) |
| `docs` | `scripts/check-docs.sh` |

`.github/workflows/repo-checks.yml` (`repo-checks`) runs the quick checks above.

Every job uses the iOS 27.2 and watchOS 27.2 Simulators. The app supports iOS, iPadOS and
watchOS 26 and 27 (issue #78), but the `xcode-27` image has no iOS 26 or watchOS 26 Simulator
runtime, and the `macos-26` image, which has them, has no Xcode 27, which the app needs (it
uses iOS 27 APIs behind `#available(iOS 27, *)` checks). In CI, version 26 is checked at build
time only: with the deployment target at 26.0, the compiler rejects any API newer than iOS or
watchOS 26 that isn't behind an `#available` check. Running on version 26 is part of the
on-device checks below.

### UI test shards

The UI suite takes about 85 minutes per device on the GitHub macOS runner (about twice as long
as on a recent Mac, so CI limits are sized from runner times, never from local ones). CI runs it
in eight shards per device, about 18.5 minutes of tests each by the times of build 43786103024
plus about 5 minutes of setup (up to 10 when the Simulator is slow to boot), with a 35-minute
limit per job. `scripts/ui-test-shards.txt` lists every UI test with its shard and
its time in seconds on the runner (the longer of the iPhone and iPad runs), or, marked `est`,
twice its local time until the runner has measured it; the shards are balanced by those times
(longest test first, into the shard with the least time so far). To rebalance, take the times
from the `Test Case … passed (n seconds)` lines of the shard jobs' logs.

`scripts/ui-test-shards.sh args <n>` prints the `-only-testing` arguments of shard n.
`scripts/ui-test-shards.sh check`, in `repo-checks`, fails when a test in `App/NopeAppUITests` is
in no shard or in two, when a listed test doesn't exist, or when the shard matrices or job names
in `build.yml` don't match the list, so a new test can't be skipped silently: add it to the
shard with the least time, marked `est` with twice its local time.

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
iPhone too, beside the watch and before the build, and waits for both, and it fails the step if
the app can't be launched once (it ignored a failed launch before).
In the first sharded CI run, two shards failed before any test started ("The test runner crashed
while preparing to run tests", after 7 to 9 minutes of "Testing started"), and the first test of
two others failed to launch the app within its time limit; both happened on a Simulator the test
runner had to boot itself. The script retries a shard once, after rebooting the Simulator, only
when the test runner failed before any test started (any "… while preparing to run tests" error,
including "Test crashed with signal term while preparing to run tests", which ended an iPad shard
of build 43786103024 after its Simulator took five minutes to boot); a run in which a test started
is never retried. `scripts/test-ui-test-shards.sh` tests both scripts.

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

To run one shard locally, with a Simulator named as in CI:

```sh
xcodebuild build-for-testing -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
scripts/run-ui-test-shard.sh 1 "iPhone 18 Pro" DerivedData/Build/Products ui-tests.xcresult
```

### Siri and Shortcuts in the UI tests

XCTest can't speak to Siri or run a shortcut, so Debug builds take
`-NopeSimulatedShortcut <request>`: a number for Take Photo with that delay in seconds,
`burst<count>` for Take Photo with a count, `bracket<count>` for Take Bracket, or
`lens-ultraWide` for Switch Lens. The app sends
the request through the same `ShortcutInbox` the intents use and shows what Siri would say
(`ShortcutUITests`: a delay with the countdown, a cancelled countdown, no camera access, a burst
of three, a bracket in full auto and a lens switch). The Interval drive mode is covered by
`testIntervalShootingFromTheDriveMenuInFullAuto` and the sheet's audits at the largest text size
and right-to-left. The request logic (counts, lenses, the light, interval shooting,
requests without a camera screen) is unit tested in `ShortcutTests`.

## On-device checks

Some behavior can only be checked on hardware. Before a release, on at least one iPhone and one
iPad, with at least one device (or, where hardware isn't needed, a Simulator) on iOS or iPadOS 26
and one on 27, the oldest and newest supported versions (issue #78):

- the camera permission prompt shows the localized `NSCameraUsageDescription`, and each answer
  leads to the right screen (`SystemCameraAuthorization`);
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
  tapping it opens Photos, where the new photo is the newest item (the `photos-redirect://` URL
  opens Photos, not a chosen asset; Apple documents no way to open one asset, and the URL itself
  isn't documented by Apple); the long-press menu and the VoiceOver actions offer Open in Photos
  and Photo Details; for each photo, the details match `exiftool -a -G1 -s` of the files exported
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
- burst (issue #46), on each lens for RAW, RAW + HEIF and HEIF: holding a volume button or the
  Camera Control takes a burst until it is released, and tapping the shutter starts and stops
  one; record the frames per second (below, "Burst rate"); every saved frame passes the
  read-back and is its own photo in Photos; memory stays flat over 50 frames (Instruments,
  Allocations); VoiceOver announces the start and the saved count;
- storage and battery warnings (issue #44): see "Low storage" below; at 20% battery, unplugged,
  "Battery Low" shows and is announced, and it goes away when the device is plugged in; Low Power
  Mode changes the explanation;
- interval shooting screen (issue #48): during a series the screen doesn't lock and is dimmed;
  a tap brightens it while the series continues; the brightness and auto-lock come back when the
  series ends, is stopped, or the app goes to the background, and after the camera screen closes.

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
  nope.", and "Take a bracket with nope." in full auto and with a bracket chosen in Pro Tools
  (three photos at different exposures; the Pro Tools bracket and Manual Controls are unchanged
  afterwards; on the front camera Siri says the lens can't take it).
- Shortcuts: Take Photo with a custom delay, each lens (a missing lens says so) and Number of
  Photos 5 (five separate photos, no "Burst stopped" announcement), Switch Lens, Turn On and Turn
  Off the Light, Start Interval Shooting with Seconds Between Photos and Number of Photos, Stop
  Interval Shooting, Take Bracket with 5 and 7 Photos and each Step (7 on a lens that takes fewer
  says so), and Set Night Mode on and off, with the app closed and with it open (the
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
- Check in each of the 11 languages that Siri accepts the localized phrases.

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

Not measured yet. On an iPhone 16 Pro Max, for each lens and RAW, RAW + HEIF and HEIF, hold the
shutter for a 20-frame burst and record frames per second here (time from the first to the last
frame, from the photos' capture times).

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
- **Which lenses have no Bayer RAW:** run the Debug tag check (`-NopeTagCheck`, "Tag check"
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
  same distortion line as the note; a RAW photo shows none.

### Viewfinder overlays on a device

The geometry, level, analysis and rate rules are unit-tested; these checks cover the hardware
(`SystemLiveView`, `PreviewRotation.previewAngle`, `MotionGravitySource`):

- grid: each style in portrait and both landscape orientations; the spiral keeps its place
  relative to the horizon when the phone turns; lines stay visible over white, yellow and dark
  scenes;
- level: the bar matches a real horizon (or a spirit level) within about 1 degree in portrait
  and both landscape orientations; the haptic fires once on becoming level; pointing straight
  down shows the top-down level; Instruments shows no motion updates while the level is off;
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
  when ISO is at the lens's highest, the hint "Hold it steady or use a tripod." appears once, is
  spoken by VoiceOver, and goes when the light comes back without flickering (the half-stop
  margin is an assumption to check); the focal lengths computed from the field of view match
  Apple's published ones within a few millimeters;
- manual controls: a manual shutter slower than the handheld rule shows the hint and is never
  changed; P mode isn't limited;
- Close-Up: a small subject 5 to 15 cm away in front of a busy background focuses with Close-Up
  on and a tap, and the pill turns it off;
- close-up hint: below the wide lens's minimum focus distance the suggestion to switch to Ultra
  Wide appears within about two seconds (the thresholds, `lensPosition` ≤ 0.05 for eight readings
  while autofocus searches, are assumptions to tune), never switches by itself, and Dismiss hides
  it until the lens changes;
- the magnifier enlarges the viewfinder around the focus point and the saved photo isn't
  zoomed (its dimensions and field of view are the same);
- energy: with the camera screen open in full auto, readings arrive at most four a second
  (Instruments), and nothing is observed after leaving the camera screen.

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

### What the capture mode does

The code is in `App/NopeApp/DebugTools/` (`TagCheckScreen.swift`, `TagCheckRunner.swift`,
`TagCheckReport.swift`), wrapped in `#if DEBUG`. It is compiled only in the Debug
configuration, and Release builds contain none of it. It runs only when the app is launched
with the `-NopeTagCheck` launch argument, or from an armed run (below).

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
   Configuration at Debug, add `-NopeTagCheck` to "Arguments Passed On Launch", and run. From the
   command line:
   ```sh
   xcrun devicectl device process launch --device <device-id> --terminate-existing \
     com.photivra.nope.dev -- -NopeTagCheck
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
  `-NopeProbeNoVideoOutput` leaves out the video data output; `-NopeProbeFront` uses the front
  camera.
- `-NopeArmDebugRun tagcheck` (or `probe`) only stores the run and shows a message. The next
  launch from the Home Screen performs it once and clears it.

Pass every argument after `--`, for example
`xcrun devicectl device process launch --device <device-id> --terminate-existing com.photivra.nope.dev -- -NopeCameraProbe -NopeProbeFront`.

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
