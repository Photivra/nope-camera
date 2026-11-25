import Foundation
import Testing

@testable import NopeCore

/// A screen that counts each change, so a test can check that the keeper leaves it alone.
@MainActor
final class CountingScreen: ScreenControlling {
    /// The brightness.
    var brightness: Double { didSet { brightnessChanges += 1 } }

    /// Whether the idle timer is off.
    var isIdleTimerDisabled = false { didSet { idleTimerChanges += 1 } }

    /// How often the brightness was set.
    var brightnessChanges = 0

    /// How often the idle timer was set.
    var idleTimerChanges = 0

    init(brightness: Double) {
        self.brightness = brightness
    }
}

/// A clock the test moves by hand. `sleep` suspends until ``advance(by:)`` passes its deadline.
@MainActor
final class KeeperClock {
    /// The time now.
    private(set) var now = ContinuousClock.now

    /// The sleepers, with their deadlines.
    private var sleepers: [(deadline: ContinuousClock.Instant, continuation: CheckedContinuation<Void, Never>)] = []

    /// How many sleeps are waiting.
    var waiting: Int { sleepers.count }

    /// Waits until the clock passes the deadline.
    func sleep(until deadline: ContinuousClock.Instant) async {
        guard deadline > now, !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            sleepers.append((deadline, continuation))
        }
    }

    /// Moves the clock on and wakes every sleeper whose deadline passed.
    func advance(by duration: Duration) {
        now += duration
        let due = sleepers.filter { $0.deadline <= now }
        sleepers.removeAll { $0.deadline <= now }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Wakes every sleeper, at the end of a test.
    func wakeAll() {
        let all = sleepers
        sleepers.removeAll()
        for sleeper in all { sleeper.continuation.resume() }
    }
}

/// Keep Screen On (issue #97): the rule for every condition and both timings, and the keeper
/// with a fake screen and clock, including a series and the setting together (issues #48 and
/// #99), and the brightness put back on each way out.
@MainActor
struct KeepScreenOnTests {
    /// Conditions with every value as Keep Screen On needs it, changed by `change`.
    static func conditions(_ change: (inout KeepScreenOnConditions) -> Void = { _ in }) -> KeepScreenOnConditions {
        var conditions = KeepScreenOnConditions(
            isSwitchOn: true, isActive: true, isCameraInFront: true, isCameraRunning: true, isBatteryLow: false,
            isLowPowerMode: false)
        change(&conditions)
        return conditions
    }

    /// A keeper on a fake screen and clock with the standard times.
    static func keeper(brightness: Double = 0.8) -> (SeriesScreenKeeper, CountingScreen, KeeperClock) {
        let screen = CountingScreen(brightness: brightness)
        let clock = KeeperClock()
        let keeper = SeriesScreenKeeper(
            screen: screen, rule: .standard, now: { clock.now }, sleep: { deadline in await clock.sleep(until: deadline) })
        return (keeper, screen, clock)
    }

