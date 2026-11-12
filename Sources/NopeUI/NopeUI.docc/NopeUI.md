# ``NopeUI``

The standard SwiftUI interface for nope.

## Overview

`NopeUI` renders a `NopeCore` camera model with native SwiftUI views and sends it intents. It
holds no business rules, so it can be replaced: see `docs/BUILDING-AN-INTERFACE.md` in the
repository and the "Building an interface" article in `NopeCore`.

Every string is in the module's `Localizable.xcstrings`, in all eleven launch languages, except
honesty claims (the RAW badge and the no-RAW fallback wording), which are in `Honesty.xcstrings`.
When the "Manual controls" option is on, the camera screen adds the manual controls: an EV
meter, the exposure modes, a six-slot grid in a fixed order with one panel per control (native
sliders and pickers), Pro Tools (metering, AE and AF locks, bracketing, interval shooting) and
"All Auto". At accessibility text sizes the grid becomes a list with steppers. Each slot is a
VoiceOver adjustable element. Clean view hides every non-essential control and keeps honesty
warnings.

The live viewfinder view is supplied by the app target, because `NopeUI` imports only `NopeCore`
and SwiftUI. The
camera screen uses the dark appearance; other screens follow the system. Each screen and state
is checked by the UI tests with `performAccessibilityAudit()`.

## Topics

### Screens

- ``CameraScreen``
