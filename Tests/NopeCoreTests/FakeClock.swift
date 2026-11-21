import Foundation

@testable import NopeCore

/// A ``NopeClock`` that moves only when a test moves it (issue #107).
///
/// ``advance(by:)`` moves the monotonic clock and the wall clock together, as time passing does;
/// ``setDate(_:)`` moves only the wall clock, as a change of the device's time does. A sleep
/// waits until the monotonic clock reaches its moment, plus ``lateness`` when the test wants every
/// wake to come late, as a busy main thread makes it.
final class FakeClock: @unchecked Sendable {
    /// One waiting sleep.
    private struct Sleeper {
        let id: Int
        let wakeAt: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var instant: ContinuousClock.Instant
    private var wallDate: Date
    private var sleepers: [Sleeper] = []
    private var nextID = 0
    private var requested: [ContinuousClock.Instant] = []
    private var late: Duration = .zero

    /// A clock at a fixed moment: the system's `ContinuousClock` now, and `date` on the wall.
    init(date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        start = .now
        instant = start
        wallDate = date
    }

    /// The clock to pass to the model.
    var clock: NopeClock {
        NopeClock(date: { self.date }, now: { self.now }, sleep: { try await self.sleep(until: $0) })
    }

    /// The monotonic time.
    var now: ContinuousClock.Instant {
        lock.withLock { instant }
    }

    /// The wall clock's date.
    var date: Date {
        lock.withLock { wallDate }
    }

    /// The number of sleeps waiting.
    var pendingSleeps: Int {
        lock.withLock { sleepers.count }
    }

    /// The moments every sleep asked to wake at, in order.
    var requestedWakes: [ContinuousClock.Instant] {
        lock.withLock { requested }
    }

    /// How late every sleep wakes after its moment. Zero by default.
    var lateness: Duration {
        get { lock.withLock { late } }
        set { lock.withLock { late = newValue } }
    }

    /// The monotonic moment the clock started at.
    let start: ContinuousClock.Instant

    /// Moves both clocks on, and wakes every sleep whose time has come.
    ///
    /// - Parameter seconds: How far, in seconds.
    func advance(by seconds: Double) {
        let woken: [Sleeper] = lock.withLock {
            instant += .seconds(seconds)
            wallDate = wallDate.addingTimeInterval(seconds)
            let due = sleepers.filter { $0.wakeAt <= instant }
            sleepers.removeAll { $0.wakeAt <= instant }
            return due
        }
        woken.forEach { $0.continuation.resume() }
    }

    /// Moves both clocks on to the earliest waiting sleep's wake, and wakes it.
    ///
    /// - Returns: The seconds moved, or `nil` when no sleep waits.
    @discardableResult
    func advanceToNextWake() -> Double? {
        let next: ContinuousClock.Instant? = lock.withLock { sleepers.map(\.wakeAt).min() }
        guard let next else { return nil }
        let seconds = Swift.max((next - now) / .seconds(1), 0)
        advance(by: seconds)
        return seconds
    }

    /// Sets the wall clock alone, as a change of the device's time does.
    ///
    /// - Parameter date: The new date.
    func setDate(_ date: Date) {
        lock.withLock { wallDate = date }
    }

    /// Moves the wall clock alone by a number of seconds, forward or back.
    ///
    /// - Parameter seconds: How far.
    func moveDate(by seconds: Double) {
        lock.withLock { wallDate = wallDate.addingTimeInterval(seconds) }
    }

    /// Waits until the monotonic clock reaches the moment, plus ``lateness``.
    ///
    /// - Parameter deadline: The moment.
    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id: Int = lock.withLock {
            nextID += 1
            requested.append(deadline)
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeNow: Bool = lock.withLock {
                    let wakeAt = deadline + late
                    if Task.isCancelled { return true }
                    if wakeAt <= instant { return true }
                    sleepers.append(Sleeper(id: id, wakeAt: wakeAt, continuation: continuation))
                    return false
                }
                if resumeNow {
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) } else { continuation.resume() }
                }
            }
        } onCancel: {
            let cancelled: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// The seconds from ``start`` to a moment.
    ///
    /// - Parameter instant: A moment of this clock.
    func seconds(at instant: ContinuousClock.Instant) -> Double {
        (instant - start) / .seconds(1)
    }
}

/// Waits on the real clock, up to five seconds, until the fake clock has at least `count` sleeps
/// waiting.
@MainActor
func waitForSleeps(_ clock: FakeClock, count: Int = 1) async {
    await waitUntil { clock.pendingSleeps >= count }
}
