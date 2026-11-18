# ``NopeUI``

The standard SwiftUI interface for Photivra Nope Camera.

## Overview

`NopeUI` renders a `NopeCore` camera model with native SwiftUI views and sends it intents. It
holds no business rules, so it can be replaced: see `docs/BUILDING-AN-INTERFACE.md` in the
repository and the "Building an interface" article in `NopeCore`.

Every string is in the module's `Localizable.xcstrings`, in English, Spanish and Latin American Spanish, except
honesty claims (the RAW badge, the no-RAW fallback wording, the privacy and signing settings and
the Honesty screen), which are in `Honesty.xcstrings` and need a fluent human review before
release.

``CameraScreen`` follows the approved clean layout (issue #68; current design in `docs/design/camera.html`): in
full auto a format chip, Settings, the lens row below the 4:3 picture with a quick-controls
button, the shutter, a camera flip and the last-photo slot. State pills, warning chips, the
quick-controls tray and the manual readout row with its dial appear only when needed; later
features register their items in the tray, pill and warning registries. A first-run screen comes
before the camera prompt. The iPhone layout stays in portrait and turns icons and text upright;
on iPad the controls are in a trailing column. ``SettingsScreen`` is a short grouped list:
Photos, Privacy, Camera and More (Accessibility, Honesty, About and licenses).

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
