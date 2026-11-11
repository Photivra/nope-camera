import NopeCore
import Testing

/// Compiles and runs the example in the "Building an interface" DocC article and
/// docs/BUILDING-AN-INTERFACE.md, so the example can't go stale. Keep them identical.
@MainActor
struct BuildingAnInterfaceExampleTests {
    /// A text-only interface: it renders the state as a sentence and sends intents.
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

    @Test func exampleInterfaceWalksThroughTheStates() async {
        let backend = SimulatedCaptureBackend(
            permission: .notDetermined,
            permissionAfterRequest: .authorized,
            capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, supportsBayerRAW: true)])
        )
        let interface = TextInterface(model: CameraModel(backend: backend))
        #expect(interface.render() == "Starting")
        await interface.appear()
        #expect(interface.render() == "Press Allow to use the camera")
        await interface.pressAllow()
        #expect(interface.render() == "1 lens(es)")
    }
}
