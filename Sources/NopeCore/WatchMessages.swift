import Foundation

/// The messages between the Apple Watch app and the iPhone app (issue #63): commands from the
/// watch, and the camera's status and results from the phone.
///
/// Both apps encode and decode them with ``WatchMessageCoding``; the apps' WatchConnectivity
/// adapters only carry the bytes. Only commands and short status cross the link, never image
/// data or metadata (issue #63, "How it talks to the phone").
///
/// The iPhone app answers with ``WatchCommandServer``; the watch app sends through
/// ``WatchRemote``.
public enum WatchCommand: Equatable, Codable, Sendable {
    /// Asks for the camera's status, for example when the watch app opens.
    case requestStatus

    /// Takes one photo with the phone's current settings, after the delay.
    case takePhoto(delay: WatchDelay)

    /// Stops a running self-timer countdown, so no photo is taken.
    case cancelTimer
}

/// The delays the watch offers before the photo: none, or the self-timer's 3 and 10 seconds
/// (issue #63, "Scope").
public enum WatchDelay: Int, CaseIterable, Codable, Sendable {
    /// No delay: the photo is taken at once.
    case none = 0

    /// Three seconds.
    case threeSeconds = 3

    /// Ten seconds.
    case tenSeconds = 10

    /// The delay, in seconds.
    public var seconds: Int {
        rawValue
    }
}

/// What the phone's camera is doing, as the watch shows it.
public enum WatchStatus: Equatable, Codable, Sendable {
    /// The camera is running and a photo can be taken. Show the shutter enabled.
    case ready

    /// The self-timer runs. Show and announce the seconds left, and offer to cancel.
    case countingDown(secondsLeft: Int)

    /// A photo, burst or series is being taken or saved. Keep the shutter disabled.
    case busy

    /// The camera can't take a photo now. Say why, from the problem.
    case unavailable(WatchCameraProblem)
}

/// Why the phone's camera can't take a photo for the watch.
public enum WatchCameraProblem: String, Equatable, Codable, Sendable {
    /// Camera access hasn't been asked for yet. Say to open the app on the phone to allow it.
    case needsPermission

    /// Camera access is declined or restricted. Say it can be turned on in the phone's Settings
    /// app.
    case permissionDenied

    /// The phone has no camera the app can use. Say so.
    case noCamera

    /// The camera isn't running: the camera screen isn't open on the phone, the app is in the
    /// background, or the camera is starting, paused or in use elsewhere. Say to open the app on
    /// the phone.
    case notRunning
}

/// How a photo the watch asked for ended. Like ``ShortcutOutcome``, it says only whether photos
/// were saved and signed, never image data or metadata.
public enum WatchResult: Equatable, Codable, Sendable {
    /// One photo was saved. Say "Saved and signed", or "Saved, not signed" when `isSigned` is
    /// false.
    case saved(isSigned: Bool)

    /// An exposure bracket was saved, because bracketing is on in the phone's manual controls.
    /// Say "Photos saved and signed", or that not all of them are signed.
    case savedSeveral(allSigned: Bool)

    /// The photo was taken but not saved, or couldn't be taken. Say that it wasn't saved and that
    /// the phone shows why.
    case notSaved

    /// The countdown was cancelled, on the watch or on the phone. Say no photo was taken.
    case cancelled

    /// A photo, countdown, burst or series was already in progress. Say so; nothing changed.
    case busy

    /// Nothing was taken because the camera can't take a photo now. Say why.
    case notTaken(WatchCameraProblem)

    /// The other app sent a message this version can't read, because the two apps are different
    /// versions. Say to update the app on both devices.
    case notUnderstood
}

/// What the phone sends the watch: the camera's status, and the result of the watch's last photo
/// request when there is one.
///
/// Every reply to a ``WatchCommand`` is one, and the phone also sends one whenever the status
/// changes or a photo ends while the watch app is reachable.
public struct PhoneUpdate: Equatable, Codable, Sendable {
    /// The camera's status.
    public let status: WatchStatus