    /// Moves the clock and lets the keeper's wake-up run.
    static func advance(_ clock: KeeperClock, by duration: Duration) async {
        clock.advance(by: duration)
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: - The rule

    @Test func theStandardTimesAreTheDesigns() {
        #expect(KeepScreenOnRule.standard.dimDelays == .standard)
        #expect(KeepScreenOnRule.standard.dimDelays.delay(for: .twoMinutes) == .seconds(120))
        #expect(KeepScreenOnRule.standard.lowPowerDimDelay == .seconds(30))
        #expect(KeepScreenOnRule.standard.limit == .seconds(1800))
        #expect(!KeepScreenOnConditions.off.isUsed)
        #expect(Self.conditions().isUsed)
    }

    @Test func notUsedUnlessEveryConditionHolds() {
        let now = ContinuousClock.now
        let changes: [(String, (inout KeepScreenOnConditions) -> Void)] = [
            ("switch off", { $0.isSwitchOn = false }),
            ("not active", { $0.isActive = false }),
            ("a sheet over the camera", { $0.isCameraInFront = false }),
            ("the camera not running", { $0.isCameraRunning = false }),
            ("Battery Low", { $0.isBatteryLow = true }),
        ]
        for (name, change) in changes {
            let decision = KeepScreenOnRule.standard.decide(Self.conditions(change), lastActivity: now, now: now)
            #expect(decision == .unused, "\(name)")
            #expect(!decision.keepsAwake && !decision.dims && decision.nextChange == nil, "\(name)")
        }
        // Low Power Mode alone doesn't stop it.
        #expect(KeepScreenOnRule.standard.decide(Self.conditions { $0.isLowPowerMode = true }, lastActivity: now, now: now).isUsed)
    }

    @Test func keepsAwakeThenDimsThenEndsAtTheLimit() {
        let rule = KeepScreenOnRule.standard
        let start = ContinuousClock.now
        let at = { (seconds: Int) in rule.decide(Self.conditions(), lastActivity: start, now: start + .seconds(seconds)) }
        #expect(at(0) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(120)))
        #expect(at(119) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(1)))
        #expect(at(120) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: true, nextChange: .seconds(1680)))
        #expect(at(1799) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: true, nextChange: .seconds(1)))
        #expect(at(1800) == KeepScreenOnDecision(isUsed: true, keepsAwake: false, dims: true, nextChange: nil))
        #expect(at(5000) == KeepScreenOnDecision(isUsed: true, keepsAwake: false, dims: true, nextChange: nil))
    }

    @Test func lowPowerModeDimsAfterThirtySeconds() {
        let rule = KeepScreenOnRule.standard
        let start = ContinuousClock.now
        let low = Self.conditions { $0.isLowPowerMode = true }
        #expect(rule.decide(low, lastActivity: start, now: start).nextChange == .seconds(30))
        #expect(!rule.decide(low, lastActivity: start, now: start + .seconds(29)).dims)
        let dimmed = rule.decide(low, lastActivity: start, now: start + .seconds(30))
        #expect(dimmed.dims && dimmed.keepsAwake)
        #expect(dimmed.nextChange == .seconds(1770))
        // The limit is the same.
        #expect(!rule.decide(low, lastActivity: start, now: start + .seconds(1800)).keepsAwake)
    }

    @Test func anActivityAfterNowCountsAsNow() {
        let now = ContinuousClock.now
        let decision = KeepScreenOnRule.standard.decide(Self.conditions(), lastActivity: now + .seconds(10), now: now)
        #expect(decision == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(120)))
    }

    @Test func aRuleWithOtherTimes() {
        let rule = KeepScreenOnRule(dimDelay: .seconds(3), lowPowerDimDelay: .seconds(1), limit: .seconds(10))
        let now = ContinuousClock.now
        #expect(rule.decide(Self.conditions(), lastActivity: now, now: now + .seconds(3)).dims)
        #expect(!rule.decide(Self.conditions(), lastActivity: now, now: now + .seconds(10)).keepsAwake)
    }

    // MARK: - The keeper with Keep Screen On

    @Test func offLeavesTheScreenAlone() async {
        let (keeper, screen, clock) = Self.keeper()
        keeper.update(isSeriesRunning: false, isInForeground: true)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.isSwitchOn = false })
        keeper.noteActivity()
        await Self.advance(clock, by: .seconds(3600))
        for _ in 0..<50 { await Task.yield() }
        #expect(screen.idleTimerChanges == 0)
        #expect(screen.brightnessChanges == 0)
        #expect(!keeper.isKeepingAwake && !keeper.isDimmed)
        #expect(clock.waiting == 0, "nothing is scheduled")
    }

    @Test func keepsAwakeDimsAndBrightens() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.8)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(screen.isIdleTimerDisabled && keeper.isKeepingAwake)
        #expect(!keeper.isDimmed)
        for _ in 0..<50 { await Task.yield() }
        #expect(clock.waiting == 1, "one wake-up, for the dimming")
        await Self.advance(clock, by: .seconds(119))
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(1))
        #expect(keeper.isDimmed)
        #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness)
        #expect(screen.isIdleTimerDisabled)
        // The cover's touch brightens and counts as activity: dims again 2 minutes later.
        keeper.brighten()
        #expect(!keeper.isDimmed)
        #expect(screen.brightness == 0.8)
        await Self.advance(clock, by: .seconds(119))
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(1))
        #expect(keeper.isDimmed)
        // A repeated update changes nothing.
        let changes = screen.brightnessChanges
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(screen.brightnessChanges == changes)
        clock.wakeAll()
    }

    @Test func autoLockAppliesAgainAtTheLimitAndTheScreenStaysDimmed() async {
        let (keeper, screen, clock) = Self.keeper()
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(120))
        #expect(keeper.isDimmed)
        await Self.advance(clock, by: .seconds(1679))
        #expect(screen.isIdleTimerDisabled)
        await Self.advance(clock, by: .seconds(1))
        #expect(!screen.isIdleTimerDisabled && !keeper.isKeepingAwake)
        #expect(keeper.isDimmed, "dimmed until touched or locked")
        #expect(clock.waiting == 0, "nothing more is scheduled")
        // A photo before the lock starts a new 30 minutes, and leaves the screen dimmed.
        keeper.noteActivity()
        #expect(screen.isIdleTimerDisabled)
        #expect(keeper.isDimmed)
        keeper.brighten()
        #expect(screen.brightness == 0.8)
        clock.wakeAll()
    }

    @Test func activityWhileDimmedKeepsItDimmedAndCountsAgain() async {
        let (keeper, screen, clock) = Self.keeper()
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(1000))
        #expect(keeper.isDimmed)
        keeper.noteActivity()
        #expect(keeper.isDimmed)
        await Self.advance(clock, by: .seconds(1799))
        #expect(screen.isIdleTimerDisabled, "the limit counts from the photo")
        await Self.advance(clock, by: .seconds(1))
        #expect(!screen.isIdleTimerDisabled)
        clock.wakeAll()
    }

    @Test func aReplacedWakeUpDoesNothing() async {
        let (keeper, _, clock) = Self.keeper()
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(60))
        keeper.noteActivity()
        // The first wake-up's time passes; it was replaced, so the screen isn't dimmed yet.
        await Self.advance(clock, by: .seconds(60))
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(60))
        #expect(keeper.isDimmed)
        clock.wakeAll()
    }

    @Test func aScreenAlreadyDarkIsNotDimmed() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.1)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(120))
        #expect(!keeper.isDimmed, "no cover when nothing would change")
        #expect(screen.brightnessChanges == 0)
        #expect(screen.isIdleTimerDisabled)
        clock.wakeAll()
    }

    @Test func lowPowerModeDimsSooner() async {
        let (keeper, _, clock) = Self.keeper()
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.isLowPowerMode = true })
        await Self.advance(clock, by: .seconds(30))
        #expect(keeper.isDimmed)
        clock.wakeAll()
    }

    @Test func eachWayOutRestoresTheScreen() async {
        let ways: [(String, (inout KeepScreenOnConditions) -> Void)] = [
            ("switch off", { $0.isSwitchOn = false }),
            ("not active", { $0.isActive = false }),
            ("a sheet over the camera", { $0.isCameraInFront = false }),
            ("the camera paused", { $0.isCameraRunning = false }),
            ("Battery Low", { $0.isBatteryLow = true }),
        ]
        for (name, change) in ways {
            let (keeper, screen, clock) = Self.keeper(brightness: 0.6)
            keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
            await Self.advance(clock, by: .seconds(120))
            #expect(keeper.isDimmed, "\(name)")
            keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions(change))
            #expect(!screen.isIdleTimerDisabled, "\(name)")
            #expect(screen.brightness == 0.6, "\(name)")
            #expect(!keeper.isDimmed && !keeper.isKeepingAwake, "\(name)")
            // Used again: a full count, so the screen doesn't dim at once.
            keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
            #expect(screen.isIdleTimerDisabled, "\(name)")
            await Self.advance(clock, by: .seconds(119))
            #expect(!keeper.isDimmed, "\(name)")
            await Self.advance(clock, by: .seconds(1))
            #expect(keeper.isDimmed, "\(name)")
            clock.wakeAll()
        }
    }

    @Test func leavingTheForegroundRestoresTheScreen() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.6)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(120))
        keeper.update(isSeriesRunning: false, isInForeground: false, keepScreenOn: Self.conditions { $0.isActive = false })
        #expect(screen.brightness == 0.6)
        #expect(!screen.isIdleTimerDisabled)
        clock.wakeAll()
    }

    // MARK: - A series and Keep Screen On together

    @Test func aRunningSeriesWins() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.7)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        // The series dims at once, with no limit.
        keeper.update(isSeriesRunning: true, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(keeper.isDimmed)
        #expect(screen.isIdleTimerDisabled)
        for _ in 0..<50 { await Task.yield() }
        #expect(clock.waiting == 0, "no wake-up during a series")
        await Self.advance(clock, by: .seconds(7200))
        #expect(screen.isIdleTimerDisabled)
        // Brightened during the series, it stays bright until the series ends.
        keeper.brighten()
        keeper.update(isSeriesRunning: true, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(!keeper.isDimmed)
        #expect(screen.brightness == 0.7)
        // The series ends: Keep Screen On counts from zero.
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(screen.isIdleTimerDisabled)
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(119))
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(1))
        #expect(keeper.isDimmed)
        clock.wakeAll()
    }

    @Test func aSeriesThatStartsDimmedKeepsTheBrightnessToRestore() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.9)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(120))
        #expect(keeper.isDimmed)
        keeper.update(isSeriesRunning: true, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(keeper.isDimmed)
        #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness)
        // The series ends with the setting off: everything is put back.
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.isSwitchOn = false })
        #expect(screen.brightness == 0.9)
        #expect(!screen.isIdleTimerDisabled)
        clock.wakeAll()
    }

    @Test func aSeriesAfterTheLimitKeepsTheScreenAwakeAgain() async {
        let (keeper, screen, clock) = Self.keeper()
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await Self.advance(clock, by: .seconds(120))
        await Self.advance(clock, by: .seconds(1680))
        #expect(!screen.isIdleTimerDisabled)
        keeper.update(isSeriesRunning: true, isInForeground: true, keepScreenOn: Self.conditions())
        #expect(screen.isIdleTimerDisabled)
        clock.wakeAll()
    }

    /// Issue #99: a series doesn't dim a screen already at 10% or darker, and shows no cover.
    @Test func aSeriesDoesNotDimAScreenAlreadyDark() {
        for brightness in [0.1, 0.05, 0] {
            let (keeper, screen, _) = Self.keeper(brightness: brightness)
            keeper.update(isSeriesRunning: true, isInForeground: true)
            #expect(screen.isIdleTimerDisabled, "\(brightness)")
            #expect(!keeper.isDimmed, "\(brightness)")
            #expect(screen.brightnessChanges == 0, "\(brightness)")
            // The person's own change during the series is kept when it ends.
            screen.brightness = 0.02
            keeper.update(isSeriesRunning: false, isInForeground: true)
            #expect(screen.brightness == 0.02, "\(brightness)")
            #expect(!screen.isIdleTimerDisabled, "\(brightness)")
        }
        // Just above the dimmed level, it dims.
        let (keeper, screen, _) = Self.keeper(brightness: 0.11)
        keeper.update(isSeriesRunning: true, isInForeground: true)
        #expect(keeper.isDimmed)
        #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness)
    }

    @Test func theSystemClockSchedulesTheWakeUp() async {
        let screen = CountingScreen(brightness: 0.8)
        let keeper = SeriesScreenKeeper(
            screen: screen, rule: KeepScreenOnRule(dimDelay: .milliseconds(20), lowPowerDimDelay: .milliseconds(20), limit: .seconds(60)))
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions())
        await waitUntil { keeper.isDimmed }
        #expect(keeper.isDimmed)
        // A pending wake-up for the limit is cancelled when the setting stops being used.
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: .off)
        #expect(!keeper.isDimmed)
        #expect(!screen.isIdleTimerDisabled)
    }

    // MARK: - Activity from the model

    @Test func theModelCountsThePersonsActionsAndPhotos() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: CameraModelTests.saver())
        await model.send(.start)
        await model.send(.setInForeground(true))
        await model.send(.releasePhotoPreviews)
        #expect(model.activityCount == 0, "the camera's own lifecycle isn't activity")
        await model.send(.setCleanView(true))
        #expect(model.activityCount == 1)
        await model.send(.capture)
        await waitUntil { model.activityCount == 3 }
        #expect(model.activityCount == 3, "the shutter and the saved photo")
        // Actions alone, for what stays until the next action: the saved photo isn't one.
        #expect(model.actionCount == 2)
    }

    @Test func whichIntentsAreActivity() {
        let lifecycle: [CameraIntent] = [.start, .requestPermission, .setPhotoSizes([:]), .setInForeground(true), .releasePhotoPreviews]
        for intent in lifecycle { #expect(!intent.isActivity, "\(intent)") }
        let actions: [CameraIntent] = [
            .selectLens("wide"), .capture, .manual(.allAuto), .setCleanView(false), .drive(.cancelTimer),
            .auto(.setFollowsFaces(true)), .light(.setTorch(false)), .astro(.stop), .bracket(.setOn(false)),
            .comparison(.close), .setViewerOpen(true),
        ]
        for intent in actions { #expect(intent.isActivity, "\(intent)") }
    }

    // MARK: - The setting

    @Test func theSettingIsOffByDefaultAndStored() {
        let defaults = UserDefaults(suiteName: "KeepScreenOnTests.\(UUID().uuidString)")!
        let settings = NopeSettings(defaults: defaults)
        #expect(!settings.keepsScreenOn)
        settings.setKeepsScreenOn(true)
        #expect(NopeSettings(defaults: defaults).keepsScreenOn)
        defaults.set(false, forKey: "NopeSettings.keepsScreenOn")
        #expect(settings.reload())
        #expect(!settings.keepsScreenOn)
    }

    // MARK: - Dim After (issue #119)

    @Test func theDimAfterChoicesAreTheDesigns() {
        #expect(DimAfter.allCases == [.oneMinute, .twoMinutes, .fiveMinutes, .never])
        #expect(DimAfter.allCases.map(\.rawValue) == ["oneMinute", "twoMinutes", "fiveMinutes", "never"])
        #expect(DimAfter.standard == .twoMinutes, "today's 2 minutes, so nothing changes by default")
        let delays = KeepScreenOnRule.DimDelays.standard
        #expect(delays.delay(for: .oneMinute) == .seconds(60))
        #expect(delays.delay(for: .twoMinutes) == .seconds(120))
        #expect(delays.delay(for: .fiveMinutes) == .seconds(300))
        #expect(delays.delay(for: .never) == nil)
        #expect(KeepScreenOnConditions.hotHeatLevel == .serious)
        #expect(KeepScreenOnConditions.off.dimAfter == .twoMinutes)
        #expect(KeepScreenOnConditions.off.heatLevel == .nominal)
        // A rule made with one delay dims after it for every choice but Never.
        let one = KeepScreenOnRule(dimDelay: .seconds(3), lowPowerDimDelay: .seconds(1), limit: .seconds(10))
        #expect(one.dimDelays == KeepScreenOnRule.DimDelays(oneMinute: .seconds(3), twoMinutes: .seconds(3), fiveMinutes: .seconds(3)))
    }

    @Test func eachChoiceDimsAtItsTime() {
        let rule = KeepScreenOnRule.standard
        let start = ContinuousClock.now
        for (choice, seconds) in [(DimAfter.oneMinute, 60), (.twoMinutes, 120), (.fiveMinutes, 300)] {
            let conditions = Self.conditions { $0.dimAfter = choice }
            let at = { (elapsed: Int) in rule.decide(conditions, lastActivity: start, now: start + .seconds(elapsed)) }
            #expect(at(0) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(seconds)), "\(choice)")
            #expect(!at(seconds - 1).dims, "\(choice)")
            #expect(
                at(seconds) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: true, nextChange: .seconds(1800 - seconds)),
                "\(choice)")
            #expect(at(1800) == KeepScreenOnDecision(isUsed: true, keepsAwake: false, dims: true, nextChange: nil), "\(choice)")
        }
    }

    @Test func neverKeepsTheBrightnessUntilTheLimit() {
        let rule = KeepScreenOnRule.standard
        let start = ContinuousClock.now
        let never = Self.conditions { $0.dimAfter = .never }
        let at = { (elapsed: Int) in rule.decide(never, lastActivity: start, now: start + .seconds(elapsed)) }
        #expect(at(0) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(1800)))
        #expect(at(300) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(1500)))
        #expect(at(1799) == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: false, nextChange: .seconds(1)))
        // The 30-minute limit stays: Auto-Lock applies again, and the screen was never dimmed.
        #expect(at(1800) == KeepScreenOnDecision(isUsed: true, keepsAwake: false, dims: false, nextChange: nil))
    }

    @Test func lowPowerModeAndHeatDimAfterThirtySecondsUnderEveryChoice() {
        let rule = KeepScreenOnRule.standard
        let start = ContinuousClock.now
        let sooner: [(String, (inout KeepScreenOnConditions) -> Void)] = [
            ("Low Power Mode", { $0.isLowPowerMode = true }),
            ("serious heat", { $0.heatLevel = .serious }),
            ("critical heat", { $0.heatLevel = .critical }),
            ("both", { $0.isLowPowerMode = true; $0.heatLevel = .serious }),
        ]
        for choice in DimAfter.allCases {
            for (name, change) in sooner {
                let conditions = Self.conditions { $0.dimAfter = choice; change(&$0) }
                #expect(rule.decide(conditions, lastActivity: start, now: start).nextChange == .seconds(30), "\(choice), \(name)")
                #expect(!rule.decide(conditions, lastActivity: start, now: start + .seconds(29)).dims, "\(choice), \(name)")
                let dimmed = rule.decide(conditions, lastActivity: start, now: start + .seconds(30))
                #expect(dimmed == KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: true, nextChange: .seconds(1770)), "\(choice), \(name)")
            }
            // Below the serious heat level, the choice holds.
            for heat in [HeatLevel.nominal, .fair] {
                let conditions = Self.conditions { $0.dimAfter = choice; $0.heatLevel = heat }
                #expect(!rule.decide(conditions, lastActivity: start, now: start + .seconds(30)).dims, "\(choice), \(heat)")
            }
        }
    }

    @Test func batteryLowAndTheLimitEndItUnderEveryChoice() {
        let rule = KeepScreenOnRule.standard
        let start = ContinuousClock.now
        for choice in DimAfter.allCases {
            let low = Self.conditions { $0.dimAfter = choice; $0.isBatteryLow = true }
            #expect(rule.decide(low, lastActivity: start, now: start) == .unused, "\(choice)")
            let atLimit = rule.decide(Self.conditions { $0.dimAfter = choice }, lastActivity: start, now: start + .seconds(1800))
            #expect(atLimit.isUsed && !atLimit.keepsAwake && atLimit.nextChange == nil, "\(choice)")
        }
    }

    @Test func theKeeperWithNeverKeepsTheScreenBrightThenLetsItLock() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.8)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.dimAfter = .never })
        #expect(screen.isIdleTimerDisabled)
        for _ in 0..<50 { await Task.yield() }
        #expect(clock.waiting == 1, "one wake-up, for the limit")
        await Self.advance(clock, by: .seconds(1799))
        #expect(!keeper.isDimmed)
        #expect(screen.brightnessChanges == 0)
        await Self.advance(clock, by: .seconds(1))
        #expect(!screen.isIdleTimerDisabled && !keeper.isKeepingAwake)
        #expect(!keeper.isDimmed, "never dimmed")
        #expect(screen.brightnessChanges == 0)
        #expect(clock.waiting == 0)
        clock.wakeAll()
    }

    @Test func theKeeperWithEachChoiceDimsAtItsTime() async {
        for (choice, seconds) in [(DimAfter.oneMinute, 60), (.fiveMinutes, 300)] {
            let (keeper, screen, clock) = Self.keeper(brightness: 0.8)
            keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.dimAfter = choice })
            await Self.advance(clock, by: .seconds(seconds - 1))
            #expect(!keeper.isDimmed, "\(choice)")
            await Self.advance(clock, by: .seconds(1))
            #expect(keeper.isDimmed, "\(choice)")
            #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness, "\(choice)")
            clock.wakeAll()
        }
    }

    @Test func theScreenDimsOnceThePhoneGetsHotEvenWithNever() async {
        let (keeper, screen, clock) = Self.keeper(brightness: 0.8)
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.dimAfter = .never })
        await Self.advance(clock, by: .seconds(10))
        // Hot after 10 seconds: dims 30 seconds after the last activity.
        keeper.update(
            isSeriesRunning: false, isInForeground: true,
            keepScreenOn: Self.conditions { $0.dimAfter = .never; $0.heatLevel = .serious })
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(19))
        #expect(!keeper.isDimmed)
        await Self.advance(clock, by: .seconds(1))
        #expect(keeper.isDimmed)
        // Cooler again: the screen stays dimmed until it is touched, then keeps its brightness.
        keeper.update(isSeriesRunning: false, isInForeground: true, keepScreenOn: Self.conditions { $0.dimAfter = .never })
        #expect(keeper.isDimmed)
        keeper.brighten()
        #expect(screen.brightness == 0.8)
        await Self.advance(clock, by: .seconds(600))
        #expect(!keeper.isDimmed)
        clock.wakeAll()
    }

    @Test func theModelPublishesTheHeatLevelForKeepScreenOn() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await CameraModelTests.runningModel(backend)
        #expect(model.heatLevel == .nominal)
        backend.emit(.heat(.serious))
        backend.finish()
        await model.observeEvents()
        #expect(model.heatLevel == .serious)
        #expect(model.sessionStatus == .running, "serious heat doesn't pause the camera")
    }

    @Test func aSeriesStillDimsAtOnceWithNever() async {
        // Decision 8 (docs/plans/1.0.0-finish.md, section 6): Dim After belongs to Keep Screen On.
        let (keeper, screen, clock) = Self.keeper(brightness: 0.7)
        keeper.update(isSeriesRunning: true, isInForeground: true, keepScreenOn: Self.conditions { $0.dimAfter = .never })
        #expect(keeper.isDimmed)
        #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness)
        clock.wakeAll()
    }

    @Test func dimAfterIsTwoMinutesByDefaultAndStoredByName() {
        let defaults = UserDefaults(suiteName: "KeepScreenOnTests.\(UUID().uuidString)")!
        let settings = NopeSettings(defaults: defaults)
        #expect(settings.dimAfter == .twoMinutes)
        for choice in DimAfter.allCases {
            settings.setDimAfter(choice)
            #expect(settings.dimAfter == choice)
            #expect(defaults.string(forKey: "NopeSettings.dimAfter") == choice.rawValue)
            #expect(NopeSettings(defaults: defaults).dimAfter == choice)
        }
        // Another process's change is picked up by reload.
        defaults.set("oneMinute", forKey: "NopeSettings.dimAfter")
        #expect(settings.reload())
        #expect(settings.dimAfter == .oneMinute)
        // An unknown stored value, as from a later version, reads as 2 Minutes.
        defaults.set("tenMinutes", forKey: "NopeSettings.dimAfter")
        #expect(NopeSettings(defaults: defaults).dimAfter == .twoMinutes)
        defaults.set(5, forKey: "NopeSettings.dimAfter")
        #expect(NopeSettings(defaults: defaults).dimAfter == .twoMinutes)
    }

    @Test func dimAfterIsInPresetsAndFactoryDefaultsResetsIt() async throws {
        let defaults = UserDefaults(suiteName: "KeepScreenOnTests.\(UUID().uuidString)")!
        let settings = NopeSettings(defaults: defaults)
        settings.setDimAfter(.never)
        let presets = SettingsPresets(settings: settings)
        let preset = try presets.saveCurrent(named: "Tripod", camera: nil)
        _ = await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(settings.dimAfter == .twoMinutes)
        _ = await presets.apply(.saved(preset.id), camera: nil, location: nil)
        #expect(settings.dimAfter == .never)
    }
}
