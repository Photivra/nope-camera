# Architecture

nope. is split into a replaceable interface and interface-free logic. The rules are in
[`AGENTS.md`](../AGENTS.md), "Architecture: interface separate from logic"; this page describes
how the code follows them. Status: scaffold (0.1.0). There is no live camera yet.

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
| `NopeCore` | `CameraModel` (the state machine), `CameraState`, `CameraIntent`, `DeviceCapabilities`, `Lens`, `CameraPermission`, `PhotoFormat`, the `CaptureBackend` protocol and `SimulatedCaptureBackend` | Foundation |
| `NopeCapture` | AVFoundation and PhotoKit adapters. Now: the camera permission adapter | `NopeCore`, AVFoundation, Photos |
| `NopeDevelop` | RAW development and encoding. Now: `EncodingSettings` for HEIF and JPEG | `NopeCore`, Core Image, ImageIO |
| `NopeSigning` | C2PA signing. Now: `PerPhotoSigner`, which uses a fresh key for every photo | `NopeCore`, CryptoKit, C2PA |
| `NopeUI` | SwiftUI views. Now: `CameraScreen` | `NopeCore`, SwiftUI |
| App (`NopeApp`) | Wires a backend into `NopeCore` and hosts `NopeUI` | Everything |

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

1. The interface appears and sends `CameraIntent.start`.
2. `CameraModel` asks its `CaptureBackend` for the current permission. Not determined leads to
   `CameraState.needsPermission`; denied or restricted leads to `.permissionDenied`.
3. When access is allowed, the model asks for `DeviceCapabilities`. No lenses leads to
   `.unavailable`; otherwise `.ready(capabilities)`.
4. The interface renders the new state. It holds no rules of its own.

The planned path from capture to Photos, to be built in later pull requests (issue #1):
capture a single-frame Bayer RAW (`NopeCapture`), remove private metadata through the system
APIs, develop HEIF and JPEG from the same RAW (`NopeDevelop`), sign each file with a fresh key
(`NopeSigning`), and add it to Photos with add-only access (`NopeCapture`). Photos go from
memory to Photos and never linger on disk.

## The development backend

Until the AVFoundation capture adapter exists, the app wires `SimulatedCaptureBackend`: asking
for access succeeds without a system prompt, and the device reports one simulated wide lens with
RAW. No camera hardware is used. `SystemCameraAuthorization` in `NopeCapture` is the real
permission adapter; it will be wired in together with capture.

## Appearance

The camera screen uses the dark appearance (`preferredColorScheme(.dark)`). Settings and other
screens, when they exist, follow the system appearance; their UI tests will cover both.

## Signing and secrets

Development builds use automatic signing with the bundle identifier `com.photivra.nope.dev`. The
development team is read from `Config/Local.xcconfig`, which git ignores; copy
`Config/Local.xcconfig.example` to create it. No team ID, certificate or profile is committed.
CI builds for the Simulator with `CODE_SIGNING_ALLOWED=NO`.
