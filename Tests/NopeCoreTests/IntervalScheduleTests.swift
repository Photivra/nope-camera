import Foundation
import Testing

@testable import NopeCore

/// Interval photos are spaced start to start (issue #123, owner decision): each photo starts one
/// interval after the last one started, on the monotonic clock; a photo that takes longer than the
/// interval makes the next start as soon as the camera is ready, with no catch-up photos; a paused
/// series takes its next photo when it resumes, and the schedule continues from that photo.
@MainActor
struct IntervalScheduleTests {
    /// A started camera on `clock`, whose photos take `photoSeconds(n)` seconds each (photo `n`,
    /// from 1), and which records when each photo started, in seconds from the clock's start.
    /// With `gate`, every photo after the first waits for it before it is saved, so a test can
    /// look at the series between photos that follow one another at once.
    func makeModel(
        clock: FakeClock, starts: StartLog, gate: Ticker? = nil, photoSeconds: @escaping @Sendable (Int) -> Double
    ) async -> (CameraModel, PausingBackend, Task<Void, Never>) {
        let backend = PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        await backend.setOnCapture { number in
            await starts.add(clock.seconds(at: clock.now))
            clock.advance(by: photoSeconds(number))
            if number > 1 { await gate?.sleep() }
            return nil
        }
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), clock: clock.clock,
            deviceStatusReader: FakeStatusReader(bytes: nil))
        model.pauseAfterErrorSleep = {}
        await model.send(.start)
        let events = Task { await model.observeEvents() }
        return (model, backend, events)
    }

    func finish(_ backend: PausingBackend, _ events: Task<Void, Never>) async {
        backend.inner.finishEvents()
        await events.value
    }

    /// Lets the series' next wait end: moves the clock to it once it waits.
    func passToNextPhoto(_ clock: FakeClock) async {
        await waitForSleeps(clock)
        clock.advanceToNextWake()
    }

    @Test func aShortPhotoEveryTenSecondsStartsTenSecondsApart() async {
        let clock = FakeClock()
        let starts = StartLog()
        let (model, backend, events) = await makeModel(clock: clock, starts: starts) { _ in 2 }
        await model.send(.manual(.setInterval(IntervalSettings(interval: 10, count: 4))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        let progress = model.manual.intervalProgress
        #expect(progress?.nextPhotoStart.map { clock.seconds(at: $0) } == 10)
        #expect(progress?.isBehindSchedule == false)
        #expect(clock.seconds(at: clock.now) == 2, "saved after its two seconds")
        for photo in 2...4 {
            await passToNextPhoto(clock)
            await waitUntil { model.manual.intervalProgress?.taken == photo || model.manual.intervalProgress == nil }
        }
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await starts.values == [0, 10, 20, 30])
        #expect(clock.requestedWakes.map { clock.seconds(at: $0) } == [10, 20, 30])
        #expect(clock.seconds(at: clock.now) == 32, "ten photos' estimate: the last starts at 30")
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    @Test func aPhotoLongerThanTheIntervalStartsTheNextAtOnceWithoutCatchingUp() async {
        let clock = FakeClock()
        let starts = StartLog()
        let gate = Ticker()
        let (model, backend, events) = await makeModel(clock: clock, starts: starts, gate: gate) { $0 <= 2 ? 12 : 2 }
        await model.send(.manual(.setInterval(IntervalSettings(interval: 10, count: 4))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(model.manual.intervalProgress?.isBehindSchedule == true, "the first photo overran")
        await tick(gate)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        #expect(model.manual.intervalProgress?.isBehindSchedule == true)
        await tick(gate)
        await waitUntil { model.manual.intervalProgress?.taken == 3 }
        #expect(model.manual.intervalProgress?.isBehindSchedule == false, "the third fits its interval")
        #expect(model.manual.intervalProgress?.nextPhotoStart.map { clock.seconds(at: $0) } == 34)
        await passToNextPhoto(clock)
        await tick(gate)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await starts.values == [0, 12, 24, 34], "each starts when the last ends, then on schedule")
        #expect(await backend.captures == 4, "no photo is taken twice to catch up")
        #expect(clock.requestedWakes.map { clock.seconds(at: $0) } == [34])
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    @Test func aSeriesPausedPastAStartTakesThePhotoOnResumeAndContinuesFromIt() async {
        let clock = FakeClock()
        let starts = StartLog()
        let (model, backend, events) = await makeModel(clock: clock, starts: starts) { _ in 2 }
        await model.send(.manual(.setInterval(IntervalSettings(interval: 10, count: 3))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await waitForSleeps(clock)
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        clock.advance(by: 20)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        #expect(await backend.captures == 1)

        backend.inner.emitEvent(.interruptionEnded)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        #expect(model.manual.intervalProgress?.nextPhotoStart.map { clock.seconds(at: $0) } == 32)
        await passToNextPhoto(clock)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await starts.values == [0, 22, 32])
        #expect(clock.requestedWakes.map { clock.seconds(at: $0) } == [10, 32])
        await finish(backend, events)
    }

    @Test func aTimedSeriesTakesAPhotoForEachStartBeforeTheEnd() async {
        let clock = FakeClock()
        let starts = StartLog()
        let (model, backend, events) = await makeModel(clock: clock, starts: starts) { _ in 2 }
        let settings = IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 60)
        await model.send(.manual(.setInterval(settings)))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        for photo in 2...6 {
            await passToNextPhoto(clock)
            await waitUntil { model.manual.intervalProgress?.taken == photo || model.manual.intervalProgress == nil }
        }
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await starts.values == [0, 10, 20, 30, 40, 50])
        #expect(await backend.captures == settings.maximumPhotoCount, "\"At most\" holds when each photo fits")
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    @Test func aCountedSeriesKeepsNoScheduleBeforeItsFirstPhoto() {
        let progress = IntervalProgress(taken: 0, total: 3)
        #expect(progress.nextPhotoStart == nil)
        #expect(!progress.isBehindSchedule)
        let next = ContinuousClock.now
        let behind = progress.with(taken: 1, nextPhotoStart: next, isBehindSchedule: true)
        #expect(behind == IntervalProgress(taken: 1, total: 3, nextPhotoStart: next, isBehindSchedule: true))
        #expect(behind.with(isPaused: true).isBehindSchedule, "pausing keeps the schedule")
        #expect(behind.with(isPaused: true).nextPhotoStart == next)
    }

    // MARK: - A manual shutter longer than the interval (decision 10)

    @Test func aManualShutterLongerThanTheIntervalIsKnownBeforeTheSeries() async {
        let longExposures = Lens(
            id: "wide", kind: .wide, bayerRAWFormat: "bgg4", isoRange: 50...6400, exposureDurationRange: 0.0001...30,
            aperture: nil, maxBracketedPhotoCount: 5, manualControls: ManualFixtures.full)
        let model = CameraModel(
            backend: ScriptedManualBackend(lenses: [longExposures]), saver: CameraModelTests.saver(), clock: FakeClock().clock)
        await model.send(.start)
        await model.send(.manual(.setInterval(IntervalSettings(interval: 10, count: 3))))
        #expect(!model.manual.isShutterLongerThanInterval, "full auto: not known in advance")
        await model.send(.manual(.setEnabled(true)))
        #expect(!model.manual.isShutterLongerThanInterval, "an automatic shutter isn't known either")
        await model.send(.manual(.setValue(.shutter, 10)))
        #expect(!model.manual.isShutterLongerThanInterval, "as long as the interval still fits")
        await model.send(.manual(.setValue(.shutter, 15)))
        #expect(model.manual.isShutterLongerThanInterval)
        await model.send(.manual(.setInterval(IntervalSettings(interval: 20, count: 3))))
        #expect(!model.manual.isShutterLongerThanInterval)
        await model.send(.manual(.setInterval(IntervalSettings(interval: 5, count: 3))))
        await model.send(.manual(.setEnabled(false)))
        #expect(!model.manual.isShutterLongerThanInterval, "manual controls off: the photos are full auto")
    }
}

/// When each photo started, from any task.
actor StartLog {
    private(set) var values: [Double] = []

    func add(_ seconds: Double) {
        values.append(seconds)
    }
}
