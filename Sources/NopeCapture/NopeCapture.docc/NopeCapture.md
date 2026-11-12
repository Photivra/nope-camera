# ``NopeCapture``

AVFoundation and PhotoKit adapters that implement the `NopeCore` protocols.

## Overview

`NopeCapture` is the only module that talks to the camera hardware and the photo library. Each
adapter is thin: conversions and rules live in small, fully tested types, and the calls that need
hardware or a person's answer are isolated in files listed in `scripts/coverage-exclusions.txt`
and verified on a device.

``AVFoundationCaptureBackend`` is the real `CaptureBackend`: it finds the physical cameras,
publishes their capabilities, and captures single-frame Bayer RAW, or the labeled processed
fallback on a lens without it, in memory. Each file is flattened with metadata built from the
allowlist (`AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata(for:)`), and for
RAW the system's own RAW image data is kept as the reference the read-back compares with. Its
decisions are in tested types; the calls that need a camera are in `SystemCaptureHardware.swift`.
``CaptureSessionPreviewSource/connect(_:)`` shows the session in the app's preview layer and
keeps the preview and photos upright with `AVCaptureDevice.RotationCoordinator`.

``PhotoKitLibrary`` adds checked photos to Photos with add-only access, a RAW and its processed
file as one asset. Its decisions are in the tested `PhotoKitMapping`.

As a `ManualCaptureBackend`, it also sets exposure, focus, white balance and metering on the
camera within each lens's real ranges, reports the values in use at a reduced rate, and takes
manual exposure brackets as separate single-frame photos.

Related documentation: `docs/ARCHITECTURE.md`, `docs/TESTING.md` and `docs/PRIVACY.md` in the
repository.

## Topics

### Capture

- ``AVFoundationCaptureBackend``
- ``CaptureSessionPreviewSource``

### Photos

- ``PhotoKitLibrary``

### Permission

- ``CameraAuthorizing``
- ``SystemCameraAuthorization``
- ``NopeCore/CameraPermission``
