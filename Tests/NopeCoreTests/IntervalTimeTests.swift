import Foundation
import Testing

@testable import NopeCore

/// Interval series that stop after a time instead of a number of photos: the end is fixed on the
/// wall clock when the series starts, the time keeps running while the series is paused, and a
/// stop, a failed photo or a camera that stops still end it early (owner decision 2026-11-18).
@MainActor
struct IntervalTimeTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A started camera on `clock`, whose interval photos wait on it.
    func makeModel(clock: FakeClock) async -> (CameraModel, PausingBackend, Task<Void, Never>) {
        let backend = PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), clock: clock.clock,
            deviceStatusReader: FakeStatusReader(bytes: nil))
        model.pauseAfterErrorSleep = {}
        await model.send(.start)
        let events = Task { await model.observeEvents() }
        return (model, backend, events)
    }

    /// Lets time pass once a sleep waits: both clocks move on by `seconds`.
    func pass(_ seconds: Double, on clock: FakeClock, whenWaiting count: Int = 1) async {
        await waitForSleeps(clock, count: count)
        clock.advance(by: seconds)
    }

    /// Starts a series one minute apart that stops after `duration` seconds.
    func startTimedSeries(_ model: CameraModel, duration: Double, interval: Double = 60) async {
        await model.send(.manual(.setInterval(IntervalSettings(interval: interval, count: 10, stopAfter: .time, duration: duration))))
        await model.send(.manual(.startInterval))
    }

    func finish(_ backend: PausingBackend, _ events: Task<Void, Never>) async {
        backend.inner.finishEvents()
        await events.value
    }

    // MARK: - Settings

    @Test func theDefaultClocksAreTheSystemOnes() async throws {
        let manual = ManualControlsModel(backend: nil)
        #expect(abs(manual.clock.date().timeIntervalSinceNow) < 60)
        let model = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens))
        #expect(abs(model.clock.date().timeIntervalSinceNow) < 60)
        try await model.clock.sleep(seconds: 0)
    }

    @Test func settingsKeepTheCountAndTheTimeInTheirRanges() {
        let standard = IntervalSettings.standard
        #expect(standard.stopAfter == .numberOfPhotos)
        #expect(standard.duration == 3600)
        #expect(IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 1).duration == 60)
        #expect(IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 100_000).duration == 86_400)
        #expect(IntervalSettings.StopAfter.allCases == [.numberOfPhotos, .time])
        #expect(IntervalSettings.StopAfter(rawValue: "time") == .time)
        #expect(IntervalSettings.listedHours.first == 0 && IntervalSettings.listedHours.last == 24)
        #expect(IntervalSettings.listedMinutes.count == 60)

        let timed = standard.with(stopAfter: .time).with(hours: 1, minutes: 30)
        #expect(timed == IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 5400))
        #expect(timed.durationHours == 1)
        #expect(timed.durationMinutes == 30)
        #expect(timed.with(hours: 0, minutes: 0).duration == 60, "no time becomes one minute")
        #expect(timed.with(hours: 24, minutes: 59).duration == 86_400, "at most 24 hours")
        #expect(timed.with(interval: 30).interval == 30)
        #expect(timed.with(count: 50).count == 50)
        #expect(timed.with(stopAfter: .numberOfPhotos).duration == 5400, "switching back keeps the time")
        #expect(timed.with(count: 50).with(stopAfter: .time).count == 50, "and the count")
    }

    @Test func theMostPhotosOfATimedSeriesCountTheFirstAndEachIntervalBeforeTheEnd() {
        #expect(IntervalSettings.standard.maximumPhotoCount == 10)
        let hour = IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 3600)
        #expect(hour.maximumPhotoCount == 360)
        #expect(hour.with(interval: 7).maximumPhotoCount == 515)
        #expect(IntervalSettings(interval: 60, count: 10, stopAfter: .time, duration: 120).maximumPhotoCount == 2)
        #expect(IntervalSettings(interval: 60, count: 10, stopAfter: .time, duration: 150).maximumPhotoCount == 3)
    }

    @Test func anIntervalAsLongAsTheTimeOrLongerIsNotShorter() {
        #expect(IntervalSettings(interval: 3600, count: 2).isIntervalShorterThanTime, "a number of photos is never blocked")
        #expect(IntervalSettings(interval: 59, count: 2, stopAfter: .time, duration: 60).isIntervalShorterThanTime)
        #expect(!IntervalSettings(interval: 60, count: 2, stopAfter: .time, duration: 60).isIntervalShorterThanTime)
        #expect(!IntervalSettings(interval: 120, count: 2, stopAfter: .time, duration: 60).isIntervalShorterThanTime)
    }

    @Test func progressMeasuresTimeLeftAndShareDone() {
        let start = ContinuousClock.now
        let timed = IntervalProgress(taken: 3, total: nil, deadline: start + .seconds(600), duration: .seconds(600))
        #expect(timed.isTimed)
        #expect(timed.secondsLeft(at: start + .seconds(150)) == 450)
        #expect(timed.secondsLeft(at: start + .seconds(900)) == 0)
        #expect(timed.fractionDone(at: start + .seconds(150)) == 0.25)
        #expect(timed.fractionDone(at: start - .seconds(10)) == 0)
        #expect(timed.fractionDone(at: start + .seconds(900)) == 1)
        #expect(
            timed.with(isPaused: true)
                == IntervalProgress(taken: 3, total: nil, isPaused: true, deadline: timed.deadline, duration: timed.duration))
        #expect(
            timed.with(isPaused: true).with(taken: 4)
                == IntervalProgress(taken: 4, total: nil, deadline: timed.deadline, duration: timed.duration))

        let counted = IntervalProgress(taken: 3, total: 10)
        #expect(!counted.isTimed)
        #expect(counted.secondsLeft(at: start) == nil)
        #expect(counted.deadline == nil)
        #expect(counted.endDate(clock: .system) == nil)
        #expect(counted.timeSpan(date: Self.start, now: start) == nil)
        #expect(counted.fractionDone(at: start) == 0.3)
        #expect(IntervalProgress(taken: 0, total: nil).fractionDone(at: start) == 0)
    }

    @Test func theEndIsShownAsADateOfTheWallClockNow() {
        let clock = FakeClock(date: Self.start)
        let timed = IntervalProgress(taken: 1, total: nil, deadline: clock.now + .seconds(600), duration: .seconds(600))
        #expect(timed.endDate(clock: clock.clock) == Self.start.addingTimeInterval(600))
        #expect(timed.timeSpan(date: clock.date, now: clock.now) == Self.start...Self.start.addingTimeInterval(600))
        clock.advance(by: 60)
        clock.moveDate(by: -3600)
        // The device's clock was set back an hour: the end is shown an hour earlier, nine minutes
        // from now, and the time left is the same.
        #expect(timed.endDate(clock: clock.clock) == Self.start.addingTimeInterval(600 - 3600))
        #expect(
            timed.timeSpan(date: clock.date, now: clock.now)
                == Self.start.addingTimeInterval(-3600)...Self.start.addingTimeInterval(600 - 3600))
        #expect(timed.secondsLeft(at: clock.now) == 540)
        #expect(timed.fractionDone(at: clock.now) == 0.1)
    }

    // MARK: - Running to the time

    @Test func theSeriesEndsWhenTheNextIntervalWouldReachTheTime() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 150)
        let span = Self.start...Self.start.addingTimeInterval(150)
        #expect(model.manual.intervalProgress?.deadline == clock.start + .seconds(150))
        #expect(model.manual.intervalProgress?.duration == .seconds(150))
        #expect(model.manual.intervalProgress?.total == nil)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(model.manual.lastIntervalEnd == nil)
        #expect(
            model.liveActivityContent(continuing: nil, isInForeground: true, now: Self.start)
                == LiveActivityContent(kind: .interval, phase: .running, taken: 1, seriesTime: span))

        await pass(60, on: clock)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        #expect(model.manual.intervalProgress?.secondsLeft(at: clock.now) == 90)
        await pass(60, on: clock)
        // The third photo at 2 minutes is the last: another minute would reach 2.5 minutes.
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 3)
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    @Test func aPhotoWhoseIntervalEndsExactlyAtTheTimeIsNotTaken() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 120)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await pass(60, on: clock)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 2)
        #expect(clock.pendingSleeps == 0, "no wait after the last photo")
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    @Test func aSeriesThatOverranItsTimeWhileWaitingEndsWithoutAnotherPhoto() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        // The wait took longer than asked, past the end.
        await pass(700, on: clock)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 1)
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    // MARK: - The device's time changes (issue #106)

    @Test func changingTheDevicesTimeDoesNotMoveTheEnd() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        // An hour forward, then two hours back: the series still takes a photo each minute and
        // ends ten minutes after it began.
        await waitForSleeps(clock)
        clock.moveDate(by: 3600)
        await pass(60, on: clock)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        #expect(model.manual.intervalProgress != nil, "an hour forward doesn't end it")
        await waitForSleeps(clock)
        clock.moveDate(by: -7200)
        for photo in 3...10 {
            await pass(60, on: clock)
            await waitUntil { model.manual.intervalProgress?.taken == photo || model.manual.intervalProgress == nil }
        }
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 10)
        #expect(model.manual.lastIntervalEnd == .finished)
        #expect(clock.seconds(at: clock.now) == 540, "the last photo was at nine minutes")
        await finish(backend, events)
    }

    // MARK: - Ending early

    @Test func stoppingBeforeTheTimeEndsItAsStopped() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 3600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        let shown = model.liveActivityContent(continuing: nil, isInForeground: false, now: clock.date)
        await model.send(.manual(.stopInterval))
        #expect(model.manual.intervalProgress == nil)
        #expect(model.manual.lastIntervalEnd == .stopped)
        let outcome = model.liveActivityOutcome(after: shown!)
        #expect(outcome.phase == .stopped)
        #expect(outcome.statusLine == .seriesStoppedBeforeTime(1))
        await finish(backend, events)
    }

    @Test func aFailedPhotoEndsItBeforeTheTime() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        // A full disk ends the series the same way: the photo can't be saved, and the camera says why.
        await backend.setOnCapture { number in number == 2 ? .captureFailed : nil }
        await startTimedSeries(model, duration: 3600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await pass(60, on: clock)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(model.captureStatus == .failed(.captureFailed))
        #expect(model.manual.lastIntervalEnd == .stopped)
        await finish(backend, events)
    }

    @Test func aCameraThatStopsForGoodEndsItBeforeTheTime() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 3600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await pass(60, on: clock)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        await backend.setStartError(.configurationFailed)
        backend.inner.emitEvent(.failed)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 1)
        #expect(model.manual.lastIntervalEnd == .stopped)
        await finish(backend, events)
    }

    // MARK: - Pausing: the time keeps running

    @Test func aPauseKeepsTheEnd() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await waitForSleeps(clock)
        await model.send(.setInForeground(false))
        clock.advance(by: 60)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        let paused = model.liveActivityContent(continuing: .interval, isInForeground: false, now: clock.date)
        #expect(paused?.statusLine == .pausedTimeLeft(1))
        #expect(paused?.showsTimeLeft == true)

        // Five minutes away: the time ran on.
        clock.advance(by: 300)
        await model.send(.setInForeground(true))
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        #expect(model.manual.intervalProgress?.isPaused == false)
        #expect(model.manual.intervalProgress?.deadline == clock.start + .seconds(600))
        #expect(model.manual.intervalProgress?.secondsLeft(at: clock.now) == 240)
        await model.send(.manual(.stopInterval))
        #expect(await backend.captures == 2)
        await finish(backend, events)
    }

    @Test func aSeriesWhoseTimeRanOutWhileAwayEndsWhenTheAppIsBack() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 120)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await waitForSleeps(clock)
        await model.send(.setInForeground(false))
        clock.advance(by: 60)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        let shown = model.liveActivityContent(continuing: .interval, isInForeground: false, now: clock.date)

        clock.advance(by: 3600)
        await model.send(.setInForeground(true))
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(await backend.captures == 1, "no photo after the time")
        #expect(model.manual.lastIntervalEnd == .finished)
        let outcome = model.liveActivityOutcome(after: shown!)
        #expect(outcome.phase == .finished)
        #expect(outcome.statusLine == .seriesDoneAfterTime(1))
        await finish(backend, events)
    }

    @Test func aSeriesPausedOnScreenEndsAtItsTime() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 120)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await waitForSleeps(clock)
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        clock.advance(by: 60)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        await waitForSleeps(clock)
        #expect(clock.requestedWakes.last.map { clock.seconds(at: $0) } == 120, "it wakes when the minute left is up")

        clock.advance(by: 60)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(model.sessionStatus == .interrupted(.inUseElsewhere), "still interrupted")
        #expect(await backend.captures == 1)
        #expect(model.manual.lastIntervalEnd == .finished)
        await finish(backend, events)
    }

    @Test func anEarlyWakeBeforeTheTimeKeepsWaiting() async {
        let fake = FakeClock(date: Self.start)
        let wakes = WaitCounter()
        // The first wait for the end returns at once, as a wait can end early; the others wait.
        var clock = fake.clock
        clock.sleep = { deadline in
            await wakes.add()
            if await wakes.count == 2 { return }
            try await fake.sleep(until: deadline)
        }
        let backend = PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), clock: clock, deviceStatusReader: FakeStatusReader(bytes: nil))
        model.pauseAfterErrorSleep = {}
        await model.send(.start)
        let events = Task { await model.observeEvents() }
        await startTimedSeries(model, duration: 600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await waitForSleeps(fake)
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        fake.advance(by: 60)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        await eventually { await wakes.count == 3 }
        await waitForSleeps(fake)
        #expect(fake.requestedWakes.map { fake.seconds(at: $0) } == [60, 600], "it waits for the end again")
        #expect(model.manual.intervalProgress?.isPaused == true)
        #expect(await backend.captures == 1)

        backend.inner.emitEvent(.interruptionEnded)
        await waitUntil { model.manual.intervalProgress?.taken == 2 }
        await model.send(.manual(.stopInterval))
        await finish(backend, events)
    }

    @Test func settingTheDevicesTimeWhilePausedKeepsOneWaitForTheEnd() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await startTimedSeries(model, duration: 600)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        await waitForSleeps(clock)
        backend.inner.emitEvent(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        clock.advance(by: 60)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        await waitForSleeps(clock)
        clock.moveDate(by: -300)
        clock.advance(by: 539)
        #expect(model.manual.intervalProgress?.secondsLeft(at: clock.now) == 1)
        clock.advance(by: 1)
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(clock.requestedWakes.map { clock.seconds(at: $0) } == [60, 600])
        #expect(model.manual.lastIntervalEnd == .finished)
        #expect(await backend.captures == 1)
        await finish(backend, events)
    }

    // MARK: - An interval as long as the time

    @Test func anIntervalNotShorterThanTheTimeBlocksTheStartAndTheShutter() async {
        let clock = FakeClock(date: Self.start)
        let (model, backend, events) = await makeModel(clock: clock)
        await model.send(.manual(.setInterval(IntervalSettings(interval: 120, count: 10, stopAfter: .time, duration: 60))))
        #expect(model.intervalBlocker == .intervalNotShorterThanTime)
        #expect(model.canPressShutter, "the other modes still take photos")
        await model.send(.drive(.setMode(.interval)))
        #expect(!model.canPressShutter, "the shutter would start nothing")
        await model.send(.manual(.startInterval))
        await model.send(.capture)
        #expect(model.manual.intervalProgress == nil)
        #expect(await backend.captures == 0)

        await model.send(.manual(.setInterval(model.manual.interval.with(stopAfter: .numberOfPhotos))))
        #expect(model.intervalBlocker == nil)
        #expect(model.canPressShutter)
        await finish(backend, events)
    }

    // MARK: - Presets

    @Test func presetsKeepTheEndAndOlderPresetsReadAsANumberOfPhotos() throws {
        var setup = CameraSetup.factory
        #expect(setup.intervalStopAfter == "numberOfPhotos")
        #expect(setup.intervalDuration == 3600)
        #expect(setup.intervalSettings == .standard)

        setup.intervalStopAfter = "time"
        setup.intervalDuration = 5400
        let data = try JSONEncoder().encode(setup)
        let decoded = try JSONDecoder().decode(CameraSetup.self, from: data)
        #expect(decoded == setup)
        #expect(decoded.intervalSettings == IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 5400))

        // A preset saved before the choice existed has neither value.
        var older = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        older["intervalStopAfter"] = nil
        older["intervalDuration"] = nil
        let olderSetup = try JSONDecoder().decode(CameraSetup.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(olderSetup.intervalSettings == .standard)

        // An end added by a later version reads as a number of photos.
        var later = setup
        later.intervalStopAfter = "sunset"
        #expect(later.intervalSettings.stopAfter == .numberOfPhotos)
    }

    @Test func aPresetSetsUpATimedSeries() async {
        let model = await CameraSetupTests.makeModel()
        var setup = model.cameraSetup
        setup.intervalStopAfter = IntervalSettings.StopAfter.time.rawValue
        setup.intervalDuration = 1800
        setup.drive = CameraSetup.driveName(.interval)
        let notices = await model.applyCameraSetup(setup, manualControlsOn: false)
        #expect(notices == [])
        #expect(model.manual.interval == IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 1800))
        #expect(model.cameraSetup.intervalStopAfter == "time")
        #expect(model.cameraSetup.intervalDuration == 1800)
    }

    // MARK: - Shortcuts

    @Test func aDurationMakesTheShortcutStopAfterATime() {
        let chosen = IntervalSettings(interval: 30, count: 20)
        let timed = chosen.with(stopAfter: .time).with(duration: 900)
        #expect(IntervalShortcut().settings(over: timed) == timed, "nothing given keeps the chosen end")
        #expect(
            IntervalShortcut(durationSeconds: 1800).settings(over: chosen)
                == IntervalSettings(interval: 30, count: 20, stopAfter: .time, duration: 1800))
        #expect(IntervalShortcut(count: 4).settings(over: timed) == IntervalSettings(interval: 30, count: 4, duration: 900))
        #expect(
            IntervalShortcut(count: 4, durationSeconds: 600).settings(over: chosen)
                == IntervalSettings(interval: 30, count: 4, stopAfter: .time, duration: 600), "the time decides")
        #expect(IntervalShortcut(durationSeconds: 999_999).settings(over: chosen).duration == 86_400)
        #expect(IntervalShortcut(durationSeconds: 1800).durationSeconds == 1800)
    }

    @Test func aShortcutWithADurationStartsATimedSeriesOrSaysWhyNot() async {
        let shortcuts = ShortcutTests()
        let (model, backend) = await shortcuts.makeManualModel(enabled: false)
        let refused = await shortcuts.run(
            .startInterval(IntervalShortcut(intervalSeconds: 120, durationSeconds: 60)), on: model)
        #expect(refused == .intervalNotShorterThanTime)
        #expect(model.manual.interval == .standard, "the chosen series is kept")
        #expect(model.manual.intervalProgress == nil)
        #expect(WatchResult(ShortcutOutcome.intervalNotShorterThanTime) == .notSaved)

        let started = await shortcuts.run(.startInterval(IntervalShortcut(intervalSeconds: 5, durationSeconds: 1800)), on: model)
        #expect(started == .intervalStarted)
        #expect(model.manual.interval == IntervalSettings(interval: 5, count: 10, stopAfter: .time, duration: 1800))
        #expect(model.manual.intervalProgress?.isTimed == true)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(await backend.captureCount == 1)
        #expect(await shortcuts.run(.stopInterval, on: model) == .intervalStopped)
    }

    // MARK: - Live Activity

    @Test func liveActivityLinesOfATimedSeries() throws {
        let span = Self.start...Self.start.addingTimeInterval(3600)
        typealias Content = LiveActivityContent
        let running = Content(kind: .interval, phase: .running, taken: 12, seriesTime: span)
        #expect(running.statusLine == .photosTakenTimeLeft(12))
        #expect(running.showsTimeLeft)
        #expect(running.progress == nil, "the bar is drawn by time")
        #expect(running.compactCount == 12)
        #expect(running.canStop)
        #expect(Content(kind: .interval, phase: .paused, taken: 12, seriesTime: span).statusLine == .pausedTimeLeft(12))
        #expect(Content(kind: .interval, phase: .finished, taken: 360, seriesTime: span).statusLine == .seriesDoneAfterTime(360))
        #expect(Content(kind: .interval, phase: .finished, taken: 360, seriesTime: span).showsTimeLeft == false)
        #expect(Content(kind: .interval, phase: .stopped, taken: 5, seriesTime: span).statusLine == .seriesStoppedBeforeTime(5))
        #expect(Content(kind: .interval, phase: .failed, taken: 5, seriesTime: span).statusLine == .failed)
        #expect(Content(kind: .interval, phase: .running, taken: 3, total: 10).showsTimeLeft == false)

        let decoded = try JSONDecoder().decode(Content.self, from: JSONEncoder().encode(running))
        #expect(decoded == running)
        // Content saved before the time existed decodes without one.
        var older = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(running)) as? [String: Any])
        older["seriesTime"] = nil
        let olderContent = try JSONDecoder().decode(Content.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(olderContent.seriesTime == nil)
    }
}
