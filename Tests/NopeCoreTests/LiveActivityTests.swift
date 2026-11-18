import Foundation
import Testing

@testable import NopeCore

/// Records what the coordinator asks of the Live Activity.
@MainActor
final class FakeLiveActivities: LiveActivityPresenting {
    var areActivitiesEnabled = true
    var acceptsStart = true
    private(set) var started: [LiveActivityContent] = []
    private(set) var updates: [LiveActivityContent] = []
    private(set) var ends: [(content: LiveActivityContent, dismissal: LiveActivityDismissal)] = []

    func start(_ content: LiveActivityContent) -> Bool {
        started.append(content)
        return acceptsStart
    }

    func update(_ content: LiveActivityContent) {
        updates.append(content)
    }

    func end(_ content: LiveActivityContent, dismissal: LiveActivityDismissal) {
        ends.append((content, dismissal))
    }
}

/// Records requests for time to finish saving.
@MainActor
final class FakeBackgroundTime: BackgroundTimeRequesting {
    var grants = true
    private(set) var begun = 0
    private(set) var ended = 0
    private(set) var onExpiration: (@MainActor () -> Void)?

    func beginBackgroundTime(onExpiration: @escaping @MainActor () -> Void) -> Bool {
        begun += 1
        self.onExpiration = onExpiration
        return grants
    }

    func endBackgroundTime() {
        ended += 1
    }

    /// Runs out of time, as the system does.
    func expire() {
        onExpiration?()
    }
}

/// A clock the test moves.
@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_000_000)

    func advance(_ seconds: Double) {
        date = date.addingTimeInterval(seconds)
    }
}

/// The Live Activity (issue #64): its content, the model's content and outcome, and the
/// coordinator that starts, updates and ends it.
@MainActor
struct LiveActivityTests {
    typealias Content = LiveActivityContent

