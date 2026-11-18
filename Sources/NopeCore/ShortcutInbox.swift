import Foundation
import Observation

/// Hands requests from Siri and Shortcuts (issue #62) to the camera screen, and their outcomes
/// back.
///
/// The app owns one inbox for its lifetime. An App Intent calls ``submit(_:)`` and waits for the
/// outcome; the camera screen runs ``CameraModel/serveShortcuts(from:settings:presets:)`` while it is shown, which
/// takes each request in turn and performs it.
///
/// ```swift
/// // In an App Intent:
/// let outcome = await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: 10)))
/// // On the camera screen:
/// .task { await model.serveShortcuts(from: inbox) }
/// ```
///
/// Battery rule (AGENTS.md, "Battery"): nothing here polls. Waiting follows the model's
/// observable state, and the only timers are one-shot timeouts that end with the request.
@MainActor
public final class ShortcutInbox {
    /// How long a request waits for the camera screen to take it, and for the camera to start,
    /// in seconds, before it ends as ``CameraUnavailability/notRunning``. An assumption, to be
    /// confirmed on a device: the camera usually starts well within a second, and Siri opens
    /// the app before the intent runs, so ten seconds leaves room for a slow start.
    public static let startTimeoutSeconds: Double = 10

    /// Waits a number of seconds, for the timeouts. Tests pass their own.
    let sleep: @Sendable (Double) async throws -> Void

    /// Requests no camera screen has taken yet, oldest first.
    private var queue: [PendingShortcut] = []

    /// The camera screen's wait for the next request, with the number of the ``next()`` call
    /// that waits, while no request it can take is queued.
    private var server: (call: Int, continuation: CheckedContinuation<PendingShortcut?, Never>)?

    /// The number of the latest ``next()`` call, so a cancelled call ends only its own wait.
    private var lastCall = 0

    /// The request the camera screen is performing that isn't an instant one
    /// (``ShortcutRequest/isInstant``), until it finishes. Only one runs at a time; the next one
    /// waits in the queue.
    private var performing: PendingShortcut?

    /// Whether a camera screen serves the inbox: from its first call to ``next()`` until its
    /// task is cancelled. While it performs a request it is still serving.
    public private(set) var isServed = false

    /// Creates an empty inbox.
    ///
    /// - Parameter sleep: Waits a number of seconds, throwing when cancelled. Tests pass their
    ///   own; the default is `Task.sleep`.
    public init(sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.sleep = sleep
    }

    /// Hands a request to the camera screen and waits until it is done.
    ///
    /// An instant request (``ShortcutRequest/isInstant``, such as turning the light off) is
    /// taken at once, even while another request is being performed. Any other request waits
    /// for the one before it to finish.
    ///
    /// - Parameter request: What Siri or Shortcuts asks for.
    /// - Returns: How it ended. Without a camera screen, a request that doesn't need one ends at
    ///   once with its ``ShortcutRequest/outcomeWithoutCameraScreen``. When no camera screen
    ///   takes any other request within ``startTimeoutSeconds``,
    ///   ``ShortcutOutcome/cameraUnavailable(_:)`` with ``CameraUnavailability/notRunning``, or
    ///   ``ShortcutOutcome/busyWithEarlierRequest`` when a camera screen is open but still
    ///   performing an earlier request.
    public func submit(_ request: ShortcutRequest) async -> ShortcutOutcome {
        if !isServed, let outcome = request.outcomeWithoutCameraScreen { return outcome }
        return await withCheckedContinuation { continuation in
            let pending = PendingShortcut(request: request, continuation: continuation)
            pending.onFinish = { [weak self] in self?.finished($0) }
            // Cancelled when a camera screen takes the request; a request already taken is no
            // longer queued, so a late expiry does nothing.
            pending.timeout = Task { [weak self, sleep] in
                try? await sleep(Self.startTimeoutSeconds)
                self?.expire(pending)
            }
            queue.append(pending)
            handOver()
        }
    }

