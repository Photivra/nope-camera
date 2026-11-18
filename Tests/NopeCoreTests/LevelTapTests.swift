import Foundation
import Testing

@testable import NopeCore

/// When the level gives its tap (docs/design/level-haptic.md, section 10, unit tests 1 to 10).
struct LevelTapRuleTests {
    /// A fixed starting time; each test adds seconds to it.
    static let start = ContinuousClock.now

    /// The time `seconds` after ``start``.
    static func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int((seconds * 1000).rounded()))
    }

    /// The horizon level for a device turned clockwise by `degrees` from upright, through a
    /// tracker so the hysteresis applies.
    static func horizon(_ tracker: inout LevelTracker, turnedBy degrees: Double) -> LevelState {
        tracker.update(LevelTests.upright(turnedBy: degrees))
    }

    /// Applies one state, not held back, at `seconds` after ``start``; whether it tapped.
    static func tap(_ rule: inout LevelTapRule, _ state: LevelState?, at seconds: Double) -> Bool {
        rule.update(state, at: at(seconds), isHeldBack: false)
    }

    /// Feeds the tilts (degrees from upright), one reading at each time, and returns the times
    /// that gave a tap.
    static func taps(
        _ readings: [(seconds: Double, degrees: Double)], isHeldBack: (Double) -> Bool = { _ in false }
    ) -> [Double] {
        var rule = LevelTapRule()
        var tracker = LevelTracker()
        var tapped: [Double] = []
        for reading in readings {
            let state = horizon(&tracker, turnedBy: reading.degrees)
            if rule.update(state, at: at(reading.seconds), isHeldBack: isHeldBack(reading.seconds)) {
                tapped.append(reading.seconds)
            }
        }
        return tapped
    }

    // 1.
    @Test func becomingLevelTapsOnce() {
        #expect(Self.taps([(0, 5), (0.05, 0)]) == [0.05])
    }

    // 2.
    @Test func holdingLevelGivesNoFurtherTap() {
        let held = (1...40).map { (seconds: 0.05 * Double($0), degrees: 0.2) }
        #expect(Self.taps([(0, 5)] + held) == [0.05])
    }

    // 3.
    @Test func theFirstReadingNeverTaps() {
        #expect(Self.taps([(0, 0), (0.05, 0)]).isEmpty, "level from the first reading: no tap")
        #expect(Self.taps([(0, 0), (0.5, 3), (1.5, 0)]) == [1.5])
    }

    // 4.
    @Test func atLeastOneSecondBetweenTapsAndNoLateTap() {
        #expect(Self.taps([(0, 5), (1, 0), (1.5, 2), (2, 0)]) == [1, 2], "1.0 second after the last tap: tap")
        // 0.9 second after the last tap: dropped, and not played later while level is held.
        #expect(Self.taps([(0, 5), (1, 0), (1.5, 2), (1.9, 0), (2.5, 0.1), (3, 0.2)]) == [1])
    }

    // 5.
    @Test func movingInsideTheReleaseToleranceGivesNoTap() {
        #expect(Self.taps([(0, 5), (1, 0.5), (2, 1.4), (3, 1.2), (4, 0.3), (5, 1.45), (6, 0)]) == [1])
        // Between 1.0 and 1.5 degrees while not level is not level.
        #expect(Self.taps([(0, 5), (1, 1.2), (2, 1.4)]).isEmpty)
    }

    // 6.
    @Test func aHeldBackEntryIsDroppedNotPlayedLater() {
        // Entering level while held back: no tap; the cause ends while still level: no tap.
        let readings: [(seconds: Double, degrees: Double)] = [(0, 5), (1, 0), (2, 0.2), (3, 0.1)]
        #expect(Self.taps(readings, isHeldBack: { $0 < 1.5 }).isEmpty)
        // Leaving and entering again once it ends: tap.
        #expect(Self.taps(readings + [(4, 3), (5, 0)], isHeldBack: { $0 < 1.5 }) == [5])
        // A held-back entry doesn't start the minimum time: the next entry 0.5 s later taps.
        #expect(Self.taps([(0, 5), (1, 0), (1.2, 3), (1.5, 0)], isHeldBack: { $0 < 1.1 }) == [1.5])
    }

    // 7.
    @Test func theTopDownLevelTapsOnceForBothAxes() {
        var rule = LevelTapRule()
        let tilted = LevelState.flat(pitchDegrees: 5, rollDegrees: 6, isLevel: false)
        let pitchOnly = LevelState.flat(pitchDegrees: 0.5, rollDegrees: 6, isLevel: false)
        let both = LevelState.flat(pitchDegrees: 0.5, rollDegrees: 0.4, isLevel: true)
        #expect(!Self.tap(&rule, tilted, at: 0))
        #expect(!Self.tap(&rule, pitchOnly, at: 1), "pitch level, roll not: no tap")
        #expect(Self.tap(&rule, both, at: 2))
        #expect(!Self.tap(&rule, LevelState.flat(pitchDegrees: 0.1, rollDegrees: 0.2, isLevel: true), at: 3))

        // Through the tracker: pitch within the tolerance and roll outside isn't level.
        var tracker = LevelTracker()
        let rollRadians = 5 * Double.pi / 180
        let rollOnly = tracker.update(GravityVector(x: -sin(rollRadians), y: 0, z: -cos(rollRadians)))
        #expect(!rollOnly.isLevel)
        let down = tracker.update(GravityVector(x: 0, y: 0, z: -1))
        #expect(down.isLevel)
    }

    // 8.
    @Test func changingBetweenTheLevelsTapsOnlyOnANewEntry() {
        var rule = LevelTapRule()
        let horizonLevel = LevelState.horizon(rotationDegrees: 0, tiltDegrees: 0, isLevel: true)
        let horizonTilted = LevelState.horizon(rotationDegrees: 4, tiltDegrees: 4, isLevel: false)
        let flatLevel = LevelState.flat(pitchDegrees: 0, rollDegrees: 0, isLevel: true)
        #expect(!Self.tap(&rule, horizonTilted, at: 0))
        #expect(Self.tap(&rule, horizonLevel, at: 1))
        #expect(!Self.tap(&rule, flatLevel, at: 3), "level throughout: no tap")
        // Not level in one, level in the other: one tap.
        #expect(!Self.tap(&rule, horizonTilted, at: 4))
        #expect(Self.tap(&rule, flatLevel, at: 5))
    }

    // 9.
    @Test func eachHorizonPositionTapsOnEntry() {
        for upright in [0.0, 90, -90, 180] {
            #expect(Self.taps([(0, upright + 5), (1, upright)]) == [1], "upright at \(upright)°")
        }
    }

    // 10.
    @Test func readingsEndingResetTheRule() {
        var rule = LevelTapRule()
        let tilted = LevelState.horizon(rotationDegrees: 4, tiltDegrees: 4, isLevel: false)
        let level = LevelState.horizon(rotationDegrees: 0, tiltDegrees: 0, isLevel: true)
        #expect(!Self.tap(&rule, tilted, at: 0))
        #expect(Self.tap(&rule, level, at: 1))
        #expect(!Self.tap(&rule, nil, at: 2))
        // Switched on again while level: the first reading gives no tap.
        #expect(!Self.tap(&rule, level, at: 5))
        // The time of the tap before the reset no longer counts.
        var fresh = LevelTapRule()
        #expect(!Self.tap(&fresh, level, at: 0))
        #expect(!Self.tap(&fresh, nil, at: 0.1))
        #expect(!Self.tap(&fresh, tilted, at: 0.2))
        #expect(Self.tap(&fresh, level, at: 0.3))
    }

    @Test func theMinimumIntervalIsOneSecond() {
        #expect(LevelTapRule.minimumInterval == .seconds(1))
    }
}

