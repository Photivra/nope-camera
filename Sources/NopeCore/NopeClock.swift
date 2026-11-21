import Foundation

/// The one source of time for the camera model and everything it owns (issue #107): the wall
/// clock for dates people see or that go into files, and the monotonic clock for everything that
/// measures elapsed time.
///
/// ``CameraModel`` takes one and passes it to its manual controls, drive modes and self-timer;
/// ``LiveActivityCoordinator`` takes the same one. Tests replace this one value, usually with a
/// clock they move by hand, instead of a separate sleep and two separate clocks.
///
/// The two readings are kept apart on purpose:
///
/// - ``date`` is the clock on the wall. The person can change it, and iOS changes it with the
///   time zone and network time, so it is only used for a photo's date, an end time shown on
///   screen and the dates a Live Activity needs.
/// - ``now`` is `ContinuousClock`, which a change of the device's time doesn't move and which
///   keeps counting while the device sleeps ([Apple: ContinuousClock]
///   (https://developer.apple.com/documentation/swift/continuousclock)). Every deadline, wait and
///   duration is measured on it: the end of a timed series, the start of the next interval photo,
///   the self-timer and the limit on Live Activity updates.
///
/// `scripts/check-architecture.sh` fails on a direct read of the wall clock (`Date()` or
/// `Date.now`) anywhere else in `NopeCore`, so the two can't be mixed up again.
///
/// ```swift
/// let model = CameraModel(backend: backend, saver: saver, clock: .system)
/// let deadline = model.clock.now() + .seconds(10)
/// try await model.clock.sleep(deadline)
/// ```
public struct NopeClock: Sendable {
    /// Reads the wall clock: only for dates people see or that go into files.
    public var date: @Sendable () -> Date

    /// Reads the monotonic clock: for everything that measures elapsed time.
    public var now: @Sendable () -> ContinuousClock.Instant

    /// Waits until a moment on the monotonic clock (``now``), and throws `CancellationError` when
    /// the calling task is cancelled. A moment already past returns at once.
    public var sleep: @Sendable (ContinuousClock.Instant) async throws -> Void

    /// Creates a clock from its three parts. Each part defaults to the system's, so a test can
    /// replace just one.
    ///
    /// - Parameters:
    ///   - date: Reads the wall clock.
    ///   - now: Reads the monotonic clock.
    ///   - sleep: Waits until a moment of ``now``, throwing when cancelled.
    public init(
        date: @escaping @Sendable () -> Date = { Date() },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
        sleep: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void = {
            try await Task.sleep(until: $0, clock: .continuous)
        }
    ) {
        self.date = date
        self.now = now
        self.sleep = sleep
    }

    /// The system's clocks: `Date()`, `ContinuousClock` and `Task.sleep(until:clock:)`.
    public static let system = NopeClock()

    /// Waits a number of seconds, measured on ``now``.
    ///
    /// - Parameter seconds: How long to wait, in seconds. Zero or less returns at once.
    /// - Throws: `CancellationError` when the calling task is cancelled.
    public func sleep(seconds: Double) async throws {
        try await sleep(now() + .seconds(seconds))
    }

    /// The date on the wall clock of a moment on the monotonic clock: now's date plus the time
    /// until that moment. Worked out when it is needed, so a change of the device's time since the
    /// moment was set doesn't move it on the monotonic clock, only the date it is shown as.
    ///
    /// - Parameter instant: A moment of ``now``, past or future.
    /// - Returns: Its date.
    public func date(of instant: ContinuousClock.Instant) -> Date {
        date().addingTimeInterval((instant - now()) / .seconds(1))
    }

    /// A clock for code written before this type, which passes a sleep that takes a number of
    /// seconds, usually one that returns at once or when a test lets it go.
    ///
    /// Such a sleep doesn't move a clock, so a deadline would never be reached. The clock this
    /// makes keeps its own time instead: it starts at the system's `ContinuousClock` and moves on
    /// only by each completed wait, by exactly the time asked for. A wait then asks the sleep for
    /// whole seconds when it is on time, as the sleeps of that code expect. With `now`, the clock
    /// reads that clock instead and leaves moving it to the sleep, as a test clock whose sleep
    /// moves it does.
    ///
    /// - Parameters:
    ///   - sleep: Waits a number of seconds, throwing when cancelled.
    ///   - now: Reads a monotonic clock that the sleep moves, or `nil` for the clock's own time.
    /// - Returns: The clock; its ``date`` is the system's.
    static func stepped(
        by sleep: @escaping @Sendable (Double) async throws -> Void,
        now: (@Sendable () -> ContinuousClock.Instant)? = nil
    ) -> NopeClock {
        if let now {
            return NopeClock(now: now) { deadline in
                try await sleep(Swift.max((deadline - now()) / .seconds(1), 0))
            }
        }
        let time = SteppedTime()
        return NopeClock(now: { time.now }) { deadline in
            let wait = Swift.max(deadline - time.now, .zero)
            try await sleep(wait / .seconds(1))
            time.advance(to: deadline)
        }
    }
}

/// The time of a ``NopeClock/stepped(by:now:)`` clock: the system's `ContinuousClock` when it was
/// made, moved on by each completed wait.
final class SteppedTime: @unchecked Sendable {
    /// Guards ``time``; waits finish on any task.
    private let lock = NSLock()

    /// The current time.
    private var time = ContinuousClock.now

    /// The current time.
    var now: ContinuousClock.Instant {
        lock.withLock { time }
    }

    /// Moves the time on to a moment, never back.
    ///
    /// - Parameter instant: The moment a wait ended at.
    func advance(to instant: ContinuousClock.Instant) {
        lock.withLock { time = Swift.max(time, instant) }
    }
}
