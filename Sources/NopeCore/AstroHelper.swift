import Foundation
import Observation

/// A request about the astro helper, sent as ``CameraIntent/astro(_:)`` (issue #60).
public enum AstroIntent: Equatable, Sendable {
    /// Turn the helper on or off. Turning it on is ignored on a lens it can't use
    /// (``AstroModel/isAvailable(on:)``) and while a photo, countdown or series runs.
    case setOn(Bool)

    /// Choose how many frames the next run takes, one of ``AstroModel/frameCounts``. Ignored
    /// while a run counts down or runs.
    case setFrameCount(Int)

    /// Choose the delay before the first frame. Ignored while a run counts down or runs.
    case setStartDelay(SelfTimerDelay)

    /// Stop the countdown or the running frames. Every frame already taken is saved.
    case stop
}

/// The astro helper: a consistent series of single Bayer RAW frames of the night sky, to be
/// stacked in other software (issue #60).
///
/// The app never stacks, merges or processes the frames: each one is an ordinary single-frame
/// photo that goes through the metadata allowlist, read-back and signing like any other
/// (AGENTS.md, "Honesty"). The helper only sets up the camera and takes the frames:
///
/// - **Turning it on** turns manual controls on if they are off, sets focus to the far end of
///   the lens's range, the shutter to the longest the lens allows and ISO to the highest
///   (``startingExposure(for:)``), turns the light off, returns the drive mode to single and
///   turns bracketing off. After that, every manual control is the person's to change; the
///   helper doesn't change them again until it is turned on again or the lens changes.
/// - **The shutter** then starts the self-timer (``startDelay``), so touching the phone doesn't
///   shake the first frame, and takes ``frameCount`` frames back to back, each saved while the
///   next is exposed.
/// - **A run stops** when the person stops it, when the next frame wouldn't fit in storage, when
///   the battery is at or below ``stopBatteryLevel`` and not charging, when the camera stops, or
///   at the first frame that can't be taken or saved. Every frame taken before that is saved.
/// - **Turning it off** turns manual controls off again if the helper turned them on.
///
/// ``CameraModel`` owns one as ``CameraModel/astro``; an interface reads it and sends
/// ``AstroIntent`` values. Turning night mode on is the interface's part, through
/// ``NopeSettings/setNightMode(_:)``, because night mode is a setting of the screens, not of
/// the camera. The helper is off at every launch (AGENTS.md, "Cognitive": no surprise modes).
@MainActor
@Observable
public final class AstroModel {
    /// The frame counts a run offers.
    public static let frameCounts = [5, 10, 20, 30, 50, 100, 200, 300]

    /// The frame count a run starts with.
    nonisolated public static let defaultFrameCount = 20

    /// At or below this charge, unplugged, a run stops before the next frame: 10%. An
    /// assumption to be checked on a device: low enough not to stop a run the person can still
    /// finish, high enough to leave charge for the frames to save and the phone to be used.
    public static let stopBatteryLevel = 0.1

    /// Whether the helper is on.
    public private(set) var isOn = false

    /// How many frames the next run takes.
    public private(set) var frameCount = AstroModel.defaultFrameCount

    /// The delay before the first frame. 10 seconds by default, so the phone is still again
    /// after the shutter is touched.
    public private(set) var startDelay = SelfTimerDelay.tenSeconds

    /// The running frames, or `nil` when no run is taking frames. The countdown before the
    /// first frame is ``DriveModel/countdown``.
    public private(set) var progress: BurstProgress?

    /// How the last run ended, or `nil` before the first one. Cleared when the next starts.
    public private(set) var lastRun: BurstResult?

    /// Whether the person asked the running frames to stop.
    private(set) var isStopRequested = false

    /// Whether turning the helper on turned manual controls on, so turning it off turns them
    /// off again.
    var turnedOnManualControls = false

    /// Creates the helper, off.
    init() {}

    /// Whether frames are being taken now.
    public var isRunning: Bool {
        progress != nil
    }

    /// Whether the helper can be used on a lens: it has Bayer RAW, manual exposure with a shutter
    /// and ISO range, and manual focus.
    ///
    /// - Parameter lens: A lens.
    /// - Returns: `true` when ``startingExposure(for:)`` has values for it.
    public static func isAvailable(on lens: Lens) -> Bool {
        startingExposure(for: lens) != nil
    }

    /// The exposure the helper starts from on a lens: the longest shutter and the highest ISO
    /// the lens reports, and focus at the far end of its range (lens position 1, the farthest
    /// the lens focuses; AVFoundation, `AVCaptureDevice.lensPosition`). The lens position isn't
    /// calibrated to a distance, so the far end may not be exactly sharp at infinity: the person
    /// checks it with the focus magnifier and fine-tunes it.
    ///
    /// - Parameter lens: A lens.
    /// - Returns: The values, or `nil` when the lens lacks Bayer RAW, manual exposure, a
    ///   shutter or ISO range, or manual focus.
    public static func startingExposure(for lens: Lens) -> AstroExposure? {
        let controls = lens.manualControls
        guard lens.supportsBayerRAW, controls.supportsManualExposure, controls.supportsManualFocus,
            let shutter = lens.exposureDurationRange?.upperBound, let iso = lens.isoRange?.upperBound
        else { return nil }
        return AstroExposure(shutter: shutter, iso: iso, focus: 1)
    }

