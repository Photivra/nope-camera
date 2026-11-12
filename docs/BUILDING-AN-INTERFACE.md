# Building an interface

nope.'s interface is a replaceable layer. You can write your own (minimal, accessibility-first,
iPad-specific or experimental) without touching capture, privacy, signing or development code.
This guide explains how in plain English. The full walkthrough, with a compiled example, is the
DocC article "Building an interface" in `NopeCore`
([`Sources/NopeCore/NopeCore.docc/BuildingAnInterface.md`](../Sources/NopeCore/NopeCore.docc/BuildingAnInterface.md)).

## The contract

Your interface depends on `NopeCore` only. It does three things:

1. **Reads state.** `CameraModel.state` is a `CameraState`: `starting`, `needsPermission`,
   `permissionDenied`, `unavailable`, or `ready` with the device's `DeviceCapabilities`. The
   documentation of each case says how to present it.
2. **Sends intents.** Call `CameraModel.send(_:)` with a `CameraIntent`: `.start` when your
   interface appears, `.requestPermission` when the person presses your "Allow" button,
   `.selectLens(id)` when they pick a lens and `.capture` from your shutter. While it is
   visible, also run `CameraModel.observeEvents()` so interruptions and heat are applied.
   In the ready state, render `sessionStatus`, `captureStatus`, `selectedLensID` and
   `captureFormat` (say plainly when it is the processed fallback; when `captureStatus` is
   `.saved`, always say whether the photo is signed), and enable the shutter only
   when `canCapture` is true.
3. **Holds no rules.** Don't decide privacy, formats, exposure or what the device supports. If
   you need a decision, it belongs in `NopeCore` as state or a capability value.

`CameraModel` runs on the main actor and uses Observation, so a SwiftUI view that reads `state`
updates automatically.

## Steps

1. Create a module or target that imports `NopeCore` (and SwiftUI, if you use it).
2. Write a root view that takes a `CameraModel` and switches over `state`.
3. Send `.start` when it appears (`.task { await model.send(.start) }` in SwiftUI).
4. In the app target, pass your root view the same `CameraModel` that `CameraScreen` gets today
   (see `App/NopeApp/NopeApp.swift`). For the live viewfinder, the app gives your interface a
   view for `CameraModel.previewSource` (`Viewfinder` in `App/NopeApp/Camera/`), because
   `NopeCore` can't show video.
   Its viewfinder view connects its `AVCaptureVideoPreviewLayer` with
   `CaptureSessionPreviewSource.connect(_:)`, which also keeps the preview and the photos
   upright as the device turns. A keyboard shortcut for the shutter can reuse `CameraCommands`
   from `NopeUI` or send `.capture` from your own command.
5. Test it against `SimulatedCaptureBackend`, which can put the model in every state without a
   camera, and add a UI test with `performAccessibilityAudit()` for each state.

## Rules that still apply

Your interface follows AGENTS.md like the standard one: native controls, Dynamic Type, VoiceOver
labels, 44-point touch targets, every string in a String Catalog in all eleven languages, and the
name written "nope.".

## Reference

- API: [`docs/api/NopeCore.md`](api/NopeCore.md)
- Architecture: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)
- Tests: [`docs/TESTING.md`](TESTING.md)
