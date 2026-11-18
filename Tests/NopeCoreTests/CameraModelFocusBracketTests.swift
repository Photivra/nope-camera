import Foundation
import Testing

@testable import NopeCore

/// A manual backend that records the order of focus moves, control changes and photos, reports
/// each position a set amount short, and can fail a move or a photo.
actor FocusBackend: ManualCaptureBackend {
    nonisolated let inner: ScriptedManualBackend
    nonisolated var events: AsyncStream<CaptureEvent> { inner.events }
    nonisolated var exposureReadings: AsyncStream<ExposureReading> { inner.exposureReadings }
    nonisolated var previewSource: (any CameraPreviewSource)? { inner.previewSource }

    /// What happened, in order: "apply", "focus 0.50" and "capture".
    private(set) var log: [String] = []

    /// How far short of each position the lens stops.
    var shortfall = 0.0

    /// The move (from 1) that fails, or `nil`.
    var failingMove: Int?

    /// Runs before each photo and may fail it.
    private var onCapture: (@Sendable (Int) async -> CaptureError?)?

    private(set) var moves = 0
    private(set) var captures = 0

    init(_ inner: ScriptedManualBackend) {
        self.inner = inner
    }

    func setShortfall(_ value: Double) { shortfall = value }
    func setFailingMove(_ move: Int?) { failingMove = move }
    func setOnCapture(_ hook: @escaping @Sendable (Int) async -> CaptureError?) { onCapture = hook }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { await inner.deviceCapabilities() }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) {
        if let startError { throw startError }
        try await inner.startSession(request)
    }

    /// The error the next starts throw, or `nil`.
    private var startError: CaptureError?

    func setStartError(_ error: CaptureError?) { startError = error }
    func stopSession() async {}
    func setExposureReadingsEnabled(_ enabled: Bool) async { await inner.setExposureReadingsEnabled(enabled) }

    func applyControls(_ controls: DeviceControls) async throws(CaptureError) {
        log.append("apply")
        try await inner.applyControls(controls)
    }

    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError) -> [CapturedPhoto] {
        try await inner.captureBracket(request, frames: frames)
    }

    func setFocus(lensPosition: Double) async throws(CaptureError) -> Double {
        moves += 1
        log.append("focus \(lensPosition.formatted(.number.precision(.fractionLength(2))))")
        if moves == failingMove { throw .configurationFailed }
        return lensPosition - shortfall
    }

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        captures += 1
        log.append("capture")
        if let error = await onCapture?(captures) { throw error }
        return try await inner.capturePhoto(request)
    }
}

/// A manual backend without its own `setFocus`: it uses the protocol's default.
actor NoFocusBackend: ManualCaptureBackend {
    nonisolated let events = AsyncStream<CaptureEvent> { _ in }
    nonisolated let exposureReadings = AsyncStream<ExposureReading> { _ in }
    nonisolated var previewSource: (any CameraPreviewSource)? { nil }
    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { DeviceCapabilities(lenses: [ManualFixtures.wide]) }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) {}
    func stopSession() async {}
    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto { throw .captureFailed }
    func applyControls(_ controls: DeviceControls) async throws(CaptureError) {}
    func setExposureReadingsEnabled(_ enabled: Bool) async {}
    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError) -> [CapturedPhoto] {
        []
    }
}

/// Lenses for the focus bracket tests.
enum FocusFixtures {
    /// Every control, tap to focus included.
    static let tapCapabilities = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: true, supportsISOPriority: true,
        supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center], supportsFocusPoint: true)

    /// Manual focus only: no manual exposure or white balance; auto exposure can be locked or not.
    static func focusOnly(exposureLock: Bool) -> ManualCapabilities {
        ManualCapabilities(
            supportsManualExposure: false, supportsShutterPriority: false, supportsISOPriority: false,
            supportsAperturePriority: false, exposureCompensationRange: nil, supportsExposureLock: exposureLock,
            supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: false,
            meteringModes: [.center])
    }

    /// A lens that can take a focus bracket but no exposure bracket.
    static let tele = Lens(
        id: "tele", kind: .telephoto, bayerRAWFormat: "bgg4", isoRange: 50...3200, exposureDurationRange: 0.0001...1,
        aperture: .fixed(2.8), manualControls: tapCapabilities)

    /// A lens with manual focus and a locked auto exposure only.
    static let lockOnly = Lens(id: "lock", kind: .ultraWide, bayerRAWFormat: "rgg4", manualControls: focusOnly(exposureLock: true))

    /// A lens with manual focus and no exposure lock.
    static let noLock = Lens(id: "nolock", kind: .ultraWide, bayerRAWFormat: "rgg4", manualControls: focusOnly(exposureLock: false))
}

