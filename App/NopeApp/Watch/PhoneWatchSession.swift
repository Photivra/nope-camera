import Foundation
import NopeCore
import WatchConnectivity

/// The iPhone app's link to the Apple Watch app over WatchConnectivity (issue #63).
///
/// It only carries bytes: the watch's commands arrive with `WCSession.sendMessageData`, and the
/// replies and status updates go back the same way, on the system's connection between the
/// paired devices. Only commands and short status cross it, never image data or metadata. What
/// the commands do is decided in `NopeCore` by ``WatchCommandServer``, which takes photos
/// through the same ``ShortcutInbox`` as Siri.
///
/// On a device without WatchConnectivity (iPad, `WCSession.isSupported()` is false) it does
/// nothing.
@MainActor
final class PhoneWatchSession: NSObject, WatchLink {
    /// The server of the camera screen being shown, or `nil` while none is shown.
    private var server: WatchCommandServer?

    /// The default session, or `nil` where WatchConnectivity isn't supported.
    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// Sets the delegate and activates the default session, as Apple asks of an app on launch
    /// (`WCSession.activate()`), so a watch command that launches the app is delivered.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Serves the watch for as long as the camera screen is shown: answers its commands and sends
    /// it each status change. Run it in the camera screen's `.task`.
    ///
    /// - Parameters:
    ///   - model: The camera.
    ///   - inbox: The app's Siri and Shortcuts inbox, which the camera screen serves.
    func serve(model: CameraModel, inbox: ShortcutInbox) async {
        guard session != nil else { return }
        let server = WatchCommandServer(model: model, inbox: inbox, link: self)
        self.server = server
        await server.sendStatusChanges()
        if self.server === server { self.server = nil }
    }

    /// Whether the watch app can get a message now: the session is active and the watch app is
    /// open on a paired watch.
    var isWatchReachable: Bool {
        guard let session else { return false }
        return session.activationState == .activated && session.isReachable
    }

    /// Sends an update to the watch app. The watch confirms each one with an empty reply;
    /// WatchConnectivity calls exactly one of the two handlers
    /// (`sendMessageData(_:replyHandler:errorHandler:)`).
    ///
    /// - Parameter message: The encoded update.
    /// - Returns: Whether the watch confirmed it.
    func send(_ message: Data) async -> Bool {
        guard let session else { return false }
        // WatchConnectivity calls these handlers on its own background queue; `@Sendable` keeps
        // them from inheriting this class's main-actor isolation (see WatchSessionLink.send).
        return await withCheckedContinuation { continuation in
            session.sendMessageData(
                message, replyHandler: { @Sendable _ in continuation.resume(returning: true) },
                errorHandler: { @Sendable _ in continuation.resume(returning: false) })
        }
    }

    /// The reply to a watch command: the camera screen's server answers, or, while no camera
    /// screen is shown, the reply says the camera isn't running.
    ///
    /// - Parameter message: The encoded command.
    /// - Returns: The encoded reply.
    private func reply(to message: Data) async -> Data {
        guard let server else { return WatchCommandServer.notServingReply }
        return await server.reply(to: message)
    }
}

/// WatchConnectivity's reply handler, passed to the main actor. WatchConnectivity doesn't
/// require it to be called on a particular queue, and it is called exactly once.
private struct ReplyHandler: @unchecked Sendable {
    /// The handler.
    let reply: (Data) -> Void
}

/// WatchConnectivity calls its delegate on a background queue; each callback moves to the main
/// actor, where the camera model lives.
extension PhoneWatchSession: WCSessionDelegate {
    /// Nothing to do: the watch asks for the status when it is ready.
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?
    ) {}

    /// Nothing to do: the next watch's session is activated in ``sessionDidDeactivate(_:)``.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The person switched to another paired watch: activates the session again for it, as
    /// Apple's documentation for this callback asks.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Answers a watch command.
    nonisolated func session(
        _ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void
    ) {
        let handler = ReplyHandler(reply: replyHandler)
        Task { @MainActor in handler.reply(await reply(to: messageData)) }
    }
}
