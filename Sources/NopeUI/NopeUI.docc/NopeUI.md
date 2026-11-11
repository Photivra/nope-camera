# ``NopeUI``

The standard SwiftUI interface for nope.

## Overview

`NopeUI` renders a `NopeCore` camera model with native SwiftUI views and sends it intents. It
holds no business rules, so it can be replaced: see `docs/BUILDING-AN-INTERFACE.md` in the
repository and the "Building an interface" article in `NopeCore`.

Every string is in the module's `Localizable.xcstrings`, in all eleven launch languages. The
camera screen uses the dark appearance; other screens follow the system. Each screen and state
is checked by the UI tests with `performAccessibilityAudit()`.

## Topics

### Screens

- ``CameraScreen``