/// Focus bracketing (issue #90; docs/design/BRACKETING.md, section 8): the run, its stop and
/// pause rules, the restore, the range on the picture, the type and the shortcut.
@MainActor
struct CameraModelFocusBracketTests {
    /// A ready model on `lenses`, with the focus bracket on, no start delay and `frames` frames.
    func makeModel(
        lenses: [Lens] = [ManualFixtures.wide, ManualFixtures.bare], frames: Int = 3,
        reader: FakeStatusReader = FakeStatusReader(bytes: nil), saver: PhotoSaver? = CameraModelTests.saver(),
        previewSource: (any CameraPreviewSource)? = nil, sleep: @escaping @Sendable (Double) async throws -> Void = { _ in },
        turnOn: Bool = true
    ) async -> (CameraModel, FocusBackend) {
        let backend = FocusBackend(ScriptedManualBackend(lenses: lenses, previewSource: previewSource))
        let model = CameraModel(backend: backend, saver: saver, sleep: sleep, deviceStatusReader: reader)
        model.pauseAfterErrorSleep = {}
        await model.send(.start)
        await model.send(.bracket(.setFocus(FocusBracketSettings(nearest: 0.2, farthest: 0.6, frameCount: frames))))
        await model.send(.bracket(.setFocusStartDelay(nil)))
        if turnOn {
            await model.send(.bracket(.setType(.focus)))
            await model.send(.bracket(.setOn(true)))
        }
        return (model, backend)
    }

    /// Delivers readings to the model, as the camera does.
    func deliver(_ readings: ExposureReading..., to model: CameraModel, from backend: FocusBackend) async {
        for reading in readings { backend.inner.emit(reading) }
        backend.inner.finishReadings()
        await model.manual.observeReadings()
    }

    // MARK: - Turning it on

    @Test func bracketTurnsOnTheTypeChosenAndTheShutterTakesTheFrames() async {
        let (model, backend) = await makeModel()
        #expect(model.isFocusBracketOn)
        #expect(model.isBracketOn)
        #expect(model.manual.bracket == nil)
        #expect(model.drive.mode == .single)
        #expect(!model.shutterUsesFlash)
        await model.send(.capture)
        let log = await backend.log
        // Lock first, then for each frame: move, wait for the handler, take the photo.
        #expect(log == ["apply", "focus 0.20", "capture", "focus 0.40", "capture", "focus 0.60", "capture", "apply"])
        guard case .savedBracket(let photos) = model.captureStatus else {
            Issue.record("no bracket saved")
            return
        }
        #expect(photos.map(\.bracket?.focus?.plannedPosition) == [0.2, 0.4, 0.6])
        #expect(photos.map(\.bracket?.number) == [1, 2, 3])
        #expect(photos.allSatisfy { $0.bracket?.type == .focus && $0.bracket?.count == 3 })
        #expect(model.lastPressPhotos.count == 3)
        #expect(model.bracketing.lastRun == FocusBracketResult(end: .limitReached, saved: 3, total: 3, offPlan: 0, focusAfter: .automatic))
        #expect(model.bracketing.progress == nil)
        #expect(model.bracketing.running == nil)
        #expect(!model.manual.holdsControls)
    }

    @Test func theFramesAreTakenFarthestFirstWhenAsked() async {
        let (model, backend) = await makeModel()
        await model.send(.bracket(.setFocus(model.bracketing.focus.with(order: .farthestFirst))))
        await model.send(.capture)
        #expect(await backend.log.filter { $0.hasPrefix("focus") } == ["focus 0.60", "focus 0.40", "focus 0.20"])
    }

    @Test func exposureAndWhiteBalanceAreHeldAtTheReadingAndRestored() async {
        let (model, backend) = await makeModel()
        await deliver(ManualFixtures.reading, to: model, from: backend)
        await model.send(.capture)
        let applied = await backend.inner.applied
        let held = applied[applied.count - 2]
        #expect(held.exposure == .custom(iso: .value(200), duration: .value(0.01), aperture: .current, compensation: 0))
        #expect(held.whiteBalance == .fixed(WhiteBalance(temperature: 4000, tint: 10)))
        #expect(held.focus == .lensPosition(0.2))
        #expect(applied.last?.focus == .automatic)
        #expect(applied.last?.exposure == .automatic(compensation: 0))
    }

    @Test func aLensWithoutManualExposureLocksAutoExposure() async {
        let (model, backend) = await makeModel(lenses: [FocusFixtures.lockOnly])
        await model.send(.capture)
        let applied = await backend.inner.applied
        #expect(applied.first?.exposure == .locked)
        let (other, otherBackend) = await makeModel(lenses: [FocusFixtures.noLock])
        await other.send(.capture)
        #expect(await otherBackend.inner.applied.first?.exposure == .automatic(compensation: 0))
    }

    @Test func theRunHoldsTheLensTheLevelAndTheShutter() async {
        // Two rear lenses, so a pinch could switch lenses before and after the run.
        let (model, backend) = await makeModel(lenses: [ManualFixtures.wide, FocusFixtures.tele])
        #expect(model.pinchSwitchesLenses(setting: .switchLenses))
        let seen = SeenDuringCapture()
        await backend.setOnCapture { _ in
            await seen.record(model)
            return nil
        }
        await model.send(.capture)
        #expect(await seen.lensBlocker == .runningSeries)
        #expect(await seen.holdsLevelTap == true)
        #expect(await seen.canPressShutter == true)
        #expect(await seen.isFinishingPhotos == true)
        #expect(await seen.content?.kind == .focusBracket)
        #expect(await seen.content?.phase == .running)
        #expect(await seen.watchBusy == true)
        #expect(await seen.pinchSwitchesLenses == false)
        #expect(await seen.keepsScreenForSeries == true)
        #expect(model.pinchSwitchesLenses(setting: .switchLenses))
        #expect(!model.keepsScreenForSeries)
    }