    /// The result of the last photo the watch asked for, or `nil` when there is no new result.
    public let result: WatchResult?

    /// Creates an update.
    ///
    /// - Parameters:
    ///   - status: The camera's status.
    ///   - result: A new result, or `nil`.
    public init(status: WatchStatus, result: WatchResult? = nil) {
        self.status = status
        self.result = result
    }
}

/// Turns ``WatchCommand`` and ``PhoneUpdate`` values into bytes for WatchConnectivity
/// (`WCSession.sendMessageData(_:replyHandler:errorHandler:)`) and back.
///
/// Each message is JSON with a protocol version. A message of another version, or one that
/// doesn't decode, throws ``WatchMessageError``, so the receiver can answer
/// ``WatchResult/notUnderstood`` instead of guessing.
public enum WatchMessageCoding {
    /// The protocol version both apps must share. Increase it when a message changes in a way an
    /// older app can't read.
    public static let version = 1

    /// Encodes a command from the watch.
    ///
    /// - Parameter command: The command.
    /// - Returns: The bytes to send.
    public static func encode(_ command: WatchCommand) -> Data {
        encode(Envelope(version: version, body: command))
    }

    /// Encodes an update from the phone.
    ///
    /// - Parameter update: The update.
    /// - Returns: The bytes to send.
    public static func encode(_ update: PhoneUpdate) -> Data {
        encode(Envelope(version: version, body: update))
    }

    /// Decodes a command the watch sent.
    ///
    /// - Parameter data: The bytes received.
    /// - Returns: The command.
    /// - Throws: ``WatchMessageError`` when the bytes aren't a command of this version.
    public static func decodeCommand(_ data: Data) throws(WatchMessageError) -> WatchCommand {
        try decode(WatchCommand.self, from: data)
    }

    /// Decodes an update the phone sent.
    ///
    /// - Parameter data: The bytes received.
    /// - Returns: The update.
    /// - Throws: ``WatchMessageError`` when the bytes aren't an update of this version.
    public static func decodeUpdate(_ data: Data) throws(WatchMessageError) -> PhoneUpdate {
        try decode(PhoneUpdate.self, from: data)
    }

    /// A message body with the protocol version.
    private struct Envelope<Body: Codable>: Codable {
        /// The protocol version the sender uses.
        let version: Int

        /// The command or update.
        let body: Body
    }

    /// Only the version of a message, read first so a message of another version is recognized
    /// even when its body has changed.
    private struct VersionOnly: Codable {
        /// The protocol version the sender uses.
        let version: Int
    }

    /// Encodes an envelope as JSON.
    ///
    /// - Parameter envelope: The envelope.
    /// - Returns: The JSON bytes.
    private static func encode<Body: Codable>(_ envelope: Envelope<Body>) -> Data {
        // The message types hold only enums, integers and Booleans, which JSONEncoder always
        // encodes, so this can't fail.
        try! JSONEncoder().encode(envelope)
    }

    /// Decodes a message body of this protocol version.
    ///
    /// - Parameters:
    ///   - type: The body type.
    ///   - data: The bytes received.
    /// - Returns: The body.
    /// - Throws: ``WatchMessageError``.
    private static func decode<Body: Codable>(_ type: Body.Type, from data: Data) throws(WatchMessageError) -> Body {
        let decoder = JSONDecoder()
        guard let sent = try? decoder.decode(VersionOnly.self, from: data) else { throw .unreadable }
        guard sent.version == version else { throw .otherVersion(sent.version) }
        guard let envelope = try? decoder.decode(Envelope<Body>.self, from: data) else { throw .unreadable }
        return envelope.body
    }
}

/// Why a watch message couldn't be decoded.
public enum WatchMessageError: Error, Equatable, Sendable {
    /// The bytes aren't a message this version knows.
    case unreadable

    /// The message is of another protocol version, given.
    case otherVersion(Int)
}