    /// The next request, waiting until one arrives. Only one camera screen serves at a time: a
    /// second caller replaces the first, whose wait ends with `nil`. A caller whose task is
    /// already cancelled gets `nil` at once and leaves another caller's wait alone.
    ///
    /// - Returns: The request, or `nil` when the calling task is cancelled.
    func next() async -> PendingShortcut? {
        guard !Task.isCancelled else {
            // No other camera screen waits, so none serves any more.
            if server == nil { isServed = false }
            return nil
        }
        server?.continuation.resume(returning: nil)
        server = nil
        isServed = true
        if let request = takeNext() { return request }
        lastCall += 1
        let call = lastCall
        return await withTaskCancellationHandler {
            // No suspension since the check above, so the task can only be cancelled from now
            // on, which the handler below sees: it runs on the main actor after this.
            await withCheckedContinuation { continuation in
                server = (call, continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stopServing(call: call) }
        }
    }

    /// Takes the oldest queued request the camera screen may start now: an instant one at any
    /// time, any other one only when no other is being performed.
    ///
    /// - Returns: The request, marked as taken, or `nil` when none may start.
    private func takeNext() -> PendingShortcut? {
        guard let index = queue.firstIndex(where: { $0.request.isInstant || performing == nil }) else { return nil }
        let pending = queue.remove(at: index)
        if !pending.request.isInstant { performing = pending }
        return pending.pickedUp()
    }

    /// Gives the waiting camera screen a request it may start now, if there is one.
    private func handOver() {
        guard let server, let pending = takeNext() else { return }
        self.server = nil
        server.continuation.resume(returning: pending)
    }

    /// Lets the next request start after one finished.
    ///
    /// - Parameter pending: The request that finished.
    private func finished(_ pending: PendingShortcut) {
        guard performing === pending else { return }
        performing = nil
        handOver()
    }

    /// Ends the camera screen's wait, because its task was cancelled. A wait that a later call
    /// replaced is left alone.
    ///
    /// - Parameter call: The number of the cancelled ``next()`` call.
    private func stopServing(call: Int) {
        guard let server, server.call == call else { return }
        self.server = nil
        server.continuation.resume(returning: nil)
        isServed = false
    }

    /// Ends a request no camera screen took in time: the camera screen is still busy with an
    /// earlier request, or no camera screen is open.
    ///
    /// - Parameter pending: The request.
    private func expire(_ pending: PendingShortcut) {
        guard let index = queue.firstIndex(where: { $0 === pending }) else { return }
        queue.remove(at: index)
        pending.finish(isServed ? .busyWithEarlierRequest : .cameraUnavailable(.notRunning))
    }

    /// Waits, without polling, until the condition holds, or until the timeout passes.
    ///
    /// The condition is checked again each time a value it read changes (Observation,
    /// `withObservationTracking`), so it must read only observable state.
    ///
    /// - Parameters:
    ///   - timeoutSeconds: The longest wait in seconds, or `nil` to wait until it holds.
    ///   - condition: What to wait for.
    /// - Returns: Whether the condition holds at the end.
    func wait(timeoutSeconds: Double? = nil, until condition: @escaping @MainActor () -> Bool) async -> Bool {
        await ChangeWaiter.wait(timeoutSeconds: timeoutSeconds, sleep: sleep, until: condition)
    }
}

/// One request in a ``ShortcutInbox``, with the intent's wait for its outcome.
@MainActor
final class PendingShortcut {
    /// What was asked for.
    let request: ShortcutRequest

    /// The intent's wait, until ``finish(_:)``.
    private var continuation: CheckedContinuation<ShortcutOutcome, Never>?

    /// The timeout for a camera screen to take the request, cancelled when one does.
    var timeout: Task<Void, Never>?

    /// Called once when the request finishes, so the inbox can start the next one.
    var onFinish: ((PendingShortcut) -> Void)?

    /// Creates a pending request.
    ///
    /// - Parameters:
    ///   - request: What was asked for.
    ///   - continuation: The intent's wait for the outcome.
    init(request: ShortcutRequest, continuation: CheckedContinuation<ShortcutOutcome, Never>) {
        self.request = request
        self.continuation = continuation
    }

    /// Marks the request as taken by a camera screen, so it no longer times out.
    ///
    /// - Returns: This request.
    func pickedUp() -> PendingShortcut {
        timeout?.cancel()
        timeout = nil
        return self
    }

    /// Ends the intent's wait with the outcome. Later calls do nothing.
    ///
    /// - Parameter outcome: How the request ended.
    func finish(_ outcome: ShortcutOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
        let onFinish = onFinish
        self.onFinish = nil
        onFinish?(self)
    }
}

/// Wakes a waiting task when observable state it read changes, or when its timeout passes.
@MainActor
final class ChangeWaiter {
    /// The waiting task, until the next change.
    private var continuation: CheckedContinuation<Void, Never>?

    /// Whether the timeout passed.
    private(set) var isExpired = false

    /// Creates a waiter that isn't waiting.
    init() {}

    /// Waits, without polling, until the condition holds, or until the timeout passes.
    ///
    /// The condition is checked again each time a value it read changes (Observation,
    /// `withObservationTracking`), so it must read only observable state.
    ///
    /// - Parameters:
    ///   - timeoutSeconds: The longest wait in seconds, or `nil` to wait until it holds.
    ///   - sleep: Waits a number of seconds, for the timeout.
    ///   - condition: What to wait for.
    /// - Returns: Whether the condition holds at the end.
    static func wait(
        timeoutSeconds: Double?, sleep: @escaping @Sendable (Double) async throws -> Void,
        until condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let waiter = ChangeWaiter()
        let timeout = timeoutSeconds.map { seconds in
            Task {
                try? await sleep(seconds)
                waiter.expire()
            }
        }
        defer { timeout?.cancel() }
        while !condition() && !waiter.isExpired {
            await waiter.waitForChange(of: condition)
        }
        return condition()
    }

    /// Waits until a value the condition reads changes, or ``expire()``.
    ///
    /// - Parameter condition: The condition whose observable reads are tracked.
    func waitForChange(of condition: @escaping @MainActor () -> Bool) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            withObservationTracking {
                _ = condition()
            } onChange: { [weak self] in
                Task { @MainActor in self?.wake() }
            }
        }
    }

    /// Marks the timeout as passed and wakes the waiting task.
    func expire() {
        isExpired = true
        wake()
    }

    /// Wakes the waiting task, if one waits.
    private func wake() {
        continuation?.resume()
        continuation = nil
    }
}