    func makeModel(
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in }
    ) async -> CameraModel {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: sleep)
        await model.send(.start)
        return model
    }

    func makeCoordinator(
        presenter: FakeLiveActivities = FakeLiveActivities(), time: FakeBackgroundTime = FakeBackgroundTime(),
        clock: TestClock = TestClock()
    ) -> LiveActivityCoordinator {
        let coordinator = LiveActivityCoordinator(presenter: presenter, backgroundTime: time, now: { clock.date })
        coordinator.isEnabled = true
        return coordinator
    }

    func photo(_ signature: SignatureStatus) -> SavedPhoto {
        SavedPhoto(formats: [.raw], isProcessedFallback: false, signature: signature, metadata: [:])
    }

    /// Starts an interval series whose first photo is taken and whose sleep never ends.
    func startInterval(_ model: CameraModel, count: Int = 5) async {
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: count))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
    }

    // MARK: - Content

    @Test func statusLines() {
        let end = Date(timeIntervalSince1970: 5)
        #expect(Content(kind: .timer, phase: .countingDown, countdownEnd: end).statusLine == .photoIn)
        #expect(Content(kind: .astro, phase: .countingDown, total: 20).statusLine == .astroStartsIn)
        #expect(Content(kind: .interval, phase: .running, taken: 3, total: 10).statusLine == .photosTaken(taken: 3, total: 10))
        #expect(Content(kind: .astro, phase: .running, taken: 3, total: 10).statusLine == .frame(number: 4, total: 10))
        #expect(Content(kind: .astro, phase: .running, taken: 10, total: 10).statusLine == .frame(number: 10, total: 10))
        #expect(Content(kind: .burst, phase: .running, taken: 7).statusLine == .burstPhotosTaken(7))
        #expect(Content(kind: .timer, phase: .running, taken: 1).statusLine == .takingPhoto)
        #expect(Content(kind: .interval, phase: .paused, taken: 42, total: 120).statusLine == .paused(taken: 42, total: 120))
        #expect(Content(kind: .burst, phase: .saving, taken: 7, saved: 4).statusLine == .saving(saved: 4, taken: 7))
        #expect(Content(kind: .timer, phase: .saving, taken: 1).statusLine == .savingPhoto)
        #expect(Content(kind: .astro, phase: .savingPaused, taken: 5, total: 20).statusLine == .savingPaused)
        #expect(Content(kind: .interval, phase: .finished, taken: 10, total: 10).statusLine == .seriesDone(taken: 10, total: 10))
        #expect(Content(kind: .burst, phase: .finished, taken: 7, saved: 7).statusLine == .photosSaved(7))
        #expect(Content(kind: .interval, phase: .stopped, taken: 4, total: 10).statusLine == .seriesStopped(taken: 4, total: 10))
        #expect(Content(kind: .timer, phase: .stopped).statusLine == .noPhotoTaken)
        #expect(Content(kind: .timer, phase: .stopped, taken: 1, saved: 1).statusLine == .photosSaved(1))
        #expect(Content(kind: .astro, phase: .stopped, taken: 5, total: 20, saved: 5).statusLine == .stoppedPhotosSaved(5))
        #expect(Content(kind: .burst, phase: .stopped, taken: 2, saved: 2).statusLine == .stoppedPhotosSaved(2))
        #expect(Content(kind: .burst, phase: .failed).statusLine == .failed)
    }

    @Test func signingStopAndProgress() throws {
        #expect(Content(kind: .burst, phase: .running, signing: .allSigned).signingLine == nil)
        #expect(Content(kind: .burst, phase: .finished, saved: 3).signingLine == nil)
        #expect(Content(kind: .burst, phase: .finished, saved: 3, signing: .allSigned).signingLine == .signed)
        #expect(Content(kind: .burst, phase: .stopped, saved: 3, signing: .notAllSigned).signingLine == .notAllSigned)
        #expect(Content(kind: .timer, phase: .failed, saved: 1, signing: .notAllSigned).signingLine == .notSigned)
        #expect(LiveActivitySigningLine.allCases.count == 3)

        #expect(Content(kind: .interval, phase: .running).canStop)
        #expect(Content(kind: .interval, phase: .paused).canStop)
        #expect(!Content(kind: .interval, phase: .stopped).canStop)
        #expect(!Content(kind: .burst, phase: .running).canStop)
        #expect(Content(kind: .interval, phase: .failed).hasEnded)
        #expect(!Content(kind: .interval, phase: .paused).hasEnded)

        #expect(Content(kind: .interval, phase: .running, taken: 3, total: 12).progress == 0.25)
        #expect(Content(kind: .interval, phase: .running, taken: 13, total: 12).progress == 1)
        #expect(Content(kind: .interval, phase: .running, taken: 3, total: 0).progress == nil)
        #expect(Content(kind: .burst, phase: .running, taken: 3).progress == nil)
        #expect(Content(kind: .astro, phase: .countingDown, total: 20).progress == nil)

        #expect(Content(kind: .timer, phase: .countingDown).compactCount == nil)
        #expect(Content(kind: .burst, phase: .failed, taken: 3).compactCount == nil)
        #expect(Content(kind: .burst, phase: .running, taken: 3, saved: 2).compactCount == 3)
        #expect(Content(kind: .interval, phase: .paused, taken: 3).compactCount == 3)
        #expect(Content(kind: .burst, phase: .saving, taken: 3, saved: 2).compactCount == 2)
        #expect(Content(kind: .interval, phase: .stopped, taken: 3).compactCount == 3)

        let content = Content(
            kind: .astro, phase: .countingDown, taken: 0, total: 20, countdownEnd: Date(timeIntervalSince1970: 9),
            isNightMode: true)
        let decoded = try JSONDecoder().decode(Content.self, from: JSONEncoder().encode(content))
        #expect(decoded == content)
        #expect(Content.Kind.allCases.count == 4)
        #expect(Content.Phase.allCases.count == 8)
        #expect(Content.Signing.allCases.count == 2)
    }

    // MARK: - The model's content

    @Test func contentForEachRun() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        let now = Date(timeIntervalSince1970: 100)
        #expect(model.liveActivityContent(continuing: nil, isInForeground: true, now: now) == nil)
        #expect(!model.isFinishingPhotos)

        // The self-timer, then its photo.
        model.drive.countdown.start(seconds: 3) {}
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: true, now: now)
                == Content(kind: .timer, phase: .countingDown, countdownEnd: now.addingTimeInterval(3)))
        model.drive.countdown.cancel()
        model.captureStatus = .capturing
        #expect(model.isFinishingPhotos)
        #expect(model.liveActivityContent(continuing: nil, isInForeground: true, now: now) == nil)
        #expect(
            model.liveActivityContent(continuing: .timer, isInForeground: true, now: now)
                == Content(kind: .timer, phase: .running, taken: 1))
        model.captureStatus = .saving
        #expect(model.isFinishingPhotos)
        #expect(
            model.liveActivityContent(continuing: .timer, isInForeground: false, now: now)
                == Content(kind: .timer, phase: .saving, taken: 1))
        model.captureStatus = .idle
        #expect(model.liveActivityContent(continuing: .timer, isInForeground: true, now: now) == nil)

        // The astro countdown and frames.
        model.astro.setOn(true)
        model.drive.countdown.start(seconds: 10) {}
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: true, now: now)
                == Content(kind: .astro, phase: .countingDown, total: 20, countdownEnd: now.addingTimeInterval(10)))
        model.drive.countdown.cancel()
        model.astro.beginRun()
        model.astro.recordTaken()
        #expect(model.isFinishingPhotos)
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: true, now: now)
                == Content(kind: .astro, phase: .running, taken: 1, total: 20))
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: false, now: now)
                == Content(kind: .astro, phase: .paused, taken: 1, total: 20))
        model.astro.endRun(.stopped)

        // A burst.
        model.drive.beginBurst()
        model.drive.recordTaken()
        model.drive.recordTaken()
        model.drive.recordSaved()
        #expect(model.isFinishingPhotos)
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: false, now: now)
                == Content(kind: .burst, phase: .saving, taken: 2, saved: 1))
        model.drive.endBurst(.stopped)

        // An interval series: paused out of the foreground.
        model.astro.setOn(false)
        await startInterval(model)
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: true, now: now)
                == Content(kind: .interval, phase: .running, taken: 1, total: 5))
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: false, now: now)
                == Content(kind: .interval, phase: .paused, taken: 1, total: 5))
        await model.send(.manual(.stopInterval))
    }

    @Test func outcomes() async {
        let model = await makeModel()
        let signed = photo(.signed)
        let unsigned = photo(.unsigned(.turnedOff))

        // A cancelled countdown, of either kind.
        let countdown = Content(kind: .timer, phase: .countingDown, countdownEnd: Date())
        #expect(model.liveActivityOutcome(after: countdown) == Content(kind: .timer, phase: .stopped))
        #expect(
            model.liveActivityOutcome(after: Content(kind: .astro, phase: .countingDown, total: 20))
                == Content(kind: .astro, phase: .stopped, total: 20))

        // An interval series, done or stopped.
        #expect(
            model.liveActivityOutcome(after: Content(kind: .interval, phase: .running, taken: 5, total: 5)).phase
                == .finished)
        #expect(
            model.liveActivityOutcome(after: Content(kind: .interval, phase: .paused, taken: 2, total: 5)).phase
                == .stopped)
        #expect(model.liveActivityOutcome(after: Content(kind: .interval, phase: .paused, taken: 2)).phase == .finished)

        // A burst: never started, then each end.
        let burst = Content(kind: .burst, phase: .saving, taken: 3, saved: 1)
        #expect(model.liveActivityOutcome(after: burst).phase == .stopped)
        model.captureStatus = .savedBurst([signed, signed, signed])
        for (end, phase) in [
            (BurstEnd.stopped, Content.Phase.finished), (.limitReached, .finished), (.countReached, .finished),
            (.storageFull, .stopped),
            (.cameraStopped, .stopped), (.batteryLow, .stopped),
        ] {
            model.drive.beginBurst()
            for _ in 0..<3 { model.drive.recordSaved() }
            model.drive.endBurst(end)
            #expect(
                model.liveActivityOutcome(after: burst)
                    == Content(kind: .burst, phase: phase, taken: 3, saved: 3, signing: .allSigned))
        }
        model.captureStatus = .failed(.saveFailed)
        model.drive.beginBurst()
        model.drive.endBurst(.failed)
        #expect(model.liveActivityOutcome(after: burst) == Content(kind: .burst, phase: .failed, taken: 3))

        // Astro: stopping isn't its planned end.
        let astro = Content(kind: .astro, phase: .running, taken: 2, total: 20, saved: 1)
        model.captureStatus = .savedBurst([signed, unsigned])
        model.astro.beginRun()
        model.astro.recordSaved()
        model.astro.recordSaved()
        model.astro.endRun(.stopped)
        #expect(
            model.liveActivityOutcome(after: astro)
                == Content(kind: .astro, phase: .stopped, taken: 2, total: 20, saved: 2, signing: .notAllSigned))

        // The self-timer's photo.
        let timer = Content(kind: .timer, phase: .saving, taken: 1)
        model.captureStatus = .saved(signed)
        #expect(
            model.liveActivityOutcome(after: timer)
                == Content(kind: .timer, phase: .finished, taken: 1, saved: 1, signing: .allSigned))
        model.captureStatus = .savedBracket([unsigned, unsigned, unsigned])
        #expect(
            model.liveActivityOutcome(after: timer)
                == Content(kind: .timer, phase: .finished, taken: 1, saved: 3, signing: .notAllSigned))
        model.captureStatus = .failed(.captureFailed)
        #expect(model.liveActivityOutcome(after: timer) == Content(kind: .timer, phase: .failed, taken: 1))
        for status in [CaptureStatus.idle, .capturing, .saving] {
            model.captureStatus = status
            #expect(model.liveActivityOutcome(after: timer) == Content(kind: .timer, phase: .stopped, taken: 1))
        }
        model.captureStatus = .savedBurst([])
        #expect(model.liveActivityOutcome(after: timer) == Content(kind: .timer, phase: .finished, taken: 1))
    }

    // MARK: - The coordinator

    @Test func startsOnlyWhenOnAllowedAndInTheForeground() async {
        let model = await makeModel()
        let presenter = FakeLiveActivities()
        let coordinator = makeCoordinator(presenter: presenter)
        model.drive.beginBurst()

        coordinator.isEnabled = false
        coordinator.apply(model)
        coordinator.isEnabled = true
        coordinator.isInForeground = false
        coordinator.isActive = false
        coordinator.apply(model)
        // Inactive (Control Center over the app): still in the foreground, but not active.
        coordinator.isInForeground = true
        coordinator.apply(model)
        coordinator.isActive = true
        presenter.areActivitiesEnabled = false
        coordinator.apply(model)
        #expect(presenter.started.isEmpty)

        // Refused once: not asked again during the same run.
        presenter.areActivitiesEnabled = true
        presenter.acceptsStart = false
        coordinator.apply(model)
        coordinator.apply(model)
        #expect(presenter.started.count == 1)
        #expect(coordinator.shown == nil)

        // The next run asks again.
        model.drive.endBurst(.stopped)
        coordinator.apply(model)
        presenter.acceptsStart = true
        coordinator.isNightMode = true
        model.drive.beginBurst()
        coordinator.apply(model)
        #expect(presenter.started.last == Content(kind: .burst, phase: .running, isNightMode: true))
        #expect(coordinator.shown?.kind == .burst)
        coordinator.isActive = false
        coordinator.apply(model)
        #expect(coordinator.shown?.phase == .running, "inactive is still the foreground: the burst runs")
        coordinator.isActive = true

        // Nothing that is already saving or ended starts one. (This one reads the system clock.)
        let other = LiveActivityCoordinator(presenter: presenter, backgroundTime: FakeBackgroundTime())
        other.isEnabled = true
        model.drive.endBurst(.stopped)
        model.captureStatus = .saving
        other.apply(model)
        #expect(presenter.started.count == 2)
    }

    @Test func updatesPhaseChangesAtOnceAndCountsRarely() async {
        let model = await makeModel()
        let presenter = FakeLiveActivities()
        let clock = TestClock()
        let coordinator = makeCoordinator(presenter: presenter, clock: clock)
        model.drive.beginBurst()
        coordinator.apply(model)

        // Nothing changed.
        coordinator.apply(model)
        #expect(presenter.updates.isEmpty)

        // Counts alone, in the foreground: not before the minimum interval.
        model.drive.recordTaken()
        clock.advance(LiveActivityCoordinator.minimumUpdateInterval - 1)
        coordinator.apply(model)
        #expect(presenter.updates.isEmpty)
        clock.advance(1)
        coordinator.apply(model)
        #expect(presenter.updates == [Content(kind: .burst, phase: .running, taken: 1)])

        // Saved count alone counts as a count change.
        model.drive.recordSaved()
        clock.advance(LiveActivityCoordinator.minimumUpdateInterval)
        coordinator.apply(model)
        #expect(presenter.updates.last == Content(kind: .burst, phase: .running, taken: 1, saved: 1))

        // Night mode is sent at once.
        coordinator.isNightMode = true
        coordinator.apply(model)
        #expect(presenter.updates.last?.isNightMode == true)

        // Leaving the foreground changes the phase: sent at once, and counts after that too.
        coordinator.isInForeground = false
        coordinator.apply(model)
        #expect(presenter.updates.last?.phase == .saving)
        model.drive.recordSaved()
        coordinator.apply(model)
        #expect(presenter.updates.last == Content(kind: .burst, phase: .saving, taken: 1, saved: 2, isNightMode: true))
        #expect(presenter.updates.count == 5)
    }

    @Test func endsAtOnceInTheForegroundAndLaterOutOfIt() async {
        let model = await makeModel()
        let presenter = FakeLiveActivities()
        let clock = TestClock()
        let coordinator = makeCoordinator(presenter: presenter, clock: clock)

        // In the foreground.
        model.drive.beginBurst()
        coordinator.apply(model)
        model.drive.endBurst(.limitReached)
        coordinator.apply(model)
        #expect(presenter.ends.last?.dismissal == .immediate)
        #expect(presenter.ends.last?.content.phase == .finished)
        #expect(coordinator.shown == nil)

        // Out of the foreground: the final content stays for a while.
        model.drive.beginBurst()
        coordinator.apply(model)
        coordinator.isInForeground = false
        coordinator.isNightMode = true
        model.drive.endBurst(.cameraStopped)
        coordinator.apply(model)
        #expect(
            presenter.ends.last?.dismissal
                == .after(clock.date.addingTimeInterval(LiveActivityCoordinator.endedActivityDuration)))
        #expect(presenter.ends.last?.content == Content(kind: .burst, phase: .stopped, isNightMode: true))

        // Turning the switch off ends it at once.
        coordinator.isInForeground = true
        model.drive.beginBurst()
        coordinator.apply(model)
        coordinator.isEnabled = false
        coordinator.apply(model)
        #expect(presenter.ends.count == 3)
        #expect(presenter.ends.last?.dismissal == .immediate)
        #expect(coordinator.shown == nil)
    }

    @Test func aNewKindOfRunReplacesTheActivity() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        let presenter = FakeLiveActivities()
        let coordinator = makeCoordinator(presenter: presenter)
        model.drive.countdown.start(seconds: 3) {}
        coordinator.apply(model)
        #expect(presenter.started.last?.kind == .timer)
        model.drive.countdown.cancel()
        model.drive.beginBurst()
        coordinator.apply(model)
        #expect(presenter.ends.last?.content == Content(kind: .timer, phase: .stopped))
        #expect(presenter.started.last?.kind == .burst)
        model.drive.endBurst(.stopped)
    }

    @Test func holdsTimeToFinishSavingOutOfTheForeground() async {
        let model = await makeModel()
        let presenter = FakeLiveActivities()
        let time = FakeBackgroundTime()
        let coordinator = makeCoordinator(presenter: presenter, time: time)

        // In the foreground, or with nothing to save: no time asked for.
        model.drive.beginBurst()
        coordinator.apply(model)
        model.drive.recordTaken()
        #expect(time.begun == 0)

        // Out of the foreground while saving: asked for once, given back when done.
        coordinator.isInForeground = false
        coordinator.apply(model)
        coordinator.apply(model)
        #expect(time.begun == 1)
        model.drive.endBurst(.cameraStopped)
        coordinator.apply(model)
        #expect(time.ended == 1)
        coordinator.apply(model)
        #expect(time.ended == 1)

        // Refused: asked again at the next change.
        time.grants = false
        model.drive.beginBurst()
        coordinator.apply(model)
        coordinator.apply(model)
        #expect(time.begun == 3)
        #expect(time.ended == 1)
        model.drive.endBurst(.cameraStopped)
        coordinator.apply(model)
    }

    @Test func runningOutOfTimeSaysSavingIsPaused() async {
        let model = await makeModel()
        let presenter = FakeLiveActivities()
        let time = FakeBackgroundTime()
        let coordinator = makeCoordinator(presenter: presenter, time: time)
        model.drive.beginBurst()
        model.drive.recordTaken()
        coordinator.apply(model)
        coordinator.isInForeground = false
        coordinator.apply(model)
        #expect(presenter.updates.last?.phase == .saving)

        time.expire()
        #expect(presenter.updates.last?.phase == .savingPaused)
        // No more time is asked for, and none is given back, until the app is open again.
        coordinator.apply(model)
        #expect(time.begun == 1)
        #expect(time.ended == 0)

        coordinator.isInForeground = true
        coordinator.apply(model)
        #expect(presenter.updates.last?.phase == .running)
        coordinator.isInForeground = false
        coordinator.apply(model)
        #expect(time.begun == 2)
        #expect(presenter.updates.last?.phase == .saving)
        model.drive.endBurst(.stopped)
        coordinator.apply(model)
    }

    @Test func expiryAfterTheModelIsGoneDoesNothing() async {
        let time = FakeBackgroundTime()
        var coordinator: LiveActivityCoordinator? = makeCoordinator(time: time)
        do {
            let model = await makeModel()
            model.drive.beginBurst()
            coordinator?.isInForeground = false
            coordinator?.apply(model)
            model.drive.endBurst(.stopped)
        }
        time.expire()
        coordinator = nil
        time.expire()
        #expect(time.begun == 1)
    }

    @Test func stopEndsTheSeriesAndTheActivityAtOnce() async {
        let gate = AsyncStream<Void>.makeStream()
        let model = await makeModel(sleep: { _ in
            gate.continuation.yield()
            try await Task.sleep(for: .seconds(60))
        })
        let presenter = FakeLiveActivities()
        let coordinator = makeCoordinator(presenter: presenter)
        await coordinator.stopSeries(model)
        #expect(presenter.ends.isEmpty)

        await startInterval(model, count: 10)
        coordinator.apply(model)
        coordinator.isInForeground = false
        coordinator.apply(model)
        #expect(presenter.updates.last?.phase == .paused)
        await coordinator.stopSeries(model)
        #expect(model.manual.intervalProgress == nil)
        #expect(presenter.ends.count == 1)
        #expect(presenter.ends.last?.content == Content(kind: .interval, phase: .stopped, taken: 1, total: 10))
        #expect(presenter.ends.last?.dismissal == .immediate)
        #expect(coordinator.shown == nil)
    }

    @Test func observeFollowsTheModelUntilCancelled() async {
        let model = await makeModel()
        let presenter = FakeLiveActivities()
        let coordinator = makeCoordinator(presenter: presenter)
        let task = Task { await coordinator.observe(model) }
        await settle()
        model.drive.beginBurst()
        await waitUntil { !presenter.started.isEmpty }
        #expect(presenter.started.last?.kind == .burst)
        coordinator.isInForeground = false
        await waitUntil { !presenter.updates.isEmpty }
        #expect(presenter.updates.last?.phase == .saving)
        model.drive.endBurst(.stopped)
        await waitUntil { !presenter.ends.isEmpty }
        #expect(presenter.ends.count == 1)
        task.cancel()
        await task.value
    }
}
