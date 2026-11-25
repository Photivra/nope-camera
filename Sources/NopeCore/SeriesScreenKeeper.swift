import Foundation
import Observation

/// The screen's brightness and idle timer. The app implements it with UIKit
/// (`UIScreen.brightness`, `UIApplication.isIdleTimerDisabled`); tests pass a fake.
@MainActor
public protocol ScreenControlling: AnyObject {
    /// The screen's brightness, from 0 to 1.
    var brightness: Double { get set }

    /// Whether the system's idle timer is off, so the screen doesn't lock.
    var isIdleTimerDisabled: Bool { get set }
}

/// Keeps the screen awake, and dims it, while an interval series runs (issue #48) or while Keep
/// Screen On is used (issue #97), and puts both back when that ends.
///
/// This is the only place the app turns the idle timer off or changes the brightness. It has two
/// reasons to keep the screen awake, and a running series wins:
///
/// - **A series** (an interval series, an Astro run or a focus bracket in the foreground,
///   ``CameraModel/keepsScreenForSeries``). The screen mustn't lock, or the camera stops and the
///   series with it. The screen dims at once and has no time limit;
///   dimming saves battery over a long series (AGENTS.md, "Battery").
/// - **Keep Screen On** (``KeepScreenOnRule``), while the camera screen is showing and running.
///   The screen dims after a while without activity, and the idle timer is turned on again at
///   the rule's limit. When a series ends, this reason starts counting from zero.
///
/// Neither reason dims a screen that is already at ``dimmedBrightness`` or darker (issue #99):
/// nothing would change, so no Brighten Screen cover is shown either.
///
/// An interface calls ``update(isSeriesRunning:isInForeground:keepScreenOn:)`` whenever a value
/// changes, ``noteActivity()`` for each touch, control change and photo, shows a "Brighten
/// Screen" control over the whole screen while ``isDimmed``, and announces the change to
/// VoiceOver. ``brighten()`` restores the brightness. For Keep Screen On the keeper schedules one
/// wake-up for the next change of the rule; nothing polls.
@MainActor
@Observable
public final class SeriesScreenKeeper {
    /// The brightness while dimmed, from 0 to 1. A screen already this dark or darker isn't
    /// changed. An assumption to be checked on a device: dark enough to save power, bright
    /// enough to see the progress.
    public static let dimmedBrightness = 0.1

    /// Whether the screen is dimmed now.
    public private(set) var isDimmed = false

    /// Whether the idle timer is off now.
    public private(set) var isKeepingAwake = false

    /// Why the screen is kept now.
    private enum Reason {
        /// A series runs.
        case series
        /// Keep Screen On is used.
        case keepScreenOn
    }

    /// The reason in effect, or `nil`.
    private var reason: Reason?

    /// The brightness to restore while dimmed, or `nil` when not dimmed.
    private var brightnessBeforeDimming: Double?

    /// The last inputs of ``update(isSeriesRunning:isInForeground:keepScreenOn:)``.
    private var isSeriesRunning = false
    private var isInForeground = false
    private var keepScreenOn = KeepScreenOnConditions.off

    /// When the person last did something, for Keep Screen On.
    private var lastActivity: ContinuousClock.Instant

    /// Counts scheduled wake-ups, so a wake-up that was replaced does nothing.
    private var wakeUpGeneration = 0

    /// The pending wake-up, or `nil`.
    private var wakeUp: Task<Void, Never>?

    /// The screen.
    private let screen: any ScreenControlling

    /// Keep Screen On's times.
    private let rule: KeepScreenOnRule

    /// Reads the time.
    private let now: @MainActor () -> ContinuousClock.Instant

    /// Waits until a time; throws when cancelled.
    private let sleep: @Sendable (ContinuousClock.Instant) async throws -> Void

    /// Creates the keeper. It changes nothing until a series runs or Keep Screen On is used.
    ///
    /// - Parameters:
    ///   - screen: The screen.
    ///   - rule: Keep Screen On's times; ``KeepScreenOnRule/standard`` by default. The UI tests
    ///     pass shorter ones.
    ///   - now: Reads the time, the continuous clock by default. Tests pass their own.
    ///   - sleep: Waits until a time on the continuous clock and throws when cancelled,
    ///     `Task.sleep(until:clock:)` by default. Tests pass their own.
    public init(
        screen: any ScreenControlling, rule: KeepScreenOnRule = .standard,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleep: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void = {
            try await Task.sleep(until: $0, clock: .continuous)
        }
    ) {
        self.screen = screen
        self.rule = rule
        self.now = now
        self.sleep = sleep
        lastActivity = now()
    }

