# ``NopeCore``

The models, state machine and capability protocols behind Photivra Nope Camera: the contract every
interface builds on.

## Overview

`NopeCore` holds the camera's state and rules, and the protocols for every hardware capability.
It imports only Foundation, so it can be tested without a camera and used by any interface.

An interface reads ``CameraModel/state`` (with ``CameraModel/sessionStatus``,
``CameraModel/captureStatus``, ``CameraModel/selectedLens`` and ``CameraModel/captureFormat``)
and sends ``CameraIntent`` values through ``CameraModel/send(_:)``. It never calls AVFoundation, PhotoKit, signing or development code, and
it holds no business rules. The hardware sits behind ``CaptureBackend``; tests, previews and
development builds use ``SimulatedCaptureBackend``.

Each photo is saved by ``PhotoSaver``: its files' metadata is built from the allowlist
(``MetadataPlan``, from the person's ``MetadataSettings``), every file is read back with the
project's own reader (``MetadataFileReader``) and checked by ``MetadataVerifier``, and only clean
files reach Photos. A file with anything off the allowlist is never saved (fail closed).

Related documentation in the repository:

- `docs/ARCHITECTURE.md`: the modules and the flow from capture to Photos.
- `docs/BUILDING-AN-INTERFACE.md`: a plain-English guide to replacing `NopeUI`.
- `docs/TESTING.md`: how to run the tests.

## Topics

### Essentials

- <doc:BuildingAnInterface>
- ``CameraModel``
- ``CameraState``
- ``CameraIntent``

### Camera status

- ``SessionStatus``
- ``InterruptionReason``
- ``HeatLevel``
- ``CaptureStatus``
- ``CaptureError``
- ``LensChangeBlocker``

### Capabilities

- ``DeviceCapabilities``
- ``Lens``
- ``PhotoDimensions``
- ``ApertureRange``
- ``ProcessedFallback``
- ``DistortionCorrection``
- ``CameraPermission``
- ``PhotoFormat``


### Flash and light

- ``LightModel``
- ``LightIntent``
- ``FlashMode``
- ``TorchStatus``
- ``LightCaptureBackend``

### Capture

- ``CaptureFormat``
- ``CaptureRequest``
- ``CapturedPhoto``

### Settings

- ``NopeSettings``
- ``SaveSettings``
- ``DevelopedLook``
- ``MetadataSettings``
- ``MetadataItem``
- ``LockedMetadataItem``

### Shared settings

- ``SharedSettingsStore``
- ``SharedSettingsSync``
- ``SettingsChangeSignaling``
- ``DarwinSettingsChangeSignal``
- ``NopeSettingsSnapshot``

### Saving

- ``PhotoSaver``
- ``SavedPhoto``
- ``SignatureStatus``
- ``PhotoFile``
- ``PhotoDeveloping``
- ``PhotoSigning``
- ``MetadataReading``
- ``MetadataReadBack``
- ``PhotoLibrary``
- ``PhotoLibraryAsset``

### Metadata allowlist and read-back

- ``MetadataPlan``
- ``MetadataAllowlist``
- ``MetadataField``
- ``LockedMetadata``
- ``ImageIOKey``
- ``TIFFDirectory``
- ``MetadataFileReader``
- ``MetadataInventory``
- ``MetadataVerifier``
- ``MetadataViolation``
### Manual controls

- ``ManualControlsModel``
- ``ManualControlIntent``
- ``ManualControl``
- ``ControlAvailability``
- ``ControlScale``
- ``ManualSettings``
- ``ManualCapabilities``
- ``ExposureMode``
- ``MeteringMode``
- ``ExposureReading``
- ``WhiteBalance``
- ``WhiteBalancePreset``
- ``BracketSettings``
- ``BracketFrame``
- ``IntervalSettings``
- ``IntervalProgress``
- ``IntervalBlocker``
- ``IntervalEnd``

### Drive modes, self-timer and burst

- ``DriveModel``
- ``DriveMode``
- ``DriveIntent``
- ``ShutterPhase``
- ``HardwareButtonPhase``
- ``BurstSpeed``
- ``BurstStart``
- ``SelfTimerDelay``
- ``Countdown``
- ``BurstProgress``
- ``BurstEnd``
- ``BurstResult``

### Storage, battery and the screen

- ``DeviceStatus``
- ``DeviceStatusReading``
- ``BatteryReading``
- ``BatteryWarning``
- ``StorageWarning``
- ``PhotoSizeEstimate``
- ``SeriesScreenKeeper``
- ``ScreenControlling``

### Live Activity

- ``LiveActivityCoordinator``
- ``LiveActivityContent``
- ``LiveActivityStatusLine``
- ``LiveActivitySigningLine``
- ``LiveActivityDismissal``
- ``LiveActivityPresenting``
- ``BackgroundTimeRequesting``

### Full-auto aids

- ``AutoControlIntent``
- ``FastShutter``
- ``FocusTarget``
- ``FramePoint``
- ``AssistSettings``

### Apple Watch remote shutter

- ``WatchRemote``
- ``PhoneLink``
- ``WatchCommandServer``
- ``WatchLink``
- ``WatchCommand``
- ``WatchDelay``
- ``WatchStatus``
- ``WatchCameraProblem``
- ``WatchResult``
- ``PhoneUpdate``
- ``WatchMessageCoding``
- ``WatchMessageError``

### Hardware

- ``CaptureBackend``
- ``ManualCaptureBackend``
- ``DeviceControls``
- ``CaptureEvent``
- ``CameraPreviewSource``
- ``SimulatedCaptureBackend``
- ``SimulatedPreviewSource``
