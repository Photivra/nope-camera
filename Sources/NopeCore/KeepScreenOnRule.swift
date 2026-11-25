import Foundation

/// How long Keep Screen On waits without a touch or photo before it dims the screen: the person's
/// Dim After choice (issue #119, `docs/design/finish-1.0.md`, section 4), under Settings › Screen.
///
/// ``standard`` (2 minutes) is the time Keep Screen On used before the choice existed, so
/// nothing changes for anyone who doesn't open the menu. With ``never`` the screen keeps its
/// brightness, except in Low Power Mode and when the phone is hot, where it still dims after
/// ``KeepScreenOnRule/lowPowerDimDelay`` (``KeepScreenOnConditions/dimsSooner``); Battery Low
/// and ``KeepScreenOnRule/limit`` apply under every choice. The choice belongs to Keep Screen
/// On only: an interval series or an Astro run still dims the screen at once
/// (``SeriesScreenKeeper``; owner decision 8, `docs/plans/1.0.0-finish.md`, section 6).
///
/// Stored by its raw value, which never changes once released (``NopeSettings/dimAfter``).
public enum DimAfter: String, CaseIterable, Codable, Sendable {
    /// After 1 minute.
    case oneMinute
    /// After 2 minutes: the default.
    case twoMinutes
    /// After 5 minutes.
    case fiveMinutes
    /// Never, apart from Low Power Mode and heat. Uses more battery and can warm the phone.
    case never

