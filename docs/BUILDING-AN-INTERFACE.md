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

Settings work the same way. `NopeSettings` holds the formats, the metadata switches
(`MetadataSettings`), signing, manual controls and clean view. Read its properties and change
them only through its methods (`setFormat(_:isSelected:)`, `setMetadataItem(_:isIncluded:)`,
`setRemovesAllOptionalDetails(_:)`, `setSignsPhotos(_:)` and the others), which apply the
rules and save the change. Show a metadata switch only where `MetadataItem.isOfferedInSettings`
is true, and every `LockedMetadataItem` as locked, with its reason. Privacy and Honesty wording
must not claim more than `docs/research/privacy-claims.md` supports.

## Steps

1. Create a module or target that imports `NopeCore` (and SwiftUI, if you use it).
2. Write a root view that takes a `CameraModel` and switches over `state`.
3. Send `.start` when it appears (`.task { await model.send(.start) }` in SwiftUI).
4. In the app target, pass your root view the same `CameraModel` that `CameraScreen` gets today
   (see `App/NopeApp/NopeApp.swift`). For the live viewfinder, the app gives your interface a
   view for `CameraModel.previewSource` (`Viewfinder` in `App/NopeApp/Camera/`), because
   `NopeCore` can't show video.
5. Test it against `SimulatedCaptureBackend`, which can put the model in every state without a
   camera, and add a UI test with `performAccessibilityAudit()` for each state.

## Manual controls

Manual controls are off by default; the "Manual controls" option in Settings turns them on, and
the app target sends `.manual(.setEnabled(_:))` when it changes. Everything about them is in
`CameraModel.manual` (`ManualControlsModel`): which controls the selected lens offers
(`availability(of:)`), the steps of each one (`scale(for:)`), the value in use (`value(of:)`), the
exposure modes, bracketing and interval shooting. Send `.manual(...)` intents to change them; the
model keeps the combination valid for the lens. Offer "All Auto" whenever
`manual.settings.isAutomatic` is false. Run `manual.observeReadings()` in a second `.task` so the
values the camera is using appear. Clean view is `CameraModel.isCleanView`; it must never hide
a warning that changes what the photo is.

## Drive modes, storage and battery

The shutter, and every hardware shutter, sends `.capture`; the model applies `drive.mode`
(single, a 3 or 10 second self-timer, or burst), and the same intent stops a running countdown
or burst. Enable the shutter with `canPressShutter`, not `canCapture`, so it can stop them. Show
`drive.countdown.remainingSeconds` and `drive.burstProgress` with a visible way to stop each
(`.drive(.cancelTimer)`, `.drive(.stopBurst)`), and announce them. Pass the hardware buttons'
phases as `.drive(.hardwareButton(_:))`. Pass a `DeviceStatusReading` to `CameraModel` and show
`storageWarning` and `deviceStatus.batteryWarning`. During an interval series, call
`SeriesScreenKeeper.update(isSeriesRunning:isInForeground:)` so the screen stays awake and is
dimmed, with a visible way to brighten it.

## The standard camera layout

`NopeUI`'s camera screen is one interface on this contract, following the approved layout in
[`design/ux-v3.html`](design/ux-v3.html). If you extend it rather than replace it, add camera
toggles to `QuickControls.builders`, non-default states to `StatePills.builders` and persistent
warnings to `CameraWarnings.builders`; the layout places them. The app target supplies four
environment values: `cameraUprightRotation` (which way up the iPhone is held),
`cameraPresentsSheet` (so the app can rotate sheets while the camera stays in portrait),
`openAppSettings` (Open Settings buttons; leave it `nil` and they are hidden) and
`openPhotosApp` (the last-photo thumbnail's Open in Photos; leave it `nil` and a tap shows the
photo's details instead). Each `SavedPhoto` carries its `thumbnail` and `details` for your own
last-photo view.

## Rules that still apply

Your interface follows AGENTS.md like the standard one: native controls, Dynamic Type, VoiceOver
labels, 44-point touch targets, every string in a String Catalog in all eleven languages, and the
name written "nope.".

## Reference

- API: [`docs/api/NopeCore.md`](api/NopeCore.md)
- Architecture: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)
- Tests: [`docs/TESTING.md`](TESTING.md)
