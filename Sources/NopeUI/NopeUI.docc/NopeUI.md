# ``NopeUI``

The standard SwiftUI interface for nope.

## Overview

`NopeUI` renders a `NopeCore` camera model with native SwiftUI views and sends it intents. It
holds no business rules, so it can be replaced: see `docs/BUILDING-AN-INTERFACE.md` in the
repository and the "Building an interface" article in `NopeCore`.

Every string is in the module's `Localizable.xcstrings`, in all eleven launch languages, except
honesty claims (the RAW badge and the no-RAW fallback wording), which are in `Honesty.xcstrings`.
The live viewfinder view is supplied by the app target, because `NopeUI` imports only `NopeCore`
and SwiftUI. The
camera screen uses the dark appearance; other screens follow the system.

The camera screen stacks its controls above and below the viewfinder when the space is taller
than wide, and puts them in a column beside a full-height viewfinder when it is wider, on iPhone
and iPad alike. It has two slots for more controls, a top bar and a controls area, described in
`docs/ARCHITECTURE.md`, "Layout". ``CameraCommands`` adds a Camera menu whose Space bar shortcut
takes a photo from a hardware keyboard. Each screen and state
is checked by the UI tests with `performAccessibilityAudit()`.

## Topics

### Screens

- ``CameraScreen``

### Commands

- ``CameraCommands``
