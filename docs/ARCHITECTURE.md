# Architecture

Photivra Nope Camera is split into a replaceable interface and interface-free logic. The rules are
in [`AGENTS.md`](../AGENTS.md), "Architecture: interface separate from logic"; this page describes
how the code follows them. Status: in development. The camera captures, each photo's metadata is
built from the allowlist and checked by reading the file back, and clean photos are saved to Photos,
signed with Content Credentials when signing is on.

## Repository layout

| Path | What it is |
|---|---|
| `Package.swift` | The `NopeKit` Swift package: every module and its tests |
| `Sources/<Module>/` | One folder per module, each with a DocC catalog (`<Module>.docc`) |
| `Tests/<Module>Tests/` | Swift Testing unit tests for each module |
| `App/NopeCamera.xcodeproj` | The app project: the `NopeApp` target and the `NopeAppUITests` UI tests |
| `App/NopeApp/` | App sources, `InfoPlist.xcstrings` and `PrivacyInfo.xcprivacy`; `Intents/` holds the Siri and Shortcuts App Intents and `AppShortcuts.xcstrings` |
| `App/NopeCaptureExtension/` | The Lock Screen camera (LockedCameraCapture capture extension), with its own privacy manifest |
| `App/NopeControls/` | The "Open nope." and Night Mode controls (WidgetKit control extension), with its own privacy manifest; its entitlements are `App/NopeControls.entitlements` |
| `App/Shared/` | Code and strings in the app and both extensions: `OpenCameraIntent`, `SharedSettings` (the App Group store and change signal) and `Localizable.xcstrings` |
| `Config/Base.xcconfig` | Shared build settings; includes the untracked `Config/Local.xcconfig` |
| `docs/api/` | The API exported as Markdown from the DocC comments (generated) |

## Modules

