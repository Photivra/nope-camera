# ``NopeCore``

The models, state machine and capability protocols behind nope.: the contract every interface
builds on.

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

### Capabilities

- ``DeviceCapabilities``
- ``Lens``
- ``PhotoDimensions``
- ``ApertureRange``
- ``ProcessedFallback``
- ``CameraPermission``
- ``PhotoFormat``

### Capture

- ``CaptureFormat``
- ``CaptureRequest``
- ``CapturedPhoto``

### Settings

- ``SaveSettings``
- ``DevelopedLook``
- ``MetadataSettings``
- ``MetadataItem``

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
- ``ManualControlsSetting``
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

### Hardware

- ``CaptureBackend``
- ``ManualCaptureBackend``
- ``DeviceControls``
- ``CaptureEvent``
- ``CameraPreviewSource``
- ``SimulatedCaptureBackend``
- ``SimulatedPreviewSource``
