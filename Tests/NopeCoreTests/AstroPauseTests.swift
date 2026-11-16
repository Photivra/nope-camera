import Foundation
import Testing

@testable import NopeCore

/// A manual backend that runs a hook before each photo, which may fail the photo, so a test can
/// leave the app or pause the camera in the middle of an astro run.
actor PausingBackend: ManualCaptureBackend {
    nonisolated let inner: ScriptedManualBackend
    nonisolated var events: AsyncStream<CaptureEvent> { inner.events }
    nonisolated var exposureReadings: AsyncStream<ExposureReading> { inner.exposureReadings }
    nonisolated var previewSource: (any CameraPreviewSource)? { nil }
    private var onCapture: (@Sendable (Int) async -> CaptureError?)?
    private(set) var captures = 0
    var startError: CaptureError?

    init(_ inner: ScriptedManualBackend) {
        self.inner = inner
    }

    func setOnCapture(_ hook: @escaping @Sendable (Int) async -> CaptureError?) {
        onCapture = hook
    }

    func setStartError(_ error: CaptureError?) {
        startError = error
    }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { await inner.deviceCapabilities() }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) {
        if let startError { throw startError }
        try await inner.startSession(request)
    }
    func stopSession() async {}
    func applyControls(_ controls: DeviceControls) async throws(CaptureError) { try await inner.applyControls(controls) }
    func setExposureReadingsEnabled(_ enabled: Bool) async { await inner.setExposureReadingsEnabled(enabled) }

    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError) -> [CapturedPhoto] {
        try await inner.captureBracket(request, frames: frames)
    }

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        captures += 1
        if let error = await onCapture?(captures) { throw error }
        return try await inner.capturePhoto(request)
    }
}

