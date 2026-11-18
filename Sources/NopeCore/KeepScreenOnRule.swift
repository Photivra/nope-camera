import Foundation

/// What Keep Screen On needs to know about the camera screen and the device
/// (`docs/design/keep-screen-on.md`, section 3).
///
/// An interface fills it in and passes it to ``SeriesScreenKeeper/update(isSeriesRunning:isInForeground:keepScreenOn:)``
/// whenever a value changes. Every value is a fact the interface or the model already has; none
/// needs a new sensor.
public struct KeepScreenOnConditions: Equatable, Sendable {
    /// Whether the Keep Screen On switch is on (``NopeSettings/keepsScreenOn``).
    public var isSwitchOn: Bool

    /// Whether the app is active in the foreground.
    public var isActive: Bool

    /// Whether the camera screen is in front: no sheet, popover or full-screen cover over it.
    public var isCameraInFront: Bool

    /// Whether the camera is running (``SessionStatus/running``): not starting, paused,
    /// interrupted, without permission or in first run.
    public var isCameraRunning: Bool

    /// Whether the Battery Low warning shows (``DeviceStatus/batteryWarning``).
    public var isBatteryLow: Bool

    /// Whether Low Power Mode is on, which dims the screen sooner.
    public var isLowPowerMode: Bool

    /// Creates the conditions.
    ///
    /// - Parameters:
    ///   - isSwitchOn: Whether the switch is on.
    ///   - isActive: Whether the app is active in the foreground.
    ///   - isCameraInFront: Whether the camera screen is in front.
    ///   - isCameraRunning: Whether the camera is running.
    ///   - isBatteryLow: Whether the Battery Low warning shows.
    ///   - isLowPowerMode: Whether Low Power Mode is on.
    public init(
        isSwitchOn: Bool, isActive: Bool, isCameraInFront: Bool, isCameraRunning: Bool, isBatteryLow: Bool,
        isLowPowerMode: Bool
    ) {
        self.isSwitchOn = isSwitchOn
        self.isActive = isActive
        self.isCameraInFront = isCameraInFront
        self.isCameraRunning = isCameraRunning
        self.isBatteryLow = isBatteryLow
        self.isLowPowerMode = isLowPowerMode
    }

    /// The switch off: Keep Screen On is never used.
    public static let off = KeepScreenOnConditions(
        isSwitchOn: false, isActive: false, isCameraInFront: false, isCameraRunning: false, isBatteryLow: false,
        isLowPowerMode: false)

    /// Whether Keep Screen On is used now: the switch is on, the app is active, the camera
    /// screen is in front, the camera runs and the Battery Low warning doesn't show.
    public var isUsed: Bool {
        isSwitchOn && isActive && isCameraInFront && isCameraRunning && !isBatteryLow
    }
}

/// What Keep Screen On asks of the screen at one moment.
public struct KeepScreenOnDecision: Equatable, Sendable {
    /// Whether the setting is used at all (``KeepScreenOnConditions/isUsed``). When `false`, the
    /// idle timer is on and the brightness is the person's.
    public let isUsed: Bool

    /// Whether the idle timer is off, so the screen doesn't lock by itself.
    public let keepsAwake: Bool

    /// Whether the screen is dimmed.
    public let dims: Bool

    /// How long until the decision changes without any new activity (the screen dims, or the
    /// limit is reached), or `nil` when nothing changes until something else does.
    public let nextChange: Duration?

    /// Creates a decision.
    ///
    /// - Parameters:
    ///   - isUsed: Whether the setting is used.
    ///   - keepsAwake: Whether the idle timer is off.
    ///   - dims: Whether the screen is dimmed.
    ///   - nextChange: How long until the decision changes, or `nil`.
    public init(isUsed: Bool, keepsAwake: Bool, dims: Bool, nextChange: Duration?) {
        self.isUsed = isUsed
        self.keepsAwake = keepsAwake
        self.dims = dims
        self.nextChange = nextChange
    }

    /// The setting isn't used: nothing is changed.
    public static let unused = KeepScreenOnDecision(isUsed: false, keepsAwake: false, dims: false, nextChange: nil)
}

/// The rule of Keep Screen On (issue #97, `docs/design/keep-screen-on.md`): while it is used,
/// the screen stays on until ``limit`` after the last touch or photo, and dims after
/// ``dimDelay`` without one (``lowPowerDimDelay`` in Low Power Mode).
///
/// A pure value: it reads no clock and changes nothing. ``SeriesScreenKeeper`` gives it the
/// conditions, the time of the last activity and the time now, applies its answer to the screen
/// and schedules one wake-up for the next change, so nothing polls (AGENTS.md, "Battery").
///
/// The times are proposals from the design, not measurements; the UI tests shorten them.
///
/// ```swift
/// let decision = KeepScreenOnRule.standard.decide(conditions, lastActivity: touched, now: .now)
/// screen.isIdleTimerDisabled = decision.keepsAwake
/// ```
public struct KeepScreenOnRule: Equatable, Sendable {
    /// How long without activity before the screen dims: 2 minutes.
    public var dimDelay: Duration

    /// How long without activity before the screen dims in Low Power Mode: 30 seconds, iOS's
    /// own shortest Auto-Lock time.
    public var lowPowerDimDelay: Duration

    /// How long without activity before the phone's Auto-Lock applies again: 30 minutes.
    public var limit: Duration

    /// Creates a rule with its times.
    ///
    /// - Parameters:
    ///   - dimDelay: How long without activity before the screen dims.
    ///   - lowPowerDimDelay: The same in Low Power Mode.
    ///   - limit: How long without activity before the phone's Auto-Lock applies again.
    public init(dimDelay: Duration, lowPowerDimDelay: Duration, limit: Duration) {
        self.dimDelay = dimDelay
        self.lowPowerDimDelay = lowPowerDimDelay
        self.limit = limit
    }

    /// The times of the design: 2 minutes, 30 seconds and 30 minutes.
    public static let standard = KeepScreenOnRule(dimDelay: .seconds(120), lowPowerDimDelay: .seconds(30), limit: .seconds(1800))

    /// What the screen should do now.
    ///
    /// - Parameters:
    ///   - conditions: The camera screen and the device now.
    ///   - lastActivity: When the person last touched the camera screen, changed a control or
    ///     took a photo, or when the setting last started being used.
    ///   - now: The time now, on the same clock.
    /// - Returns: Whether the idle timer is off, whether the screen is dimmed, and when that
    ///   next changes. After ``limit`` the idle timer is on again and the screen stays dimmed
    ///   until it is touched or locks.
    public func decide(
        _ conditions: KeepScreenOnConditions, lastActivity: ContinuousClock.Instant, now: ContinuousClock.Instant
    ) -> KeepScreenOnDecision {
        guard conditions.isUsed else { return .unused }
        // A last activity in the future (a clock read out of order) counts as now.
        let elapsed = max(.zero, lastActivity.duration(to: now))
        let delay = conditions.isLowPowerMode ? lowPowerDimDelay : dimDelay
        let dims = elapsed >= delay
        guard elapsed < limit else { return KeepScreenOnDecision(isUsed: true, keepsAwake: false, dims: dims, nextChange: nil) }
        return KeepScreenOnDecision(
            isUsed: true, keepsAwake: true, dims: dims, nextChange: dims ? limit - elapsed : delay - elapsed)
    }
}
