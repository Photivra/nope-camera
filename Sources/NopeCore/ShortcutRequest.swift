import Foundation

/// A request from outside the camera screen: Siri, the Shortcuts app, or another system entry
/// point that runs one of the app's App Intents (issue #62).
///
/// The app's intents hold no rules of their own (AGENTS.md, "Siri and Shortcuts"): an intent
/// turns its parameters into a request, hands it to a ``ShortcutInbox`` and reports the
/// ``ShortcutOutcome``. ``CameraModel/serveShortcuts(from:)`` performs it with the same intents
/// as the on-screen controls.
public enum ShortcutRequest: Equatable, Sendable {
    /// Take one photo or a burst, after an optional delay, with an optional lens.
    case takePhoto(PhotoShortcut)

    /// Take one exposure bracket, after an optional delay, with an optional lens, without
    /// changing the bracket chosen in Pro Tools.
    case takeBracket(BracketShortcut)

    /// Switch to a lens of this kind, as the lens buttons do.
    case selectLens(Lens.Kind)

    /// Turn the light (the torch) on or off, as the Light switch in the quick-controls tray does.
    case setLight(isOn: Bool)

    /// Start an interval series, as Start in Pro Tools does.
    case startInterval(IntervalShortcut)

    /// Stop the running interval series, as its Stop button does.
    case stopInterval

    /// What the request ends with when no camera screen is open to take it, or `nil` when it
    /// waits for one (``ShortcutInbox/startTimeoutSeconds``).
    ///
    /// Turning the light off and stopping a series don't need the camera: without a camera
    /// screen, the camera isn't running, so the light is already off and no series runs
    /// (AGENTS.md, "Battery": the light turns off and the session stops when the camera screen
    /// isn't in use). Their intents therefore run without opening the app.
    public var outcomeWithoutCameraScreen: ShortcutOutcome? {
        switch self {
        case .setLight(isOn: false): .lightOff
        case .stopInterval: .noIntervalRunning
        case .takePhoto, .takeBracket, .selectLens, .setLight(isOn: true), .startInterval: nil
        }
    }
}

/// The parameters of a "Take Photo" request: the delay before the shot, the lens and how many
/// photos.
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

    /// How many photos, from 1 to ``DriveModel/maximumBurstFrames``. One takes a single photo
    /// (an exposure bracket that is on in the manual controls still applies, as it does to the
    /// shutter); more takes a burst of exactly that many frames with the burst's own loop, each
    /// frame its own photo.
    public let count: Int

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - delaySeconds: The delay in seconds. Values below 0 become 0, and values above
    ///     ``maximumDelaySeconds`` become ``maximumDelaySeconds``.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    ///   - count: How many photos. Values below 1 become 1, and values above
    ///     ``DriveModel/maximumBurstFrames`` become ``DriveModel/maximumBurstFrames``.
    public init(delaySeconds: Int = 0, lensKind: Lens.Kind? = nil, count: Int = 1) {
        self.delaySeconds = min(max(delaySeconds, 0), Self.maximumDelaySeconds)
        self.lensKind = lensKind
        self.count = min(max(count, 1), DriveModel.maximumBurstFrames)
    }

    /// Creates a request from a preset delay and an optional custom one, as the "Take Photo"
    /// intent offers them: a custom delay, when given, replaces the preset.
    ///
    /// - Parameters:
    ///   - timer: The preset delay, or `nil` for none.
    ///   - customDelaySeconds: A custom delay in seconds, or `nil` to use the preset.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    ///   - count: How many photos, or `nil` for one.
    public init(timer: SelfTimerDelay?, customDelaySeconds: Int?, lensKind: Lens.Kind? = nil, count: Int? = nil) {
        self.init(delaySeconds: customDelaySeconds ?? timer?.seconds ?? 0, lensKind: lensKind, count: count ?? 1)
    }
}

/// The parameters of a "Take Bracket" request: the frames, the step between them, the delay and
/// the lens.
///
/// The bracket is taken once, through the same bracket path as the one in Pro Tools, whether or
/// not manual controls are on; the person's own bracket setting doesn't change. Values are moved
/// to the nearest the app offers (``BracketSettings/frameCounts`` and ``BracketSettings/steps``);
/// whether the lens can take it is checked when it is taken.
public struct BracketShortcut: Equatable, Sendable {
    /// The frames and the step, each one the app offers.
    public let bracket: BracketSettings

