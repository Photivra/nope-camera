import Foundation

/// A request from outside the camera screen: Siri, the Shortcuts app, or another system entry
/// point that runs one of the app's App Intents (issue #62).
///
/// The app's intents hold no rules of their own (AGENTS.md, "Siri and Shortcuts"): an intent
/// turns its parameters into a request, hands it to a ``ShortcutInbox`` and reports the
/// ``ShortcutOutcome``. ``CameraModel/serveShortcuts(from:)`` performs it with the same intents
/// as the on-screen controls.
public enum ShortcutRequest: Equatable, Sendable {
    /// Take one photo, after an optional delay, with an optional lens.
    case takePhoto(PhotoShortcut)
}

/// The parameters of a "Take Photo" request: the delay before the shot and the lens.
///
/// Every value is checked here, so an intent can pass what the person typed in Shortcuts as it
/// is.
public struct PhotoShortcut: Equatable, Sendable {
    /// The longest delay a request may ask for, in seconds. A product choice for issue #62, not
    /// a platform limit: Siri waits for the result, and a minute keeps that wait short. Longer
    /// requests are shortened to it.
    public static let maximumDelaySeconds = 60

    /// The delay before the photo, in seconds, from 0 (none) to ``maximumDelaySeconds``. A delay
    /// runs the self-timer, with its countdown on screen and announced.
    public let delaySeconds: Int

    /// The kind of lens to use, or `nil` for the lens already selected.
    public let lensKind: Lens.Kind?

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - delaySeconds: The delay in seconds. Values below 0 become 0, and values above
    ///     ``maximumDelaySeconds`` become ``maximumDelaySeconds``.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    public init(delaySeconds: Int = 0, lensKind: Lens.Kind? = nil) {
        self.delaySeconds = min(max(delaySeconds, 0), Self.maximumDelaySeconds)
        self.lensKind = lensKind
    }

    /// Creates a request from a preset delay and an optional custom one, as the "Take Photo"
    /// intent offers them: a custom delay, when given, replaces the preset.
    ///
    /// - Parameters:
    ///   - timer: The preset delay, or `nil` for none.
    ///   - customDelaySeconds: A custom delay in seconds, or `nil` to use the preset.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    public init(timer: SelfTimerDelay?, customDelaySeconds: Int?, lensKind: Lens.Kind? = nil) {
        self.init(delaySeconds: customDelaySeconds ?? timer?.seconds ?? 0, lensKind: lensKind)
    }
}

/// How a ``ShortcutRequest`` ended, for Siri or Shortcuts to say.
///
/// It reports only whether photos were saved and signed, never image data or metadata
/// (issue #62, "Privacy"). Each case says what an intent should say.
public enum ShortcutOutcome: Equatable, Sendable {
    /// One photo was saved. Say "Photo saved and signed." or, when `isSigned` is false, "Photo
    /// saved. It isn't signed."
    case saved(isSigned: Bool)

    /// An exposure bracket was saved, each frame its own photo, because bracketing is on in
    /// the manual controls. Say "Photos saved and signed." or "Photos saved. Not all of them are
    /// signed."
    case savedSeveral(allSigned: Bool)

    /// The photo was taken but not saved, or couldn't be taken. Say that it wasn't saved, and
    /// that the app shows why.
    case notSaved(CaptureError)

    /// The countdown was cancelled on the device, so no photo was taken. Say so.
    case cancelled

    /// A photo, countdown or burst was already in progress. Say so; nothing changed.
    case busy

    /// The device has no lens of the kind asked for. Say so; nothing was taken.
    case lensUnavailable

    /// The camera can't take a photo now. Say why, from the reason.
    case cameraUnavailable(CameraUnavailability)
}

/// Why the camera couldn't take a photo for a ``ShortcutRequest``.
public enum CameraUnavailability: Equatable, Sendable {
    /// The person hasn't been asked for camera access yet. Say to open the app to allow it.
    case needsPermission

    /// Camera access is declined or restricted. Say it can be turned on in the Settings app.
    case permissionDenied

    /// The device has no camera the app can use. Say so.
    case noCamera

    /// The camera didn't start or isn't running: it is starting too slowly, in use by another
    /// app, paused for heat, failed, or the camera screen isn't open. Say the camera isn't
    /// available right now.
    case notRunning
}
