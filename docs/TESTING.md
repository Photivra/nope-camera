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
| `interrupted` | The "in use by another app or a call" message, shutter disabled; also at the largest accessibility text size |
| `hot` | The "cool down" message, shutter disabled |
| `captureFails` | The capture failure message |
| `blankPicture` | Every photo is blank: after the shutter, one automatic restart and retry, then "The camera isn't sending a picture.", the blank-picture capture message, shutter disabled |
| `denied`, `noCamera` | The access-off and no-camera screens |

At the largest text sizes the screen scrolls, and the audit ignores a contrast issue only for an element that runs past the screen edge (it measures the clipped edge); every other issue still fails (`auditScrollingScreen`).

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
- the manual accessibility pass in AGENTS.md (VoiceOver, Voice Control, Switch Control, the
  largest text size).

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