| Module | Holds | May import |
|---|---|---|
| `NopeCore` | `CameraModel` (the state machine), `CameraState`, `SessionStatus`, `CaptureStatus`, `CameraIntent`, `DeviceCapabilities`, `Lens`, `CaptureFormat` (RAW or the labeled fallback), `CapturedPhoto`, `CaptureEvent`, the `CaptureBackend` and `CameraPreviewSource` protocols, `SimulatedCaptureBackend`; the settings (`SaveSettings`, `MetadataSettings`); the metadata allowlist (`MetadataPlan`, `MetadataField`, `MetadataAllowlist`), the project's own tag reader (`MetadataFileReader`: TIFF/DNG, JPEG, HEIF, XMP) and `MetadataVerifier`; the save pipeline `PhotoSaver` and its protocols (`PhotoDeveloping`, `PhotoSigning`, `MetadataReading`, `PhotoLibrary`), and the manual controls: `ManualControlsModel`, `ManualControlIntent`, `ManualCapabilities`, `ControlScale`, `ManualSettings`, `DeviceControls` and the `ManualCaptureBackend` protocol, the full-auto aids (`AutoControlIntent`, `FastShutter`, `FocusTarget`, `FramePoint`, `AssistSettings`, and the internal `AutoShutter` and `CloseUpDetector` rules), and the settings model `NopeSettings` (which stores `SaveSettings`) with `LockedMetadataItem`; the drive modes (`DriveModel`, `DriveMode`, `DriveIntent`, the self-timer `Countdown`, bursts), the astro helper (`AstroModel`, `AstroIntent`, `AstroExposure`, `AstroEstimate`), the Siri and Shortcuts requests (`ShortcutInbox`, `ShortcutRequest`, `PhotoShortcut`, `ShortcutOutcome`, `CameraUnavailability`), the storage and battery warnings (`DeviceStatus`, `DeviceStatusReading`, `PhotoSizeEstimate`) and `SeriesScreenKeeper` with the `ScreenControlling` protocol | Foundation |
| `NopeCapture` | AVFoundation and PhotoKit adapters: `AVFoundationCaptureBackend` (writes each file with allowlisted metadata), `PhotoKitLibrary` (add-only saving) and the camera permission adapter | `NopeCore`, AVFoundation, Photos |
| `NopeDevelop` | RAW development and encoding: `RAWDeveloper` (Core Image, system encoders, `EncodingSettings`) and `ImageIOReadBack` | `NopeCore`, Core Image, ImageIO |
| `NopeSigning` | C2PA signing. Now: `ContentCredentialsSigner` (implements `PhotoSigning`), a new Secure Enclave key and self-issued certificate for every file, fully offline | `NopeCore`, CryptoKit, Security, C2PA, X509 and SwiftASN1 (swift-certificates, for the certificate) |
| `NopeUI` | SwiftUI views. Now: `CameraScreen` (the clean layout of issue #68: format chip, state pills, warning chips, viewfinder, lens row with the quick-controls tray, manual readout and dial, shutter, camera flip, last-photo slot, failure banner, first-run screen) and `SettingsScreen` (Photos, Privacy, Camera, More: Accessibility, Honesty, About and licenses) | `NopeCore`, SwiftUI |
| App (`NopeApp`) | Wires `AVFoundationCaptureBackend` and a `PhotoSaver` (`RAWDeveloper`, `ImageIOReadBack`, `PhotoKitLibrary`, `ContentCredentialsSigner`) into `NopeCore`, supplies the preview view and the hardware shutter, hosts `NopeUI`, and holds the App Intents | Everything |
| Extensions (`NopeCaptureExtension`, `NopeControls`) | The Lock Screen camera, wired like the app; the "Open nope." control | Everything; the controls use only `NopeCore` (for `NopeSettings`), AppIntents, WidgetKit and SwiftUI |

`scripts/check-architecture.sh` enforces the import column on every pull request.

## Data flow

```
 NopeUI (or any interface)
   │  reads CameraModel.state         ▲
   │  sends CameraIntent              │ state changes (Observation)
   ▼                                  │
 NopeCore: CameraModel ───────────────┘
   │  asks for facts through CaptureBackend
   ▼
 NopeCapture (AVFoundation)  or  SimulatedCaptureBackend (tests, development builds)
```

1. The interface appears, sends `CameraIntent.start`, and runs `CameraModel.observeEvents()`.
2. `CameraModel` asks its `CaptureBackend` for the current permission. Not determined leads to
   `CameraState.needsPermission`; denied or restricted leads to `.permissionDenied`.
3. When access is allowed, the model asks for `DeviceCapabilities`. No lenses leads to
   `.unavailable`; otherwise `.ready(capabilities)`, with the rear wide lens selected.
4. The model chooses the `CaptureFormat` for the lens (Bayer RAW, or the processed fallback when
   the lens has none) and asks the backend to start with a `CaptureRequest`. `sessionStatus`
   goes from `.starting` to `.running`.
5. `.selectLens` reconfigures the backend for another lens. `.capture` builds a `MetadataPlan`
   from `saveSettings` and asks the backend for one photo, whose file is written with that
   plan's metadata. `PhotoSaver` then develops, reads back, signs (when a signer exists), reads
   back again, checks and saves it (below). The result is `captureStatus = .saved(photo)` or
   `.failed(error)`.
6. Backend events (`CaptureEvent`) update `sessionStatus`: interruptions (calls, other apps,
   multitasking), critical heat (the model stops the camera and restarts it when the device
   cools), and runtime errors (the model restarts the camera).
7. The interface renders the new state. It holds no rules of its own.

### The AVFoundation backend

```
 AVFoundationCaptureBackend (actor, tested with fakes)
   ├─ LensCatalog: physical cameras only, first Bayer RAW format, labels, order
   ├─ CapturePolicy: ProcessingSwitches (.speed, no ProRAW, no zero shutter lag, no deferred
   │                 delivery, constant color or distortion correction, zoom 1.0) and photo plans
   └─ CaptureHardware protocol
        └─ SystemCaptureHardware (AVCaptureSession on a serial queue; device-only, excluded
           from the coverage gate): applies the plan, prepares the output, waits for
           captureReadiness, captures, and reports interruptions and thermal state
```

### Manual controls

Manual controls are off by default. The "Manual controls" option is
`NopeSettings.showsManualControls`; the app target sends `.manual(.setEnabled(_:))` when it
changes. "Start in clean view" (`NopeSettings.startsInCleanView`) sends `.setCleanView(_:)`
when the camera opens and when the option changes.

```
 NopeUI ── .manual(ManualControlIntent) ──▶ CameraModel.manual (ManualControlsModel)
                                              │ rules: availability, scales, P/S/I/M,
                                              │ locks, bracket plan, interval timer
                                              ▼
                                   DeviceControls(settings:lens:)  (checked against the lens)
                                              │
 ManualCaptureBackend.applyControls ◀─────────┘      exposureReadings ──▶ ManualControlsModel.reading
   └─ SystemCaptureHardware: lockForConfiguration, setExposureModeCustom (iOS 27 priority
      constants where the format supports them), setFocusModeLocked(lensPosition:),
      setWhiteBalanceModeLocked(with:), exposureRectOfInterest (iOS 26), each value limited
      again to the active format
```

- **Capabilities are data.** `SystemCaptureHardware` copies each camera's answers
  (`isExposureModeSupported`, `supportsExposureModeCustom(lensAperture:duration:iso:)`,
  `isLockingFocusWithCustomLensPositionSupported`, `isLockingWhiteBalanceWithCustomDeviceGainsSupported`,
  `isExposureRectOfInterestSupported`, the bias range) into `ManualControlSupport`, which
  `LensCatalog` turns into `Lens.manualControls`. The interface shows only what the lens offers.
- **Starting the camera resets its controls** to continuous auto, so `CameraModel` asks
  `ManualControlsModel` to apply its settings again after every start and lens switch.
- **Readings** (exposure offset, ISO, shutter, focus position, aperture, white balance, whether
  autofocus is searching) come from key-value observation of the camera, at most four a second,
  while the camera runs: full auto's fast shutter rule and the close-up hint read them too. They
  are shown only while manual controls are on. No video data output is added for them; the meter
  is the camera's own exposure offset. The live camera readout is built from the same
  observations (below, "Viewfinder overlays").

### Full-auto aids (issues #35, #41, #51, #56)

```
 NopeUI ── .auto(AutoControlIntent) ──▶ CameraModel ── viewfinder point ──▶ CameraPreviewSource
                                            │            .devicePoint(forViewfinderPoint:)
                                            ▼            (captureDevicePointConverted)
                                  ManualControlsModel: focusTarget, nearFocusLimit,
                                  fastShutter, AutoShutter limit, hints
                                            ▼
                          DeviceControls(settings:lens:assist:)  (aids only where still automatic)
                                            ▼
 SystemCaptureHardware: focus/exposurePointOfInterest, .autoFocus/.autoExpose for a lock,
 isSubjectAreaChangeMonitoringEnabled, autoFocusRangeRestriction, activeMaxExposureDuration
```

- **Tap to focus** aims autofocus and auto exposure at the tapped point and follows it until
  `AVCaptureDevice.subjectAreaDidChangeNotification` (`CaptureEvent.subjectAreaChanged`), then
  returns to continuous auto at the center. A lock adjusts once and then locks (`.autoFocus` and
  `.autoExpose`), and stays until it is unlocked, another point is tapped, the lens changes or
  All Auto. With manual controls on, the point aims only what is still automatic.
- **Fast shutter (full auto only)** sets `activeMaxExposureDuration` so the camera's own auto
  exposure raises ISO instead of slowing the shutter: no slower than the `FastShutter` choice or
  1/(2 × the 35 mm-equivalent focal length, computed from the field of view). When even the
  handheld limit can't expose the scene at the lens's highest ISO (`ISO × time × 2^(−offset)`
  from the readings), the limit is lifted and the screen says "Hold it steady or use a tripod."
  With manual controls on nothing is limited; the hint shows when the shutter is slower than the
  handheld rule.
- **Close-Up** sets `autoFocusRangeRestriction = .near`. The **close-up hint** suggests the ultra
  wide lens when the lens stays at its nearest position while autofocus searches; the app never
  switches lenses itself. The **magnifier** scales the preview view only.
- **Focus peaking** is part of the live frame analysis (below, "Viewfinder overlays").
- **Bracketing** uses `AVCapturePhotoBracketSettings` with
  `AVCaptureManualExposureBracketedStillImageSettings`; each frame is a separate single-frame
  photo, and each is saved through the same pipeline as a single photo
  (`CaptureStatus.savedBracket`). Bayer RAW rules still apply: `.speed`, zoom 1.0, no
  multi-frame processing.
- **Interval shooting** calls the same capture path as the shutter; its timer exists only while a
  series runs, and the camera screen stops it when it disappears. While a series runs in the
  foreground, `SeriesScreenKeeper` turns the idle timer off and dims the screen; it puts both
  back when the series ends or stops, the camera screen goes away, or the app goes to the
  background (issue #48). The app supplies the UIKit screen (`SystemScreen`).

### Drive modes: single, self-timer, burst

`CameraIntent.capture` is what every shutter sends (the on-screen shutter, the volume buttons,
the Camera Control, the Space bar); `CameraModel` applies `drive.mode`. Single takes one photo;
a timer mode starts `drive.countdown` (`Countdown`, 3 or 10 seconds), which takes one photo at
zero; burst takes frames until it is stopped. While a countdown or burst runs, the same intent
stops it (`canPressShutter`). `.drive(.startTimer(seconds:))` starts a countdown of any length,
for Siri and Shortcuts (issue #62). The app maps the hardware buttons' capture event phases to
`.drive(.hardwareButton(_:))`: a photo on release, as the system Camera app does, or in burst
mode a burst while the button is held.

A burst is single frames through `capturePhoto`, each saved through the same `PhotoSaver` as any
photo (allowlist, read-back, a signature per file); nothing is merged. Each frame is saved while
the next one is taken, so at most two frames are in memory. The burst stops when asked, at
`DriveModel.maximumBurstFrames`, when the next frame wouldn't fit in storage, when the camera
stops, or at the first frame that can't be taken or saved; frames already taken are still
saved. It ends as `CaptureStatus.savedBurst` (or `.failed`) and `drive.lastBurst`.

### Astro helper (issue #60)

`CameraModel.astro` (`AstroModel`) receives `CameraIntent.astro(AstroIntent)`. It never stacks
or processes anything: it sets up the camera and takes a run of single Bayer RAW frames with the
burst's loop (`takeFrames(limit:tracker:stopsOnLowBattery:)`, the same save pipeline per frame).
Turning it on (only on a lens where `AstroModel.startingExposure(for:)` has values: Bayer RAW,
manual exposure with shutter and ISO ranges, manual focus) turns manual controls on if needed,
sets focus to lens position 1, the longest shutter and the highest ISO the lens reports, turns
the light off, returns the drive mode to single and turns bracketing off; after that the manual
controls are the person's. While it is on, the shutter starts `drive.countdown` with
`astro.startDelay` and then `astro.frameCount` frames; the same shutter (or `.astro(.stop)`)
stops them. A run also stops before a frame that wouldn't fit in storage, at or below
`AstroModel.stopBatteryLevel` unplugged (`BurstEnd.batteryLow`), when the camera stops, or at a
failed frame. `CameraModel.astroEstimate` gives the total exposure time and an upper estimate of
the storage. Turning it off turns manual controls off again only if it turned them on. The torch
can't be turned on while it is on, and a lens it can't use turns it off. It is offered only
where `DeviceStatus.canRead` (`CameraModel.canUseAstro`): the Lock Screen capture extension has
no storage and battery reader, so it has no Astro. `NopeUI` turns night
mode on with it (`NopeSettings.setNightMode(_:)`), shows an Astro tray item, pill and panel and
an Astro Settings sheet, and keeps the screen awake and dimmed while frames run
(`SeriesScreenKeeper`).

### Storage and battery

`CameraModel.deviceStatus` (`DeviceStatus`) reads the free storage and the battery through
`DeviceStatusReading`, implemented in the app with `volumeAvailableCapacityForImportantUsageKey`,
`UIDevice` battery monitoring and `ProcessInfo.isLowPowerModeEnabled`
(`SystemDeviceStatusReader`). Nothing polls: the model reads it when the camera starts, before
each photo, after each save and before each burst frame, and the app reads it again on the
system's battery and power state notifications. `CameraModel.storageWarning` compares the free
space with `PhotoSizeEstimate` for the selected lens and formats; `DeviceStatus.batteryWarning`
applies at 20% unplugged. `NopeUI` shows them as `CameraWarnings` chips and announces them.

### Flash and light (issue #38)

`CameraModel.light` (`LightModel`) holds the flash mode and the torch, and receives
`CameraIntent.light(LightIntent)`. The flash is per photo: the model puts
`LightModel.flashModeForCapture` into `CaptureRequest.flashMode` (off when the lens has no flash
or the torch is on), and `AVFoundationCaptureBackend` applies it to that photo's settings only
(`CapturePolicy.photoSettings(_:flashMode:)`), so the session's configuration and prepared
settings never depend on it. Brackets never use it (`AVCapturePhotoBracketSettings` doesn't
support it). The torch goes through `LightCaptureBackend.setTorch(level:)`, which
`SystemCaptureHardware` implements with `setTorchModeOn(level:)`; it turns the torch off before
a camera leaves the session and reports `CaptureEvent.torchUnavailable` when `isTorchAvailable`
turns false. The model turns it off on interruptions, heat pauses and lenses without a torch,
re-applies it after a restart of a lens with one, and `CameraScreen` turns it off when the scene
goes to the background. `Lens.flashModes` (from `supportedFlashModes` with the camera attached;
none for the front camera) and `Lens.hasTorch` are capabilities as data. The remembered flash
mode and brightness are `NopeSettings.flashMode` and `torchLevel`, passed in by the app target.

### Night mode (issue #61)

`NopeSettings.isNightModeOn` (and `setNightMode(_:)`, for features such as the Astro helper) and
`tintsViewfinderInNightMode`. `NopeUI` applies `NightModeStyle` at the root of the camera screen
and of each sheet: every text style is drawn white, then everything is multiplied by pure red,
so white becomes red (5.25:1 on black), grays darker reds and black stays black; `CameraColor`
turns teal and amber white first, so they don't vanish. To keep the viewfinder in natural
colors, the ready camera leaves its frame clear and reports it (`ViewfinderFrame`), and
`CameraScreen` draws the viewfinder there, behind the red interface, in every mode; Red
Viewfinder multiplies only that view by red. The viewfinder is never moved or rebuilt when night
mode or Red Viewfinder changes: on a device a new viewfinder is a new
`AVCaptureVideoPreviewLayer`, which attaches to the running capture session on the main thread,
and switching night mode froze the camera in 0.2.0 (`NightModeViewfinderTests`). The focus
magnifier is the same `focusMagnified(_:)` modifier on both: on the picture and focus peaking in
the ready camera, and on the viewfinder in `CameraScreen`, so all three stay aligned. System menus, alerts, the
keyboard and the status bar are drawn by the system and keep its dark appearance.

### Siri, Shortcuts, Control Center and the Lock Screen (issues #42, #62)

The App Intents hold no rules (AGENTS.md, "Siri and Shortcuts"). `TakePhotoIntent` (a delay of
none, 3 or 10 seconds or a custom number up to 60, and an optional lens) opens the app, turns its
parameters into a `PhotoShortcut` and calls `ShortcutInbox.submit(_:)`, which waits for the
outcome. The camera screen runs `CameraModel.serveShortcuts(from:)` while it is shown: the model
waits for the camera to start (at most `ShortcutInbox.startTimeoutSeconds`, following its
observable state, without polling), switches the lens if asked, then takes one photo at once or
starts the self-timer with `.drive(.startTimer(seconds:))`, and reports a `ShortcutOutcome`:
saved and signed or not, or why not. Siri says it (`ShortcutDialog`); nothing about the photo's
content or metadata leaves the model. `SetNightModeIntent` calls `NopeSettings.setNightMode(_:)`
without opening the app. The app registers its `ShortcutInbox` and `NopeSettings` with
`AppDependencyManager`, and `NopeShortcuts` lists the Siri phrases.

`OpenCameraIntent` is a `CameraCaptureIntent`, compiled into the app, the capture extension and
the control extension (`App/Shared`), as Apple requires. The `NopeControls` extension offers it
as the "Open nope." control for Control Center, the Lock Screen and the Action button. On a
locked device the system opens `NopeCaptureExtension`, which runs the same `CameraModel` and
`PhotoSaver` as the app (RAW, the allowlist and read-back, a signature per photo, add-only
saving). It sees only its own container (not the App Group's), so it starts from the copy of the
person's settings in `OpenCameraIntent`'s app context (see "Shared settings" below), and offers no
button that opens another app; it has no location reader and no storage and battery warnings
(their system reader uses API that extensions can't use). It shares `CameraPreviewView.swift`
and `MotionGravitySource.swift` with the app through the project's file membership, with the
`NOPE_CAPTURE_EXTENSION` compilation condition leaving out the Debug UI-test scenarios.

### Shared settings: App Group, controls and the Lock Screen camera (issue #42)

The person's settings live in one place that every target of the app can read: the
`UserDefaults` of the App Group `$(NOPE_APP_GROUP_IDENTIFIER)` (`group.$(NOPE_BUNDLE_IDENTIFIER)`,
`Config/Base.xcconfig`). The app (`App/NopeApp.entitlements`) and `NopeControls`
(`App/NopeControls.entitlements`) request it; each reads the name from its Info.plist key
`NopeAppGroupIdentifier` (`App/NopeApp-Info.plist`, `App/NopeControls/Info.plist`).

```
 app: NopeSettings ──┐                               ┌── NopeControls: NightModeControl
                     ├──▶ App Group UserDefaults ◀───┤     (value provider, SetNightModeControlIntent)
 SharedSettingsSync ─┘                               │
        ▲ │ Darwin notification "<group>.settings-changed" (posted by the writer, heard by all)
        │ ▼
 app ── makeSnapshot() ──▶ OpenCameraIntent.updateAppContext ──▶ NopeCaptureExtension: apply(_:)
```

- **`NopeCore` API** (`SharedSettings.swift`, `NopeSettingsSnapshot.swift`):
  `SharedSettingsStore` (`groupIdentifier(infoDictionary:)`, `defaults(groupIdentifier:)`,
  `migrate(from:domainName:to:)`, `changeSignalName(groupIdentifier:)`, `isSettingsKey(_:)`);
  `SettingsChangeSignaling` and `DarwinSettingsChangeSignal`; `SharedSettingsSync`;
  `NopeSettings.reload()`, `makeSnapshot()` and `apply(_:)`; `NopeSettingsSnapshot`. The app-side
  glue for every target is `App/Shared/SharedSettings.swift` (`SharedSettings.store()`,
  `appStore()`, `changeSignal`, `publishToLockScreenCamera(_:)`) and `NopeControlKind`.
- **Moving old settings.** The app's first launch with the App Group copies every
  `NopeSettings.` key from its standard `UserDefaults` once (`migrate`), keeping any value a
  control already wrote. Extensions never migrate: their own stores are empty.
- **Changes between processes, without polling.** `SharedSettingsSync` posts the Darwin
  notification whenever this process writes the store (`UserDefaults.didChangeNotification`, which
  is posted only for this process's writes, before the setter returns), and calls
  `NopeSettings.reload()` when it hears one, assigning only the values that changed. The app also
  reloads when it returns to the foreground, for a notification sent while it was suspended. After
  a change the app refreshes the Night Mode control (`ControlCenter.reloadControls(ofKind:)`) and
  hands the settings to the Lock Screen camera.
- **The Night Mode control** (`NightModeControl`, a `ControlWidgetToggle`) reads
  `NopeSettings.isNightModeOn` from the App Group in its value provider and sets it with
  `SetNightModeControlIntent` (a `SetValueIntent`, hidden from Shortcuts), which then posts the
  signal and updates the Lock Screen camera's copy.
- **The Lock Screen camera can't open the App Group** (Apple: a capture extension "can't read from
  or write to the App Group's shared container"). The app writes a `NopeSettingsSnapshot` (a
  property list of every `NopeSettings.` key, well under Apple's 4 KB `appContext` limit, checked
  by a test) to `OpenCameraIntent.updateAppContext(_:)` at launch and after every change; the
  extension shows black until it has read and applied it, so it never starts in the wrong mode.
  Its changes last until it closes.
- **Later targets.** A Live Activity or widget extension joins the same App Group (an entitlement
  and the Info.plist key) and uses `SharedSettings.store()` and `changeSignal`. A Watch app can't
  share an App Group with the iPhone (each device has its own containers): on the watch, the Watch
  app and its own extensions can share a group the same way, and the iPhone would send a
  `NopeSettingsSnapshot` across with WatchConnectivity.

### The viewfinder

`NopeUI` may import only `NopeCore` and SwiftUI, and `NopeCapture` may not import UIKit, so the
preview crosses the layers as an opaque `CameraPreviewSource`. The AVFoundation backend's source
is a `CaptureSessionPreviewSource`; the app target's `Viewfinder` view turns it into an
`AVCaptureVideoPreviewLayer` and passes it to `CameraScreen(model:settings:viewfinder:)`. The app also
attaches `onCameraCaptureEvent` (AVKit), so the volume buttons and the Camera Control are the
shutter (enabled only while `CameraModel.handlesHardwareButtons`, so the buttons keep their
system behavior otherwise), and `CameraCommands`, so a hardware keyboard's Space bar is.

`CaptureSessionPreviewSource.connect(_:)` attaches the session to the app's preview layer and
keeps the preview and photos upright with `AVCaptureDevice.RotationCoordinator`
(`PreviewRotation`): the preview angle follows the interface, and the capture angle, applied to
the photo output's connection before each photo, follows gravity. The photo output records the
angle as the Exif orientation and doesn't rotate pixels (`AVCaptureSession.h`,
`videoRotationAngle`), so it becomes the Orientation tag, a locked metadata item.

### Viewfinder overlays

Guides and live aids drawn over the picture (issues #40, #47, #51 and #52), each off by default
and each its own switch in `NopeSettings.overlays` (`OverlayOptions`; Settings, "Viewfinder
Overlays"; Grid and Level are also in the quick-controls tray, and the live aids in Pro Tools).
Nothing they show is written to a photo, stored or logged, and nothing takes touches.

- **Grid** (`GridStyle`): rule of thirds, 4 × 4, a centered square, golden ratio lines or a
  golden spiral in one of eight placements (`SpiralPlacement`, "Turn Spiral" in Settings). The
  lines come from `GridGeometry` and `GoldenSpiral` in unit coordinates; `NopeUI` draws them as
  thin white lines on a dark outline. The spiral turns with an iPhone held sideways.
- **Level** (`LevelModel`, `LevelTracker`): a horizon bar, or a top-down level when the device
  points straight down, from gravity readings of a `GravitySource`. The app target supplies Core
  Motion device motion (`MotionGravitySource`, no permission needed) through
  `EnvironmentValues.cameraGravitySource`; updates run only while the level is shown. A haptic
  marks the moment it becomes level; VoiceOver reads the tilt as the level's value.
- **Live analysis** (`LiveViewModel`, `CameraModel.live`, `LiveViewBackend`): focus peaking and
  the histogram with clipping indicators. `SystemLiveView` adds an `AVCaptureVideoDataOutput`
  only while one of them is shown (`LiveAnalysisNeeds`: peaking whenever on; the histogram only
  with the manual controls and outside clean view). It delivers preview-sized frames with the
  `.photo` preset; at most four a second (two in Low Power Mode or at serious heat, none at
  critical heat, `LiveUpdateRate`) are sampled to about 160 × 120 cells (`LumaSampler`), turned to
  the viewfinder's orientation and analyzed (`Histogram`, `FocusPeakingMap`). The photo output
  and its settings are untouched. Peaking is drawn on the picture itself, so the focus magnifier
  enlarges it with the preview; the grid and level stay on the whole frame.
- **Live camera readout** ("stats for nerds"): the values AVFoundation reports
  (`CameraStatsReading`), built from the camera readings' own key-value observations (at most
  four a second) while the readout is shown; no second set of observations and no video. Hidden
  in clean view.

```
 NopeUI ViewfinderOverlays ── setNeeds / setShowsStats ──▶ CameraModel.live (LiveViewModel)
                                                             │
 LiveViewBackend.setFrameAnalysis / setStatsReadingsEnabled ◀┘   frameAnalyses, statsReadings ──▶ analysis, stats
   └─ SystemLiveView: video data output (only while needed) ─▶ LumaSampler ─▶ FrameAnalysis
                      camera readings' observations (while shown) ─▶ CameraStatsReading
```

### Camera layout

The camera screen follows the approved layout in [`design/ux-v3.html`](design/ux-v3.html)
(issue #68). `CameraLayout` chooses the arrangement from the space and the text size:

- **iPhone (stacked):** top bar (pills, format chip, Settings), the whole 4:3 picture, the lens
  row with the quick-controls button (⋯), the manual readout when manual controls are on, and the
  shutter row (last photo, shutter, camera flip). When the bands don't fit below the picture, as
  on a 4.7-inch iPhone, they overlay its bottom on a dark backing. The app target keeps the
  iPhone interface in portrait (`AppDelegate`, `application(_:supportedInterfaceOrientationsFor:)`)
  and tells `NopeUI` which way up the phone is (`EnvironmentValues.cameraUprightRotation`, from
  `UIDevice.orientation`); icons and text blocks turn upright as units (`UprightUnit`), and the
  chip, pills and warnings move to the picture's upper edge. While Settings or another sheet is
  open, the app lets the interface rotate (`EnvironmentValues.cameraPresentsSheet`).
- **iPad, or any window wider than tall (column):** the interface rotates; the picture sits
  beside a trailing column with the shutter centered, and Settings and the format details open as
  popovers. In a reduced window the camera shows the multitasking pause.
- **Accessibility text sizes (scrolling):** the iPhone bands in a scroll view.

Three registries let later features add to the camera without touching the layout:
`QuickControls.builders` (tray items: buttons, switches or native menus), `StatePills.builders`
(pills for settings not at their defaults, at most three then "+n") and
`CameraWarnings.builders` (persistent amber chips, such as "Not Signed"). Feedback has three
tiers: a good save is quiet (the last-photo slot with a teal seal, a light haptic and a
low-priority VoiceOver announcement); anything that changes what the photo is stays as an amber
chip; a failed capture or save is a banner that stays until dismissed or the next good save,
takes VoiceOver focus and offers one action (Try Again or Open Settings, through
`EnvironmentValues.openAppSettings`).

### From capture to Photos

```
 CameraModel.capture ── MetadataPlan(saveSettings.metadata) ──► CaptureRequest
   │
   ▼
 AVFoundationCaptureBackend / SystemCaptureHardware
   │  AVCapturePhoto.fileDataRepresentation(with: MetadataCustomizer)
   │    replacementMetadata(for:) = MetadataPlan.properties(for:from:)   (built from the allowlist)
   │  RAW only: the system's own DNG is flattened once to copy its RAW image data (reference)
   ▼
 PhotoSaver (NopeCore)
   1. files: the DNG, plus HEIF/JPEG from RAWDeveloper (NopeDevelop), as SaveSettings.formats
      say; a lens without RAW gives its processed fallback file
   2. read-back of every file: ImageIOReadBack = MetadataFileReader (every tag, block and XMP
      property) + ImageIO's keys; MetadataVerifier against MetadataPlan.allowlist(for:signed:);
      for the DNG, its RAW image data must equal the reference. Any violation: nothing is saved
   3. PhotoSigning (ContentCredentialsSigner, NopeSigning) when signing is on; each signed file
      is read back the same way, and one that fails is replaced by its unsigned file, with
      "not signed" and the reason in the status
   4. PhotoKitLibrary (NopeCapture): add-only access, one PHAssetCreationRequest per asset;
      the DNG as `.photo` (from memory) and its HEIF (or JPEG) as `.alternatePhoto` (from a
      file with complete protection, moved into Photos: PhotoKit rejects an alternate added
      from memory with error 3300)
   5. in memory, for the interface: SavedPhoto.thumbnail (PhotoThumbnailing: ImageIOThumbnailer,
      NopeDevelop) and SavedPhoto.details (PhotoDetails, built from each file's read-back, the
      plan, the signer's ContentCredentialsSummary and SaveTimings)
```

**Last photo and its details (issues #36, #53).** The read-back already holds every tag; the
TIFF reader also records each numeric tag's values (`MetadataInventory.Tag.values`, at most 16,
never for offset tags), and `ImageIOReadBack` reports ImageIO's pixel size and bit depth
(`ImageProperties`). `PhotoDetails` turns these into plain facts; it estimates nothing, so a
value the file doesn't hold is left out. `PhotoSaver` and `CameraModel` time each step with an
injected monotonic clock (`ContinuousClock`), so tests use a scripted one. The camera screen
shows the thumbnail in the last-photo slot: a tap opens Photos through
`EnvironmentValues.openPhotosApp` (or the details when that is `nil`), and its long-press menu
and accessibility actions offer Open in Photos and Photo Details.

**Why the DNG's metadata is written by AVFoundation.** ImageIO can't write DNG: on macOS 27 and
the iOS 27 Simulator, `CGImageDestinationCopyTypeIdentifiers()` doesn't list
`com.adobe.raw-image`, and `CGImageDestinationCreateWithData` returns `nil` for it (asserted by
`ImageIOReadBackTests.imageIOCantWriteDNG`; to be confirmed on a device), so `CGImageDestinationCopyImageSource`
(which `CGImageDestination.h` describes as a lossless copy that "will not modify" the image data)
isn't available for DNG. AVFoundation's own path is documented for this:
`AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata(for:)` in
`AVCapturePhotoOutput.h` returns "a dictionary of keys and values from
<ImageIO/CGImageProperties.h> … To replace metadata, pass a replacement dictionary." AVFoundation
then flattens the in-memory photo itself, so the app never re-encodes or touches the sensor data,
and never edits file bytes (AGENTS.md, "remove metadata through system APIs"). The read-back
proves the result: every tag of the saved DNG must be on the allowlist, and its RAW image data
(IFD0's tiles or strips) must equal the data of the system's own DNG. Whether AVFoundation adds
anything beyond the replacement dictionary is a device check (docs/TESTING.md).

**HEIF and JPEG** developed from the RAW are written with `CGImageDestinationAddImage` from a
rendered image that carries no metadata, with only the allowlisted property dictionary, and no
embedded thumbnail. ImageIO adds a few things that describe the image (resolution, color space,
for HEIF a mirrored XMP packet for dates, name and copyright, and for JPEG an empty IPTC record);
each is on the allowlist only where it holds nothing beyond what the switches allow
(docs/PRIVACY.md).

Photos go from memory to Photos (`addResource(with:data:options:)`) and never linger on disk.
The one exception is the alternate of a RAW pair, which PhotoKit accepts only from a file
(`PhotoKitMapping.Resource.addsFromFile`): `ResourceStaging` writes it with complete file
protection under a random name in the temporary directory, Photos moves it into the library
(`shouldMoveFile`), and anything left is deleted as soon as the change ends
(docs/TESTING.md, "RAW pairs not saved (PhotoKit error 3300)").

### Signing

`NopeCore` defines the signing hook, `PhotoSigning.sign(_:)`, which takes and returns a
`PhotoFile` (its format, bytes, and whether the phone's camera processed it). `PhotoSaver` builds
each file's metadata and reads the file back, then, when `MetadataSettings.signsPhotos` is on,
calls the signer, then reads the signed file back against `MetadataPlan.allowlist(for:signed:)`,
which permits the Content Credentials item of a signed file and nothing else, then saves it. If
signing fails, or the signed file fails the read-back, the unsigned file is saved and the status
says so. `NopeSigning` implements the hook:

```
 ContentCredentialsSigner (PhotoSigning)
   ├─ SigningKeyProvider: SecureEnclaveKeyProvider on a device (excluded from the coverage gate),
   │                      SimulatorSoftwareKeyProvider in the Simulator only
   ├─ SelfIssuedCertificate (swift-certificates): anonymous, non-CA, C2PA EKU, fixed validity
   ├─ ContentCredentialsManifest: one c2pa.created action, the app as claim generator
   ├─ OfflineC2PAContext: every fetch off, no network host
   ├─ DNGManifestSlot: a DNG's tag 52545 inserted into IFD0 in place, so iOS still opens it
   │                   as a DNG; signed with the library's data-hash workflow (issue #66)
   └─ InMemoryFile and InMemoryStream: the C2PA library reads and writes memory, never a file
```

The C2PA library is c2pa-rs built from source with every network feature off
(`c2pa-lib/README.md`), and its Swift wrapper is vendored without its networking code
(`Vendor/c2pa-swift`). Details and the exact contents are in [`PRIVACY.md`](PRIVACY.md),
"Content Credentials".

### Comparison shot (issue #55)

`CameraModel.comparison` (`ComparisonModel`) holds whether Compare is on (off at launch, not
remembered) and the compare view's content (`ComparisonModel.State`); its intents arrive as
`CameraIntent.comparison(ComparisonIntent)`. It is offered only with a
`ComparisonCaptureBackend` and a renderer for the pictures (`ComparisonModel.isAvailable`); the
Lock Screen capture extension sets no renderer, so it isn't offered on a locked device.

```
 shutter ──▶ CameraModel.capture()
               ├─ backend.capturePhoto(request)            the app's photo, exactly as without Compare
               ├─ ComparisonCaptureBackend.captureComparison(request)
               │     └─ second photo, .quality, system metadata kept   (PhoneProcessedPhoto)
               ├─ PhotoSaver.saveReturningFiles(photo)     only the app's files go to Photos
               └─ ComparisonModel.present(...)             pictures (renderer) + MetadataComparison
 Done ──▶ .comparison(.close)                              everything above is dropped
```

- **Only single and self-timer photos** are comparison shots (`CameraModel.comparisonAppliesToNextPhoto`):
  never a burst, a bracket or an interval series.
- **The app's photo is unchanged.** The session keeps `ProcessingSwitches.leastProcessing`; for the
  second photo only, `SystemCaptureHardware` raises the photo output's
  `maxPhotoQualityPrioritization` to `.quality` (a `.quality` photo needs it), then sets it back
  to `.speed` and prepares the session's RAW settings again before returning
  (`ComparisonHardware`, `CapturePolicy.comparisonPlan(for:)`, `ProcessingSwitches.phoneProcessing`).
- **The phone's version can't be saved.** It is a `PhoneProcessedPhoto`, not a `CapturedPhoto`,
  so it can't be handed to `PhotoSaver`; the unit tests assert that only the app's files reach the
  library. If the app's photo fails to save, the phone's version is dropped; if the second photo
  fails, the app's photo is still saved and the view says there is nothing to compare.
- **Pictures** are decoded off the main actor by `ComparisonModel.renderer` (the app passes
  `ImageIOThumbnailer` at 4032 pixels): the app's saved HEIF or JPEG, or the DNG when only RAW
  was saved, and the phone's file. **Metadata** (`MetadataComparison`) pairs the read-back of
  the app's shown file with the phone's file read by `MetadataFileReader`, grouped as only in the
  phone's version, different, only in the app's file and the same, each item linked to its privacy
  switch and marked when its value identifies the device or the photo.
- While the compare view is open, `canCapture` and `handlesHardwareButtons` are false. `NopeUI`
  shows it as a full-screen cover (`ComparisonScreen`): the pictures with a divider (a slider,
  VoiceOver adjustable action, nope. Only / Split / Phone Only buttons, pinch and zoom buttons),
  and a pushed Details list. It hides its contents while the scene isn't active, so the app
  switcher's snapshot doesn't show them. The Compare item is in the quick-controls tray, with a
  pill and the hint "Hold the camera steady or use a tripod. Two photos are taken, a moment apart."

## Settings

`NopeSettings` (in `NopeCore`, main actor, Observation) holds the person's choices:
`SaveSettings` (the formats, at least one, RAW and HEIF by default; `MetadataSettings`, with the
master switch "Remove all optional details", on by default, one switch per optional item, as in
[`PRIVACY.md`](PRIVACY.md), "Metadata plan", and signing, on by default; and the HEIF and JPEG
look, `DevelopedLook`, standard by default, or flat, which never changes the RAW), manual
controls (off) and clean view (off). Interfaces change it only through its methods, which hold the rules (the
last format can't be turned off; turning on one item turns the master switch off). Each change
is written at once to the app's own `UserDefaults` on the device: never iCloud, never the
network. The app target creates one `NopeSettings` and passes it to `CameraScreen`, whose
Settings button opens `SettingsScreen` (a sheet on iPhone, a popover on iPad) in every camera
state. Settings is a short grouped list: Photos (formats with the RAW pairing, look, file
options), Privacy (the master switch, "Choose Details", signing), Camera (manual controls, clean
view, front camera mirroring) and More (Accessibility, Honesty, About); explanations are in
footers and on the detail screens.

The app passes `NopeSettings.save` to `CameraModel.saveSettings` whenever it changes, so the
next photo uses it. For each capture, `CameraModel` adds two per-photo values to the metadata
plan: `MetadataPlan.mirrorsHorizontally` (a front camera photo with mirroring on) and
`MetadataPlan.location` (from `CameraModel.location`, a `LocationTagging`, while the Location
switch is on). `LocationTagging` holds the location rules (ask when the switch is turned on;
updates only while the camera runs) behind the `LocationProviding` protocol; the app target
implements it with Core Location (`CoreLocationProvider`) and starts or stops it from
`.task(id:)` as the switch and the session change. The name and copyright have no switch yet
(`MetadataItem.isOfferedInSettings`): text entry isn't built, so they stay off.

The Honesty screen and About are static: every Honesty statement comes from
[`research/privacy-claims.md`](research/privacy-claims.md), and About shows bundled copies of
`LICENSE` and `NOTICE` (a unit test keeps them identical) with the source address as a link.
Tapping it hands the `https` address to the system browser; the app makes no network request,
registers no URL scheme. The only system setting it opens is the app's own page in the Settings
app, when the person presses Open Settings after declining camera or photo library access.

## The simulated backend

Tests and previews use `SimulatedCaptureBackend`. Debug builds launched with
`-NopeSimulatedCamera <scenario>` use it too, so the UI tests can reach every state on the
Simulator (docs/TESTING.md). Release builds always use `AVFoundationCaptureBackend`.

## Appearance

The camera screen uses the dark appearance (`preferredColorScheme(.dark)`). The settings sheet
is presented from it and inherits the dark appearance for now; following the system appearance
in the sheet is a follow-up.

## Signing and secrets

Development builds use automatic signing with the bundle identifier `com.photivra.nope.dev`. The
development team is read from `Config/Local.xcconfig`, which git ignores; copy
`Config/Local.xcconfig.example` to create it. No team ID, certificate or profile is committed.
CI builds for the Simulator with `CODE_SIGNING_ALLOWED=NO`.
