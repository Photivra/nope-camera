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
| `NopeCore` | `CameraModel` (the state machine), `CameraState`, `SessionStatus`, `CaptureStatus`, `CameraIntent`, `DeviceCapabilities`, `Lens`, `CaptureFormat` (RAW or the labeled fallback), `CapturedPhoto`, `CaptureEvent`, the `CaptureBackend` and `CameraPreviewSource` protocols, and `SimulatedCaptureBackend` | Foundation |
| `NopeCapture` | AVFoundation and PhotoKit adapters. Now: `AVFoundationCaptureBackend` and the camera permission adapter | `NopeCore`, AVFoundation, Photos |
| `NopeDevelop` | RAW development and encoding. Now: `EncodingSettings` for HEIF and JPEG | `NopeCore`, Core Image, ImageIO |
| `NopeSigning` | C2PA signing. Now: `PerPhotoSigner`, which uses a fresh key for every photo | `NopeCore`, CryptoKit, C2PA |
| `NopeUI` | SwiftUI views. Now: `CameraScreen` (format badge, viewfinder, lens buttons, shutter, status; stacked or side by side) and `CameraCommands` (the Camera menu) | `NopeCore`, SwiftUI |
| App (`NopeApp`) | Wires `AVFoundationCaptureBackend` into `NopeCore`, supplies the preview view, the hardware shutter and the Camera menu, and hosts `NopeUI` | Everything |

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
           captureReadiness, captures, and reports interruptions and thermal state;
           PreviewRotation (device-only, excluded) keeps the preview and photos upright
```

### The viewfinder

`NopeUI` may import only `NopeCore` and SwiftUI, and `NopeCapture` may not import UIKit, so the
preview crosses the layers as an opaque `CameraPreviewSource`. The AVFoundation backend's source
is a `CaptureSessionPreviewSource`; the app target's `Viewfinder` view turns it into an
`AVCaptureVideoPreviewLayer` and passes it to `CameraScreen(model:viewfinder:)`. The app also
attaches `onCameraCaptureEvent` (AVKit), so the volume buttons and the Camera Control take a
photo, and adds `CameraCommands`, so Space on a hardware keyboard does too.

The app hands its layer to `CaptureSessionPreviewSource.connect(_:)`. That is the one rotation
hook: `PreviewRotation` in `NopeCapture` makes an `AVCaptureDevice.RotationCoordinator` (iOS 17)
for the camera in use and the layer, applies its preview angle to the layer's connection as the
device turns, and `SystemCaptureHardware` applies its capture angle to the photo output's
connection before each photo. The photo output records that angle as the photo's Orientation
tag and doesn't rotate pixels (`AVCaptureSession.h`, `videoRotationAngle`); Orientation is a
locked metadata item (docs/PRIVACY.md).

### Layout

`CameraLayout` (in `NopeUI`) picks the arrangement from the screen's shape alone, so it works on
iPhone and iPad, in every orientation and window size:

- **Stacked**, when the space is at least as tall as it is wide: top bar, format badge,
  viewfinder, status, controls, lens buttons and shutter, top to bottom.
- **Side by side**, when it is wider than tall: the viewfinder at full height with the format
  badge on its top edge (so the RAW or no-RAW statement never scrolls away), and everything else
  in a column on the trailing edge, at least 300 points wide (360 at accessibility text sizes)
  and at most 45% of the width. The lens buttons are two to a row at every text size. The
  shutter stays at the bottom of the column; the top bar, controls, status and lens buttons
  above it scroll when they don't fit, starting scrolled to the bottom.

The camera screen has two slots for more controls: `topBar` (first in the stack, or at the top
of the column) and `controls` (between the status and the lens buttons, or above the status in
the column's scrolling part). They are the `topBar:` and `controls:` closures where `CameraScreen` creates
`CameraReadyView`; an empty slot takes no space.

On iPad, Split View, Slide Over and Stage Manager interrupt the session
(`videoDeviceNotAvailableWithMultipleForegroundApps`), and the viewfinder says "The camera works
only when nope. fills the screen." nope. doesn't turn on multitasking camera access: Apple
documents it for video conferencing apps and apps with the
`com.apple.developer.avfoundation.multitasking-camera-access` entitlement (`AVCaptureSession.h`,
`multitaskingCameraAccessSupported`; "Accessing the camera while multitasking"), and the epic
adds it only if users ask (issue #1, "iPad").

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
