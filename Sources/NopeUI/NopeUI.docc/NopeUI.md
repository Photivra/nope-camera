# ``NopeUI``

The standard SwiftUI interface for Photivra Nope Camera.

## Overview

`NopeUI` renders a `NopeCore` camera model with native SwiftUI views and sends it intents. It
holds no business rules, so it can be replaced: see `docs/BUILDING-AN-INTERFACE.md` in the
repository and the "Building an interface" article in `NopeCore`.

Every string is in the module's `Localizable.xcstrings` (English only in version 1.0.0), except
honesty claims (the RAW badge, the no-RAW fallback wording, the privacy and signing settings and
the Honesty screen), which are in `Honesty.xcstrings` and need a fluent human review before
release.

``CameraScreen`` follows the 1.0.0 design, direction B (issue #74; `docs/design/BUILD-SPEC.md`):
in full auto a status line with the format status, the 4:3 picture, the lens row (the Manual
Controls button, the lenses, Switch Camera), the drive strip, and the shutter row with the
last-photo slot and Q, the quick menu, whose foot opens Settings. State pills, warning chips,
the mode cards, Q's panel and the manual readout row with its dial appear only when needed;
later features register their items in the Q, pill and warning registries. A first-run screen
comes before the camera prompt. The iPhone layout stays in portrait and turns icons and text
upright; on iPad the controls, Settings among them, are in a trailing column.
``SettingsScreen`` is a short grouped list with search: Presets, Photos, Privacy, Camera, Screen
and More (Accessibility, Honesty, About and licenses).

The app target supplies ``CameraCommands`` (the Space bar takes a photo) and three environment
values: ``SwiftUICore/EnvironmentValues/cameraUprightRotation``,
``SwiftUICore/EnvironmentValues/cameraPresentsSheet`` and
``SwiftUICore/EnvironmentValues/openAppSettings``.

The live viewfinder view is supplied by the app target, because `NopeUI` imports only `NopeCore`
and SwiftUI. The
camera screen and its own sheets use the dark appearance; Settings, first run and the other
screens that aren't the camera follow the system's light or dark setting (`ScreenAppearance`,
``SwiftUICore/EnvironmentValues/systemColorScheme``). Each screen and state
is checked by the UI tests with `performAccessibilityAudit()`.

## Topics

### Screens

- ``CameraScreen``
- ``SettingsScreen``

### App target hooks

- ``CameraCommands``
- ``UprightRotation``
- ``CameraAction``
- ``SheetPresentationAction``
- ``WindowAppearanceAction``
- ``WindowAppearanceRequest``