/// When the camera holds the level's tap back (docs/design/level-haptic.md, section 10, unit
/// test 11).
@MainActor
struct LevelTapHeldBackTests {
    @Test func aRunningIdleCameraDoesNotHoldTheTapBack() async {
        let model = await CameraModelTests.runningModel(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        #expect(model.sessionStatus == .running)
        #expect(!model.holdsBackLevelTap)
        for status in [CaptureStatus.idle, .saving, .failed(.captureFailed)] {
            model.captureStatus = status
            #expect(!model.holdsBackLevelTap, "\(status)")
        }
    }

    @Test func capturingHoldsTheTapBack() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = CameraModel(backend: hooked, saver: CameraModelTests.saver())
        await model.send(.start)
        await hooked.setOnCapture { [model] _ in
            await MainActor.run {
                #expect(model.captureStatus == .capturing)
                #expect(model.holdsBackLevelTap)
            }
        }
        await model.send(.capture)
        #expect(!model.holdsBackLevelTap)
        // A bracket and a long exposure are captures too.
        model.captureStatus = .capturing
        #expect(model.holdsBackLevelTap)
    }

    @Test func aCountdownHoldsTheTapBack() async {
        let ticker = Ticker()
        let model = CameraModel(
            backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: CameraModelTests.saver(),
            sleep: { _ in await ticker.sleep() })
        await model.send(.start)
        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        await model.send(.capture)
        #expect(model.drive.countdown.isRunning)
        #expect(model.captureStatus == .idle)
        #expect(model.holdsBackLevelTap)
        await model.send(.capture)
        #expect(!model.holdsBackLevelTap)
    }

