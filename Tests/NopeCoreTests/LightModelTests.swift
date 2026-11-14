import Foundation
import Testing

@testable import NopeCore

/// A light backend that records every torch request and answers from a script.
actor ScriptedLightBackend: LightCaptureBackend {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil
    private nonisolated let continuation: AsyncStream<CaptureEvent>.Continuation
    let capabilities: DeviceCapabilities
    /// Whether the system allows the torch.
    private var available = true
    private(set) var torchRequests: [Double?] = []
    private(set) var captureRequests: [CaptureRequest] = []

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
    }

    nonisolated func emit(_ event: CaptureEvent) { continuation.yield(event) }
    nonisolated func finish() { continuation.finish() }
    func setAvailable(_ isAvailable: Bool) { available = isAvailable }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { capabilities }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) {}
    func stopSession() async {}

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        captureRequests.append(request)
        throw .captureFailed
    }

    func setTorch(level: Double?) async -> TorchStatus {
        torchRequests.append(level)
        guard let level else { return .off }
        return available ? .on(level: level) : .unavailable
    }
}

@MainActor
struct LightModelTests {
    static let wide = Lens(
        id: "wide", kind: .wide, bayerRAWFormat: "bgg4", flashModes: [.on, .off, .auto], hasTorch: true)
    static let ultraWide = Lens(id: "ultra", kind: .ultraWide, bayerRAWFormat: "rgg4")
    static let tele = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, hasTorch: true)
    static let lenses = DeviceCapabilities(lenses: [ultraWide, wide, tele])

    static func running() async -> (CameraModel, ScriptedLightBackend) {
        let backend = ScriptedLightBackend(capabilities: lenses)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        return (model, backend)
    }

    @Test func defaults() {
        let light = LightModel(backend: nil)
        #expect(light.flashMode == .off)
        #expect(light.torchLevel == LightModel.defaultTorchLevel)
        #expect(light.torch == .off)
        #expect(!light.supportsTorch)
        #expect(!light.supportsFlash)
        #expect(light.supportedFlashModes.isEmpty)
        #expect(!light.isTorchOn)
        #expect(light.flashModeForCapture == .off)
        #expect(LightModel.torchLevels.allSatisfy(LightModel.torchLevelRange.contains))
        #expect(LightModel.torchLevelRange.contains(LightModel.defaultTorchLevel))
    }

    @Test func applyingWithoutABackendDoesNothing() async {
        let light = LightModel(backend: nil)
        await light.applyTorch()
        #expect(light.torch == .off)
    }

    @Test(arguments: [(-1.0, 0.01), (0.0, 0.01), (0.5, 0.5), (2.0, 1.0)])
    func levelsStayInRange(level: Double, expected: Double) {
        #expect(LightModel.clampedTorchLevel(level) == expected)
    }

    @Test func lensCapabilitiesInDisplayOrder() async {
        let (model, _) = await Self.running()
        #expect(model.light.supportsTorch)
        #expect(model.light.supportsFlash)
        #expect(model.light.supportedFlashModes == [.off, .auto, .on])
        await model.send(.selectLens("ultra"))
        #expect(!model.light.supportsTorch)
        #expect(!model.light.supportsFlash)
    }

    @Test func withoutALightBackendThereIsNoTorch() async {
        let backend = SimulatedCaptureBackend(permission: .authorized, capabilities: Self.lenses)
        let model = CameraModel(backend: ScriptedBackend(capabilities: Self.lenses))
        await model.send(.start)
        #expect(!model.light.supportsTorch)
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .off)
        // The simulated backend has one.
        let simulated = CameraModel(backend: backend)
        await simulated.send(.start)
        #expect(simulated.light.supportsTorch)
    }

    @Test func torchTurnsOnAtTheLevelAndOff() async {
        let (model, backend) = await Self.running()
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .on(level: 0.25))
        #expect(model.light.isTorchOn)
        await model.send(.light(.setTorchLevel(0.75)))
        #expect(model.light.torch == .on(level: 0.75))
        await model.send(.light(.setTorch(false)))
        #expect(model.light.torch == .off)
        // Turning off when already off asks nothing.
        await model.send(.light(.setTorch(false)))
        #expect(await backend.torchRequests == [0.25, 0.75, nil])
    }

    @Test func levelWhileOffIsKeptForLater() async {
        let (model, backend) = await Self.running()
        await model.send(.light(.setTorchLevel(5)))
        #expect(model.light.torchLevel == 1)
        #expect(await backend.torchRequests.isEmpty)
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .on(level: 1))
    }

    @Test func torchOnALensWithoutOneIsIgnored() async {
        let (model, backend) = await Self.running()
        await model.send(.selectLens("ultra"))
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .off)
        #expect(await backend.torchRequests.isEmpty)
    }

    @Test func torchBeforeTheCameraRunsWaitsForTheStart() async {
        let backend = ScriptedLightBackend(capabilities: Self.lenses)
        let model = CameraModel(backend: backend)
        await model.light.handle(.setTorch(true))
        #expect(model.light.torch == .off)
        await model.send(.start)
        // No lens yet when asked, so nothing was wanted.
        #expect(model.light.torch == .off)
        // Asked between the lens choice and the start: applied once running.
        model.light.lensWillStart(Self.wide)
        await model.light.handle(.setTorch(true))
        #expect(await backend.torchRequests.isEmpty)
        await model.light.sessionDidStart()
        #expect(model.light.torch == .on(level: 0.25))
    }

    @Test func torchFollowsLensSwitches() async {
        let (model, backend) = await Self.running()
        await model.send(.light(.setTorch(true)))
        // Another lens with a torch: the light comes back on there.
        await model.send(.selectLens("tele"))
        #expect(model.light.torch == .on(level: 0.25))
        // A lens without one: off, and it stays off back on a lens with a torch.
        await model.send(.selectLens("ultra"))
        #expect(model.light.torch == .off)
        await model.send(.selectLens("wide"))
        #expect(model.light.torch == .off)
        #expect(await backend.torchRequests == [0.25, 0.25])
    }

    @Test func interruptionAndHeatTurnTheTorchOff() async {
        let (model, backend) = await Self.running()
        await model.send(.light(.setTorch(true)))
        backend.emit(.interrupted(.inUseElsewhere))
        backend.emit(.interruptionEnded)
        backend.emit(.heat(.critical))
        backend.finish()
        await model.observeEvents()
        #expect(model.light.torch == .off)
        #expect(await backend.torchRequests == [0.25, nil])
    }

    @Test func pauseWithTheTorchOffAsksNothing() async {
        let (model, backend) = await Self.running()
        await model.light.cameraDidPause()
        #expect(await backend.torchRequests.isEmpty)
    }

    @Test func refusedTorchIsReportedUntilTurnedOff() async {
        let (model, backend) = await Self.running()
        await backend.setAvailable(false)
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .unavailable)
        #expect(!model.light.isTorchOn)
        // A restart keeps the report; the light isn't retried by itself.
        await model.send(.selectLens("tele"))
        #expect(model.light.torch == .unavailable)
        await model.send(.light(.setTorch(false)))
        #expect(model.light.torch == .off)
        #expect(await backend.torchRequests == [0.25])
    }

    @Test func systemTakingTheLightAwayIsReported() async {
        let (model, backend) = await Self.running()
        // Nothing to report while the light is off.
        model.light.systemMadeTorchUnavailable()
        #expect(model.light.torch == .off)
        await model.send(.light(.setTorch(true)))
        backend.emit(.torchUnavailable)
        backend.finish()
        await model.observeEvents()
        #expect(model.light.torch == .unavailable)
        // Trying again asks the hardware again.
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .on(level: 0.25))
    }

    @Test func flashModeForTheNextPhoto() async {
        let (model, backend) = await Self.running()
        await model.send(.light(.setFlashMode(.auto)))
        #expect(model.light.flashModeForCapture == .auto)
        await model.send(.capture)
        #expect(await backend.captureRequests.last?.flashMode == .auto)
        // The torch replaces the flash.
        await model.send(.light(.setTorch(true)))
        #expect(model.light.flashModeForCapture == .off)
        await model.send(.capture)
        #expect(await backend.captureRequests.last?.flashMode == .off)
        // A lens without a flash: off, but the choice is kept.
        await model.send(.selectLens("ultra"))
        #expect(model.light.flashModeForCapture == .off)
        #expect(model.light.flashMode == .auto)
    }

    @Test func choosingAFlashTurnsTheTorchOff() async {
        let (model, _) = await Self.running()
        await model.send(.light(.setTorch(true)))
        await model.send(.light(.setFlashMode(.off)))
        #expect(model.light.isTorchOn)
        await model.send(.light(.setFlashMode(.on)))
        #expect(!model.light.isTorchOn)
        #expect(model.light.flashModeForCapture == .on)
    }

    @Test func simulatedBackendTorch() async {
        let on = SimulatedCaptureBackend(permission: .authorized)
        #expect(await on.setTorch(level: 0.5) == .on(level: 0.5))
        #expect(await on.setTorch(level: nil) == .off)
        let hot = SimulatedCaptureBackend(permission: .authorized, torchAvailable: false)
        #expect(!hot.torchAvailable)
        #expect(await hot.setTorch(level: 0.5) == .unavailable)
    }

    @Test func requestsCarryTheFlashMode() {
        #expect(CaptureRequest(lens: Self.wide).flashMode == .off)
        #expect(CaptureRequest(lens: Self.wide, flashMode: .on).flashMode == .on)
        #expect(CaptureRequest(lens: Self.wide, format: .processedFallback(.heif)).flashMode == .off)
        #expect(Self.wide.hasTorch && !Self.ultraWide.hasTorch)
        #expect(Self.ultraWide.flashModes.isEmpty)
    }
}

@MainActor
struct NightAndLightSettingsTests {
    @Test func defaults() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.flashMode == .off)
        #expect(settings.torchLevel == LightModel.defaultTorchLevel)
        #expect(!settings.isNightModeOn)
        #expect(!settings.tintsViewfinderInNightMode)
    }

    @Test func changesAreRemembered() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setFlashMode(.auto)
        settings.setTorchLevel(3)
        settings.setNightMode(true)
        settings.setTintsViewfinderInNightMode(true)
        #expect(settings.torchLevel == 1)
        let reloaded = NopeSettings(defaults: scratch.defaults)
        #expect(reloaded.flashMode == .auto)
        #expect(reloaded.torchLevel == 1)
        #expect(reloaded.isNightModeOn)
        #expect(reloaded.tintsViewfinderInNightMode)
        reloaded.setNightMode(false)
        #expect(!NopeSettings(defaults: scratch.defaults).isNightModeOn)
    }

    @Test func unreadableValuesFallBack() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("strobe", forKey: NopeSettings.Key.flashMode)
        scratch.defaults.set(-4.0, forKey: NopeSettings.Key.torchLevel)
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.flashMode == .off)
        #expect(settings.torchLevel == LightModel.torchLevelRange.lowerBound)
    }
}
