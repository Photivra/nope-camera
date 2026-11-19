import Foundation

/// A request from outside the camera screen: Siri, the Shortcuts app, or another system entry
/// point that runs one of the app's App Intents (issue #62).
///
/// The app's intents hold no rules of their own (AGENTS.md, "Siri and Shortcuts"): an intent
/// turns its parameters into a request, hands it to a ``ShortcutInbox`` and reports the
/// ``ShortcutOutcome``. ``CameraModel/serveShortcuts(from:settings:presets:)`` performs it with the same intents
/// as the on-screen controls.
public enum ShortcutRequest: Equatable, Sendable {
    /// Take one photo or a burst, after an optional delay, with an optional lens.
    case takePhoto(PhotoShortcut)

    /// Take one exposure bracket, after an optional delay, with an optional lens, without
    /// changing the bracket chosen on the drive strip.
    case takeBracket(BracketShortcut)

    /// Switch to a lens of this kind, as the lens buttons do.
    case selectLens(Lens.Kind)

    /// Turn the light (the torch) on or off, as the Light switch in the quick-controls tray does.
    case setLight(isOn: Bool)

    /// Start an interval series, as Start in Pro Tools does.
    case startInterval(IntervalShortcut)

    /// Stop the running interval series, as its Stop button does.
    case stopInterval

    /// Limit autofocus to near or far subjects, or lift the limit, as Close-Up and Far Focus in
    /// the quick-controls tray do.
    case setFocusRange(FocusRangeChoice)

    /// Choose the photo size of a lens that offers more than one, as Settings > Photo Size does.
    case setPhotoSize(PhotoSizeShortcut)