    /// The screen during a focus bracket follows the one keeper rule for a series: kept awake
    /// and dimmed with Keep Screen On on or off, the series winning, and a screen already at
    /// 10% or darker left alone (issue #99).
    @Test func aFocusBracketKeepsTheScreenAsASeries() async {
        let keepScreenOn = KeepScreenOnConditions(
            isSwitchOn: true, isActive: true, isCameraInFront: true, isCameraRunning: true, isBatteryLow: false,
            isLowPowerMode: false)
        for (brightness, conditions) in [(0.8, keepScreenOn), (0.8, KeepScreenOnConditions.off), (0.05, keepScreenOn)] {
            let (model, backend) = await makeModel()
            let screen = FakeScreen(brightness: brightness)
            let keeper = SeriesScreenKeeper(screen: screen)
            keeper.update(isSeriesRunning: model.keepsScreenForSeries, isInForeground: true, keepScreenOn: conditions)
            #expect(!keeper.isDimmed)
            let seen = SeenScreen()
            await backend.setOnCapture { _ in
                await MainActor.run {
                    keeper.update(isSeriesRunning: model.keepsScreenForSeries, isInForeground: true, keepScreenOn: conditions)
                }
                await seen.record(keeper: keeper, screen: screen)
                return nil
            }
            await model.send(.capture)
            #expect(await seen.isKeepingAwake == true)
            #expect(await seen.isDimmed == (brightness > SeriesScreenKeeper.dimmedBrightness))
            #expect(await seen.brightness == min(brightness, SeriesScreenKeeper.dimmedBrightness))
            keeper.update(isSeriesRunning: model.keepsScreenForSeries, isInForeground: true, keepScreenOn: conditions)
            #expect(screen.brightness == brightness)
            #expect(keeper.isKeepingAwake == conditions.isUsed)
        }
    }

    @Test func returnFocusOffKeepsTheLastPosition() async {
        let (model, backend) = await makeModel()
        await model.send(.bracket(.setFocus(model.bracketing.focus.with(returnsFocus: false))))
        await model.send(.capture)
        #expect(model.bracketing.lastRun?.focusAfter == .stays(0.6))
        #expect(await backend.inner.applied.last?.focus == .lensPosition(0.6))
        // With manual controls on, the position becomes the focus set by hand.
        await model.send(.manual(.setEnabled(true)))
        await model.send(.capture)
        #expect(model.manual.settings.focus == 0.6)
        #expect(model.bracketing.lastRun?.focusAfter == .stays(0.6))
    }

