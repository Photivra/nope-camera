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

`audit(_:)` in `NopeAppUITests.swift` runs every audit with these documented exceptions; every
other finding fails the test:

- an element cut by the window's edge (a form row below the fold), and a contrast finding with
  no element, which comes from such a row: the audit measures the clipped edge;
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
  and element-less clipped-text findings on iPad (they run both on iPhone);
  three more iPad contrast findings with no visible cause (white text on near-black: the manual
  dial over a white or yellow picture, and the format chip and the failure banner in the scrolling
  layout at the largest text size) are skipped on iPad in `testControlsOverWhiteAndYellowFrames`,
  `testLargestTextSize` and `testBlankPictureAtTheLargestTextSize`, which run every check on
  iPhone;
- `testSpaceTakesAPhoto` is skipped on iPad, an open finding: on the iPad Simulator the Space
  bar reached the focused button instead of the Camera menu's command, and no photo was taken; it
  passes on iPhone. The device check below covers a hardware keyboard on iPad;
- on an iPhone held sideways, clipped-text and contrast findings on SwiftUI nodes the audit
  can't tie to an element: it measures turned text in its unturned frame. The same views pass
  every check in portrait; the turned layout is on the manual accessibility pass below.

The Simulator has no camera, so `NopeAppUITests` launches Debug builds with
`-NopeSimulatedCamera <scenario>` (`App/NopeApp/DebugTools/SimulatedCameraLaunch.swift`), which
swaps in `SimulatedCaptureBackend` and simulated save steps (`SimulatedSaving.swift`; nothing
touches the Simulator's photo library). Release builds ignore the argument. The scenarios and what
each test checks, with `performAccessibilityAudit()` in every state:

| Scenario | Test |
|---|---|
| `allow` | First-run screen (three statements, Continue); camera ready with the format chip ("single-frame RAW, RAW + HEIF") and the wide lens selected; no thumbnail before the first photo; the shutter gives the last-photo slot "Saved and signed." (a simulated signer stands in for the real one, which `NopeSigningTests` cover); the telephoto (no RAW) turns the chip into its warning; full auto shows only the default controls; the camera flip; the format chip's sheet; the quick-controls tray (closes on the shutter and on ⋯); signing off in Settings shows the "Not Signed" chip, also in clean view; landscape on iPhone (layout fixed, Settings rotates) and iPad (column); the first run at the largest text size and right-to-left |
| `allow`, `signingFails`, `noRAW` | The last photo (issues #36, #53): after a save the thumbnail is a button named "Last Photo" with a simulated picture; its long-press menu offers Open in Photos and Photo Details; "What's in This Photo" lists the files, signature (signed, or "Not signed" with the reason), processing (the fallback's "processed by the phone's camera"), the details left out with "Off in Settings", and the timings, at the default and largest text sizes and right-to-left; tapping the thumbnail brings the Photos app to the front; with `manual` and a bracket, the details' Photo picker shows each frame |
| `noRAW` | A device without RAW (wide and front, no Bayer RAW): the fallback chip and the HEIF fallback in the viewfinder description, portrait and landscape, default and largest text sizes; Space takes a photo |
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
| `allow`, `denied` | Settings from the camera's Settings button: Settings, Formats, Look, Choose Details (top and bottom), Accessibility, Honesty (top and bottom), About and the license text, each audited at the default size, at the largest accessibility text size and in right-to-left layout; the format rule (the last format can't be turned off), the Look row (shown only with HEIF or JPEG selected) and the privacy rules (master switch and signing on by default, one item on makes it "Custom", locked items read "Locked") |

UI test launches store settings in their own `UserDefaults` suite, emptied at each launch
(`SimulatedCameraLaunch.settingsStore()`), so every test starts from the defaults and the real
settings are never touched.
| `manual` (with `-NopeSettings.showsManualControls YES`) | Manual controls: hidden without the option; the M pill; the readout row; a dial with the lens's range, Auto, − and +; "All Auto" from the row's last button; exposure compensation blocked in M; the ultra wide's fixed aperture; Pro Tools and a 3-frame bracket; the lock pill after AE-L, which unlocks; the M pill turns manual controls off; interval progress and Stop; clean view from the tray; the list at the largest text size; right-to-left |
| `allow` (clean view) | The no-RAW chip stays visible in clean view |
| `allow` (light and flash) | The Light switch turns the light on with its pill ("25%"), which stays through a photo and in clean view, changes the brightness and turns the light off; the Flash menu and its pill; the light hides the flash pill; no Light or Flash on the ultra wide |
| `lightUnavailable` | The system refuses the light: the "Light Unavailable" warning, cleared by turning Light off |
| `allow`, `signingFails`, `photosDenied` with `-NopeSettings.isNightModeOn YES` | Night mode from the tray and at launch: the camera with a photo, a warning and the light, at the largest text size, and every Settings screen (default, largest, right-to-left); a screenshot check finds no white, green or blue pixel outside the viewfinder and the status bar; the viewfinder stays white (natural) by default and turns red with Red Viewfinder |

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
| `ui-tests` | App build and the UI tests with accessibility audits on the iPhone 18 Pro Simulator |
| `ui-tests-ipad` | The same UI tests on the iPad Air 11-inch (M4) Simulator, in a separate job, except `testSourceCodeIsAnHTTPSLink`: on iPad the About screen's source link isn't found in the Settings popover, an open finding |
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
  a photo and the last-photo slot appears with a teal seal; a lens
  without Bayer RAW turns the format chip amber; a phone call or another camera app shows the interruption message, and
  the camera comes back afterwards; and the tag check (below) shows exposed frames;
- saving (`PhotoKitLibrary`, `SystemCaptureHardware`, `CoreImageRAWRenderer`): the add-only
  prompt appears once and declining it shows the "isn't allowed to add photos" banner, whose
  Open Settings opens nope.'s page in the Settings app; a RAW
  plus HEIF appears as one photo in Photos with the RAW as the original; every saved file passes
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
  file sizes, and the tag list; with signing on, c2patool shows the same claim generator and
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
  multitasking pause; a hardware keyboard's Space bar takes a photo;
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
  series ends, is stopped, or nope. goes to the background, and after the camera screen closes.

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

### Flash, light and night mode on a device

- the Light and Flash controls appear on each rear lens that has them and never on the front
  camera; record which lenses report a torch and which flash modes on each test device;
- light on at 10%, 25% and 100%: it stays on, without blinking, through framing, focusing,
  single RAW (DNG) photos, RAW + HEIF, a bracket and an interval series, and the photos are
  lit by it; a Bayer RAW photo with Flash On and Auto fires the flash, is saved and passes the
  read-back (`docs/PRIVACY.md`, "Device checks"); does Flash On keep a locked focus (capability
  survey, question 6)?
- the light turns off when nope. goes to the background, on a phone call or another camera
  app, on a lens without a light, and at a critical heat level; warm the device and check the
  "Light Unavailable" warning and that a lower level can be chosen;
- night mode at night: no white or blue element in nope.'s own screens (camera, tray, pills,
  manual controls, Pro Tools, the format sheet, Settings and every detail screen, warning
  popovers); list what the system still draws (status bar, menus, alerts); nope. never changes
  the screen's brightness; the real viewfinder keeps its colors by default and is red with Red
  Viewfinder; energy with the red viewfinder on (Instruments).

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
  the torch show when another feature turns them on.

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
- exposure compensation in full auto: the tray's Exposure dial brightens and darkens the
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
