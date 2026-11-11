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
``CameraIntent/requestPermission`` only when the person presses a button. The model decides what
happens next.

### Test against a simulated backend

Create the model with a ``SimulatedCaptureBackend`` to drive every state without a camera:

```swift
let backend = SimulatedCaptureBackend(
    permission: .notDetermined,
    permissionAfterRequest: .authorized,
    capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, supportsBayerRAW: true)])
)
let interface = TextInterface(model: CameraModel(backend: backend))
```

In a SwiftUI interface, pass the model to your root view and read ``CameraModel/state`` in
`body`; observation updates the view when the state changes.