    /// The default: 2 minutes, Keep Screen On's time before the choice existed.
    public static let standard = DimAfter.twoMinutes
}

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

    /// The person's Dim After choice (``NopeSettings/dimAfter``).
    public var dimAfter: DimAfter

    /// How hot the device is, as the camera last reported it (``CameraModel/heatLevel``). At
    /// ``hotHeatLevel`` or above the screen dims sooner, as in Low Power Mode.
    public var heatLevel: HeatLevel

    /// The heat level from which the screen dims after ``KeepScreenOnRule/lowPowerDimDelay``
    /// whatever ``dimAfter`` says: `serious`, where the system "may reduce performance" and
    /// Apple asks apps to reduce their work
    /// ([ProcessInfo.ThermalState.serious](https://developer.apple.com/documentation/foundation/processinfo/thermalstate/serious)).
    /// Owner decision 7 (`docs/plans/1.0.0-finish.md`, section 6). At `critical` the camera
    /// pauses, so Keep Screen On isn't used at all.
    public static let hotHeatLevel = HeatLevel.serious

    /// Creates the conditions.
    ///
    /// - Parameters:
    ///   - isSwitchOn: Whether the switch is on.
    ///   - isActive: Whether the app is active in the foreground.
    ///   - isCameraInFront: Whether the camera screen is in front.
    ///   - isCameraRunning: Whether the camera is running.
    ///   - isBatteryLow: Whether the Battery Low warning shows.
    ///   - isLowPowerMode: Whether Low Power Mode is on.
    ///   - dimAfter: The Dim After choice; ``DimAfter/standard`` by default.
    ///   - heatLevel: How hot the device is; `nominal` by default.
    public init(
        isSwitchOn: Bool, isActive: Bool, isCameraInFront: Bool, isCameraRunning: Bool, isBatteryLow: Bool,
        isLowPowerMode: Bool, dimAfter: DimAfter = .standard, heatLevel: HeatLevel = .nominal
    ) {
        self.isSwitchOn = isSwitchOn
        self.isActive = isActive
        self.isCameraInFront = isCameraInFront
        self.isCameraRunning = isCameraRunning
        self.isBatteryLow = isBatteryLow
        self.isLowPowerMode = isLowPowerMode
        self.dimAfter = dimAfter
        self.heatLevel = heatLevel
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

    /// Whether the screen dims after ``KeepScreenOnRule/lowPowerDimDelay`` whatever
    /// ``dimAfter`` says: in Low Power Mode, and when the device is at ``hotHeatLevel`` or above.
    public var dimsSooner: Bool {
        isLowPowerMode || heatLevel >= Self.hotHeatLevel
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
/// the screen stays on until ``limit`` after the last touch or photo, and dims after the
/// person's Dim After choice without one (issue #119, ``dimDelays``), or after
/// ``lowPowerDimDelay`` in Low Power Mode and when the phone is hot
/// (``KeepScreenOnConditions/dimsSooner``). With Dim After set to Never it doesn't dim otherwise.
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
    /// How long without activity before the screen dims, for each Dim After choice but Never.
    public struct DimDelays: Equatable, Sendable {
        /// For ``DimAfter/oneMinute``.
        public var oneMinute: Duration
        /// For ``DimAfter/twoMinutes``.
        public var twoMinutes: Duration
        /// For ``DimAfter/fiveMinutes``.
        public var fiveMinutes: Duration

        /// Creates the delays.
        ///
        /// - Parameters:
        ///   - oneMinute: The delay for 1 Minute.
        ///   - twoMinutes: The delay for 2 Minutes.
        ///   - fiveMinutes: The delay for 5 Minutes.
        public init(oneMinute: Duration, twoMinutes: Duration, fiveMinutes: Duration) {
            self.oneMinute = oneMinute
            self.twoMinutes = twoMinutes
            self.fiveMinutes = fiveMinutes
        }

        /// The design's times: 1, 2 and 5 minutes (`docs/design/finish-1.0.md`, 4.1).
        public static let standard = DimDelays(oneMinute: .seconds(60), twoMinutes: .seconds(120), fiveMinutes: .seconds(300))

        /// The delay of a choice.
        ///
        /// - Parameter choice: The Dim After choice.
        /// - Returns: The delay, or `nil` for ``DimAfter/never``.
        public func delay(for choice: DimAfter) -> Duration? {
            switch choice {
            case .oneMinute: oneMinute
            case .twoMinutes: twoMinutes
            case .fiveMinutes: fiveMinutes
            case .never: nil
            }
        }
    }

    /// How long without activity before the screen dims, for each Dim After choice.
    public var dimDelays: DimDelays

    /// How long without activity before the screen dims in Low Power Mode and when the phone is
    /// hot, whatever Dim After says: 30 seconds, iOS's own shortest Auto-Lock time.
    public var lowPowerDimDelay: Duration

    /// How long without activity before the phone's Auto-Lock applies again: 30 minutes.
    public var limit: Duration

    /// Creates a rule with its times.
    ///
    /// - Parameters:
    ///   - dimDelays: How long without activity before the screen dims, for each choice.
    ///   - lowPowerDimDelay: The same in Low Power Mode and when the phone is hot.
    ///   - limit: How long without activity before the phone's Auto-Lock applies again.
    public init(dimDelays: DimDelays, lowPowerDimDelay: Duration, limit: Duration) {
        self.dimDelays = dimDelays
        self.lowPowerDimDelay = lowPowerDimDelay
        self.limit = limit
    }

    /// Creates a rule that dims after the same time for every Dim After choice but Never, as the
    /// UI tests and the clock test need.
    ///
    /// - Parameters:
    ///   - dimDelay: How long without activity before the screen dims, for 1, 2 and 5 minutes.
    ///   - lowPowerDimDelay: The same in Low Power Mode and when the phone is hot.
    ///   - limit: How long without activity before the phone's Auto-Lock applies again.
    public init(dimDelay: Duration, lowPowerDimDelay: Duration, limit: Duration) {
        self.init(
            dimDelays: DimDelays(oneMinute: dimDelay, twoMinutes: dimDelay, fiveMinutes: dimDelay),
            lowPowerDimDelay: lowPowerDimDelay, limit: limit)
    }

    /// The times of the design: 1, 2 or 5 minutes, 30 seconds and 30 minutes.
    public static let standard = KeepScreenOnRule(dimDelays: .standard, lowPowerDimDelay: .seconds(30), limit: .seconds(1800))

    /// What the screen should do now.
    ///
    /// - Parameters:
    ///   - conditions: The camera screen and the device now.
    ///   - lastActivity: When the person last touched the camera screen, changed a control or
    ///     took a photo, or when the setting last started being used.
    ///   - now: The time now, on the same clock.
    /// - Returns: Whether the idle timer is off, whether the screen is dimmed, and when that
    ///   next changes. After ``limit`` the idle timer is on again and a dimmed screen stays
    ///   dimmed until it is touched or locks.
    public func decide(
        _ conditions: KeepScreenOnConditions, lastActivity: ContinuousClock.Instant, now: ContinuousClock.Instant
    ) -> KeepScreenOnDecision {
        guard conditions.isUsed else { return .unused }
        // A last activity in the future (a clock read out of order) counts as now.
        let elapsed = max(.zero, lastActivity.duration(to: now))
        // `nil` with Never: the screen dims only in Low Power Mode or when hot.
        let delay = conditions.dimsSooner ? lowPowerDimDelay : dimDelays.delay(for: conditions.dimAfter)
        let dims = delay.map { elapsed >= $0 } ?? false
        guard elapsed < limit else { return KeepScreenOnDecision(isUsed: true, keepsAwake: false, dims: dims, nextChange: nil) }
        let nextChange: Duration = if let delay, !dims { delay - elapsed } else { limit - elapsed }
        return KeepScreenOnDecision(isUsed: true, keepsAwake: true, dims: dims, nextChange: nextChange)
    }
}
