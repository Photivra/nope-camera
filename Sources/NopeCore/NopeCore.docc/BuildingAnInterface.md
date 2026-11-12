# Building an interface

Write a minimal interface for nope. that renders the camera state and sends intents.

## Overview

Any interface (minimal, accessibility-first, iPad-specific or experimental) talks to nope. the
same way: it observes a ``CameraModel`` and sends it ``CameraIntent`` values. It needs nothing
from `NopeCapture`, `NopeDevelop` or `NopeSigning`.

### Render every state

Switch over ``CameraModel/state`` and give each ``CameraState`` case a presentation. Each case's
documentation says how to present it. This text-only interface is compiled and run by
`BuildingAnInterfaceExampleTests` in `Tests/NopeCoreTests`, so it stays correct:

```swift
@MainActor
struct TextInterface {
    let model: CameraModel

    func render() -> String {
        switch model.state {
        case .starting: "Starting"
        case .needsPermission: "Press Allow to use the camera"
        case .permissionDenied: "Camera access is off"
        case .unavailable: "No camera"
        case .ready(let capabilities): "\(capabilities.lenses.count) lens(es)"
        }
    }

    func appear() async { await model.send(.start) }
    func pressAllow() async { await model.send(.requestPermission) }
}
```

### Send intents, not commands

Send ``CameraIntent/start`` once when the interface appears, and
``CameraIntent/requestPermission`` only when the person presses a button. Send
``CameraIntent/selectLens(_:)`` when the person picks a lens and ``CameraIntent/capture`` from
the shutter. The model decides what happens next.

While the interface is visible, run ``CameraModel/observeEvents()`` (in SwiftUI, a second
`.task`), so interruptions and heat reach ``CameraModel/sessionStatus``.

### Show the camera

In the ready state, render:

- the lenses from the capabilities, with ``CameraModel/selectedLensID`` marked;
- ``CameraModel/captureFormat``: say plainly when it is the processed fallback;
- ``CameraModel/sessionStatus``: each case's documentation says what to show;
- ``CameraModel/captureStatus``: announce each result. A saved photo's
  ``SavedPhoto/signature`` must be shown: never present an unsigned photo as signed;
- a viewfinder for ``CameraModel/previewSource``. `NopeCore` can't show video, so the app target
  gives your interface a view for the handle; the standard app uses `AVCaptureVideoPreviewLayer`.

Enable the shutter only when ``CameraModel/canCapture`` is `true`.

### Offer manual controls

Manual controls are off by default and stay hidden until the person turns on the "Manual
controls" option (stored under ``ManualControlsSetting/userDefaultsKey``; send
``ManualControlIntent/setEnabled(_:)`` when it changes). While ``ManualControlsModel/isEnabled``
is `true`, read ``CameraModel/manual``:

- show every ``ManualControl`` in the same order, with ``ManualControlsModel/availability(of:)``
  for each: adjustable, fixed (such as a fixed aperture), blocked, or not available;
- show ``ManualControlsModel/value(of:)``, marked Manual or Auto with
  ``ManualSettings/isManual(_:)``;
- draw sliders over ``ManualControlsModel/scale(for:)``, and make each control a VoiceOver
  adjustable element that sends ``ManualControlIntent/step(_:by:)``;
- offer ``ManualControlsModel/exposureModes`` and send ``ManualControlIntent/setExposureMode(_:)``;
- offer "All Auto" (``ManualControlIntent/allAuto``) whenever ``ManualSettings/isAutomatic`` is
  `false`.

Run ``ManualControlsModel/observeReadings()`` in another `.task`, so the values the camera is
using reach the interface. Clean view is ``CameraModel/isCleanView``, set with
``CameraIntent/setCleanView(_:)``; it never hides a warning that changes what the photo is, such
as the no-RAW badge.

### Test against a simulated backend

Create the model with a ``SimulatedCaptureBackend`` to drive every state without a camera:

```swift
let backend = SimulatedCaptureBackend(
    permission: .notDetermined,
    permissionAfterRequest: .authorized,
    capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")])
)
let interface = TextInterface(model: CameraModel(backend: backend))
```

In a SwiftUI interface, pass the model to your root view and read ``CameraModel/state`` in
`body`; observation updates the view when the state changes.
