import Foundation
import Observation

/// The Apple Watch side's link to the iPhone app: sends a message and waits for the reply.
///
/// The watch app implements it with WatchConnectivity (`WCSession.sendMessageData`); tests and
/// the watch UI tests pass a fake. Only the bytes of ``WatchCommand`` values cross it.
@MainActor
public protocol PhoneLink: AnyObject {
    /// Whether the iPhone app can get a message now (`WCSession.isReachable`).
    var isPhoneReachable: Bool { get }

    /// Sends a message to the iPhone app and waits for its reply.
    ///
    /// - Parameter message: The encoded ``WatchCommand``.
    /// - Returns: The encoded ``PhoneUpdate`` the phone replied with.
    /// - Throws: When the message couldn't be delivered or the phone didn't reply.
    func send(_ message: Data) async throws -> Data
}

/// The Apple Watch app's model (issue #63): the shutter and the delay, and the phone camera's
/// status and the last result.
///
/// The watch takes no photos and runs no timer of its own: it sends ``WatchCommand`` values to
/// the iPhone app, whose camera does the capture and whose self-timer counts down. The watch
/// shows what the phone reports. An interface reads ``display``, ``lastResult`` and
/// ``delay``, and calls ``takePhoto()``, ``cancelTimer()`` and ``refresh()``.
///
/// ```swift
/// let remote = WatchRemote(link: session)
/// await remote.refresh()          // when the app opens
/// remote.delay = .threeSeconds
/// await remote.takePhoto()        // display: .waiting, then .countingDown(3), …
/// remote.lastResult               // .saved(isSigned: true)
/// ```
@MainActor
@Observable
public final class WatchRemote {
    /// What the watch shows, from the link and the phone's status.
    public enum Display: Equatable, Sendable {
        /// The watch hasn't heard from the phone yet. Show a neutral placeholder.
        case connecting

        /// The iPhone app can't be reached: the phone is away, off or locked out of the link.
        /// Say to keep the phone nearby with the app open.
        case phoneNotReachable

        /// The phone's camera is ready. Enable the shutter.
        case ready

        /// The phone's self-timer runs, with the seconds left. Show, announce and offer cancel.
        case countingDown(secondsLeft: Int)

        /// A photo was asked for and the phone is taking or saving one, or is busy with
        /// another. Keep the shutter disabled.
        case waiting

        /// The phone's camera can't take a photo now. Say why.
        case unavailable(WatchCameraProblem)
    }

    /// Whether the phone has been reached, and how the last attempt went.
    private enum Connection: Equatable {
        /// Not tried yet.
        case connecting
        /// The last message wasn't delivered.
        case notReachable
        /// The last message got a reply.
        case connected
    }

    /// The delay for the next photo. The watch keeps it only while its app runs.
    public var delay = WatchDelay.none

    /// The phone's last reported status, or `nil` before the first reply.
    public private(set) var status: WatchStatus?

    /// How the last photo the watch asked for ended, or `nil` before one ends. Cleared when the
    /// next photo is asked for.
    public private(set) var lastResult: WatchResult?

    /// Why the photos of ``lastResult`` aren't all signed (``PhoneUpdate/unsignedReason``), or
    /// `nil` when they are, there is no result, or the phone didn't say. Show
    /// ``SignatureStatus/UnsignedReason/turnedOff`` as plain status: signing is off by choice.
    public private(set) var lastUnsignedReason: SignatureStatus.UnsignedReason?

    /// Whether a photo was asked for and its result hasn't arrived yet.
    public private(set) var isAwaitingResult = false

    /// Whether the phone has been reached.
    private var connection = Connection.connecting

    /// The link to the iPhone app.
    let link: any PhoneLink

    /// Creates a model that hasn't reached the phone yet.
    ///
    /// - Parameter link: The link to the iPhone app.
    public init(link: any PhoneLink) {
        self.link = link
    }

    /// What the watch shows now.
    public var display: Display {
        switch connection {
        case .connecting: return .connecting
        case .notReachable: return .phoneNotReachable
        case .connected: break
        }
        switch status {
        case .countingDown(let seconds): return .countingDown(secondsLeft: seconds)
        case .busy: return .waiting
        case .unavailable(let problem): return .unavailable(problem)
        case .ready, nil: return isAwaitingResult ? .waiting : .ready
        }
    }

    /// Whether the shutter is enabled: the phone's camera is ready and no photo is awaited.
    public var canTakePhoto: Bool {
        display == .ready
    }

    /// Whether a countdown runs that the watch can cancel.
    public var canCancelTimer: Bool {
        if case .countingDown = display { return true }
        return false
    }

    /// Asks the phone for its status. Call it when the watch app opens or becomes active, and
    /// when the phone becomes reachable.
    public func refresh() async {
        await send(.requestStatus)
    }

    /// Asks the phone to take a photo after ``delay``. Does nothing unless ``canTakePhoto``.
    ///
    /// Side effects on the phone: its self-timer may start, and a photo is taken and added to
    /// Photos with the phone's current settings. The result arrives in ``lastResult``.
    public func takePhoto() async {
        guard canTakePhoto else { return }
        lastResult = nil
        lastUnsignedReason = nil
        isAwaitingResult = true
        await send(.takePhoto(delay: delay))
    }

    /// Asks the phone to stop its countdown, so no photo is taken. Does nothing unless
    /// ``canCancelTimer``.
    public func cancelTimer() async {
        guard canCancelTimer else { return }
        await send(.cancelTimer)
    }

    /// Applies a message the phone sent without being asked: a status change or a result.
    ///
    /// - Parameter message: The bytes received.
    public func receive(_ message: Data) {
        apply(message)
    }

    /// Follows a change in whether the phone can be reached (`WCSession` reachability).
    ///
    /// - Parameter isReachable: Whether the phone is reachable now.
    public func reachabilityChanged(isReachable: Bool) async {
        if isReachable {
            await refresh()
        } else {
            markNotReachable()
        }
    }

    /// Sends a command and applies the reply.
    ///
    /// - Parameter command: The command.
    private func send(_ command: WatchCommand) async {
        guard link.isPhoneReachable else { return markNotReachable() }
        do {
            apply(try await link.send(WatchMessageCoding.encode(command)))
        } catch {
            markNotReachable()
        }
    }

    /// Applies an update from the phone. One this version can't read ends the wait for a result
    /// with ``WatchResult/notUnderstood``.
    ///
    /// - Parameter message: The bytes received.
    private func apply(_ message: Data) {
        connection = .connected
        guard let update = try? WatchMessageCoding.decodeUpdate(message) else {
            return finish(with: .notUnderstood)
        }
        status = update.status
        if let result = update.result { finish(with: result, unsignedReason: update.unsignedReason) }
    }

    /// Ends the wait for a result.
    ///
    /// - Parameters:
    ///   - result: How the photo ended.
    ///   - unsignedReason: Why its photos aren't all signed, or `nil`.
    private func finish(with result: WatchResult, unsignedReason: SignatureStatus.UnsignedReason? = nil) {
        lastResult = result
        lastUnsignedReason = unsignedReason
        isAwaitingResult = false
    }

    /// Marks the phone as unreachable. A photo already asked for may still be taken; its result
    /// comes with the next reply once the phone is reachable again.
    private func markNotReachable() {
        connection = .notReachable
        isAwaitingResult = false
    }
}
