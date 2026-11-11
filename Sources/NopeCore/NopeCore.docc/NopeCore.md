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

### Hardware

- ``CaptureBackend``
- ``CaptureEvent``
- ``CameraPreviewSource``
- ``SimulatedCaptureBackend``
- ``SimulatedPreviewSource``
