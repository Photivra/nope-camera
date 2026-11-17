import Foundation
import Observation

/// The iPhone side's link to the watch app: sends a message to it while it is reachable.
///
/// The app implements it with WatchConnectivity (`WCSession.sendMessageData`); tests pass a
/// fake. Only the bytes of ``PhoneUpdate`` values cross it.
@MainActor
public protocol WatchLink: AnyObject {
    /// Whether the watch app can get a message now: it is open on a paired watch
    /// (`WCSession.isReachable`).
    var isWatchReachable: Bool { get }

    /// Sends a message to the watch app.
    ///
    /// - Parameter message: The encoded ``PhoneUpdate``.
    /// - Returns: Whether the message was delivered.
    func send(_ message: Data) async -> Bool
}

/// Answers the Apple Watch app's commands on the iPhone (issue #63), and keeps the watch up to
/// date while its app is open.
///
/// It holds no capture logic of its own: a photo goes through the app's ``ShortcutInbox``, as a
/// Siri request does, so the camera screen takes it with the same intents as its own shutter,
/// and a delay runs the camera's self-timer (``DriveIntent/startTimer(seconds:)``). A photo is
/// asked for only while ``CameraModel/watchStatus`` is ``WatchStatus/ready``; otherwise the
/// watch hears why at once and nothing is taken.
///
/// ```swift
/// let server = WatchCommandServer(model: model, inbox: inbox, link: session)
/// // When a message arrives: reply with the bytes this returns.
/// let reply = await server.reply(to: message)
/// // While the camera screen is shown:
/// .task { await server.sendStatusChanges() }
/// ```
///
/// Battery rule (AGENTS.md, "Battery"): nothing polls. Status changes are followed with
/// Observation, and a message is sent only while the watch app is reachable.
@MainActor
public final class WatchCommandServer {
    /// The camera.
    let model: CameraModel

    /// Where photo requests go; the camera screen serves it.
    let inbox: ShortcutInbox

    /// The link to the watch app.
    let link: any WatchLink

    /// The status last sent, so an unchanged status isn't sent again.
    private(set) var lastSentStatus: WatchStatus?

    /// A result that couldn't be delivered because the watch app wasn't reachable. It goes with
    /// the next reply, then is cleared.
    private(set) var undeliveredResult: WatchResult?

    /// Why the undelivered result's photos aren't all signed (``PhoneUpdate/unsignedReason``).
    private(set) var undeliveredUnsignedReason: SignatureStatus.UnsignedReason?

    /// Creates a server.
    ///
    /// - Parameters:
    ///   - model: The camera.
    ///   - inbox: The app's Siri and Shortcuts inbox, which the camera screen serves.
    ///   - link: The link to the watch app.
    public init(model: CameraModel, inbox: ShortcutInbox, link: any WatchLink) {
        self.model = model
        self.inbox = inbox
        self.link = link
    }

    /// The reply to send when no camera screen serves the watch: the app was started in the
    /// background, or its camera screen isn't shown. It says the camera isn't running.
    public static let notServingReply = WatchMessageCoding.encode(PhoneUpdate(status: .unavailable(.notRunning)))

    /// Handles a message from the watch app and returns the reply.
    ///
    /// Side effects: a ``WatchCommand/takePhoto(delay:)`` may start the self-timer, take a photo
    /// and add it to Photos, through the inbox; its result is sent to the watch when the photo
    /// ends. A ``WatchCommand/cancelTimer`` stops a running countdown.
    ///
    /// - Parameter message: The bytes the watch sent.
    /// - Returns: The encoded ``PhoneUpdate``: the status after the command, with a result when
    ///   there is one (``WatchResult/notUnderstood`` for a message this version can't read).
    public func reply(to message: Data) async -> Data {
        let result: WatchResult?
        do {
            result = await handle(try WatchMessageCoding.decodeCommand(message))
        } catch {
            result = .notUnderstood
        }
        let update =
            if let result {
                PhoneUpdate(status: model.watchStatus, result: result)
            } else {
                takeUndeliveredUpdate()
            }
        lastSentStatus = update.status
        return WatchMessageCoding.encode(update)
    }

    /// Sends the status to the watch each time it changes, while the watch app is reachable,
    /// until the calling task is cancelled. Run it while the camera screen is shown.
    public func sendStatusChanges() async {
        let waiter = ChangeWaiter()
        await withTaskCancellationHandler {
            // Nothing suspends between the check and the wait, so a cancellation always ends the
            // wait (``ChangeWaiter/expire()``).
            while !waiter.isExpired {
                let status = model.watchStatus
                if status != lastSentStatus, link.isWatchReachable { send(status) }
                await waiter.waitForChange { [model] in model.watchStatus == status }
            }
        } onCancel: {
            Task { @MainActor in waiter.expire() }
        }
    }

    /// Sends a status to the watch. It counts as sent at once, so a change that follows isn't
    /// held back, and is sent again with the next change if delivery fails.
    ///
    /// - Parameter status: The camera's status.
    private func send(_ status: WatchStatus) {
        lastSentStatus = status
        Task {
            let delivered = await link.send(WatchMessageCoding.encode(PhoneUpdate(status: status)))
            if !delivered, lastSentStatus == status { lastSentStatus = nil }
        }
    }

    /// Performs a command.
    ///
    /// - Parameter command: The command.
    /// - Returns: A result to reply with at once, or `nil` when there is none yet.
    private func handle(_ command: WatchCommand) async -> WatchResult? {
        switch command {
        case .requestStatus:
            return nil
        case .cancelTimer:
            if model.drive.countdown.isRunning { await model.send(.drive(.cancelTimer)) }
            return nil
        case .takePhoto(let delay):
            if let refusal = WatchResult(refusing: model.watchStatus) { return refusal }
            undeliveredResult = nil
            undeliveredUnsignedReason = nil
            let photo = PhotoShortcut(delaySeconds: delay.seconds)
            Task {
                let result = WatchResult(await inbox.submit(.takePhoto(photo)))
                // Read from the capture status the request ended with. Should another photo
                // start before this line runs, the status no longer holds saved photos and the
                // reason is left out.
                let reason = result.includesUnsignedPhotos
                    ? SignatureStatus.UnsignedReason(photosOf: model.captureStatus) : nil
                await deliver(result, unsignedReason: reason)
            }
            return nil
        }
    }

    /// Sends a photo's result to the watch, or keeps it for the next reply when the watch app
    /// isn't reachable.
    ///
    /// - Parameters:
    ///   - result: How the photo ended.
    ///   - unsignedReason: Why its photos aren't all signed, or `nil`.
    private func deliver(_ result: WatchResult, unsignedReason: SignatureStatus.UnsignedReason?) async {
        let status = model.watchStatus
        let message = WatchMessageCoding.encode(PhoneUpdate(status: status, result: result, unsignedReason: unsignedReason))
        if link.isWatchReachable, await link.send(message) {
            lastSentStatus = status
        } else {
            undeliveredResult = result
            undeliveredUnsignedReason = unsignedReason
        }
    }

    /// The camera's status with the undelivered result, if any, which is cleared once taken.
    ///
    /// - Returns: The update to reply with.
    private func takeUndeliveredUpdate() -> PhoneUpdate {
        defer {
            undeliveredResult = nil
            undeliveredUnsignedReason = nil
        }
        return PhoneUpdate(status: model.watchStatus, result: undeliveredResult, unsignedReason: undeliveredUnsignedReason)
    }
}
