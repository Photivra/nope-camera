# Building an interface

Write a minimal interface for Photivra Nope Camera that renders the camera state and sends intents.

## Overview

Any interface (minimal, accessibility-first, iPad-specific or experimental) talks to the app the
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
the shutter. The model decides what happens next. Disable the lens controls while
``CameraModel/canChangeLens`` is false (``CameraModel/lensChangeBlocker`` says why); the model
ignores a lens change then anyway.

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

Manual controls are off by default and stay hidden until the person turns them on. A control
that turns them on or off, such as a Manual Controls button, calls
``CameraModel/setManualControls(_:settings:)``, which stores the "Manual controls" option
(``NopeSettings/showsManualControls``) and turns them on or off at once, including after the
astro helper turned them on. An interface that also lets the option change elsewhere sends
``ManualControlIntent/setEnabled(_:)`` when it changes. While ``ManualControlsModel/isEnabled``
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
using reach the interface. In full auto the readings drive the fast shutter rule and the hints,
so run it whether or not manual controls are on.

### Offer the full-auto aids

These work with manual controls off, and never change a manual setting
(``AutoControlIntent``):

- tap to focus: send ``AutoControlIntent/focusAndExpose(at:)`` with the tapped point divided by
  the viewfinder's size (``FramePoint/normalized(locationX:locationY:width:height:)``), and draw
  a focus mark at ``ManualControlsModel/focusTarget``; offer a lock button that sends
  ``AutoControlIntent/lockFocusAndExposure(at:)`` and, once
  ``FocusTarget/isLocked``, ``AutoControlIntent/unlockFocusAndExposure``. Show these only where
  ``ManualCapabilities/supportsTapToFocus``;
- exposure compensation: while ``ManualControlsModel/canAdjustExposureCompensation``, send
  ``AutoControlIntent/setExposureCompensation(_:)`` or
  ``AutoControlIntent/stepExposureCompensation(by:)``;
- Close-Up: where ``ManualCapabilities/supportsNearFocusLimit``, send
  ``AutoControlIntent/setNearFocusLimit(_:)``;
- Far Focus: where ``ManualCapabilities/supportsFarFocusLimit``, send
  ``AutoControlIntent/setFarFocusLimit(_:)`` (it lifts the near limit, and Close-Up lifts it);
- send the person's ``NopeSettings/followsFaces`` with ``AutoControlIntent/setFollowsFaces(_:)``,
  and their ``NopeSettings/photoSizes`` with ``CameraIntent/setPhotoSizes(_:)`` (offer a size
  only from ``Lens/photoSizeChoices``);
- show "Hold it steady or use a tripod." while ``ManualControlsModel/showsSteadyHint``, and offer
  a button to switch to ``CameraModel/closeUpLens`` when it isn't `nil`;
- send the person's ``NopeSettings/fastShutter`` with ``AutoControlIntent/setFastShutter(_:)``. Clean view is ``CameraModel/isCleanView``, set with
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
