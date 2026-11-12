# ``NopeCapture``

AVFoundation and PhotoKit adapters that implement the `NopeCore` protocols.

## Overview

`NopeCapture` is the only module that talks to the camera hardware and the photo library. Each
adapter is thin: conversions and rules live in small, fully tested types, and the calls that need
hardware or a person's answer are isolated in files listed in `scripts/coverage-exclusions.txt`
and verified on a device.

``AVFoundationCaptureBackend`` is the real `CaptureBackend`: it finds the physical cameras,
publishes their capabilities, and captures single-frame Bayer RAW, or the labeled processed
fallback on a lens without it, in memory. Its decisions are in tested types; the calls that need
a camera are in `SystemCaptureHardware.swift`. ``CaptureSessionPreviewSource/connect(_:)`` shows
the session in the app's preview layer and keeps the preview and photos upright with
`AVCaptureDevice.RotationCoordinator`. Saving to Photos follows in a later step.

Related documentation: `docs/ARCHITECTURE.md`, `docs/TESTING.md` and `docs/PRIVACY.md` in the
repository.

## Topics

### Capture

- ``AVFoundationCaptureBackend``
- ``CaptureSessionPreviewSource``

### Permission

- ``CameraAuthorizing``
- ``SystemCameraAuthorization``
- ``NopeCore/CameraPermission``
