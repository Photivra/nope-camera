import Foundation
import Observation

/// Hands requests from Siri and Shortcuts (issue #62) to the camera screen, and their outcomes
/// back.
///
/// The app owns one inbox for its lifetime. An App Intent calls ``submit(_:)`` and waits for the
/// outcome; the camera screen runs ``CameraModel/serveShortcuts(from:)`` while it is shown, which
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

    /// The camera screen's wait for the next request, while the queue is empty.
    private var server: CheckedContinuation<PendingShortcut?, Never>?

    /// Creates an empty inbox.
    ///
    /// - Parameter sleep: Waits a number of seconds, throwing when cancelled. Tests pass their
    ///   own; the default is `Task.sleep`.
    public init(sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.sleep = sleep
    }

    /// Hands a request to the camera screen and waits until it is done.
    ///
    /// - Parameter request: What Siri or Shortcuts asks for.
    /// - Returns: How it ended. When no camera screen takes the request within
    ///   ``startTimeoutSeconds``, ``ShortcutOutcome/cameraUnavailable(_:)`` with
    ///   ``CameraUnavailability/notRunning``.
    public func submit(_ request: ShortcutRequest) async -> ShortcutOutcome {
        await withCheckedContinuation { continuation in
            let pending = PendingShortcut(request: request, continuation: continuation)
            // Cancelled when a camera screen takes the request; a request already taken is no
            // longer queued, so a late expiry does nothing.
            pending.timeout = Task { [weak self, sleep] in
                try? await sleep(Self.startTimeoutSeconds)
                self?.expire(pending)
            }
            if let server {
                self.server = nil
                server.resume(returning: pending.pickedUp())
            } else {
                queue.append(pending)
            }
        }
    }

    /// The next request, waiting until one arrives. Only one camera screen serves at a time: a
    /// second caller replaces the first, whose wait ends with `nil`.
    ///
    /// - Returns: The request, or `nil` when the calling task is cancelled.
    func next() async -> PendingShortcut? {
        server?.resume(returning: nil)
        server = nil
        if !queue.isEmpty { return queue.removeFirst().pickedUp() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    server = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stopServing() }
        }
    }

    /// Ends the camera screen's wait, because its task was cancelled.
    private func stopServing() {
        server?.resume(returning: nil)
        server = nil
    }

    /// Ends a request no camera screen took in time.
    ///
    /// - Parameter pending: The request.
    private func expire(_ pending: PendingShortcut) {
        guard let index = queue.firstIndex(where: { $0 === pending }) else { return }
        queue.remove(at: index)
        pending.finish(.cameraUnavailable(.notRunning))
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
        let waiter = ChangeWaiter()
        let timeout = timeoutSeconds.map { seconds in
            Task { [sleep] in
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
        continuation?.resume(returning: outcome)
        continuation = nil
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