    @Test func returnFocusOnGoesBackToTheFocusSetByHand() async {
        let (model, _) = await makeModel()
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.focus, 0.9)))
        await model.send(.capture)
        #expect(model.bracketing.lastRun?.focusAfter == .returned(0.9))
        #expect(model.manual.settings.focus == 0.9)
    }

    @Test func aLensThatStopsShortIsCountedAndShowsBothValues() async {
        let (model, backend) = await makeModel()
        await backend.setShortfall(0.05)
        await model.send(.capture)
        #expect(model.bracketing.lastRun?.offPlan == 3)
        guard case .savedBracket(let photos) = model.captureStatus else {
            Issue.record("no bracket saved")
            return
        }
        #expect(abs((photos.first?.bracket?.focus?.reportedPosition ?? 0) - 0.15) < 1e-9)
        #expect(photos.first?.bracket?.focus?.plannedPosition == 0.2)
    }

    // MARK: - Stopping

    @Test func theShutterStopsAfterTheCurrentFrameAndKeepsEveryPhoto() async {
        let (model, backend) = await makeModel(frames: 5)
        await backend.setOnCapture { count in
            if count == 2 { await model.send(.capture) }
            return nil
        }
        await model.send(.capture)
        #expect(await backend.captures == 2)
        #expect(model.bracketing.lastRun?.end == .stopped)
        #expect(model.bracketing.lastRun?.saved == 2)
        #expect(model.lastPressPhotos.count == 2)
    }

    @Test func theStopIntentStopsTheRun() async {
        let (model, backend) = await makeModel(frames: 5)
        await backend.setOnCapture { count in
            if count == 1 { await model.send(.bracket(.stop)) }
            return nil
        }
        await model.send(.capture)
        #expect(model.bracketing.lastRun?.saved == 1)
    }

    @Test func storageAndBatteryStopTheRunBeforeAFrame() async {
        let full = FakeStatusReader(bytes: 0)
        let (model, _) = await makeModel(reader: full)
        await model.send(.capture)
        #expect(model.bracketing.lastRun?.end == .storageFull)
        #expect(model.captureStatus == .idle)
        let low = FakeStatusReader(bytes: nil, battery: BatteryReading(level: 0.05, isCharging: false, isLowPowerMode: false))
        let (other, _) = await makeModel(reader: low)
        await other.send(.capture)
        #expect(other.bracketing.lastRun?.end == .batteryLow)
    }

    @Test func aFailedFrameStopsTheRunAndLastPhotoShowsTheNewestSaved() async {
        let (model, backend) = await makeModel(frames: 5)
        await backend.setOnCapture { count in count == 3 ? .captureFailed : nil }
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.captureFailed))
        #expect(model.bracketing.lastRun?.end == .failed)
        #expect(model.bracketing.lastRun?.saved == 2)
        #expect(model.lastPressPhotos.count == 2)
        #expect(model.lastPressPhotos.last?.bracket?.number == 2)
        #expect(!model.manual.holdsControls)
    }

    @Test func aMoveTheCameraRefusesStopsTheRun() async {
        let (model, backend) = await makeModel()
        await backend.setFailingMove(2)
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.configurationFailed))
        #expect(model.bracketing.lastRun?.saved == 1)
    }

    @Test func aSaveThatFailsStopsTheRun() async {
        let library = FakeLibrary(error: .savingUnavailable)
        let (model, _) = await makeModel(saver: CameraModelTests.saver(library: library))
        await model.send(.capture)
        #expect(model.bracketing.lastRun?.end == .failed)
        #expect(model.bracketing.lastRun?.saved == 0)
    }

    @Test func aCameraThatFailsWhilePausedStopsTheRun() async {
        let (model, backend) = await makeModel(frames: 3)
        let events = Task { await model.observeEvents() }
        await backend.setOnCapture { count in
            if count == 1 { await model.send(.setInForeground(false)) }
            return nil
        }
        let run = Task { await model.send(.capture) }
        await waitUntil { model.bracketing.progress?.isPaused == true }
        // The camera fails to start again while the app is away.
        await backend.setStartError(.configurationFailed)
        backend.inner.emitEvent(.failed)
        await waitUntil { model.sessionStatus == .failed(.configurationFailed) }
        await model.send(.setInForeground(true))
        await run.value
        events.cancel()
        #expect(model.bracketing.lastRun?.end == .cameraStopped)
        #expect(model.bracketing.lastRun?.saved == 1)
    }

    @Test func noPipelineOrNoLensTakesNothing() async {
        let (model, _) = await makeModel(saver: nil)
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.savingUnavailable))
        #expect(model.bracketing.lastRun == nil)
        let (other, _) = await makeModel()
        await other.send(.selectLens(ManualFixtures.bare.id))
        #expect(!other.isFocusBracketOn)
        #expect(await other.takeFocusBracket(.standard) == false)
    }

    // MARK: - Pausing

    @Test func theRunPausesWhenTheAppLeavesAndContinuesOnReturn() async {
        let (model, backend) = await makeModel(frames: 3)
        await backend.setOnCapture { count in
            if count == 1 {
                await model.send(.setInForeground(false))
            }
            return nil
        }
        let run = Task { await model.send(.capture) }
        await waitUntil { model.bracketing.progress?.isPaused == true }
        #expect(model.liveActivityContent(continuing: nil, isInForeground: false, now: Date())?.phase == .paused)
        #expect(!model.isFinishingPhotos)
        await model.send(.setInForeground(true))
        await run.value
        #expect(model.bracketing.lastRun?.saved == 3)
        // The controls are held again after the pause: a second lock before frame 2.
        #expect(await backend.log.filter { $0 == "apply" }.count == 3)
    }

    @Test func aFrameCutShortByAPauseIsTakenAgain() async {
        let (model, backend) = await makeModel(frames: 3)
        await backend.setOnCapture { count in
            guard count == 1 else { return nil }
            await model.send(.setInForeground(false))
            return .notRunning
        }
        let run = Task { await model.send(.capture) }
        await waitUntil { model.bracketing.progress?.isPaused == true }
        await model.send(.setInForeground(true))
        await run.value
        #expect(model.bracketing.lastRun?.saved == 3)
        #expect(await backend.captures == 4)
    }

    @Test func stoppingWhilePausedEndsTheRun() async {
        let (model, backend) = await makeModel(frames: 3)
        await backend.setOnCapture { count in
            if count == 1 { await model.send(.setInForeground(false)) }
            return nil
        }
        let run = Task { await model.send(.capture) }
        await waitUntil { model.bracketing.progress?.isPaused == true }
        await model.send(.capture)
        await run.value
        #expect(model.bracketing.lastRun?.end == .stopped)
        #expect(model.bracketing.lastRun?.saved == 1)
    }

    @Test func theStartDelayCountsDownAgainAfterAPause() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(frames: 2, sleep: { seconds in
            if seconds >= 1 { await ticker.sleep() }
        })
        await model.send(.bracket(.setFocusStartDelay(.threeSeconds)))
        await backend.setOnCapture { count in
            if count == 1 { await model.send(.setInForeground(false)) }
            return nil
        }
        await model.send(.capture)
        #expect(model.drive.countdown.isRunning)
        for _ in 0..<3 {
            await waitForTicker(ticker)
            await ticker.tick()
        }
        await waitUntil { model.bracketing.progress?.isPaused == true }
        // Back in the app: the start delay counts down again, and the shutter then stops it.
        await model.send(.setInForeground(true))
        await waitUntil { model.drive.countdown.isRunning }
        #expect(model.drive.countdown.isRunning)
        await model.send(.capture)
        await waitUntil { model.bracketing.lastRun != nil }
        #expect(model.bracketing.lastRun?.end == .stopped)
    }

    /// Waits until a sleep is waiting on the ticker.
    func waitForTicker(_ ticker: Ticker) async {
        for _ in 0..<500 where await ticker.pending == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - The countdown

    @Test func theStartDelayCountsDownAndTheShutterCancelsIt() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { seconds in
            if seconds >= 1 { await ticker.sleep() }
        })
        await model.send(.bracket(.setFocusStartDelay(.threeSeconds)))
        await model.send(.capture)
        #expect(model.drive.countdown.remainingSeconds == 3)
        await model.send(.capture)
        #expect(!model.drive.countdown.isRunning)
        #expect(await backend.captures == 0)
        await model.send(.capture)
        // The cancelled countdown's sleep may still wait on the ticker; tick until the run ends.
        for _ in 0..<10 where model.bracketing.lastRun == nil {
            await waitForTicker(ticker)
            await ticker.tick()
            await settle()
        }
        await waitUntil { model.bracketing.lastRun != nil }
        #expect(model.bracketing.lastRun?.saved == 3)
    }

    @Test func theShutterDoesNothingWhileTheCameraCantTakeAPhoto() async {
        let (model, backend) = await makeModel()
        model.captureStatus = .saving
        await model.pressFocusBracketShutter()
        #expect(await backend.captures == 0)
    }

    // MARK: - Type, strip and other modes

    @Test func theTypeSwitchesTheBracketThatIsOn() async {
        let (model, _) = await makeModel(turnOn: false)
        #expect(model.bracketing.type == .exposure)
        await model.send(.bracket(.setOn(true)))
        #expect(model.manual.bracket == .standard)
        #expect(!model.isFocusBracketOn)
        await model.send(.bracket(.setType(.focus)))
        #expect(model.isFocusBracketOn)
        #expect(model.manual.bracket == nil)
        await model.send(.bracket(.setType(.exposure)))
        #expect(!model.isFocusBracketOn)
        #expect(model.manual.bracket == .standard)
        #expect(model.bracketing.type == .exposure)
        await model.send(.bracket(.setOn(false)))
        #expect(!model.isBracketOn)
        await model.send(.bracket(.setOn(false)))
        #expect(!model.isBracketOn)
    }

    @Test func aLensThatCantFocusBracketOffersOnlyExposure() async {
        let (model, _) = await makeModel(lenses: [ManualFixtures.basicLens.withoutManualFocus], turnOn: false)
        #expect(!model.canFocusBracket)
        #expect(model.canExposureBracket)
        await model.send(.bracket(.setType(.focus)))
        #expect(model.bracketing.type == .exposure)
        await model.send(.bracket(.setOn(true)))
        #expect(model.manual.bracket != nil)
    }

    @Test func aLensThatOnlyFocusBracketsTurnsFocusOn() async {
        let (model, _) = await makeModel(lenses: [FocusFixtures.tele], turnOn: false)
        #expect(!model.canExposureBracket)
        #expect(model.offersBracket)
        await model.send(.bracket(.setType(.exposure)))
        #expect(model.bracketing.type == .exposure)
        await model.send(.bracket(.setOn(true)))
        #expect(model.isFocusBracketOn)
        #expect(model.bracketing.type == .focus)
    }

    @Test func nothingIsOfferedBeforeTheCameraIsReady() async {
        let backend = FocusBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        #expect(!model.canFocusBracket)
        #expect(model.focusBracketStorageBytes == nil)
    }

    @Test func noLensBracketsWithoutAManualBackend() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: DeviceCapabilities(lenses: [ManualFixtures.bare])), saver: CameraModelTests.saver())
        await model.send(.start)
        #expect(!model.canFocusBracket)
        #expect(!model.offersBracket)
        await model.send(.bracket(.setOn(true)))
        #expect(!model.isBracketOn)
        #expect(model.focusBracketStorageBytes != nil)
    }

    @Test func otherModesAndAstroTurnTheFocusBracketOff() async {
        let (model, _) = await makeModel()
        await model.send(.drive(.setMode(.burst)))
        #expect(!model.isFocusBracketOn)
        await model.send(.bracket(.setOn(true)))
        await model.send(.astro(.setOn(true)))
        #expect(!model.bracketing.isFocusOn)
        await model.send(.astro(.setOn(false)))
        await model.send(.bracket(.setOn(true)))
        await model.send(.drive(.setMode(.single)))
        #expect(model.isFocusBracketOn)
        await model.send(.manual(.setBracket(.standard)))
        #expect(!model.bracketing.isFocusOn)
        #expect(model.manual.bracket == .standard)
    }

    @Test func aLensWithoutManualFocusTurnsTheFocusBracketOff() async {
        let (model, _) = await makeModel()
        await model.send(.selectLens(ManualFixtures.bare.id))
        #expect(!model.bracketing.isFocusOn)
        #expect(model.drive.mode == .single)
    }

    @Test func settingsAreIgnoredWhileTheRunGoes() async {
        let (model, backend) = await makeModel(frames: 3)
        await backend.setOnCapture { count in
            if count == 1 {
                await model.send(.bracket(.setFocus(.standard)))
                await model.send(.bracket(.setFocusStartDelay(.tenSeconds)))
                await model.send(.bracket(.useWholeRange))
                await model.send(.bracket(.setType(.exposure)))
                await model.send(.bracket(.setOn(false)))
                await model.send(.bracket(.beginSettingRange(.nearest)))
                await model.send(.selectLens(ManualFixtures.bare.id))
            }
            return nil
        }
        await model.send(.capture)
        #expect(model.bracketing.focus.frameCount == 3)
        #expect(model.bracketing.focusStartDelay == nil)
        #expect(model.isFocusBracketOn)
        #expect(model.selectedLensID == ManualFixtures.wide.id)
        #expect(model.bracketing.rangeEditing == nil)
    }

    @Test func theStorageEstimateIsForEveryFrame() async {
        let (model, _) = await makeModel(frames: 10)
        let lens = ManualFixtures.wide
        #expect(model.focusBracketStorageBytes == PhotoSizeEstimate.bytes(for: lens, settings: model.saveSettings) * 10)
        await model.send(.bracket(.useWholeRange))
        #expect(model.bracketing.focus.isWholeRange)
    }

    // MARK: - The range on the picture

    @Test func anEndIsSetWithTheSliderAndKeptOrCancelled() async {
        let (model, backend) = await makeModel()
        await model.send(.bracket(.beginSettingRange(.nearest)))
        #expect(model.bracketing.rangeEditing == FocusRangeEditing(end: .nearest, value: 0.2))
        #expect(model.manual.holdsControls)
        await model.send(.bracket(.beginSettingRange(.farthest)))
        #expect(model.bracketing.rangeEditing?.end == .nearest)
        await model.send(.bracket(.setRangeValue(0.333)))
        #expect(model.focusRangeValue == 0.33)
        await model.send(.bracket(.setRangeValue(2)))
        #expect(model.focusRangeValue == 1)
        await model.send(.bracket(.setRangeValue(0.05)))
        await model.send(.bracket(.finishSettingRange(keeps: true)))
        #expect(model.bracketing.focus.nearest == 0.05)
        #expect(model.bracketing.rangeEditing == nil)
        #expect(!model.manual.holdsControls)
        #expect(await backend.log.contains("focus 0.33"))
        // Farthest, cancelled: the range stays.
        await model.send(.bracket(.beginSettingRange(.farthest)))
        #expect(model.focusRangeValue == 0.6)
        await model.send(.bracket(.setRangeValue(0.9)))
        await model.send(.bracket(.finishSettingRange(keeps: false)))
        #expect(model.bracketing.focus.farthest == 0.6)
        // Farthest set below the nearest: the two swap.
        await model.send(.bracket(.beginSettingRange(.farthest)))
        await model.send(.bracket(.setRangeValue(0.01)))
        await model.send(.bracket(.finishSettingRange(keeps: true)))
        #expect(model.bracketing.focus.nearest == 0.01)
        #expect(model.bracketing.focus.farthest == 0.05)
    }

    @Test func settingTheRangeEndsWhenTheFocusBracketGoesOrTheLensChanges() async {
        let (model, _) = await makeModel(lenses: [ManualFixtures.wide, FocusFixtures.tele])
        await model.send(.bracket(.beginSettingRange(.nearest)))
        await model.send(.bracket(.setRangeValue(0.4)))
        await model.send(.selectLens(FocusFixtures.tele.id))
        #expect(model.bracketing.rangeEditing == nil)
        #expect(!model.manual.holdsControls)
        #expect(model.bracketing.focus.nearest == 0.2)
        #expect(model.isFocusBracketOn)
        await model.send(.bracket(.beginSettingRange(.farthest)))
        await model.send(.bracket(.setRangeValue(0.9)))
        await model.send(.capture)
        #expect(model.bracketing.rangeEditing == nil)
        #expect(model.bracketing.focus.farthest == 0.6)
        #expect(model.bracketing.lastRun?.saved == 3)
        await model.send(.bracket(.beginSettingRange(.farthest)))
        await model.send(.drive(.setMode(.burst)))
        #expect(model.bracketing.rangeEditing == nil)
        #expect(!model.manual.holdsControls)
    }

    @Test func endingOrMovingWithoutARangeDoesNothing() async {
        let (model, backend) = await makeModel()
        await model.send(.bracket(.setRangeValue(0.5)))
        await model.send(.bracket(.finishSettingRange(keeps: true)))
        await model.send(.bracket(.focusRange(at: .center)))
        #expect(await backend.moves == 0)
        #expect(model.focusRangeValue == nil)
        let (off, _) = await makeModel(lenses: [ManualFixtures.bare])
        await off.send(.bracket(.beginSettingRange(.nearest)))
        #expect(off.bracketing.rangeEditing == nil)
    }

    @Test func aTapOnThePictureFocusesOnceAndTheValueFollowsTheLens() async {
        let (model, backend) = await makeModel(lenses: [FocusFixtures.tele])
        await model.send(.bracket(.beginSettingRange(.farthest)))
        await model.send(.auto(.focusAndExpose(at: FramePoint(x: 0.3, y: 0.4))))
        #expect(model.bracketing.rangeEditing?.followsLens == true)
        let applied = await backend.inner.applied
        #expect(applied.last?.focus == .automatic)
        #expect(applied.last?.pointOfInterest == DeviceControls.PointOfInterest(
            point: FramePoint(x: 0.3, y: 0.4), focuses: true, exposes: false, locks: true))
        // No reading yet: the value is the slider's.
        #expect(model.focusRangeValue == 0.6)
        await deliver(ManualFixtures.reading, to: model, from: backend)
        #expect(model.focusRangeValue == 0.8)
        await model.send(.bracket(.finishSettingRange(keeps: true)))
        #expect(model.bracketing.focus.farthest == 0.8)
    }

    @Test func aTapIsIgnoredWithoutTapToFocusOrAViewfinder() async {
        let (model, backend) = await makeModel()
        await model.send(.bracket(.beginSettingRange(.nearest)))
        await model.send(.bracket(.focusRange(at: .center)))
        #expect(model.bracketing.rangeEditing?.followsLens == false)
        let (hidden, hiddenBackend) = await makeModel(
            lenses: [FocusFixtures.tele], previewSource: FixedPreviewSource(result: nil))
        await hidden.send(.bracket(.beginSettingRange(.nearest)))
        await hidden.send(.bracket(.focusRange(at: .center)))
        #expect(hidden.bracketing.rangeEditing?.followsLens == false)
        #expect(await backend.inner.applied.allSatisfy { $0.pointOfInterest == nil })
        #expect(await hiddenBackend.inner.applied.allSatisfy { $0.pointOfInterest == nil })
    }

    @Test func aBackendWithoutFocusRefusesEveryMove() async throws {
        let backend = NoFocusBackend()
        await #expect(throws: CaptureError.configurationFailed) { _ = try await backend.setFocus(lensPosition: 0.5) }
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        model.pauseAfterErrorSleep = {}
        await model.send(.start)
        await model.send(.bracket(.setType(.focus)))
        await model.send(.bracket(.setFocusStartDelay(nil)))
        await model.send(.bracket(.setOn(true)))
        await model.send(.bracket(.beginSettingRange(.nearest)))
        await model.send(.bracket(.finishSettingRange(keeps: false)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.configurationFailed))
    }

    @Test func theSimulatedLensStopsShortAsScripted() async throws {
        let exact = SimulatedCaptureBackend(permission: .authorized)
        #expect(try await exact.setFocus(lensPosition: 0.4) == 0.4)
        let short = SimulatedCaptureBackend(permission: .authorized, focusShortfall: 0.5)
        #expect(try await short.setFocus(lensPosition: 0.4) == 0)
        let failing = SimulatedCaptureBackend(permission: .authorized, captureError: .captureFailed)
        await #expect(throws: CaptureError.captureFailed) { _ = try await failing.setFocus(lensPosition: 0.4) }
    }

    // MARK: - Presets, Live Activity and Shortcuts

    @Test func aPresetStoresAndAppliesTheFocusBracket() async throws {
        let (model, _) = await makeModel()
        let setup = model.cameraSetup
        #expect(setup.focusBracket == model.bracketing.focus)
        let data = try JSONEncoder().encode(setup)
        let decoded = try JSONDecoder().decode(CameraSetup.self, from: data)
        #expect(decoded.focusBracket == setup.focusBracket)
        let (other, _) = await makeModel(turnOn: false)
        _ = await other.applyCameraSetup(decoded, manualControlsOn: false)
        #expect(other.isFocusBracketOn)
        #expect(other.bracketing.focus == setup.focusBracket)
        #expect(CameraSetup.factory.focusBracket == nil)
    }

    @Test func theLiveActivityEndsAsTheRunDid() async {
        let (model, backend) = await makeModel(frames: 3)
        let running = LiveActivityContent(kind: .focusBracket, phase: .running, taken: 1, total: 3, saved: 1)
        #expect(model.liveActivityOutcome(after: running).phase == .stopped)
        await model.send(.capture)
        #expect(model.liveActivityOutcome(after: running).phase == .finished)
        #expect(model.liveActivityOutcome(after: running).saved == 3)
        await backend.setOnCapture { $0 == 4 ? .captureFailed : nil }
        await model.send(.capture)
        #expect(model.liveActivityOutcome(after: running).phase == .failed)
        await backend.setOnCapture { count in
            if count == 6 { await model.send(.capture) }
            return nil
        }
        await model.send(.capture)
        #expect(model.liveActivityOutcome(after: running).phase == .stopped)
        #expect(running.statusLine == .frame(number: 2, total: 3))
        var paused = running
        paused.phase = .paused
        #expect(paused.statusLine == .framesPaused(taken: 1, total: 3))
        paused.phase = .stopped
        #expect(paused.statusLine == .stoppedPhotosSaved(1))
        #expect(!running.canStop)
    }

    @Test func takeBracketWithTypeFocusTakesOneFocusBracket() async {
        let (model, backend) = await makeModel(turnOn: false)
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let request = BracketShortcut(type: .focus, focusFrameCount: 5, focusRange: .wholeRange, frameCount: 3, step: 1)
        let outcome = await model.perform(.takeBracket(request), inbox: inbox, settings: nil, presets: nil)
        #expect(outcome == .savedSeveral(count: 5, allSigned: false))
        #expect(outcome.photosSaved == 5)
        #expect(await backend.captures == 5)
        #expect(await backend.log.first(where: { $0.hasPrefix("focus") }) == "focus 0.00")
        // The app's own bracket is unchanged.
        #expect(!model.isFocusBracketOn)
        #expect(model.bracketing.focus.frameCount == 3)
    }

    @Test func takeBracketWithTypeFocusAsSetAfterADelay() async {
        let (model, backend) = await makeModel(turnOn: false)
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let request = BracketShortcut(type: .focus, focusFrameCount: 3, frameCount: 3, step: 1, delaySeconds: 3)
        let outcome = await model.perform(.takeBracket(request), inbox: inbox, settings: nil, presets: nil)
        #expect(outcome == .savedSeveral(count: 3, allSigned: false))
        #expect(await backend.log.first(where: { $0.hasPrefix("focus") }) == "focus 0.20")
    }

    @Test func takeBracketWithTypeFocusReportsAStopAndAMissingFocus() async {
        let (model, backend) = await makeModel(reader: FakeStatusReader(bytes: 0), turnOn: false)
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let request = BracketShortcut(type: .focus, focusFrameCount: 3, frameCount: 3, step: 1)
        #expect(await model.perform(.takeBracket(request), inbox: inbox, settings: nil, presets: nil) == .focusBracketStopped(saved: 0, total: 3))
        #expect(await backend.captures == 0)
        let (other, otherBackend) = await makeModel(turnOn: false)
        await otherBackend.setOnCapture { _ in .captureFailed }
        #expect(await other.perform(.takeBracket(request), inbox: inbox, settings: nil, presets: nil) == .notSaved(.captureFailed))
        let (bare, _) = await makeModel(lenses: [ManualFixtures.bare], turnOn: false)
        #expect(await bare.perform(.takeBracket(request), inbox: inbox, settings: nil, presets: nil) == .focusBracketUnavailable)
        #expect(WatchResult(ShortcutOutcome.focusBracketUnavailable) == .notSaved)
        #expect(WatchResult(ShortcutOutcome.focusBracketStopped(saved: 1, total: 3)) == .notSaved)
    }

    @Test func takeBracketWithTypeFocusIsBusyDuringACountdown() async {
        let (model, _) = await makeModel(sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        await model.send(.bracket(.setFocusStartDelay(.tenSeconds)))
        await model.send(.capture)
        let request = BracketShortcut(type: .focus, frameCount: 3, step: 1)
        #expect(await model.perform(.takeBracket(request), inbox: ShortcutInbox(sleep: ShortcutTests.neverTimesOut), settings: nil, presets: nil) == .busy)
        let delayed = BracketShortcut(type: .focus, frameCount: 3, step: 1, delaySeconds: 3)
        model.drive.countdown.cancel()
        let task = Task { await model.perform(.takeBracket(delayed), inbox: ShortcutInbox(sleep: ShortcutTests.neverTimesOut), settings: nil, presets: nil) }
        await waitUntil { model.drive.countdown.isRunning }
        model.drive.countdown.cancel()
        #expect(await task.value == .cancelled)
    }
}