    /// The delay before the bracket, in seconds, from 0 to ``PhotoShortcut/maximumDelaySeconds``.
    public let delaySeconds: Int

    /// The kind of lens to use, or `nil` for the lens already selected.
    public let lensKind: Lens.Kind?

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - frameCount: The number of frames, moved to the nearest of ``BracketSettings/frameCounts``.
    ///   - step: The exposure difference between neighboring frames in EV (stops), moved to the
    ///     nearest of ``BracketSettings/steps``.
    ///   - delaySeconds: The delay in seconds, kept within 0 to ``PhotoShortcut/maximumDelaySeconds``.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    public init(frameCount: Int, step: Double, delaySeconds: Int = 0, lensKind: Lens.Kind? = nil) {
        bracket = BracketSettings(
            frameCount: Self.nearest(frameCount, in: BracketSettings.frameCounts),
            step: Self.nearest(step, in: BracketSettings.steps))
        self.delaySeconds = PhotoShortcut(delaySeconds: delaySeconds).delaySeconds
        self.lensKind = lensKind
    }

    /// The value in a list closest to a value: the first of two equally close ones.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - values: The values offered; not empty.
    /// - Returns: The closest.
    static func nearest<Value: Numeric & Comparable>(_ value: Value, in values: [Value]) -> Value {
        values.dropFirst().reduce(values[0]) { best, next in
            distance(next, value) < distance(best, value) ? next : best
        }
    }

    /// The distance between two values.
    private static func distance<Value: Numeric & Comparable>(_ first: Value, _ second: Value) -> Value {
        first > second ? first - second : second - first
    }
}

/// The parameters of a "Start Interval Shooting" request: the time between photos and how many,
/// each `nil` to keep the value chosen in Pro Tools (``ManualControlsModel/interval``).
///
/// Values are moved into the ranges ``IntervalSettings`` allows.
public struct IntervalShortcut: Equatable, Sendable {
    /// The time from one photo to the next in seconds, or `nil` to keep the chosen one.
    public let intervalSeconds: Double?

    /// How many photos the series takes, or `nil` to keep the chosen number.
    public let count: Int?

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - intervalSeconds: The time between photos in seconds, or `nil` to keep the chosen one.
    ///   - count: The number of photos, or `nil` to keep the chosen number.
    public init(intervalSeconds: Double? = nil, count: Int? = nil) {
        self.intervalSeconds = intervalSeconds
        self.count = count
    }

    /// The series to run: this request's values over the chosen ones.
    ///
    /// - Parameter chosen: The interval and count chosen in Pro Tools.
    /// - Returns: The settings, each value inside its allowed range.
    public func settings(over chosen: IntervalSettings) -> IntervalSettings {
        IntervalSettings(interval: intervalSeconds ?? chosen.interval, count: count ?? chosen.count)
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

    /// A photo, countdown, burst, interval series or astro run was already in progress. Say so;
    /// nothing changed.
    case busy

    /// The device has no lens of the kind asked for. Say so; nothing was taken or changed.
    case lensUnavailable

    /// The camera now uses a lens of this kind. Say which.
    case lensSelected(Lens.Kind)

    /// The light is on. Say so.
    case lightOn

    /// The light is off. Say so.
    case lightOff

    /// The lens in use has no light. Say so; nothing changed.
    case noLight

    /// The light was asked for, but the system didn't allow it (for example while the device is
    /// hot) or the astro helper keeps it off. Say the light isn't available right now.
    case lightUnavailable

    /// An interval series started. Say so; the camera screen shows its progress.
    case intervalStarted

    /// The interval series was stopped. Say so; every photo already taken is saved.
    case intervalStopped

    /// No interval series was running, so nothing was stopped. Say so.
    case noIntervalRunning

    /// The lens in use can't take the bracket asked for: it has no manual exposure, or takes
    /// fewer frames in one bracket. Say so; nothing was taken.
    case bracketUnavailable

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
