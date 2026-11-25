import Foundation
import Observation

/// The self-timer delays the shutter offers: 3 and 10 seconds (AGENTS.md, "Taking photos
/// without seeing the screen"; issue #39).
public enum SelfTimerDelay: Int, CaseIterable, Sendable {
    /// Three seconds.
    case threeSeconds = 3

    /// Ten seconds.
    case tenSeconds = 10

    /// The delay, in seconds.
    public var seconds: Int {
        rawValue
    }
}

/// A countdown in whole seconds to a deadline that runs an action when it reaches zero: the
/// self-timer.
///
/// ``CameraModel`` owns one through ``DriveModel/countdown``. The shutter starts it in a timer
/// drive mode (``DriveMode/timer(_:)``), and ``DriveIntent/startTimer(seconds:)`` starts it with
/// any number of seconds, for example from a Siri or Shortcuts request with a delay (issue #62).
/// An interface shows and announces ``remainingSeconds`` and gives a haptic tick when it changes.
///
/// Battery rule (AGENTS.md, "Battery"): the countdown only sleeps between numbers; it does no
/// other work, and nothing keeps running once it ends or is cancelled.
///
/// It counts to a fixed deadline on the camera model's monotonic clock (issue #122), so the
/// photo is taken on time however late each wake is.
///
/// ```swift
/// countdown.start(seconds: 3) { await takePhoto() }
/// countdown.remainingSeconds  // 3, then 2, then 1, then nil when the photo is taken
/// ```
@MainActor
@Observable
public final class Countdown {
    /// The longest countdown, in seconds: one day. Longer requests are shortened to it, so the
    /// deadline's arithmetic can't overflow (final review of 1.0.0, minor 6). The app asks for at
    /// most 60 seconds; the limit only guards the public API.
    public static let longestSeconds = 86_400

    /// The seconds left, from the starting number down to 1, or `nil` when no countdown runs:
    /// the whole seconds until ``deadline``, rounded up. When the app is held up for more than a
    /// second, a number is skipped; the photo is still on time (issue #122).
    public private(set) var remainingSeconds: Int?

    /// When the running countdown reaches zero, on the monotonic clock (``NopeClock/now``), or
    /// `nil` when none runs. Set when it starts; a late tick never moves it. The Live Activity
    /// draws its countdown to this moment.
    public private(set) var deadline: ContinuousClock.Instant?

    /// The camera model's clock, which the countdown waits on.
    private let clock: NopeClock

    /// The running countdown.
    private var task: Task<Void, Never>?

    /// The caller waiting in ``run(seconds:)``, told whether the countdown reached zero.
    private var waiter: CheckedContinuation<Bool, Never>?

    /// Creates a countdown that isn't running.
    ///
    /// - Parameter clock: The clock it waits on. Tests pass one they move.
    public init(clock: NopeClock) {
        self.clock = clock
    }

    /// Creates a countdown that waits on a sleep of a number of seconds, as tests written before
    /// ``NopeClock`` pass (``NopeClock/stepped(by:now:)``).
    ///
    /// - Parameter sleep: Waits a number of seconds, throwing when cancelled.
    public convenience init(sleep: @escaping @Sendable (Double) async throws -> Void) {
        self.init(clock: .stepped(by: sleep))
    }

    /// Whether a countdown is running.
    public var isRunning: Bool {
        remainingSeconds != nil
    }

    /// Starts counting down to a deadline `seconds` from now, and runs the action when it is
    /// reached. Does nothing when a countdown already runs or `seconds` is less than 1.
    ///
    /// The count is the whole seconds left until the deadline, rounded up. Between numbers the
    /// countdown waits until the next whole second before the deadline, so the time the app takes
    /// to wake doesn't add up from tick to tick: a 10-second timer fires 10 seconds after it was
    /// started, late only by its last wake (issue #122). A wake more than a second late skips a
    /// number rather than moving the deadline.
    ///
    /// - Parameters:
    ///   - seconds: The delay, in seconds, at most ``longestSeconds``; a longer one is shortened
    ///     to it.
    ///   - fire: What happens at zero, such as taking a photo. It doesn't run when the countdown
    ///     is cancelled.
    public func start(seconds: Int, fire: @escaping @MainActor () async -> Void) {
        guard seconds > 0, task == nil else { return }
        let seconds = min(seconds, Self.longestSeconds)
        let deadline = clock.now() + .seconds(seconds)
        self.deadline = deadline
        remainingSeconds = seconds
        // The count changes only after a wait that wasn't cancelled, so a cancelled countdown
        // never writes over the state of the next one.
        task = Task {
            var remaining = seconds
            while remaining > 0 {
                try? await clock.sleep(deadline - .seconds(remaining - 1))
                if Task.isCancelled { return }
                remaining = Self.wholeSeconds(until: deadline, at: clock.now())
                remainingSeconds = remaining > 0 ? remaining : nil
            }
            task = nil
            self.deadline = nil
            await fire()
        }
    }

    /// The whole seconds from a moment until the deadline, rounded up, and never less than 0.
    ///
    /// - Parameters:
    ///   - deadline: When the countdown reaches zero.
    ///   - now: The moment, on the same clock.
    /// - Returns: The seconds shown.
    nonisolated static func wholeSeconds(until deadline: ContinuousClock.Instant, at now: ContinuousClock.Instant) -> Int {
        Int(Swift.max(((deadline - now) / .seconds(1)).rounded(.up), 0))
    }

    /// Counts down and waits until the count reaches zero or the countdown is cancelled: the
    /// astro helper's start delay before it resumes a paused run (issue #64).
    ///
    /// - Parameter seconds: The delay, in seconds. Less than 1 doesn't wait.
    /// - Returns: `true` when the count reached zero, `false` when the countdown was cancelled or
    ///   another countdown was already running.
    public func run(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        guard task == nil else { return false }
        return await withCheckedContinuation { continuation in
            waiter = continuation
            start(seconds: seconds) { [weak self] in self?.finishWaiting(fired: true) }
        }
    }

    /// Stops the countdown without running its action. Does nothing when none runs.
    public func cancel() {
        task?.cancel()
        task = nil
        remainingSeconds = nil
        deadline = nil
        finishWaiting(fired: false)
    }

    /// Tells the caller of ``run(seconds:)``, if any, how the countdown ended.
    ///
    /// - Parameter fired: Whether the count reached zero.
    private func finishWaiting(fired: Bool) {
        waiter?.resume(returning: fired)
        waiter = nil
    }
}
