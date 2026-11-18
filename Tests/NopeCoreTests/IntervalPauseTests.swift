import Foundation
import Testing

@testable import NopeCore

/// Interval series count only the photos they take, pause while the app is out of the foreground
/// or the camera is paused, and continue afterwards; they start only when nothing else holds the
/// camera (issue #48).
@MainActor
struct IntervalPauseTests {
    /// A started camera whose interval sleeps wait for `ticker`, and whose pause after a failed
    /// photo ends at once unless `pauseAfterError` is given.
    func makeModel(
        ticker: Ticker, pauseAfterError: (@Sendable () async throws -> Void)? = nil
    ) async -> (CameraModel, PausingBackend, Task<Void, Never>) {
        let backend = PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in await ticker.sleep() },
            deviceStatusReader: FakeStatusReader(bytes: nil))
        model.pauseAfterErrorSleep = pauseAfterError ?? {}
        await model.send(.start)
        let events = Task { await model.observeEvents() }
        return (model, backend, events)
    }

    /// Starts a series of `count` photos, one minute apart.
    func startSeries(_ model: CameraModel, count: Int) async {
        await model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: count))))
        await model.send(.manual(.startInterval))
    }

    /// Lets the interval sleep go once one is waiting, waiting on the clock rather than a number
    /// of yields.
    func tick(_ ticker: Ticker) async {
        for _ in 0..<500 {
            if await ticker.pending > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        await ticker.tick()
    }

    func finish(_ backend: PausingBackend, _ events: Task<Void, Never>) async {
        backend.inner.finishEvents()
        await events.value
    }

    // MARK: - Pausing

    @Test func aCameraPauseHoldsThePhotoInsteadOfCountingIt() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        await startSeries(model, count: 3)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }

        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        #expect(model.manual.intervalProgress == IntervalProgress(taken: 1, total: 3, isPaused: true))
        #expect(await backend.captures == 1, "no photo is taken, or counted, while the camera is paused")
        #expect(
            model.liveActivityContent(continuing: .interval, isInForeground: true, now: Date())
                == LiveActivityContent(kind: .interval, phase: .paused, taken: 1, total: 3))

        backend.inner.emitEvent(.interruptionEnded)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        #expect(model.manual.intervalProgress?.isPaused == false)
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 3)
        await finish(backend, events)
    }

    @Test func leavingTheAppPausesTheSeriesUntilItIsBack() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        await startSeries(model, count: 2)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await model.send(.setInForeground(false))
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        #expect(await backend.captures == 1)

        await model.send(.setInForeground(true))
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 2)
        await finish(backend, events)
    }

    @Test func aStartWhileThePreviousPhotoSavesWaitsForIt() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        // The shutter's photo is still being saved when a hardware button starts the series.
        model.captureStatus = .saving
        await startSeries(model, count: 2)
        await settle()
        #expect(model.manual.intervalProgress == IntervalProgress(taken: 0, total: 2), "waiting, not paused")
        #expect(await backend.captures == 0)

        model.captureStatus = .idle
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(await backend.captures == 1)
        await model.send(.manual(.stopInterval))
        await finish(backend, events)
    }

    @Test func stoppingWhilePausedTakesNoMorePhotos() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        await startSeries(model, count: 3)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await model.send(.setInForeground(false))
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        await model.send(.manual(.stopInterval))
        #expect(model.manual.intervalProgress == nil)

        await model.send(.setInForeground(true))
        await settle()
        #expect(await backend.captures == 1)
        #expect(model.manual.intervalProgress == nil)
        await finish(backend, events)
    }

    @Test func aCameraThatStopsForGoodEndsThePausedSeries() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        await startSeries(model, count: 3)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        // A runtime error restarts the camera, which fails: the series ends with what it took.
        await backend.setStartError(.configurationFailed)
        backend.inner.emitEvent(.failed)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(model.manual.intervalProgress == nil)
        #expect(await backend.captures == 1)
        await finish(backend, events)
    }

    // MARK: - Failed photos

    @Test func aPhotoCutShortBeforeThePauseArrivesIsTakenAgain() async {
        let ticker = Ticker()
        let waits = WaitCounter()
        let (model, backend, events) = await makeModel(ticker: ticker) {
            await waits.add()
            try await Task.sleep(for: .seconds(60))
        }
        await backend.setOnCapture { number in number == 2 ? .notRunning : nil }
        await startSeries(model, count: 3)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await tick(ticker)
        // The second photo's error arrives first; the interruption comes while the model waits.
        await eventually { await waits.count == 1 }
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        #expect(model.manual.intervalProgress?.taken == 1)

        backend.inner.emitEvent(.interruptionEnded)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 4, "the cut-short photo is taken again")
        #expect(model.captureStatus != .failed(.notRunning))
        await finish(backend, events)
    }

    @Test func aFailedPhotoEndsTheSeriesWithoutCountingIt() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        await backend.setOnCapture { number in number == 2 ? .captureFailed : nil }
        await startSeries(model, count: 3)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(model.manual.intervalProgress == nil, "the series ends at the failed photo")
        #expect(model.captureStatus == .failed(.captureFailed))
        #expect(await backend.captures == 2)
        await finish(backend, events)
    }

    // MARK: - When a series can start

    @Test func astroOrABusyDriveBlocksTheStart() async {
        let ticker = Ticker()
        let (model, backend, events) = await makeModel(ticker: ticker)
        #expect(model.intervalBlocker == nil)

        await model.send(.astro(.setOn(true)))
        #expect(model.intervalBlocker == .astroIsOn)
        await startSeries(model, count: 3)
        #expect(model.manual.intervalProgress == nil)
        await model.send(.astro(.setOn(false)))

        await model.send(.drive(.startTimer(seconds: 3)))
        #expect(model.intervalBlocker == .driveIsBusy)
        await startSeries(model, count: 3)
        #expect(model.manual.intervalProgress == nil)
        await model.send(.drive(.cancelTimer))

        // Stopping is never blocked.
        await model.send(.manual(.stopInterval))
        #expect(await backend.captures == 0)
        await finish(backend, events)
    }

    @Test func listedChoicesIncludeTheValueInUse() {
        let standard = IntervalSettings.standard
        #expect(standard.intervalChoices == IntervalSettings.listedIntervals)
        #expect(standard.countChoices == IntervalSettings.listedCounts)
        let custom = IntervalSettings(interval: 7, count: 42)
        #expect(custom.intervalChoices == [1, 2, 3, 5, 7, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600])
        #expect(custom.countChoices == [2, 3, 5, 10, 20, 30, 42, 50, 100, 200, 500, 999])
        #expect(IntervalProgress(taken: 1, total: 3) != IntervalProgress(taken: 1, total: 3, isPaused: true))
    }
}

/// Counts calls from any task.
actor WaitCounter {
    private(set) var count = 0

    func add() {
        count += 1
    }
}

/// Waits on the clock, up to five seconds, until the asynchronous condition holds.
@MainActor
func eventually(_ condition: () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
