# Architecture

nope. is split into a replaceable interface and interface-free logic. The rules are in
[`AGENTS.md`](../AGENTS.md), "Architecture: interface separate from logic"; this page describes
how the code follows them. Status: in development. The camera captures, each photo's metadata is
built from the allowlist and checked by reading the file back, and clean photos are saved to
Photos. Signing is not built yet, so photos are saved unsigned and the app says so.

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
| `NopeCore` | `CameraModel` (the state machine), `CameraState`, `SessionStatus`, `CaptureStatus`, `CameraIntent`, `DeviceCapabilities`, `Lens`, `CaptureFormat` (RAW or the labeled fallback), `CapturedPhoto`, `CaptureEvent`, the `CaptureBackend` and `CameraPreviewSource` protocols, `SimulatedCaptureBackend`; the settings (`SaveSettings`, `MetadataSettings`); the metadata allowlist (`MetadataPlan`, `MetadataField`, `MetadataAllowlist`), the project's own tag reader (`MetadataFileReader`: TIFF/DNG, JPEG, HEIF, XMP) and `MetadataVerifier`; the save pipeline `PhotoSaver` and its protocols (`PhotoDeveloping`, `PhotoSigning`, `MetadataReading`, `PhotoLibrary`), and the manual controls: `ManualControlsModel`, `ManualControlIntent`, `ManualCapabilities`, `ControlScale`, `ManualSettings`, `DeviceControls` and the `ManualCaptureBackend` protocol, and the settings model `NopeSettings` (which stores `SaveSettings`) with `LockedMetadataItem` | Foundation |
| `NopeCapture` | AVFoundation and PhotoKit adapters: `AVFoundationCaptureBackend` (writes each file with allowlisted metadata), `PhotoKitLibrary` (add-only saving) and the camera permission adapter | `NopeCore`, AVFoundation, Photos |
| `NopeDevelop` | RAW development and encoding: `RAWDeveloper` (Core Image, system encoders, `EncodingSettings`) and `ImageIOReadBack` | `NopeCore`, Core Image, ImageIO |
| `NopeSigning` | C2PA signing. Now: `ContentCredentialsSigner` (implements `PhotoSigning`), a new Secure Enclave key and self-issued certificate for every file, fully offline | `NopeCore`, CryptoKit, Security, C2PA, X509 and SwiftASN1 (swift-certificates, for the certificate) |
| `NopeUI` | SwiftUI views. Now: `CameraScreen` (format badge, viewfinder, lens buttons, shutter, status, Settings button) and `SettingsScreen` (formats, privacy and signing, manual controls, Honesty, About and licenses) | `NopeCore`, SwiftUI |
| App (`NopeApp`) | Wires `AVFoundationCaptureBackend` and a `PhotoSaver` (`RAWDeveloper`, `ImageIOReadBack`, `PhotoKitLibrary`, `ContentCredentialsSigner`) into `NopeCore`, supplies the preview view and the hardware shutter, and hosts `NopeUI` | Everything |

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
   plan's metadata. `PhotoSaver` then develops, signs (when a signer exists), reads back,
   checks and saves it (below). The result is `captureStatus = .saved(photo)` or
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
- **Readings** (exposure offset, ISO, shutter, focus position, aperture, white balance) come from
  key-value observation of the camera, at most four a second, only while manual controls are on.
  No video data output is added, so there is no live histogram; the meter is the camera's own
  exposure offset.
- **Bracketing** uses `AVCapturePhotoBracketSettings` with
  `AVCaptureManualExposureBracketedStillImageSettings`; each frame is a separate single-frame
  photo, and each is saved through the same pipeline as a single photo
  (`CaptureStatus.savedBracket`). Bayer RAW rules still apply: `.speed`, zoom 1.0, no
  multi-frame processing.
- **Interval shooting** calls the same capture path as the shutter; its timer exists only while a
  series runs, and the camera screen stops it when it disappears.

### The viewfinder

