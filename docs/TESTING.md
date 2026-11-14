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

## UI tests and accessibility audits

```sh
xcodebuild test -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' CODE_SIGNING_ALLOWED=NO
```

The Simulator has no camera, so `NopeAppUITests` launches Debug builds with
`-NopeSimulatedCamera <scenario>` (`App/NopeApp/DebugTools/SimulatedCameraLaunch.swift`), which
swaps in `SimulatedCaptureBackend` and simulated save steps (`SimulatedSaving.swift`; nothing
touches the Simulator's photo library). Release builds ignore the argument. The scenarios and what
each test checks, with `performAccessibilityAudit()` in every state:

| Scenario | Test |
|---|---|
| `allow` | Permission screen; allow; camera ready with the RAW badge and the wide lens selected; shutter gives "Saved and signed." (a simulated signer stands in for the real one, which `NopeSigningTests` cover); the telephoto (no RAW) shows the fallback badge |
| `metadataRejected` | Every file carries a simulated future system tag: "Not saved: nope. couldn't confirm that the photo holds only the details you chose."; also at the largest accessibility text size |
| `photosDenied` | Adding to Photos isn't allowed: the "isn't allowed to add photos" message |
| `signingFails` | The signer fails: the photo is saved unsigned, "Saved. Not signed: the signature couldn't be created.", shutter still enabled |
| `signedFileRejected` | Every signed file fails the read-back: the unsigned files are saved, "Saved. Not signed: the signed file didn't pass the check.", shutter still enabled |
| `interrupted` | The "in use by another app or a call" message, shutter disabled; also at the largest accessibility text size |
| `hot` | The "cool down" message, shutter disabled |
| `captureFails` | The capture failure message |
| `blankPicture` | Every photo is blank: after the shutter, one automatic restart and retry, then "The camera isn't sending a picture.", the blank-picture capture message, shutter disabled |
| `denied`, `noCamera` | The access-off and no-camera screens |
| `allow`, `denied` | Settings from the camera's Settings button: Settings, Formats, Privacy (top and bottom), Honesty (top and bottom), About and the license text, each audited at the default size, at the largest accessibility text size and in right-to-left layout; the format rule (the last format can't be turned off), the HEIF and JPEG look picker (shown only with HEIF or JPEG selected) and the privacy rules (master switch on by default, one item on makes it "Custom", signing on, locked items read "Locked") |

UI test launches store settings in their own `UserDefaults` suite, emptied at each launch
(`SimulatedCameraLaunch.settingsStore()`), so every test starts from the defaults and the real
settings are never touched.
| `manual` (with `-NopeSettings.showsManualControls YES`) | Manual controls: hidden without the option; the six slots; a panel with the lens's range; Manual and "All Auto"; P/S/I/M; exposure compensation blocked in M; the ultra wide's fixed aperture; Pro Tools and a 3-frame bracket; interval progress and Stop; clean view; the list at the largest text size; right-to-left |
| `allow` (clean view) | The no-RAW badge stays visible in clean view |

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
| `unit-tests` | Coverage gate tests, the tag dumper's TIFF walker test, NopeKit unit tests on the iOS 27.2 Simulator, the coverage gate |
| `ui-tests` | App build and the UI smoke test with accessibility audits |
| `docs` | `scripts/check-docs.sh` |

`.github/workflows/repo-checks.yml` (`repo-checks`) runs the quick checks above.

## On-device checks

Some behavior can only be checked on hardware. Before a release, on at least one iPhone and one
iPad:

- the camera permission prompt shows the localized `NSCameraUsageDescription`, and each answer
  leads to the right screen (`SystemCameraAuthorization`);
- a Secure Enclave key signs and verifies (`SecureEnclaveSigningKey`), and a DNG, HEIF and JPEG
  saved on the device validate with c2patool (below) as `Valid` with only
  `signingCredential.untrusted` failing;
- capture (`SystemCaptureHardware`): every physical lens appears with the right label; the
  viewfinder shows the scene; the shutter, the volume buttons and the Camera Control each take
  a photo and show "Saved and signed."; a lens
  without Bayer RAW shows the fallback badge; a phone call or another camera app shows the interruption message, and
  the camera comes back afterwards; and the tag check (below) shows exposed frames;
- saving (`PhotoKitLibrary`, `SystemCaptureHardware`, `CoreImageRAWRenderer`): the add-only
  prompt appears once and declining it shows the "isn't allowed to add photos" message; a RAW
  plus HEIF appears as one photo in Photos with the RAW as the original; every saved file passes
  the read-back (`docs/PRIVACY.md`, "Device checks") and an exiftool dump matches the tables in
  `docs/PRIVACY.md`;
- manual controls (`SystemCaptureHardware`), on each lens of each test device, with manual
  controls turned on: see "Manual controls on a device" below;
- the manual accessibility pass in AGENTS.md (VoiceOver, Voice Control, Switch Control, the
  largest text size).

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
- readings: the meter and the Auto values update while manual controls are on, and nothing is
  observed while they are off (Instruments: no key-value observation callbacks);
- with VoiceOver: each slot adjusts by swiping up and down, and the eyes-free shutter (volume
  buttons, Camera Control) still works with manual controls on and in clean view.

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
and runs `scripts/check-no-networking.sh` on both, with no exceptions.

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

**Fix.** nope. inserts the entry into IFD0 in place and appends the store
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
2. Install a Debug build. Open nope. normally from the Home Screen once and check that the
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
6. Open nope. normally again and check that the viewfinder still shows the scene.
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
the room. Tapping **Stop Session** brought nope.'s live viewfinder back at once, with no code
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
bundle identifier and a session with none of nope.'s settings were all blank while the viewing
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
the phone's screen** (above), and open nope. normally first to check the viewfinder: a run while
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
