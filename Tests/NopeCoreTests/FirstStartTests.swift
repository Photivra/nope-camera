import Foundation
import NopeCore
import Testing

/// `CameraModel.isFirstStart` (docs/design/LAUNCH-SCREEN.md, 6.3): `true` from creation, `false`
/// for good the first time the state or the camera's status says how the start went.
@MainActor
struct FirstStartTests {
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")
    static let tele = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, magnification: 5)
    static let oneLens = DeviceCapabilities(lenses: [wide])
    static let twoLenses = DeviceCapabilities(lenses: [wide, tele])

    @Test func aNewModelIsOnItsFirstStart() {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        #expect(model.isFirstStart)
    }

    @Test(arguments: [CameraPermission.notDetermined, .denied, .restricted])
    func aScreenBeforeTheCameraEndsIt(permission: CameraPermission) async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: permission, capabilities: Self.oneLens))
        await model.send(.start)
        #expect(!model.isFirstStart)
    }

    @Test func noCameraEndsIt() async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        await model.send(.start)
        #expect(model.state == .unavailable)
        #expect(!model.isFirstStart)
    }

    @Test func itLastsWhileTheCameraStartsAndEndsWhenItRuns() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        let duringStart = FirstStartRecorder()
        await backend.setOnStart { @MainActor in
            duringStart.record(model.isFirstStart, model.sessionStatus)
        }
        await model.send(.start)
        #expect(duringStart.isFirstStart == true)
        #expect(duringStart.sessionStatus == .starting)
        #expect(model.sessionStatus == .running)
        #expect(!model.isFirstStart)
    }

    @Test func aFailedStartEndsIt() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens, startErrors: [.configurationFailed])
        let model = CameraModel(backend: backend)
        await model.send(.start)
        #expect(model.sessionStatus == .failed(.configurationFailed))
        #expect(!model.isFirstStart)
    }

    @Test func anInterruptionWhileStartingEndsIt() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        backend.emit(.interrupted(.inUseElsewhere))
        backend.finish()
        await backend.setOnStart { await model.observeEvents() }
        await model.send(.start)
        #expect(model.sessionStatus == .interrupted(.inUseElsewhere))
        #expect(!model.isFirstStart)
    }

    @Test func aPauseForHeatEndsIt() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        backend.emit(.heat(.critical))
        backend.finish()
        await model.observeEvents()
        #expect(model.isFirstStart)
        await model.send(.start)
        #expect(model.sessionStatus == .pausedForHeat)
        #expect(!model.isFirstStart)
    }

    @Test func itStaysOverALaterStartAfterTheBackground() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        #expect(!model.isFirstStart)
        backend.emit(.interrupted(.backgrounded), .interruptionEnded)
        backend.finish()
        await model.observeEvents()
        #expect(model.sessionStatus == .running)
        #expect(!model.isFirstStart)
    }

    @Test func itStaysOverALensChangeAndARestart() async {
        let backend = ScriptedBackend(capabilities: Self.twoLenses)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        let duringLensChange = FirstStartRecorder()
        await backend.setOnStart { @MainActor in
            duringLensChange.record(model.isFirstStart, model.sessionStatus)
        }
        await model.send(.selectLens("tele"))
        #expect(duringLensChange.sessionStatus == .starting)
        #expect(duringLensChange.isFirstStart == false)
        // A runtime error restarts the camera.
        backend.emit(.failed)
        backend.finish()
        await model.observeEvents()
        #expect(await backend.startRequests.count == 3)
        #expect(!model.isFirstStart)
    }

    @Test func noRequestForPermissionYetKeepsItEndedAfterAccessIsAllowed() async {
        let backend = SimulatedCaptureBackend(
            permission: .notDetermined, permissionAfterRequest: .authorized, capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        #expect(!model.isFirstStart)
        await model.send(.requestPermission)
        #expect(model.sessionStatus == .running)
        #expect(!model.isFirstStart)
    }
}

/// Records what the model said while the backend was starting the camera.
@MainActor
final class FirstStartRecorder {
    /// ``CameraModel/isFirstStart`` during the start, or `nil` before it was recorded.
    private(set) var isFirstStart: Bool?

    /// ``CameraModel/sessionStatus`` during the start, or `nil` before it was recorded.
    private(set) var sessionStatus: SessionStatus?

    /// Records the two values.
    func record(_ isFirstStart: Bool, _ sessionStatus: SessionStatus) {
        self.isFirstStart = isFirstStart
        self.sessionStatus = sessionStatus
    }
}
