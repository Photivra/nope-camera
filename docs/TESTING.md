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
| `Sources/NopeSigning/SecureEnclaveSigningKey.swift` | The Simulator has no Secure Enclave | On-device check |

Each excluded file is a thin wrapper; its logic lives in a tested file. For capture, the
decisions are in `LensCatalog` (which cameras and formats), `CapturePolicy` (every processing
switch), `PhotoSettingsFactory` (the photo settings) and `CaptureReadiness` (when to capture),
and `AVFoundationCaptureBackend` is tested against a fake `CaptureHardware`. `NopeUI` is not part of
the coverage gate: it is covered by UI tests and accessibility audits instead.

## UI tests and accessibility audits

```sh
xcodebuild test -project App/NopeCamera.xcodeproj -scheme NopeApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' CODE_SIGNING_ALLOWED=NO
```

The Simulator has no camera, so `NopeAppUITests` launches Debug builds with
`-NopeSimulatedCamera <scenario>` (`App/NopeApp/DebugTools/SimulatedCameraLaunch.swift`), which
swaps in `SimulatedCaptureBackend`. Release builds ignore the argument. The scenarios and what
each test checks, with `performAccessibilityAudit()` in every state:

| Scenario | Test |
|---|---|
| `allow` | Permission screen; allow; camera ready with the RAW badge and the wide lens selected; shutter gives "Captured (not saved yet: development build)"; the telephoto (no RAW) shows the fallback badge |
| `interrupted` | The "in use by another app or a call" message, shutter disabled; also at the largest accessibility text size |
| `hot` | The "cool down" message, shutter disabled |
| `captureFails` | The capture failure message |
| `denied`, `noCamera` | The access-off and no-camera screens |

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
- a Secure Enclave key signs and verifies (`SecureEnclaveSigningKey`);
- capture (`SystemCaptureHardware`): every physical lens appears with the right label; the
  viewfinder shows the scene; the shutter, the volume buttons and the Camera Control each take
  a photo and show "Captured (not saved yet: development build)"; a lens without Bayer RAW shows
  the fallback badge; a phone call or another camera app shows the interruption message, and
  the camera comes back afterwards; and the tag check (below) shows exposed frames;
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
   no flash, and zero shutter lag and responsive capture off. The output's switches and an
   explicit `maxPhotoDimensions` (the format's smallest size, 12 MP) are committed before the
   session starts, and the photo output is prepared for the first capture
   (`setPreparedPhotoSettingsArray`). Each capture waits for `captureReadiness` to be `.ready`.
   RAW is requested as RAW-only DNG (`rawFileType: .dng`), the processed photo with its file
   type (`.heic`). This is the same order as the app's backend; see "Black frames" below.
   No location is requested and no GPS metadata is supplied.
   Auto exposure, focus and white balance stay continuous, and a video data output keeps
   frames flowing. The screen shows the live view, so you can aim at a lit scene. Before the first capture with each lens, it waits at least 1 second and
   until the session is running, at least 10 frames have arrived, and exposure, focus and white
   balance have stopped adjusting, up to 5 seconds. The report records whether it settled or
   timed out. (A fixed 1-second wait without a video output gave black frames on a device.)
3. It captures, per lens:
   - `<lens>-raw.dng`: a Bayer RAW-only capture, written with `fileDataRepresentation()`;
   - `<lens>-raw-stripped.dng`: the same RAW photo written with
     `fileDataRepresentation(with:)` and a customizer whose `replacementMetadata` removes
     `{MakerApple}`, `{GPS}` and every key whose name contains "SerialNumber" or "UniqueID"
     (the planned native removal path);
   - `<lens>-speed.heic`: a processed HEVC photo at `.speed` (`<lens>-speed.jpg` if the device
     offers no HEVC).

   - `<lens>-preview.jpg`: one live video frame, saved after the camera settles.

   A lens without a Bayer RAW format gets only the processed photo, and its report says so.
4. It writes `<lens>-report.json` for each lens (device model identifier, OS version, camera
   type and position, active format, RAW formats and whether each is Bayer, ISO, exposure and
   aperture ranges, every supported maximum photo size, iOS 27 aperture values,
   `maxBracketedCapturePhotoCount`, the photo output's processing switches, the settle result,
   the exposure duration, ISO, aperture, focus and white balance at each capture, the requested
   and resolved photo settings, `photo.metadata`, whether the output was prepared, the capture
   readiness before each capture, and the decoded `luminance` of every file and of the preview
   frame), and a `summary.json`.

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

### Checking that frames are exposed

Every file and the preview frame are decoded on the device (`CIRAWFilter` for DNGs, `CIImage`
otherwise) and measured. In each `<lens>-report.json`, `captures.<file>.luminance` and
`previewFrame.luminance` have:

- `meanLuma`, `minLuma`, `maxLuma`: Rec. 709 luma of the sRGB-encoded image, 0 to 1;
- `looksBlack`: the mean is below 0.01;
- `looksFlat`: the whole image is within one 8-bit step, a constant fill.

The status list and `summary.json` say "done, but the image looks black or flat" for such a
file. For a lit scene, expect `looksBlack` and `looksFlat` to be `false` for the RAW, the HEIF
and the preview, a `meanLuma` well above 0.01 and a `maxLuma` above `minLuma`. The HEIF's EXIF
`ExposureTime` and `ISOSpeedRatings` should no longer be 0. Open `<lens>-preview.jpg` to see what
the camera saw. The thresholds are tool settings, not platform values.

### Black frames (first device runs)

**Symptom.** The first two runs (iPhone 16 Pro Max, iOS 27.2.1) gave black files on every lens:
the RAW DNGs and the 15 KB HEIFs, whose EXIF said `ExposureTime` 0 and ISO 0.

**What the files show.** In every DNG, all 16 tiles have the same byte count and the
lossless-JPEG data repeats a single byte value: a constant fill, not a sensor readout, which
would contain noise. Decoded, every file has a mean of exactly 0. Meanwhile the front camera's
auto exposure had settled on a lit scene (exposure target offset −0.03 EV at ISO 1607, 1/15 s),
so the camera saw light while the still pipeline delivered a blank buffer. This rules out
underexposure as the cause. (The rear cameras were at their highest ISO with an offset near
−5 EV, so they were also pointed at something dark.)

**Likely causes, from the code and Apple's documentation.** The capture setup departed from the
documented flow in these ways; which one is responsible can only be shown on a device:

1. **Zero shutter lag was on.** The report shows `isZeroShutterLagEnabled: true`: it is
   "automatically enabled when supported" for apps built for iOS 17 or later, takes the photo
   from a buffer of earlier frames, and is meant for `.balanced` and `.quality`
   (`AVCapturePhotoOutput.h`, `zeroShutterLagEnabled`;
   [documentation](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/iszeroshutterlagenabled)).
   nope. uses `.speed` and wants the frame exposed after the shutter, so it is now off.
2. **The output was never prepared for RAW.** "Some types of photo capture, such as bracketed
   captures and RAW captures, require the receiver to allocate additional buffers", and by
   default only default settings are prepared (`setPreparedPhotoSettingsArray(_:completionHandler:)`,
   [documentation](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/setpreparedphotosettingsarray(_:completionhandler:))).
3. **Captures weren't gated on readiness.** Apple's `captureReadiness` says when the output can
   take a request in a timely manner
   ([documentation](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/capturereadiness)).
   WebKit reported the first `AVCapturePhotoOutput` photo "often all black" and fixed it with
   `AVCapturePhotoOutputReadinessCoordinator`
   ([WebKit bug 313854](https://bugs.webkit.org/show_bug.cgi?id=313854)).
4. **`maxPhotoDimensions` was implicit** (0 × 0 in the requested settings), and the RAW and
   processed settings named no file type.
5. **Pipeline switches were set in the same configuration as the input.** The header asks for
   switches that reconfigure the pipeline (zero shutter lag, responsive capture,
   `maxPhotoDimensions`) to be set before `startRunning()`.

**Fix.** Both the app's backend (`SystemCaptureHardware`) and the tag check now: commit the
preset, input and outputs first; then commit every output switch, with zero shutter lag and
responsive capture off and an explicit `maxPhotoDimensions`; start the session; prepare the
photo settings; and wait for `.ready` before each capture, with RAW-only DNG and HEIC settings
that name their file types. The tag check also attaches a live preview layer, as the app does.
The luminance check above proves the result on the next device run.

### Black frames: third run and status (open)

**Third run.** With the fix above, a third run (iPhone 16 Pro Max, iOS 27.2.1, launched with
`xcrun devicectl device process launch ... -NopeTagCheck`) was still black on every lens and
every output: the Bayer DNGs (a constant fill), the 15 KB `.speed` HEIFs (no `ExposureTime`,
`FNumber` or `ISOSpeedRatings` in `{Exif}` at all), and the live video data output frame
(1760 × 1320, maximum luma exactly 0). At the same time the device reported the session
running, 29 frames delivered, auto exposure settled (1/60 s, ISO 134, target offset −0.06 EV),
`captureReadiness` `.ready`, zero shutter lag and responsive capture off, and the RAW buffers
prepared. Because the video frames are zero too, the cause is upstream of the photo output,
so none of the photo-output settings above explain it.

**Normal launch works.** When the maintainer opened nope. from the Home Screen (no launch
argument, not launched by `devicectl`), the camera screen showed a correct live viewfinder on
the 1× lens with the RAW badge, and a capture completed. Every black run so far was launched
by `devicectl` with `-NopeTagCheck`. Two differences remain, and only a device run can tell
them apart:

1. **(a) The launch.** A `devicectl` launch versus a launch the user starts from the Home
   Screen. This is an assumption to test; no Apple documentation found so far says that a
   remotely launched app receives blank camera frames.
2. **(b) The tag check's pipeline.** The tag check adds an `AVCaptureVideoDataOutput` and
   configures each physical camera itself; the camera screen uses `SystemCaptureHardware` with
   only a preview layer and a photo output.

**Tools for the next run (Debug builds only).**

- `-NopeCameraProbe` runs the simplest pipeline from Apple's sample flow
  ([Setting up a capture session](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session),
  [AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)):
  the `.photo` preset, `AVCaptureDevice.default(for: .video)`, a full-screen preview layer, a
  video data output and one default HEVC photo. It writes `probe-report.json`,
  `probe-frame.jpg` and `probe-photo.heic` to `Documents/TagCheck/`, with the app and scene
  activation state, the authorization status, `isInterrupted` and every interruption or
  runtime-error notification (with its reason), `isSuspended`, multitasking camera access,
  the exposure state, the photo's `{Exif}` and the decoded luminance of the frame and photo.
  `-NopeProbeNoVideoOutput` leaves out the video data output, as the camera screen does.
- `-NopeArmDebugRun tagcheck` (or `probe`) only stores the run and shows a message. The next
  launch from the Home Screen performs it once and clears it, so a run started by the user
  can be compared with one started by `devicectl`.

**Next device test, in order.** Copy `Documents/TagCheck/` after each step.

1. `devicectl ... launch --terminate-existing com.photivra.nope.dev -NopeCameraProbe`.
2. The same with `-NopeCameraProbe -NopeProbeNoVideoOutput`.
3. `devicectl ... launch --terminate-existing com.photivra.nope.dev -NopeArmDebugRun probe`,
   then swipe the app away and open nope. from the Home Screen.
4. The same as step 3 with `tagcheck`.

If steps 1 and 2 are black and step 3 is exposed, the cause is the `devicectl` launch (a). If
step 3 is exposed and step 4 is black, the cause is in the tag check's pipeline (b), and the
probe is bisected toward the tag check one change at a time.

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
