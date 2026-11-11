import NopeCore
import Testing

@MainActor
struct CameraModelTests {
    static let wideRAW = Lens(id: "wide", kind: .wide, supportsBayerRAW: true)
    static let oneLens = DeviceCapabilities(lenses: [wideRAW])

    @Test func startsInStartingState() {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        #expect(model.state == .starting)
    }

    @Test(arguments: [
        (CameraPermission.notDetermined, CameraState.needsPermission),
        (.denied, .permissionDenied),
        (.restricted, .permissionDenied),
    ])
    func startMapsPermissionToState(permission: CameraPermission, expected: CameraState) async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: permission, capabilities: Self.oneLens))
        await model.send(.start)
        #expect(model.state == expected)
    }

    @Test func authorizedWithCameraIsReady() async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized, capabilities: Self.oneLens))
        await model.send(.start)
        #expect(model.state == .ready(Self.oneLens))
    }

    @Test func authorizedWithoutCameraIsUnavailable() async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        await model.send(.start)
        #expect(model.state == .unavailable)
    }

    @Test func requestingPermissionUsesTheAnswer() async {
        let backend = SimulatedCaptureBackend(
            permission: .notDetermined, permissionAfterRequest: .authorized, capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        #expect(model.state == .needsPermission)
        await model.send(.requestPermission)
        #expect(model.state == .ready(Self.oneLens))
    }

    @Test func declinedRequestIsDenied() async {
        let backend = SimulatedCaptureBackend(permission: .notDetermined, permissionAfterRequest: .denied)
        let model = CameraModel(backend: backend)
        await model.send(.requestPermission)
        #expect(model.state == .permissionDenied)
    }
}
