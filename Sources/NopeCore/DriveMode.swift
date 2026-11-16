import Foundation
import Observation

/// What one press of the shutter does: take one photo, start the self-timer, take a burst, or
/// start an interval series (issue #68, "Drive"). Single is the default.
public enum DriveMode: Hashable, Sendable {
    /// One photo per press.
    case single

    /// A countdown, then one photo (issue #39).
    case timer(SelfTimerDelay)

    /// A rapid run of single, unprocessed frames, each saved as its own photo (issue #46).
    case burst

    /// An interval series (issue #48): separate photos at a fixed interval, with the interval
    /// and count chosen with ``ManualControlIntent/setInterval(_:)``
    /// (``ManualControlsModel/interval``). It works in full auto and with manual controls on.
    case interval

    /// Every mode, in the order an interface lists them: single, 3 s, 10 s, burst, interval.
    public static let allCases: [DriveMode] = [.single, .timer(.threeSeconds), .timer(.tenSeconds), .burst, .interval]
}

/// How a hardware shutter button moved: the volume buttons or the Camera Control (issue #37).
///
/// The app maps the system's capture event phases to these values (AVKit, `AVCaptureEvent`).
public enum HardwareButtonPhase: Equatable, Sendable {
    /// The button went down.
    case pressed

    /// The button came up.
    case released

    /// The system cancelled the press.
    case cancelled
}

/// A request about the drive mode, the self-timer or a burst, sent as ``CameraIntent/drive(_:)``.
public enum DriveIntent: Equatable, Sendable {
    /// Choose what the shutter does. Ignored while a countdown or burst runs.
    case setMode(DriveMode)

    /// Count down this many seconds, then take one photo, whatever the drive mode. Ignored while
    /// a photo can't be taken or a countdown or burst runs. A Siri or Shortcuts request with a
    /// delay (issue #62) sends it.
    ///
    /// - Parameter seconds: The delay, at least 1.
    case startTimer(seconds: Int)

    /// Stop the countdown without taking a photo.
    case cancelTimer

    /// Stop a running burst after the frame being taken. Every frame already taken is saved.
    case stopBurst

    /// A hardware shutter button moved. In burst mode, holding it takes a burst until it comes
    /// up; in the other modes, it acts like the on-screen shutter when it comes up, as the
    /// system Camera app does.
    case hardwareButton(HardwareButtonPhase)
}

/// The progress of a running burst.
public struct BurstProgress: Equatable, Sendable {
    /// The frames taken so far.
    public let taken: Int

    /// The frames saved so far. Saving follows taking, so it can be one behind.
    public let saved: Int

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The frames taken so far.
    ///   - saved: The frames saved so far.
    public init(taken: Int, saved: Int) {
        self.taken = taken
        self.saved = saved
    }
}

/// Why a burst ended.
public enum BurstEnd: Equatable, Sendable {
    /// The person let go of the button, or pressed Stop.
    case stopped

    /// The burst reached ``DriveModel/maximumBurstFrames``, or an astro run took all its frames.
    case limitReached

    /// The burst took the number of frames a Siri or Shortcuts request asked for (issue #62),
    /// fewer than ``DriveModel/maximumBurstFrames``. Siri reports the result, so an interface
    /// needn't announce it.
    case countReached

    /// The next frame wouldn't fit in the device's free storage (issue #44).
    case storageFull

    /// The camera stopped running, for example because of an interruption or a lens change.
    case cameraStopped

    /// The battery is at or below ``AstroModel/stopBatteryLevel`` and not charging. Only astro
    /// runs stop for it; a burst is too short to need it.
    case batteryLow

    /// A frame couldn't be taken or saved; ``CameraModel/captureStatus`` holds the error.
    case failed
}

/// How the last burst went: why it ended and how many frames were saved.
public struct BurstResult: Equatable, Sendable {
    /// Why it ended.
    public let end: BurstEnd

    /// The frames saved, each its own photo.
    public let saved: Int

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - end: Why it ended.
    ///   - saved: The frames saved.
    public init(end: BurstEnd, saved: Int) {
        self.end = end
        self.saved = saved
    }
}

/// The drive mode and the state of the self-timer and of a burst.
///
/// ``CameraModel`` owns one as ``CameraModel/drive``. An interface reads it and sends
/// ``DriveIntent`` values as ``CameraIntent/drive(_:)``; the shutter itself sends
/// ``CameraIntent/capture``, and the model applies the mode. Single is the default, and the mode
/// isn't stored: every launch starts in single (AGENTS.md, "Cognitive": no surprise modes).
@MainActor
@Observable
public final class DriveModel {
    /// The most frames one burst takes (issue #46, "Limits"). An assumption to be confirmed on a
    /// device: with RAW and HEIF at 12 MP this is under 2 GB, and memory stays bounded at any
    /// count, because each frame is saved while the next is taken.
    nonisolated public static let maximumBurstFrames = 50

    /// What the shutter does.
    public private(set) var mode = DriveMode.single

    /// The self-timer.
    public let countdown: Countdown

    /// The running burst, or `nil` when none runs.
    public private(set) var burstProgress: BurstProgress?

    /// How the last burst ended, or `nil` before the first one. Cleared when the next starts.
    public private(set) var lastBurst: BurstResult?

    /// Whether the person asked the running burst to stop.
    private(set) var isBurstStopRequested = false

    /// Creates the model in single mode.
    ///
    /// - Parameter sleep: Waits a number of seconds between countdown ticks.
    init(sleep: @escaping @Sendable (Double) async throws -> Void) {
        countdown = Countdown(sleep: sleep)
    }

    /// Whether a countdown or a burst runs, so the shutter stops it instead of taking a photo.
    public var isBusy: Bool {
        countdown.isRunning || burstProgress != nil
    }

    /// Changes the mode, unless a countdown or burst runs.
    ///
    /// - Parameter mode: The new mode.
    func setMode(_ mode: DriveMode) {
        guard !isBusy else { return }
        self.mode = mode
    }

    /// Marks a burst as started.
    func beginBurst() {
        isBurstStopRequested = false
        lastBurst = nil
        burstProgress = BurstProgress(taken: 0, saved: 0)
    }

    /// Asks the running burst to stop after the frame being taken.
    func requestBurstStop() {
        guard burstProgress != nil else { return }
        isBurstStopRequested = true
    }

    /// Counts a frame taken.
    func recordTaken() {
        burstProgress = burstProgress.map { BurstProgress(taken: $0.taken + 1, saved: $0.saved) }
    }

    /// Counts a frame saved.
    func recordSaved() {
        burstProgress = burstProgress.map { BurstProgress(taken: $0.taken, saved: $0.saved + 1) }
    }

    /// Marks the burst as ended.
    ///
    /// - Parameter end: Why it ended.
    func endBurst(_ end: BurstEnd) {
        lastBurst = BurstResult(end: end, saved: burstProgress?.saved ?? 0)
        burstProgress = nil
        isBurstStopRequested = false
    }
}
