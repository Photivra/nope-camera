# Architecture

nope. is split into a replaceable interface and interface-free logic. The rules are in
[`AGENTS.md`](../AGENTS.md), "Architecture: interface separate from logic"; this page describes
how the code follows them. Status: capture core, in development. The camera runs and
captures in memory; nothing is saved yet.

## Repository layout

| Path | What it is |
|---|---|
| `Package.swift` | The `NopeKit` Swift package: every module and its tests |
| `Sources/<Module>/` | One folder per module, each with a DocC catalog (`<Module>.docc`) |
| `Tests/<Module>Tests/` | Swift Testing unit tests for each module |
| `App/NopeCamera.xcodeproj` | The app project: the `NopeApp` target and the `NopeAppUITests` UI tests |
| `App/NopeApp/` | App sources, `InfoPlist.xcstrings` and `PrivacyInfo.xcprivacy` |
| `Config/Base.xcconfig` | Shared build settings; includes the untracked `Config/Local.xcconfig` |
| `docs/api/` | The API exported as Markdown from the DocC comments (generated) |

## Modules

| Module | Holds | May import |
|---|---|---|
| `NopeCore` | `CameraModel` (the state machine), `CameraState`, `SessionStatus`, `CaptureStatus`, `CameraIntent`, `DeviceCapabilities`, `Lens`, `CaptureFormat` (RAW or the labeled fallback), `CapturedPhoto`, `CaptureEvent`, the `CaptureBackend` and `CameraPreviewSource` protocols, `SimulatedCaptureBackend`, and the manual controls: `ManualControlsModel`, `ManualControlIntent`, `ManualCapabilities`, `ControlScale`, `ManualSettings`, `DeviceControls` and the `ManualCaptureBackend` protocol | Foundation |
| `NopeCapture` | AVFoundation and PhotoKit adapters. Now: `AVFoundationCaptureBackend` and the camera permission adapter | `NopeCore`, AVFoundation, Photos |
| `NopeDevelop` | RAW development and encoding. Now: `EncodingSettings` for HEIF and JPEG | `NopeCore`, Core Image, ImageIO |
| `NopeSigning` | C2PA signing. Now: `PerPhotoSigner`, which uses a fresh key for every photo | `NopeCore`, CryptoKit, C2PA |
| `NopeUI` | SwiftUI views. Now: `CameraScreen` (format badge, viewfinder, lens buttons, shutter, status) | `NopeCore`, SwiftUI |
| App (`NopeApp`) | Wires `AVFoundationCaptureBackend` into `NopeCore`, supplies the preview view and the hardware shutter, and hosts `NopeUI` | Everything |

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
5. `.selectLens` reconfigures the backend for another lens. `.capture` asks the backend for one
   photo; the result is `captureStatus = .captured(photo)`, held in memory only.
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

Manual controls are off by default. The "Manual controls" option is stored in `UserDefaults`
under `ManualControlsSetting.userDefaultsKey`; the app target sends
`.manual(.setEnabled(_:))` when it changes.

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
- **Readings** (exposure offset, ISO, shutter, focus position, aperture, white balance) come from
  key-value observation of the camera, at most four a second, only while manual controls are on.
  No video data output is added, so there is no live histogram; the meter is the camera's own
  exposure offset.
- **Bracketing** uses `AVCapturePhotoBracketSettings` with
  `AVCaptureManualExposureBracketedStillImageSettings`; each frame is a separate single-frame
  photo (`CaptureStatus.capturedBracket`). Bayer RAW rules still apply: `.speed`, zoom 1.0, no
  multi-frame processing.
- **Interval shooting** calls the same capture path as the shutter; its timer exists only while a
  series runs, and the camera screen stops it when it disappears.

### The viewfinder

`NopeUI` may import only `NopeCore` and SwiftUI, and `NopeCapture` may not import UIKit, so the
preview crosses the layers as an opaque `CameraPreviewSource`. The AVFoundation backend's source
is a `CaptureSessionPreviewSource`; the app target's `Viewfinder` view turns it into an
`AVCaptureVideoPreviewLayer` and passes it to `CameraScreen(model:viewfinder:)`. The app also
attaches `onCameraCaptureEvent` (AVKit), so the volume buttons and the Camera Control take a
photo.

### From capture to Photos

Today a photo stops in memory: the app shows "Captured (not saved yet: development build)". The
next steps, in later pull requests (issue #1): build the file's metadata from the allowlist and
verify it by reading the file back, develop HEIF and JPEG from the same RAW (`NopeDevelop`),
sign each file with a fresh key (`NopeSigning`), and add it to Photos with add-only access
(`NopeCapture`). Photos go from memory to Photos and never linger on disk.

## The simulated backend

Tests and previews use `SimulatedCaptureBackend`. Debug builds launched with
`-NopeSimulatedCamera <scenario>` use it too, so the UI tests can reach every state on the
Simulator (docs/TESTING.md). Release builds always use `AVFoundationCaptureBackend`.

## Appearance

The camera screen uses the dark appearance (`preferredColorScheme(.dark)`). Settings and other
screens, when they exist, follow the system appearance; their UI tests will cover both.

## Signing and secrets

Development builds use automatic signing with the bundle identifier `com.photivra.nope.dev`. The
development team is read from `Config/Local.xcconfig`, which git ignores; copy
`Config/Local.xcconfig.example` to create it. No team ID, certificate or profile is committed.
CI builds for the Simulator with `CODE_SIGNING_ALLOWED=NO`.
