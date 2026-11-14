import Foundation
import Testing

@testable import NopeCore

/// A manual backend that runs a hook before each photo and records each capture request, so a
/// test can act in the middle of an astro run.
actor HookedManualBackend: ManualCaptureBackend {
    nonisolated let inner: ScriptedManualBackend
    nonisolated var events: AsyncStream<CaptureEvent> { inner.events }
    nonisolated var exposureReadings: AsyncStream<ExposureReading> { inner.exposureReadings }
    nonisolated var previewSource: (any CameraPreviewSource)? { nil }
    private var onCapture: (@Sendable (Int) async -> Void)?
    private(set) var requests: [CaptureRequest] = []

    init(_ inner: ScriptedManualBackend) {
        self.inner = inner
    }

    func setOnCapture(_ hook: @escaping @Sendable (Int) async -> Void) {
        onCapture = hook
    }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { await inner.deviceCapabilities() }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) { try await inner.startSession(request) }
    func stopSession() async {}
    func applyControls(_ controls: DeviceControls) async throws(CaptureError) { try await inner.applyControls(controls) }
    func setExposureReadingsEnabled(_ enabled: Bool) async { await inner.setExposureReadingsEnabled(enabled) }

    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError) -> [CapturedPhoto] {
        try await inner.captureBracket(request, frames: frames)
    }

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        requests.append(request)
        await onCapture?(requests.count)
        return try await inner.capturePhoto(request)
    }
}

/// The astro helper through `CameraModel` (issue #60): availability, the starting exposure,
/// turning it on and off, the frame run and its stop conditions.
@MainActor
struct AstroTests {
    static let wide = ManualFixtures.wide
    static let basic = ManualFixtures.basicLens
    static let bare = ManualFixtures.bare

