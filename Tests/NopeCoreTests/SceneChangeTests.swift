import Foundation
import Testing

@testable import NopeCore

/// A light backend whose request to turn the torch off waits until the test lets it finish, so a
/// test can change the scene phase again while the light is still turning off.
actor GatedLightBackend: LightCaptureBackend {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil
    private nonisolated let continuation: AsyncStream<CaptureEvent>.Continuation
    let capabilities: DeviceCapabilities
    /// Whether a request to turn the torch off waits for ``openGate()``.
    private var holdsOff = false
    /// The waiting request to turn the torch off.
    private var waitingOff: CheckedContinuation<Void, Never>?

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
    }

    func holdNextOff() { holdsOff = true }
    var isHoldingOff: Bool { waitingOff != nil }
    func openGate() {
        waitingOff?.resume()
        waitingOff = nil
    }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { capabilities }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) {}
    func stopSession() async {}
    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        throw .captureFailed
    }

    func setTorch(level: Double?) async -> TorchStatus {
        guard let level else {
            if holdsOff {
                holdsOff = false
                await withCheckedContinuation { waitingOff = $0 }
            }
            return .off
        }
        return .on(level: level)
    }
}

/// Changes of the scene phase apply in the order they happened (final review of 1.0.0, S4).
@MainActor
struct SceneChangeTests {
    static func running() async -> (CameraModel, GatedLightBackend) {
        let backend = GatedLightBackend(capabilities: LightModelTests.lenses)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        return (model, backend)
    }

    @Test func goingToTheBackgroundTurnsTheLightOffAndComingBackIsInTheForeground() async {
        let (model, _) = await Self.running()
        await model.send(.light(.setTorch(true)))
        #expect(model.light.isTorchOn)
        await model.sceneDidChange(isInBackground: true)
        #expect(!model.light.isTorchOn)
        #expect(!model.isInForeground)
        await model.sceneDidChange(isInBackground: false)
        #expect(model.isInForeground)
    }

    @Test func aQuickReturnWhileTheLightTurnsOffEndsInTheForeground() async {
        let (model, backend) = await Self.running()
        await model.send(.light(.setTorch(true)))
        await backend.holdNextOff()
        let leaving = Task { await model.sceneDidChange(isInBackground: true) }
        while await !backend.isHoldingOff { await Task.yield() }
        // Back before the light is off: this change waits for the older one.
        let returning = Task { await model.sceneDidChange(isInBackground: false) }
        for _ in 0..<20 { await Task.yield() }
        #expect(model.isInForeground)
        await backend.openGate()
        await leaving.value
        await returning.value
        #expect(model.isInForeground)
        #expect(!model.light.isTorchOn)
    }
}
