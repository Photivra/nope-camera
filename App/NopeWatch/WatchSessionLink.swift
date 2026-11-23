import Foundation
import NopeCore
import WatchConnectivity

/// The watch app's link to the iPhone app over WatchConnectivity (issue #63).
///
/// It only carries bytes: commands go out with `WCSession.sendMessageData`, and the phone's
/// replies and updates come back the same way, on the system's connection between the paired
/// devices. The app makes no network requests of its own and sends no image data or metadata.
/// Everything the messages mean is in `NopeCore` (``WatchRemote``, ``WatchMessageCoding``).
@MainActor
final class WatchSessionLink: NSObject, PhoneLink {
    /// The model that gets the phone's updates and reachability changes.
    private weak var remote: WatchRemote?

    /// Sets the delegate and activates the default session, as Apple asks of an app on launch
    /// (`WCSession.activate()`). The model refreshes once activation completes.
    ///
    /// - Parameter remote: The watch app's model.
    func connect(to remote: WatchRemote) {
        self.remote = remote
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Whether the iPhone app can get a message now.
    var isPhoneReachable: Bool {
        WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    /// Sends a command to the iPhone app and waits for its reply. WatchConnectivity calls
    /// exactly one of the two handlers (`sendMessageData(_:replyHandler:errorHandler:)`).
    ///
    /// - Parameter message: The encoded command.
    /// - Returns: The phone's encoded reply.
    /// - Throws: The WatchConnectivity error when the message or its reply wasn't delivered.
    func send(_ message: Data) async throws -> Data {
        // WatchConnectivity calls these handlers on its own background queue. They are
        // `@Sendable` so they don't inherit this class's main-actor isolation: an isolated
        // closure run off the main thread fails Swift's executor check and the app traps.
        try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessageData(
                message, replyHandler: { @Sendable reply in continuation.resume(returning: reply) },
                errorHandler: { @Sendable error in continuation.resume(throwing: error) })
        }
    }

    /// Hands an update from the phone to the model.
    ///
    /// - Parameter message: The encoded update.
    private func received(_ message: Data) {
        remote?.receive(message)
    }

    /// Tells the model whether the phone is reachable now.
    private func reachabilityChanged() async {
        await remote?.reachabilityChanged(isReachable: isPhoneReachable)
    }
}

/// WatchConnectivity calls its delegate on a background queue; each callback moves to the main
/// actor, where the model lives.
extension WatchSessionLink: WCSessionDelegate {
    /// Asks the phone for its status once the session is active.
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?
    ) {
        Task { @MainActor in await reachabilityChanged() }
    }

    /// Follows the phone's reachability.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in await reachabilityChanged() }
    }

    /// Applies an update the phone sent, and confirms it with an empty reply, so the phone knows
    /// it was delivered.
    nonisolated func session(
        _ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void
    ) {
        replyHandler(Data())
        Task { @MainActor in received(messageData) }
    }
}