    /// Apply a settings preset (issue #72), as tapping it in the Presets list does.
    case applyPreset(PresetChoice)

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
        case .takePhoto, .takeBracket, .selectLens, .setLight(isOn: true), .startInterval, .setFocusRange,
            .setPhotoSize, .applyPreset:
            nil
        }
    }

    /// Whether the request ends at once, without waiting for the camera or a photo: turning
    /// the light off and stopping a series. A ``ShortcutInbox`` hands it to the camera screen
    /// even while another request is being performed, so stopping never waits behind a
    /// countdown or a slow camera start.
    public var isInstant: Bool {
        outcomeWithoutCameraScreen != nil
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

    /// How many photos, from 1 to ``DriveModel/maximumBurstFrames``. One takes a single photo;
    /// more takes a burst of exactly that many frames with the burst's own loop, each frame its
    /// own photo.
    public let count: Int

    /// Whether an exposure bracket that is on in the manual controls applies to a single photo,
    /// as it does to the shutter: `true` for the Apple Watch's shutter, which takes what the
    /// phone's drive strip says (docs/design/BRACKETING.md, section 6); `false` for Siri and
    /// Shortcuts, whose Take Photo always takes one photo, so the question and the answer
    /// match what was taken (third review of 1.0.0, question 7). Take Bracket is the action
    /// for a bracket.
    public let appliesBracketInApp: Bool

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - delaySeconds: The delay in seconds. Values below 0 become 0, and values above
    ///     ``maximumDelaySeconds`` become ``maximumDelaySeconds``.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    ///   - count: How many photos. Values below 1 become 1, and values above
    ///     ``DriveModel/maximumBurstFrames`` become ``DriveModel/maximumBurstFrames``.
    ///   - appliesBracketInApp: Whether an exposure bracket on in the manual controls applies
    ///     to a single photo (the Apple Watch), or not (Siri and Shortcuts, the default).
    public init(delaySeconds: Int = 0, lensKind: Lens.Kind? = nil, count: Int = 1, appliesBracketInApp: Bool = false) {
        self.delaySeconds = min(max(delaySeconds, 0), Self.maximumDelaySeconds)
        self.lensKind = lensKind
        self.count = min(max(count, 1), DriveModel.maximumBurstFrames)
        self.appliesBracketInApp = appliesBracketInApp
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

/// The range of a focus bracket asked for from Siri or Shortcuts.
public enum FocusBracketRange: String, CaseIterable, Equatable, Sendable {
    /// The range set in the app (``BracketModel/focus``).
    case asSet

    /// The whole range, 0 to 1.
    case wholeRange
}

/// The parameters of a "Take Bracket" request: the frames, the step between them, their order,
/// the delay and the lens.
///
/// The bracket is taken once, through the same bracket path as the shutter's, whether or not
/// manual controls are on; the person's own bracket setting doesn't change. Values are moved
/// to the nearest the app offers (``BracketSettings/frameCounts`` and ``BracketSettings/steps``);
/// whether the lens can take it is checked when it is taken.
public struct BracketShortcut: Equatable, Sendable {
    /// The frames, the step and the order, each one the app offers.
    public let bracket: BracketSettings

    /// The delay before the bracket, in seconds, from 0 to ``PhotoShortcut/maximumDelaySeconds``.
    public let delaySeconds: Int

    /// The kind of lens to use, or `nil` for the lens already selected.
    public let lensKind: Lens.Kind?

    /// The kind of bracket: ``BracketType/exposure`` by default. A focus bracket uses
    /// ``focusFrameCount`` and ``focusRange``; the step and order are an exposure bracket's.
    public let type: BracketType

    /// A focus bracket's frames, one of ``FocusBracketSettings/frameCounts``.
    public let focusFrameCount: Int

    /// A focus bracket's range: as set in the app, or the whole range.
    public let focusRange: FocusBracketRange

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - type: The kind of bracket; ``BracketType/exposure`` by default.
    ///   - focusFrameCount: A focus bracket's frames, moved to the nearest of
    ///     ``FocusBracketSettings/frameCounts``; 10 by default.
    ///   - focusRange: A focus bracket's range; as set in the app by default.
    ///   - frameCount: The number of frames, moved to the nearest of ``BracketSettings/frameCounts``.
    ///   - step: The exposure difference between neighboring frames in EV (stops), moved to the
    ///     nearest of ``BracketSettings/steps``.
    ///   - order: The order of the frames; ``BracketOrder/darkestFirst`` by default.
    ///   - delaySeconds: The delay in seconds, kept within 0 to ``PhotoShortcut/maximumDelaySeconds``.
    ///   - lensKind: The kind of lens, or `nil` for the lens already selected.
    public init(
        type: BracketType = .exposure, focusFrameCount: Int = FocusBracketSettings.defaultFrameCount,
        focusRange: FocusBracketRange = .asSet, frameCount: Int, step: Double, order: BracketOrder = .darkestFirst,
        delaySeconds: Int = 0, lensKind: Lens.Kind? = nil
    ) {
        self.type = type
        self.focusFrameCount = FocusBracketSettings.offeredFrameCount(nearestTo: focusFrameCount)
        self.focusRange = focusRange
        bracket = BracketSettings(
            frameCount: Self.nearest(frameCount, in: BracketSettings.frameCounts),
            step: Self.nearest(step, in: BracketSettings.steps), order: order)
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

/// The autofocus range a "Set Focus Range" request asks for. The camera has one range
/// restriction (`AVCaptureDevice.autoFocusRangeRestriction`), so Close-Up and Far Focus exclude
/// each other.
public enum FocusRangeChoice: Equatable, Sendable {
    /// No limit: autofocus searches the whole range, the default.
    case unlimited

    /// Close-Up: autofocus limited to near subjects (``AutoControlIntent/setNearFocusLimit(_:)``).
    case closeUp

    /// Far Focus: autofocus limited to far subjects (``AutoControlIntent/setFarFocusLimit(_:)``).
    case far
}

/// The parameters of a "Set Photo Size" request: the lens and the size.
public struct PhotoSizeShortcut: Equatable, Sendable {
    /// The size, of those the lens offers (``Lens/photoSizeChoices``).
    public enum Size: Equatable, Sendable {
        /// The lens's default, smallest size (``Lens/defaultPhotoSize``).
        case standard

        /// The largest size the lens offers.
        case largest
    }

    /// The kind of lens, or `nil` for the lens in use.
    public let lensKind: Lens.Kind?

    /// The size.
    public let size: Size

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - lensKind: The kind of lens, or `nil` for the lens in use.
    ///   - size: The size.
    public init(lensKind: Lens.Kind? = nil, size: Size) {
        self.lensKind = lensKind
        self.size = size
    }

    /// The photo size this request chooses on a lens.
    ///
    /// - Parameter lens: The lens.
    /// - Returns: The size, or `nil` when the lens offers no choice of size.
    public func dimensions(on lens: Lens) -> PhotoDimensions? {
        let choices = lens.photoSizeChoices
        switch size {
        case .standard: return choices.first
        case .largest: return choices.last
        }
    }
}

/// The parameters of a "Start Interval Shooting" request: the time between photos, and how many
/// photos or for how long, each `nil` to keep the value chosen in Interval Settings
/// (``ManualControlsModel/interval``).
///
/// Values are moved into the ranges ``IntervalSettings`` allows. A time makes the series stop
/// after that time, and a count without a time makes it stop after that number of photos; when
/// a request has both, the time decides and the count is kept as the chosen number.
public struct IntervalShortcut: Equatable, Sendable {
    /// The time from one photo to the next in seconds, or `nil` to keep the chosen one.
    public let intervalSeconds: Double?

    /// How many photos the series takes, or `nil` to keep the chosen number.
    public let count: Int?

    /// How long the series runs in seconds, or `nil` to keep the chosen end.
    public let durationSeconds: Double?

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - intervalSeconds: The time between photos in seconds, or `nil` to keep the chosen one.
    ///   - count: The number of photos, or `nil` to keep the chosen number.
    ///   - durationSeconds: How long the series runs in seconds, or `nil` to keep the chosen end.
    public init(intervalSeconds: Double? = nil, count: Int? = nil, durationSeconds: Double? = nil) {
        self.intervalSeconds = intervalSeconds
        self.count = count
        self.durationSeconds = durationSeconds
    }

    /// The series to run: this request's values over the chosen ones.
    ///
    /// - Parameter chosen: The series chosen in Interval Settings.
    /// - Returns: The settings, each value inside its allowed range.
    public func settings(over chosen: IntervalSettings) -> IntervalSettings {
        let stopAfter: IntervalSettings.StopAfter =
            if durationSeconds != nil { .time } else if count != nil { .numberOfPhotos } else { chosen.stopAfter }
        return IntervalSettings(
            interval: intervalSeconds ?? chosen.interval, count: count ?? chosen.count, stopAfter: stopAfter,
            duration: durationSeconds ?? chosen.duration)
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

    /// Several photos were saved, each its own photo: a burst, or an exposure bracket (asked
    /// for, or on in the manual controls). `count` is how many were saved. Say "Photos saved
    /// and signed." or "Photos saved. Not all of them are signed."
    case savedSeveral(count: Int, allSigned: Bool)

    /// The photo was taken but not saved, or couldn't be taken. Say that it wasn't saved, and
    /// that the app shows why.
    case notSaved(CaptureError)

    /// The countdown was cancelled on the device, so no photo was taken. Say so.
    case cancelled

    /// A photo, countdown, burst, interval series or astro run was already in progress. Say so;
    /// nothing changed.
    case busy

    /// The camera screen was still performing an earlier request from Siri, Shortcuts or the
    /// watch when this one had waited ``ShortcutInbox/startTimeoutSeconds``. Say so; nothing
    /// changed.
    case busyWithEarlierRequest

    /// A lens change was asked for while the lens can't be changed
    /// (``CameraModel/canChangeLens``): a photo, countdown, burst, interval series or astro run
    /// is in progress, or the compare view is open. Say the app is busy and the lens didn't
    /// change.
    case lensBusy

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

    /// The astro helper is on, so no interval series was started. Say so, and that turning Astro
    /// off allows one.
    case intervalBlockedByAstro

    /// The series would stop after a time no longer than its interval, so no interval series was
    /// started (``IntervalBlocker/intervalNotShorterThanTime``). Say so, and that the interval
    /// must be shorter than the time.
    case intervalNotShorterThanTime

    /// The interval series was stopped. Say so; every photo already taken is saved.
    case intervalStopped

    /// No interval series was running, so nothing was stopped. Say so.
    case noIntervalRunning

    /// Autofocus now has this range. Say which.
    case focusRangeSet(FocusRangeChoice)

    /// The lens can't limit its autofocus range. Say so; nothing changed.
    case focusRangeUnavailable

    /// The lens's photo size is now the one asked for, from the next photo. Say so.
    case photoSizeSet

    /// The lens offers only one photo size (a lens with Bayer RAW always takes its full-size
    /// RAW). Say so; nothing changed.
    case noPhotoSizeChoice

    /// The lens in use can't take the bracket asked for: it has no manual exposure, or takes
    /// fewer frames in one bracket. Say so; nothing was taken.
    case bracketUnavailable

    /// The lens in use can't take a focus bracket: its focus can't be set. Say so; nothing was
    /// taken.
    case focusBracketUnavailable

    /// A focus bracket stopped before its last frame (stopped, storage, battery or the camera).
    /// Say how many photos were saved, of how many.
    case focusBracketStopped(saved: Int, total: Int)

    /// The astro helper is on, so no focus bracket was taken. Say so, and that turning Astro off
    /// allows one. While the helper is on the app treats a focus bracket as off, and the shutter
    /// belongs to the astro run.
    case focusBracketBlockedByAstro

    /// A bracket, burst or focus bracket saved some of its photos and then failed. `saved` is
    /// how many were saved, `total` how many were planned. Say how many of how many were saved,
    /// and that the app shows why the others weren't.
    case savedSome(saved: Int, total: Int)

    /// The camera can't take a photo now. Say why, from the reason.
    case cameraUnavailable(CameraUnavailability)

    /// A settings preset was applied. Say which (Factory Defaults or the preset's name), whether
    /// everything applied as saved or the Presets list shows what didn't, and that it can be
    /// undone in the Presets list.
    case presetApplied(PresetApplyResult)

    /// The preset asked for no longer exists or can't be read. Say so; nothing changed.
    case presetUnavailable
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
