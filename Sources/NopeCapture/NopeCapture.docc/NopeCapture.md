# ``NopeCapture``

AVFoundation and PhotoKit adapters that implement the `NopeCore` protocols.

## Overview

`NopeCapture` is the only module that talks to the camera hardware and the photo library. Each
adapter is thin: conversions and rules live in small, fully tested types, and the calls that need
hardware or a person's answer are isolated in files listed in `scripts/coverage-exclusions.txt`
and verified on a device.

The scaffold contains the camera permission adapter. Capture, RAW and PhotoKit adapters follow.

Related documentation: `docs/ARCHITECTURE.md`, `docs/TESTING.md` and `docs/PRIVACY.md` in the
repository.

## Topics

### Permission

- ``SystemCameraAuthorization``
- ``NopeCore/CameraPermission``