    /// Keeps the screen awake, and dims it, while a series runs in the foreground or Keep
    /// Screen On is used, and puts both back otherwise.
    ///
    /// - Parameters:
    ///   - isSeriesRunning: Whether an interval series, an Astro run or a focus bracket is going on
    ///     the camera screen (``CameraModel/keepsScreenForSeries``).
    ///   - isInForeground: Whether the app is in the foreground.
    ///   - keepScreenOn: Keep Screen On's conditions; ``KeepScreenOnConditions/off`` by default.
    public func update(
        isSeriesRunning: Bool, isInForeground: Bool, keepScreenOn: KeepScreenOnConditions = .off
    ) {
        self.isSeriesRunning = isSeriesRunning
        self.isInForeground = isInForeground
        self.keepScreenOn = keepScreenOn
        apply()
    }

    /// Records a touch on the camera screen, a changed control or a photo: Keep Screen On
    /// counts again from now. A dimmed screen stays dimmed; ``brighten()`` brightens it.
    public func noteActivity() {
        lastActivity = now()
        apply()
    }

    /// Restores the brightness; the screen still doesn't lock. During a series the screen stays
    /// bright until the series ends; for Keep Screen On it counts as activity.
    public func brighten() {
        restoreBrightness()
        if reason == .keepScreenOn { noteActivity() }
    }

    /// Applies the inputs to the screen.
    private func apply() {
        if isSeriesRunning && isInForeground {
            cancelWakeUp()
            guard reason != .series else { return }
            reason = .series
            setKeepsAwake(true)
            dim()
            return
        }
        if reason == .series {
            // The series ended: Keep Screen On, if used, counts from zero.
            reason = nil
            restoreBrightness()
        }
        let decision = rule.decide(keepScreenOn, lastActivity: reason == .keepScreenOn ? lastActivity : now(), now: now())
        guard decision.isUsed else {
            reason = nil
            cancelWakeUp()
            restoreBrightness()
            setKeepsAwake(false)
            return
        }
        if reason != .keepScreenOn {
            // Starts being used (the camera screen came back, the series ended, the warning
            // went away): a full count, so the screen doesn't dim at once.
            reason = .keepScreenOn
            lastActivity = now()
        }
        setKeepsAwake(decision.keepsAwake)
        // A dimmed screen stays dimmed until it is brightened (``brighten()``, the cover's
        // touch): a photo from a hardware button, the watch or Siri counts as activity, but
        // leaves the screen as it is.
        if decision.dims { dim() }
        schedule(after: decision.nextChange)
    }

    /// Dims the screen, unless it is dimmed already or is already at ``dimmedBrightness`` or
    /// darker (issue #99).
    private func dim() {
        guard brightnessBeforeDimming == nil else { return }
        let brightness = screen.brightness
        guard brightness > Self.dimmedBrightness else { return }
        brightnessBeforeDimming = brightness
        screen.brightness = Self.dimmedBrightness
        isDimmed = true
    }

    /// Puts the brightness back, if the keeper dimmed it.
    private func restoreBrightness() {
        guard let brightness = brightnessBeforeDimming else { return }
        screen.brightness = brightness
        brightnessBeforeDimming = nil
        isDimmed = false
    }

    /// Turns the idle timer off or on, when that changes it.
    ///
    /// - Parameter keepsAwake: Whether the idle timer is off.
    private func setKeepsAwake(_ keepsAwake: Bool) {
        guard keepsAwake != isKeepingAwake else { return }
        isKeepingAwake = keepsAwake
        screen.isIdleTimerDisabled = keepsAwake
    }

    /// Schedules one wake-up to apply the rule again, replacing any earlier one.
    ///
    /// - Parameter delay: When, or `nil` for none.
    private func schedule(after delay: Duration?) {
        cancelWakeUp()
        guard let delay else { return }
        let generation = wakeUpGeneration
        let sleep = sleep
        let deadline = now() + delay
        wakeUp = Task { [weak self] in
            try? await sleep(deadline)
            guard let self, self.wakeUpGeneration == generation else { return }
            self.wakeUp = nil
            self.apply()
        }
    }

    /// Cancels the pending wake-up.
    private func cancelWakeUp() {
        wakeUpGeneration += 1
        wakeUp?.cancel()
        wakeUp = nil
    }
}

extension CameraModel {
    /// Whether a series that keeps the screen awake and dims it is going
    /// (``SeriesScreenKeeper``): an interval series (running or paused), an Astro run or a focus
    /// bracket (issue #90). Each can outlast the auto-lock. A countdown or a burst isn't one; Keep
    /// Screen On covers those.
    public var keepsScreenForSeries: Bool {
        manual.intervalProgress != nil || astro.isRunning || bracketing.isRunning
    }
}