/// Astro runs pause when the app leaves the foreground or the camera pauses, and continue after
/// the start delay when both are back (issue #64, owner decision).
@MainActor
struct AstroPauseTests {
    func makeModel(
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in },
        reader: FakeStatusReader = FakeStatusReader(bytes: nil), saver: PhotoSaver = CameraModelTests.saver()
    ) async -> (CameraModel, PausingBackend) {
        let backend = PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        let model = CameraModel(backend: backend, saver: saver, sleep: sleep, deviceStatusReader: reader)
        await model.send(.start)
        await model.send(.astro(.setOn(true)))
        await model.send(.astro(.setFrameCount(5)))
        await model.send(.astro(.setStartDelay(.threeSeconds)))
        return (model, backend)
    }

    func waitForRun(_ model: CameraModel) async {
        for _ in 0..<500 where model.astro.lastRun == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilPaused(_ model: CameraModel) async {
        for _ in 0..<500 where !model.astro.isPaused {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Waits until the model has applied an interruption.
    nonisolated func waitForInterruption(_ model: CameraModel) async {
        for _ in 0..<10_000 {
            if await model.sessionStatus != .running { return }
            await Task.yield()
        }
    }

    /// Lets the oldest sleep go once one is waiting. It waits on the clock, up to five seconds,
    /// rather than a number of yields, so a busy test runner can't make it tick too early and
    /// lose the tick.
    func tickWhenWaiting(_ ticker: Ticker) async {
        for _ in 0..<500 {
            if await ticker.pending > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        await ticker.tick()
    }

    /// Ticks until the running countdown has ended. A cancelled countdown can leave a sleep
    /// waiting on the ticker; a tick that only lets that one go changes nothing, and the next
    /// tick reaches the running countdown.
    func countDown(_ ticker: Ticker, _ model: CameraModel) async {
        await waitFor { model.drive.countdown.isRunning }
        for _ in 0..<20 where model.drive.countdown.isRunning {
            let before = model.drive.countdown.remainingSeconds
            await tickWhenWaiting(ticker)
            await waitFor { model.drive.countdown.remainingSeconds != before }
        }
    }

    /// Waits on the clock, up to five seconds, until the condition holds.
    func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Countdown.run

    @Test func countdownRunWaitsForZeroOrCancel() async {
        let ticker = Ticker()
        let countdown = Countdown(sleep: { _ in await ticker.sleep() })
        #expect(await countdown.run(seconds: 0))

        let firing = Task { await countdown.run(seconds: 2) }
        await waitFor { countdown.isRunning }
        #expect(await countdown.run(seconds: 5) == false, "another countdown is running")
        await tickWhenWaiting(ticker)
        await tickWhenWaiting(ticker)
        #expect(await firing.value)

        let cancelled = Task { await countdown.run(seconds: 3) }
        await waitFor { countdown.isRunning }
        countdown.cancel()
        #expect(await cancelled.value == false)
        await tickWhenWaiting(ticker)
    }

    // MARK: - Leaving and coming back

    @Test func leavingCancelsTheSelfTimerButNotAstro() async {
        let ticker = Ticker()
        let (model, _) = await makeModel(sleep: { _ in await ticker.sleep() })
        #expect(model.isInForeground)
        await model.send(.astro(.setOn(false)))
        await model.send(.drive(.startTimer(seconds: 3)))
        await model.send(.setInForeground(false))
        #expect(!model.isInForeground)
        #expect(!model.drive.countdown.isRunning)
        await model.send(.setInForeground(true))

        // Astro on with nothing running: leaving changes nothing.
        await model.send(.astro(.setOn(true)))
        await model.send(.setInForeground(false))
        #expect(!model.astro.isRunning)
        await model.send(.setInForeground(true))
    }

    @Test func leavingDuringTheStartDelayStartsTheRunPaused() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.capture)
        #expect(model.drive.countdown.isRunning)
        await model.send(.setInForeground(false))
        #expect(model.astro.isRunning, "begun at once, so it reads as paused")
        await waitUntilPaused(model)
        #expect(model.astro.progress == BurstProgress(taken: 0, saved: 0))
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: false, now: Date())
                == LiveActivityContent(kind: .astro, phase: .paused, total: 5))
        #expect(!model.isFinishingPhotos)

        await model.send(.setInForeground(true))
        await waitFor { model.drive.countdown.isRunning }
        #expect(!model.astro.isPaused)
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .limitReached, saved: 5))
        #expect(await backend.captures == 5)
    }

    @Test func leavingMidRunPausesAndComingBackContinues() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await backend.setOnCapture { number in
            // The app leaves while the third frame is being taken; the frame is cut short.
            guard number == 3 else { return nil }
            await model.send(.setInForeground(false))
            return .captureFailed
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        #expect(model.astro.progress == BurstProgress(taken: 2, saved: 2), "every frame taken is saved before the pause")
        #expect(
            model.liveActivityContent(continuing: .astro, isInForeground: false, now: Date())
                == LiveActivityContent(kind: .astro, phase: .paused, taken: 2, total: 5, saved: 2))
        #expect(!model.isFinishingPhotos)
        #expect(model.astro.lastRun == nil)

        await model.send(.setInForeground(true))
        await waitFor { model.drive.countdown.isRunning }
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .limitReached, saved: 5))
        #expect(await backend.captures == 6, "the cut-short frame is taken again")
    }

    @Test func aCameraPauseInTheForegroundPausesTheRun() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        let events = Task { await model.observeEvents() }
        await backend.setOnCapture { number in
            guard number == 2 else { return nil }
            backend.inner.emitEvent(.interrupted(.inUseElsewhere))
            await waitForInterruption(model)
            return .notRunning
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        #expect(model.astro.progress?.taken == 1)
        #expect(
            model.liveActivityContent(continuing: .astro, isInForeground: true, now: Date())?.phase == .paused)
        backend.inner.emitEvent(.interruptionEnded)
        await waitFor { model.drive.countdown.isRunning }
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .limitReached, saved: 5))
        backend.inner.finishEvents()
        await events.value
    }

    @Test func stoppingWhilePausedKeepsTheFramesTaken() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await backend.setOnCapture { number in
            if number == 2 { await model.send(.setInForeground(false)) }
            return nil
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        #expect(model.astro.progress?.taken == 2)
        await model.send(.astro(.stop))
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .stopped, saved: 2))
        #expect(!model.astro.isPaused)
    }

    @Test func stoppingDuringTheResumeDelayStopsTheRun() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await backend.setOnCapture { number in
            if number == 2 { await model.send(.setInForeground(false)) }
            return nil
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        await model.send(.setInForeground(true))
        await waitFor { model.drive.countdown.isRunning }
        // The shutter stops the run and its countdown.
        await model.send(.capture)
        #expect(!model.drive.countdown.isRunning)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .stopped, saved: 2))
        #expect(await backend.captures == 2)
    }

    @Test func resumingChecksStorageAgain() async {
        let ticker = Ticker()
        let reader = FakeStatusReader(bytes: 10_000_000_000)
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() }, reader: reader)
        await backend.setOnCapture { number in
            if number == 2 { await model.send(.setInForeground(false)) }
            return nil
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        reader.bytes = 0
        await model.send(.setInForeground(true))
        await waitFor { model.drive.countdown.isRunning }
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .storageFull, saved: 2))
    }

    @Test func aCameraThatStopsForGoodEndsThePausedRun() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        let events = Task { await model.observeEvents() }
        await backend.setOnCapture { number in
            guard number == 2 else { return nil }
            backend.inner.emitEvent(.interrupted(.inUseElsewhere))
            await waitForInterruption(model)
            return .notRunning
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        // A runtime error restarts the camera, which fails: no countdown, the run ends.
        await backend.setStartError(.configurationFailed)
        backend.inner.emitEvent(.failed)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .cameraStopped, saved: 1))
        #expect(!model.drive.countdown.isRunning)
        backend.inner.finishEvents()
        await events.value
    }

    @Test func aSaveThatFailsBeforeThePauseEndsTheRun() async {
        let ticker = Ticker()
        let saver = PhotoSaver(
            developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: FailingLibrary(failingAdd: 2),
            appVersion: "0.2.0")
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() }, saver: saver)
        await backend.setOnCapture { number in
            // The app leaves while the second frame is taken; its save, collected before the
            // pause, fails.
            if number == 2 { await model.send(.setInForeground(false)) }
            return nil
        }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .failed, saved: 1))
        #expect(!model.astro.isPaused)
        await model.send(.setInForeground(true))
    }

    @Test func aFrameErrorThatArrivesBeforeThePauseStillPauses() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        let waits = WaitCounter()
        model.pauseAfterErrorSleep = {
            await waits.add()
            try await Task.sleep(for: .seconds(60))
        }
        let events = Task { await model.observeEvents() }
        // The second frame's error arrives before the camera says it was interrupted.
        await backend.setOnCapture { number in number == 2 ? .notRunning : nil }
        await model.send(.capture)
        await countDown(ticker, model)
        await eventually { await waits.count == 1 }
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntilPaused(model)
        #expect(model.astro.progress == BurstProgress(taken: 1, saved: 1))
        #expect(model.astro.lastRun == nil, "the run waits instead of failing")

        backend.inner.emitEvent(.interruptionEnded)
        await waitFor { model.drive.countdown.isRunning }
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .limitReached, saved: 5))
        #expect(await backend.captures == 6, "the cut-short frame is taken again")
        backend.inner.finishEvents()
        await events.value
    }

    @Test func aFailedFrameInTheForegroundStillEndsTheRun() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        await backend.setOnCapture { number in number == 2 ? .captureFailed : nil }
        await model.send(.capture)
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .failed, saved: 1))
    }

    @Test func aRunCanStartWhileTheCameraIsPaused() async {
        let ticker = Ticker()
        let (model, backend) = await makeModel(sleep: { _ in await ticker.sleep() })
        let events = Task { await model.observeEvents() }
        await model.send(.capture)
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitFor { model.sessionStatus == .interrupted(.inUseElsewhere) }
        #expect(!model.canCapture)
        await countDown(ticker, model)
        await waitUntilPaused(model)
        #expect(model.astro.progress == BurstProgress(taken: 0, saved: 0))
        backend.inner.emitEvent(.interruptionEnded)
        await waitFor { model.drive.countdown.isRunning }
        await countDown(ticker, model)
        await waitForRun(model)
        #expect(model.astro.lastRun == BurstResult(end: .limitReached, saved: 5))
        backend.inner.finishEvents()
        await events.value
    }

    @Test func whenTheRunPauses() async {
        let (model, _) = await makeModel()
        #expect(!model.seriesShouldPause)
        model.setInForeground(false)
        #expect(model.seriesShouldPause)
        model.setInForeground(true)
        let stopped = CameraModel(backend: PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide])))
        #expect(!stopped.seriesShouldPause)
        // The canStop and status line of a paused astro run.
        let paused = LiveActivityContent(kind: .astro, phase: .paused, taken: 4, total: 20)
        #expect(paused.canStop)
        #expect(paused.statusLine == .framesPaused(taken: 4, total: 20))
        #expect(LiveActivityContent(kind: .astro, phase: .running).canStop)
        #expect(!LiveActivityContent(kind: .burst, phase: .running).canStop)
    }
}