    @Test func aBurstHoldsTheTapBack() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = CameraModel(backend: hooked, saver: CameraModelTests.saver())
        await model.send(.start)
        await hooked.setOnCapture { [model] count in
            await MainActor.run {
                #expect(model.drive.burstProgress != nil)
                #expect(model.holdsBackLevelTap)
            }
            guard count == 2 else { return }
            await model.send(.drive(.hardwareButton(.released)))
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(model.drive.burstProgress == nil)
        #expect(!model.holdsBackLevelTap)
    }

    @Test func aBurstHeldOnTheScreenHoldsTheTapBack() async {
        // The on-screen shutter held in Burst (docs/design/BURST.md): held back from the first
        // photo, which is requested as the shutter goes down.
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = CameraModel(backend: hooked, saver: CameraModelTests.saver())
        await model.send(.start)
        await hooked.setOnCapture { [model] count in
            await MainActor.run {
                #expect(model.drive.burstProgress != nil)
                #expect(model.holdsBackLevelTap)
            }
            guard count == 2 else { return }
            await model.send(.drive(.shutter(.released)))
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.shutter(.pressed)))
        #expect(model.drive.burstProgress == nil)
        #expect(!model.holdsBackLevelTap)
    }

    @Test func aBracketInFullAutoHoldsTheTapBack() async {
        // A bracket from the drive strip with Manual Controls off (docs/design/BRACKETING.md),
        // and its start delay, which counts down as the self-timer does.
        let backend = GatedLensBackend(lenses: [ManualFixtures.wide])
        let ticker = Ticker()
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in await ticker.sleep() },
            deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        await model.manual.record(ManualFixtures.reading)
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        #expect(!model.manual.isEnabled)
        await backend.setHoldsCapture(true)
        let shot = Task { await model.send(.capture) }
        await waitForActor { await backend.isCaptureHeld }
        #expect(model.bracketProgress != nil)
        #expect(model.holdsBackLevelTap)
        await backend.releaseCapture()
        await shot.value
        #expect(!model.holdsBackLevelTap)

        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        await model.send(.capture)
        #expect(model.drive.countdown.isRunning)
        #expect(model.holdsBackLevelTap)
        await model.send(.capture)
        #expect(!model.holdsBackLevelTap)
    }

    @Test func anIntervalSeriesThatStopsAfterATimeHoldsTheTapBack() async {
        let ticker = Ticker()
        let model = CameraModel(
            backend: ScriptedManualBackend(lenses: [ManualFixtures.wide]), saver: CameraModelTests.saver(),
            sleep: { _ in await ticker.sleep() }, deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        await model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: 10, stopAfter: .time, duration: 600))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(model.manual.intervalProgress?.timeSpan != nil)
        #expect(model.captureStatus != .capturing)
        #expect(model.holdsBackLevelTap)
        await model.send(.manual(.stopInterval))
        await waitUntil { model.manual.intervalProgress == nil }
        #expect(!model.holdsBackLevelTap)
    }

    @Test func anIntervalSeriesHoldsTheTapBackRunningAndPaused() async {
        let ticker = Ticker()
        let backend = PausingBackend(ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in await ticker.sleep() },
            deviceStatusReader: FakeStatusReader(bytes: nil))
        model.pauseAfterErrorSleep = {}
        await model.send(.start)
        let events = Task { await model.observeEvents() }
        await model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: 3))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        // Between photos: running, not capturing.
        #expect(model.manual.intervalProgress?.isPaused == false)
        #expect(model.captureStatus != .capturing)
        #expect(model.holdsBackLevelTap)

        await model.send(.setInForeground(false))
        await tick(ticker)
        await waitUntil { model.manual.intervalProgress?.isPaused == true }
        #expect(model.holdsBackLevelTap)

        await model.send(.manual(.stopInterval))
        await model.send(.setInForeground(true))
        #expect(model.manual.intervalProgress == nil)
        backend.inner.finishEvents()
        await events.value
    }

    @Test func astroHoldsTheTapBack() async {
        let backend = HookedManualBackend(ScriptedManualBackend(lenses: [AstroTests.wide]))
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in }, deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        await model.send(.astro(.setOn(true)))
        await model.send(.astro(.setFrameCount(10)))
        await backend.setOnCapture { [model] count in
            await MainActor.run {
                #expect(model.astro.isRunning)
                #expect(model.holdsBackLevelTap)
            }
            guard count == 2 else { return }
            await model.send(.astro(.stop))
        }
        await model.send(.capture)
        for _ in 0..<500 where model.astro.lastRun == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.astro.isRunning)
        #expect(!model.holdsBackLevelTap)
    }

    @Test func everySessionStatusButRunningHoldsTheTapBack() async {
        // Stopped: before the camera starts.
        let stopped = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens))
        #expect(stopped.sessionStatus == .stopped)
        #expect(stopped.holdsBackLevelTap)

        // Starting.
        let starting = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let startingModel = CameraModel(backend: starting)
        await starting.setOnStart { [startingModel] in
            await MainActor.run {
                #expect(startingModel.sessionStatus == .starting)
                #expect(startingModel.holdsBackLevelTap)
            }
        }
        await startingModel.send(.start)
        #expect(!startingModel.holdsBackLevelTap)

        // Interrupted.
        let interrupted = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let interruptedModel = await CameraModelTests.runningModel(interrupted)
        interrupted.emit(.interrupted(.inUseElsewhere))
        interrupted.finish()
        await interruptedModel.observeEvents()
        #expect(interruptedModel.sessionStatus == .interrupted(.inUseElsewhere))
        #expect(interruptedModel.holdsBackLevelTap)

        // Paused for heat.
        let hot = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hotModel = CameraModel(backend: hot)
        hot.emit(.heat(.critical))
        hot.finish()
        await hotModel.observeEvents()
        await hotModel.send(.start)
        #expect(hotModel.sessionStatus == .pausedForHeat)
        #expect(hotModel.holdsBackLevelTap)

        // Failed.
        let failed = await CameraModelTests.runningModel(
            ScriptedBackend(capabilities: CameraModelTests.oneLens, startErrors: [.configurationFailed]))
        #expect(failed.sessionStatus == .failed(.configurationFailed))
        #expect(failed.holdsBackLevelTap)

        // No picture.
        let blank = await CameraModelTests.runningModel(
            ScriptedBackend(capabilities: CameraModelTests.oneLens, captureErrors: [.blankPicture, .blankPicture]))
        await blank.send(.capture)
        #expect(blank.sessionStatus == .noPicture)
        #expect(blank.holdsBackLevelTap)
    }
}