    /// Records the helper as on or off.
    ///
    /// - Parameter isOn: Whether it is on.
    func setOn(_ isOn: Bool) {
        self.isOn = isOn
    }

    /// Chooses the frame count, if it is one of ``frameCounts``.
    ///
    /// - Parameter count: The frame count.
    func setFrameCount(_ count: Int) {
        guard Self.frameCounts.contains(count) else { return }
        frameCount = count
    }

    /// Chooses the start delay.
    ///
    /// - Parameter delay: The delay.
    func setStartDelay(_ delay: SelfTimerDelay) {
        startDelay = delay
    }
}

extension AstroModel: FrameRunTracking {
    /// Marks a run as started.
    func beginRun() {
        isStopRequested = false
        lastRun = nil
        progress = BurstProgress(taken: 0, saved: 0)
    }

    /// Asks the running frames to stop after the frame being taken. Called only while they run.
    func requestStop() {
        isStopRequested = true
    }

    /// Counts a frame taken.
    func recordTaken() {
        progress = progress.map { BurstProgress(taken: $0.taken + 1, saved: $0.saved) }
    }

    /// Counts a frame saved.
    func recordSaved() {
        progress = progress.map { BurstProgress(taken: $0.taken, saved: $0.saved + 1) }
    }

    /// Marks the run as ended.
    ///
    /// - Parameter end: Why it ended.
    func endRun(_ end: BurstEnd) {
        lastRun = BurstResult(end: end, saved: progress?.saved ?? 0)
        progress = nil
        isStopRequested = false
    }
}

/// The exposure the astro helper starts from on a lens (``AstroModel/startingExposure(for:)``).
public struct AstroExposure: Equatable, Sendable {
    /// The shutter, in seconds.
    public let shutter: Double

    /// The ISO.
    public let iso: Double

    /// The focus, on the relative scale from 0 (closest) to 1 (far).
    public let focus: Double

    /// Creates the values.
    ///
    /// - Parameters:
    ///   - shutter: The shutter, in seconds.
    ///   - iso: The ISO.
    ///   - focus: The focus, from 0 to 1.
    public init(shutter: Double, iso: Double, focus: Double) {
        self.shutter = shutter
        self.iso = iso
        self.focus = focus
    }
}

/// What the next astro run will take, for an interface to show before the shutter is pressed
/// (``CameraModel/astroEstimate``).
public struct AstroEstimate: Equatable, Sendable {
    /// The frames the run takes.
    public let frameCount: Int

    /// Each frame's shutter, in seconds, or `nil` before the camera reports one.
    public let shutter: Double?

    /// The most bytes the run's files can take (``PhotoSizeEstimate``, an upper bound).
    public let bytes: Int64

    /// How many frames fit in the free storage, or `nil` when the free storage is unknown.
    public let framesThatFit: Int?

    /// Creates an estimate.
    ///
    /// - Parameters:
    ///   - frameCount: The frames the run takes.
    ///   - shutter: Each frame's shutter, in seconds, or `nil`.
    ///   - bytes: The most bytes the run's files can take.
    ///   - framesThatFit: How many frames fit, or `nil` when unknown.
    public init(frameCount: Int, shutter: Double?, bytes: Int64, framesThatFit: Int?) {
        self.frameCount = frameCount
        self.shutter = shutter
        self.bytes = bytes
        self.framesThatFit = framesThatFit
    }

    /// The exposure time of all frames together, in seconds, or `nil` without a shutter. The run
    /// takes longer than this: each frame also needs time to be read out and saved, which this
    /// estimate doesn't know.
    public var totalExposureSeconds: Double? {
        shutter.map { $0 * Double(frameCount) }
    }

    /// Whether every frame is expected to fit in the free storage. `true` when it is unknown.
    public var fits: Bool {
        framesThatFit.map { $0 >= frameCount } ?? true
    }
}

/// What a run of single frames reports to: a burst (``DriveModel``) or the astro helper
/// (``AstroModel``). Both runs share one loop in ``CameraModel``.
@MainActor
protocol FrameRunTracking: AnyObject {
    /// Whether the person asked the run to stop.
    var isStopRequested: Bool { get }

    /// Marks a run as started.
    func beginRun()

    /// Counts a frame taken.
    func recordTaken()

    /// Counts a frame saved.
    func recordSaved()

    /// Marks the run as ended.
    ///
    /// - Parameter end: Why it ended.
    func endRun(_ end: BurstEnd)
}

extension DriveModel: FrameRunTracking {
    /// Whether the person asked the running burst to stop.
    var isStopRequested: Bool { isBurstStopRequested }

    /// Marks a burst as started.
    func beginRun() { beginBurst() }

    /// Marks the burst as ended.
    ///
    /// - Parameter end: Why it ended.
    func endRun(_ end: BurstEnd) { endBurst(end) }
}