    func makeModel(
        lenses: [Lens] = [AstroTests.wide],
        saver: PhotoSaver? = CameraModelTests.saver(),
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in },
        reader: (any DeviceStatusReading)? = nil
    ) async -> (CameraModel, HookedManualBackend) {
        let backend = HookedManualBackend(ScriptedManualBackend(lenses: lenses))
        let model = CameraModel(backend: backend, saver: saver, sleep: sleep, deviceStatusReader: reader)
        await model.send(.start)
        return (model, backend)
    }

    /// Waits, for up to five seconds, until the run has ended: saving a frame does real work
    /// (read-back, thumbnails), which takes longer than a few thousand yields.
    func waitForRun(_ model: CameraModel) async {
        for _ in 0..<500 where model.astro.lastRun == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func savedCount(_ model: CameraModel) -> Int? {
        guard case .savedBurst(let photos) = model.captureStatus else { return nil }
        return photos.count
    }

    /// A lens like `wide` with one capability changed.
    func lens(
        raw: Bool = true, manualExposure: Bool = true, manualFocus: Bool = true, shutter: Bool = true, iso: Bool = true
    ) -> Lens {
        let full = ManualFixtures.full
        let controls = ManualCapabilities(
            supportsManualExposure: manualExposure, supportsShutterPriority: full.supportsShutterPriority,
            supportsISOPriority: full.supportsISOPriority, supportsAperturePriority: false,
            exposureCompensationRange: full.exposureCompensationRange, supportsExposureLock: true, supportsAutoFocus: true,
            supportsFocusLock: true, supportsManualFocus: manualFocus, supportsManualWhiteBalance: true,
            meteringModes: [.center])
        return Lens(
            id: "lens", kind: .wide, bayerRAWFormat: raw ? "bgg4" : nil, isoRange: iso ? 50...6400 : nil,
            exposureDurationRange: shutter ? 0.0001...1 : nil, manualControls: controls)
    }

    // MARK: - Values

    @Test func availabilityAndStartingExposure() {
        #expect(AstroModel.startingExposure(for: Self.wide) == AstroExposure(shutter: 1, iso: 6400, focus: 1))
        #expect(AstroModel.isAvailable(on: Self.wide))
        #expect(AstroModel.isAvailable(on: lens()))
        #expect(!AstroModel.isAvailable(on: Self.bare))
        #expect(!AstroModel.isAvailable(on: lens(raw: false)))
        #expect(!AstroModel.isAvailable(on: lens(manualExposure: false)))
        #expect(!AstroModel.isAvailable(on: lens(manualFocus: false)))
        #expect(!AstroModel.isAvailable(on: lens(shutter: false)))
        #expect(!AstroModel.isAvailable(on: lens(iso: false)))
    }

    @Test func estimates() {
        let estimate = AstroEstimate(frameCount: 20, shutter: 1, bytes: 2_000, framesThatFit: 30)
        #expect(estimate.totalExposureSeconds == 20)
        #expect(estimate.fits)
        #expect(!AstroEstimate(frameCount: 20, shutter: nil, bytes: 0, framesThatFit: 19).fits)
        #expect(AstroEstimate(frameCount: 20, shutter: nil, bytes: 0, framesThatFit: 19).totalExposureSeconds == nil)
        #expect(AstroEstimate(frameCount: 20, shutter: nil, bytes: 0, framesThatFit: nil).fits)
        let astro = AstroModel()
        astro.endRun(.stopped)
        #expect(astro.lastRun == BurstResult(end: .stopped, saved: 0))
    }

    @Test func batteryBelow() {
        func status(_ battery: BatteryReading?) -> DeviceStatus {
            let status = DeviceStatus(reader: FakeStatusReader(bytes: nil, battery: battery))
            status.refresh()
            return status
        }
        #expect(!status(nil).isBatteryBelow(0.1))
        #expect(!status(BatteryReading(level: nil, isCharging: false, isLowPowerMode: false)).isBatteryBelow(0.1))
        #expect(!status(BatteryReading(level: 0.05, isCharging: true, isLowPowerMode: false)).isBatteryBelow(0.1))
        #expect(!status(BatteryReading(level: 0.5, isCharging: false, isLowPowerMode: false)).isBatteryBelow(0.1))
        #expect(status(BatteryReading(level: 0.1, isCharging: false, isLowPowerMode: true)).isBatteryBelow(0.1))
    }

    // MARK: - On and off

    @Test func turningOnSetsUpTheCameraAndOffPutsItBack() async {
        let (model, _) = await makeModel()
        #expect(model.canUseAstro)
        #expect(model.astroEstimate == nil)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.isOn)
        #expect(model.drive.mode == .single)
        #expect(model.manual.isEnabled)
        #expect(model.manual.settings.focus == 1)
        #expect(model.manual.settings.shutter == 1)
        #expect(model.manual.settings.iso == 6400)
        #expect(model.manual.bracket == nil)
        // Turning it on again changes nothing.
        await model.send(.manual(.setValue(.iso, 800)))
        await model.send(.astro(.setOn(true)))
        #expect(model.manual.settings.iso == 800)
        await model.send(.astro(.setOn(false)))
        #expect(!model.astro.isOn)
        #expect(!model.manual.isEnabled)
        #expect(model.manual.settings == .automatic)
        // Off again, and Stop while off, do nothing.
        await model.send(.astro(.setOn(false)))
        await model.send(.astro(.stop))
        #expect(!model.astro.isOn)
    }

    @Test func manualControlsTheHelperDidNotTurnOnStayOn() async {
        let (model, _) = await makeModel()
        await model.send(.manual(.setEnabled(true)))
        await model.send(.astro(.setOn(true)))
        await model.send(.astro(.setOn(false)))
        #expect(model.manual.isEnabled)
        #expect(model.manual.settings.shutter == 1)
    }

    @Test func theManualControlsOptionWinsOverTheHelper() async {
        let (model, _) = await makeModel()
        await model.send(.astro(.setOn(true)))
        // The option turned on in Settings: the controls are now the person's.
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.iso, 400)))
        await model.send(.astro(.setOn(false)))
        #expect(model.manual.isEnabled)
        // Turning manual controls off turns the helper off.
        await model.send(.astro(.setOn(true)))
        await model.send(.manual(.setEnabled(false)))
        #expect(!model.astro.isOn)
        #expect(!model.manual.isEnabled)
    }

    @Test func refusedOnALensItCannotUseAndWhileBusy() async {
        let (bareModel, _) = await makeModel(lenses: [Self.bare])
        #expect(!bareModel.canUseAstro)
        await bareModel.send(.astro(.setOn(true)))
        #expect(!bareModel.astro.isOn)

        let ticker = Ticker()
        let (model, _) = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 3)))
        await model.send(.astro(.setOn(true)))
        #expect(!model.astro.isOn)
        await model.send(.drive(.cancelTimer))
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 && model.canCapture }
        await model.send(.astro(.setOn(true)))
        #expect(!model.astro.isOn)
        await model.send(.manual(.stopInterval))
    }

    @Test func notBeforeTheCameraIsReady() async {
        let model = CameraModel(backend: ScriptedManualBackend(lenses: [Self.wide]))
        #expect(!model.canUseAstro)
        await model.send(.astro(.setOn(true)))
        #expect(!model.astro.isOn)
    }

    @Test func theTorchStaysOff() async {
        let (model, _) = await makeModel()
        #expect(!model.astroRefuses(.setTorch(true)))
        await model.send(.astro(.setOn(true)))
        #expect(model.astroRefuses(.setTorch(true)))
        #expect(!model.astroRefuses(.setTorch(false)))
        await model.send(.light(.setTorch(true)))
        #expect(!model.light.isTorchOn)
    }

    @Test func lensChangesApplyTheNewLensOrTurnTheHelperOff() async {
        let (model, _) = await makeModel(lenses: [Self.wide, Self.basic, Self.bare])
        await model.send(.astro(.setOn(true)))
        await model.send(.selectLens(Self.basic.id))
        #expect(model.astro.isOn)
        #expect(model.manual.settings.iso == 3200)
        await model.send(.selectLens(Self.bare.id))
        #expect(!model.astro.isOn)
        // Without the helper, a lens change leaves it off.
        await model.send(.selectLens(Self.wide.id))
        #expect(!model.astro.isOn)
    }

    // MARK: - Settings and estimate

    @Test func frameCountAndDelay() async {
        let (model, _) = await makeModel(reader: FakeStatusReader(bytes: 10_000_000_000))
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.frameCount == AstroModel.defaultFrameCount)
        #expect(model.astro.startDelay == .tenSeconds)
        await model.send(.astro(.setFrameCount(7)))
        #expect(model.astro.frameCount == 20)
        await model.send(.astro(.setFrameCount(50)))
        await model.send(.astro(.setStartDelay(.threeSeconds)))
        #expect(model.astro.frameCount == 50)
        #expect(model.astro.startDelay == .threeSeconds)
        let perFrame = PhotoSizeEstimate.bytes(for: Self.wide, settings: model.saveSettings)
        let estimate = model.astroEstimate
        #expect(estimate?.frameCount == 50)
        #expect(estimate?.shutter == 1)
        #expect(estimate?.bytes == perFrame * 50)
        #expect(estimate?.framesThatFit == Int(10_000_000_000 / perFrame))
    }

    @Test func unknownStorageFits() async {
        let (model, _) = await makeModel()
        await model.send(.astro(.setOn(true)))
        #expect(model.astroEstimate?.framesThatFit == nil)
        #expect(model.astroEstimate?.fits == true)
    }

    // MARK: - Runs

    @Test func shutterCountsDownThenTakesEveryFrame() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.astro(.setOn(true)))
        await model.send(.astro(.setFrameCount(5)))
        await model.send(.astro(.setStartDelay(.threeSeconds)))
        await model.send(.capture)
        #expect(model.drive.countdown.remainingSeconds == 3)
        // Nothing changes while counting down.
        await model.send(.astro(.setFrameCount(10)))
        await model.send(.astro(.setStartDelay(.tenSeconds)))
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.frameCount == 5)
        #expect(model.astro.startDelay == .threeSeconds)
        for _ in 0..<3 {
            await tick(ticker)
        }
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .limitReached, saved: 5))
        #expect(model.astro.progress == nil)
        #expect(savedCount(model) == 5)
        let requests = await backend.requests
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.flashMode == .off && $0.format.isBayerRAW })
    }

    @Test func shutterOrStopCancelsTheCountdown() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.astro(.setOn(true)))
        await model.send(.capture)
        #expect(model.drive.countdown.isRunning)
        await model.send(.capture)
        #expect(!model.drive.countdown.isRunning)
        await model.send(.capture)
        await model.send(.astro(.stop))
        #expect(!model.drive.countdown.isRunning)
        await tick(ticker)
        await settle()
        #expect(await backend.requests.isEmpty)
    }

    @Test func stoppingKeepsTheFramesTaken() async {
        let (model, backend) = await makeModel()
        await model.send(.astro(.setOn(true)))
        await model.send(.astro(.setFrameCount(10)))
        await backend.setOnCapture { count in
            guard count == 3 else { return }
            await MainActor.run {
                #expect(model.astro.isRunning)
                #expect(model.canPressShutter)
                #expect(model.astro.progress?.taken == 2)
            }
            await model.send(.capture)
        }
        await model.send(.capture)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .stopped, saved: 3))
        #expect(savedCount(model) == 3)
    }

    @Test func turningOffStopsTheFrames() async {
        let (model, backend) = await makeModel()
        await model.send(.astro(.setOn(true)))
        await backend.setOnCapture { count in
            if count == 2 { await model.send(.astro(.setOn(false))) }
        }
        await model.send(.capture)
        await waitForRun(model)
        #expect(model.astro.lastRun?.end == .stopped)
        #expect(!model.astro.isOn)
    }

    @Test func lowBatteryStopsTheFrames() async {
        let low = BatteryReading(level: 0.05, isCharging: false, isLowPowerMode: false)
        let (model, backend) = await makeModel(reader: FakeStatusReader(bytes: nil, battery: low))
        await model.send(.astro(.setOn(true)))
        await model.send(.capture)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .batteryLow, saved: 0))
        #expect(await backend.requests.isEmpty)
        #expect(model.captureStatus == .idle)
    }

    @Test func fullStorageStopsTheFrames() async {
        let perFrame = PhotoSizeEstimate.bytes(for: Self.wide, settings: SaveSettings())
        let reader = FakeStatusReader(bytes: perFrame * 2)
        reader.shrinkPerRead = perFrame / 2
        let (model, _) = await makeModel(reader: reader)
        await model.send(.astro(.setOn(true)))
        await model.send(.capture)
        await waitForRun(model)
        #expect(model.astro.lastRun?.end == .storageFull)
    }

    @Test func noFramesWhileTheCameraIsPaused() async {
        let backend = ScriptedManualBackend(lenses: [Self.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: { _ in })
        await model.send(.start)
        await model.send(.astro(.setOn(true)))
        let events = Task { await model.observeEvents() }
        backend.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { !model.canCapture }
        await model.send(.capture)
        #expect(!model.drive.countdown.isRunning)
        backend.finishEvents()
        await events.value
    }

    @Test func withoutASaverNothingIsTaken() async {
        let (model, backend) = await makeModel(saver: nil)
        await model.send(.astro(.setOn(true)))
        await model.send(.capture)
        await waitUntil { model.captureStatus != .idle }
        #expect(model.captureStatus == .failed(.savingUnavailable))
        #expect(await backend.requests.isEmpty)
    }
}