/// What a test sees about the model while a frame is taken.
actor SeenDuringCapture {
    private(set) var lensBlocker: LensChangeBlocker?
    private(set) var holdsLevelTap: Bool?
    private(set) var canPressShutter: Bool?
    private(set) var isFinishingPhotos: Bool?
    private(set) var content: LiveActivityContent?
    private(set) var watchBusy: Bool?
    private(set) var pinchSwitchesLenses: Bool?
    private(set) var keepsScreenForSeries: Bool?

    func record(_ model: CameraModel) async {
        let values = await MainActor.run {
            (
                model.lensChangeBlocker, model.holdsBackLevelTap, model.canPressShutter, model.isFinishingPhotos,
                model.liveActivityContent(continuing: nil, isInForeground: true, now: Date()), model.isRunningSeries,
                model.pinchSwitchesLenses(setting: .switchLenses), model.keepsScreenForSeries
            )
        }
        (
            lensBlocker, holdsLevelTap, canPressShutter, isFinishingPhotos, content, watchBusy, pinchSwitchesLenses,
            keepsScreenForSeries
        ) = values
    }
}

/// What a test sees about the screen while a frame is taken.
actor SeenScreen {
    private(set) var isKeepingAwake: Bool?
    private(set) var isDimmed: Bool?
    private(set) var brightness: Double?

    func record(keeper: SeriesScreenKeeper, screen: FakeScreen) async {
        let values = await MainActor.run { (keeper.isKeepingAwake, keeper.isDimmed, screen.brightness) }
        (isKeepingAwake, isDimmed, brightness) = values
    }
}

extension Lens {
    /// This lens with manual focus taken away.
    var withoutManualFocus: Lens {
        let controls = manualControls
        return Lens(
            id: id, kind: kind, bayerRAWFormat: bayerRAWFormat, isoRange: isoRange,
            exposureDurationRange: exposureDurationRange, aperture: aperture, maxBracketedPhotoCount: maxBracketedPhotoCount,
            manualControls: ManualCapabilities(
                supportsManualExposure: controls.supportsManualExposure,
                supportsShutterPriority: controls.supportsShutterPriority, supportsISOPriority: controls.supportsISOPriority,
                supportsAperturePriority: controls.supportsAperturePriority,
                exposureCompensationRange: controls.exposureCompensationRange,
                supportsExposureLock: controls.supportsExposureLock, supportsAutoFocus: controls.supportsAutoFocus,
                supportsFocusLock: controls.supportsFocusLock, supportsManualFocus: false,
                supportsManualWhiteBalance: controls.supportsManualWhiteBalance, meteringModes: controls.meteringModes))
    }
}