`NopeUI` may import only `NopeCore` and SwiftUI, and `NopeCapture` may not import UIKit, so the
preview crosses the layers as an opaque `CameraPreviewSource`. The AVFoundation backend's source
is a `CaptureSessionPreviewSource`; the app target's `Viewfinder` view turns it into an
`AVCaptureVideoPreviewLayer` and passes it to `CameraScreen(model:settings:viewfinder:)`. The app also
attaches `onCameraCaptureEvent` (AVKit), so the volume buttons and the Camera Control take a
photo.

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
   2. PhotoSigning hook (NopeSigning, not built yet: files are saved unsigned, status says so)
   3. read-back of every file: ImageIOReadBack = MetadataFileReader (every tag, block and XMP
      property) + ImageIO's keys; MetadataVerifier against MetadataPlan.allowlist(for:signed:);
      for the DNG, its RAW image data must equal the reference. Any violation: nothing is saved
   4. PhotoKitLibrary (NopeCapture): add-only access, one PHAssetCreationRequest per asset;
      the DNG as `.photo` and its HEIF (or JPEG) as `.alternatePhoto`
```

**Why the DNG's metadata is written by AVFoundation.** ImageIO can't write DNG: on macOS 27 and
the iOS 27 Simulator, `CGImageDestinationCopyTypeIdentifiers()` doesn't list
`com.adobe.raw-image`, and `CGImageDestinationCreateWithData` returns `nil` for it (asserted by
`ImageIOReadBackTests.imageIOCantWriteDNG`; to be confirmed on a device), so `CGImageDestinationCopyImageSource`
(which `CGImageDestination.h` describes as a lossless copy that "will not modify" the image data)
isn't available for DNG. AVFoundation's own path is documented for this:
`AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata(for:)` in
`AVCapturePhotoOutput.h` returns "a dictionary of keys and values from
<ImageIO/CGImageProperties.h> … To replace metadata, pass a replacement dictionary." AVFoundation
then flattens the in-memory photo itself, so nope. never re-encodes or touches the sensor data,
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

### Signing

`NopeCore` defines the signing hook, `PhotoSigning.sign(_:)`, which takes and returns a
`PhotoFile` (its format, bytes, and whether the phone's camera processed it). `PhotoSaver` builds
each file's metadata, then, when `MetadataSettings.signsPhotos` is on, calls the signer, then
reads the signed file back against `MetadataPlan.allowlist(for:signed:)`, which permits the
Content Credentials item of a signed file and nothing else, then saves it. If signing fails, the
file is saved unsigned and the status says so. `NopeSigning` implements the hook:

```
 ContentCredentialsSigner (PhotoSigning)
   ├─ SigningKeyProvider: SecureEnclaveKeyProvider on a device (excluded from the coverage gate),
   │                      SimulatorSoftwareKeyProvider in the Simulator only
   ├─ SelfIssuedCertificate (swift-certificates): anonymous, non-CA, C2PA EKU, fixed validity
   ├─ ContentCredentialsManifest: one c2pa.created action, nope. as claim generator
   ├─ OfflineC2PAContext: every fetch off, no network host
   └─ InMemoryFile and InMemoryStream: the C2PA library reads and writes memory, never a file
```

The C2PA library is c2pa-rs built from source with every network feature off
(`c2pa-lib/README.md`), and its Swift wrapper is vendored without its networking code
(`Vendor/c2pa-swift`). Details and the exact contents are in [`PRIVACY.md`](PRIVACY.md),
"Content Credentials".


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
Settings button opens `SettingsScreen` as a sheet in every camera state.

The app passes `NopeSettings.save` to `CameraModel.saveSettings` whenever it changes, so the
next photo uses it. Location and the
name and copyright have no switch yet (`MetadataItem.isOfferedInSettings`): their flows (the
location prompt, text entry) aren't built, so they stay off.

The Honesty screen and About are static: every Honesty statement comes from
[`research/privacy-claims.md`](research/privacy-claims.md), and About shows bundled copies of
`LICENSE` and `NOTICE` (a unit test keeps them identical) with the source address as a link.
Tapping it hands the `https` address to the system browser; nope. makes no network request,
registers no URL scheme and opens no system setting.

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
