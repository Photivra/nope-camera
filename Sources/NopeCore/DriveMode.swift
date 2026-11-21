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

/// How a shutter moved: a hardware shutter button (the volume buttons or the Camera Control,
/// issue #37), or the on-screen shutter in burst mode (docs/design/BURST.md, 3.1).
///
/// The app maps the system's capture event phases to these values (AVKit, `AVCaptureEvent`);
/// an interface maps the on-screen shutter's touch to them.
public enum ShutterPhase: Equatable, Sendable {
    /// The shutter went down.
    case pressed

    /// The shutter came up.
    case released

    /// The system cancelled the press, or the finger slid off the on-screen shutter.
    case cancelled
}

/// The earlier name of ``ShutterPhase``, from when only the hardware buttons reported phases.
@available(*, deprecated, renamed: "ShutterPhase")
public typealias HardwareButtonPhase = ShutterPhase

/// How fast a burst takes its photos (docs/design/BURST.md, 3.2). The speed is held for the
/// session and not stored: each launch starts at ``fast``.
public enum BurstSpeed: CaseIterable, Hashable, Sendable {
    /// Each photo is requested as soon as the camera is ready for it. No rate is promised: the
    /// rate is the camera's and the saving's.
    case fast

    /// The same, with at least ``minimumFrameInterval`` between the starts of two photos: at
    /// most ``maximumPhotosPerSecond`` a second, and fewer when the camera needs longer.
    case slow

    /// The least time between the starts of two photos, or `nil` for none.
    public var minimumFrameInterval: Duration? {
        switch self {
        case .fast: nil
        case .slow: .milliseconds(500)
        }
    }

    /// The most photos a second this speed takes, or `nil` when only the camera limits it. Slow
    /// is worded "up to" this figure: it can take fewer.
    public var maximumPhotosPerSecond: Int? {
        switch self {
        case .fast: nil
        case .slow: 2
        }
    }
}

/// Who began a burst, so an interface knows how it ends: "Release to stop" for a held shutter,
/// Stop Burst for the others (docs/design/BURST.md, 4.1).
public enum BurstStart: Hashable, Sendable {
    /// A shutter held down: the on-screen shutter or a hardware button. It ends when the
    /// shutter comes up.
    case held

    /// Start Burst, which needs no holding (``DriveIntent/startBurst``). It ends with the
    /// shutter, Stop Burst or a limit.
    case started

    /// A set number of photos: a Siri or Shortcuts request (issue #62), or one photo for a press
    /// of the shutter that reports no phases (``CameraIntent/capture``). Always at ``BurstSpeed/fast``.
    case counted

    /// A press of the shutter (on screen, a hardware button, assistive activation or Start
    /// Burst) with a Burst Limit set (``DriveModel/burstLimit``, issue #121): it takes the
    /// limit's count of photos at the session's speed and doesn't end when the shutter comes
    /// up. A second press, Stop Burst or the other stops (storage, the camera) end it early.
    case limited
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
    case hardwareButton(ShutterPhase)

    /// The on-screen shutter moved, in burst mode: touching down takes the first photo at once
    /// and starts a burst, which ends when the shutter comes up, the finger slides off or the
    /// touch is cancelled (docs/design/BURST.md, 3.1). Ignored in the other modes, where the
    /// shutter sends ``CameraIntent/capture`` when it comes up.
    case shutter(ShutterPhase)

    /// Start a burst that needs no holding, in burst mode: it ends with the shutter, Stop Burst
    /// or a limit. Ignored outside burst mode, with the astro helper on, while a photo can't be
    /// taken, and while a countdown or burst runs.
    case startBurst

    /// Choose the burst speed for this session. Ignored while a countdown or burst runs.
    ///
    /// - Parameter speed: The speed.
    case setBurstSpeed(BurstSpeed)

    /// Use the person's Burst Limit (``NopeSettings/burstLimit``, issue #121): with a limit, a
    /// press of the shutter in burst mode takes that many photos, and a second press stops it
    /// early. Send it when the camera screen appears and whenever the setting changes. A
    /// running burst keeps the count it began with. Siri and Shortcuts keep their own count.
    ///
    /// - Parameter limit: The limit, or ``BurstLimit/off``.
    case setBurstLimit(BurstLimit)
}

/// The progress of a running burst, or of an astro run.
public struct BurstProgress: Equatable, Sendable {
    /// The frames taken so far.
    public let taken: Int

    /// The frames saved so far. Saving follows taking, so it can be one behind.
    public let saved: Int

    /// Who began the burst. An astro run reports ``BurstStart/started``.
    public let start: BurstStart

    /// The photos a second over the most recent photos of this burst (``DriveModel/rateWindow``),
    /// measured from their times, or `nil` before the third photo (docs/design/BURST.md, 3.3).
    public let rate: Double?

    /// Whether no more photos will be taken and the last ones are being saved. A new burst
    /// can't start until they are.
    public let isSaving: Bool

    /// The photos the press asked for with a Burst Limit set (``BurstStart/limited``), for "3 of
    /// 10"; `nil` for every other burst.
    public let limit: Int?

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The frames taken so far.
    ///   - saved: The frames saved so far.
    ///   - start: Who began the burst.
    ///   - rate: The measured photos a second, or `nil`.
    ///   - isSaving: Whether only saving is left.
    ///   - limit: The photos a limited burst asked for, or `nil`.
    public init(
        taken: Int, saved: Int, start: BurstStart = .started, rate: Double? = nil, isSaving: Bool = false,
        limit: Int? = nil
    ) {
        self.taken = taken
        self.saved = saved
        self.start = start
        self.rate = rate
        self.isSaving = isSaving
        self.limit = limit
    }

    /// The same progress with some values changed.
    ///
    /// - Parameters:
    ///   - taken: The frames taken so far.
    ///   - saved: The frames saved so far.
    ///   - rate: The measured photos a second.
    ///   - isSaving: Whether only saving is left.
    /// - Returns: The new progress.
    func with(taken: Int? = nil, saved: Int? = nil, rate: Double?? = nil, isSaving: Bool? = nil) -> BurstProgress {
        BurstProgress(
            taken: taken ?? self.taken, saved: saved ?? self.saved, start: start, rate: rate ?? self.rate,
            isSaving: isSaving ?? self.isSaving, limit: limit)
    }
}

/// Why a burst ended.
public enum BurstEnd: Equatable, Sendable {
    /// The person let go of the button, or pressed Stop.
    case stopped

    /// The burst reached ``DriveModel/maximumBurstFrames``, or an astro run took all its frames.
    case limitReached

    /// The burst took the number of frames asked for: a Siri or Shortcuts request's count (issue
    /// #62), fewer than ``DriveModel/maximumBurstFrames``, which Siri reports, so an interface
    /// needn't announce it; or a Burst Limit's count (``BurstStart/limited``, issue #121), also
    /// 50, which an interface shows as "10 of 10 photos saved".
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

/// How the last burst went: why it ended, how many frames were saved, and how fast it ran.
public struct BurstResult: Equatable, Sendable {
    /// Why it ended.
    public let end: BurstEnd

    /// The frames saved, each its own photo.
    public let saved: Int

    /// The frames taken. Every frame taken is saved unless one failed.
    public let taken: Int

    /// Who began the burst. An astro run reports ``BurstStart/started``.
    public let start: BurstStart

    /// The time from the first photo to the last; zero for fewer than two photos.
    public let duration: Duration

    /// The photos a second over the whole burst: the photos taken less one, divided by
    /// ``duration``; `nil` under three photos (docs/design/BURST.md, 3.3).
    public let rate: Double?

    /// The photos a press with a Burst Limit asked for (``BurstStart/limited``), for "4 of 10
    /// photos saved"; `nil` for every other burst.
    public let limit: Int?

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - end: Why it ended.
    ///   - saved: The frames saved.
    ///   - taken: The frames taken; `saved` when not given.
    ///   - start: Who began the burst.
    ///   - duration: The time from the first photo to the last, in the clock's units.
    ///   - rate: The photos a second, or `nil`.
    ///   - limit: The photos a limited burst asked for, or `nil`.
    public init(
        end: BurstEnd, saved: Int, taken: Int? = nil, start: BurstStart = .started, duration: Duration = .zero,
        rate: Double? = nil, limit: Int? = nil
    ) {
        self.end = end
        self.saved = saved
        self.taken = taken ?? saved
        self.start = start
        self.duration = duration
        self.rate = rate
        self.limit = limit
    }

    /// Whether an interface shows a summary of this burst ("12 photos saved", the time and the
    /// rate) until the next action: a burst of two photos or more that the person ended, not a
    /// Siri or Shortcuts count and not a failure. A burst of one photo is a photo. A burst with a
    /// Burst Limit has one whenever it saved a photo and reached its count or was stopped: the
    /// person asked for a count, so the summary says how many of it were saved ("4 of 10").
    public var hasSummary: Bool {
        switch start {
        case .counted: false
        case .limited: (end == .stopped || end == .countReached) && saved >= 1
        case .held, .started: end == .stopped && saved >= 2
        }
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

    /// The burst speed chosen for this session: ``BurstSpeed/fast`` at launch, and never stored
    /// (docs/design/BURST.md, decision 13). ``CameraModel/burstSpeed`` is the speed a burst on
    /// the selected lens uses.
    public private(set) var burstSpeed = BurstSpeed.fast

    /// The person's Burst Limit (``NopeSettings/burstLimit``, issue #121), as the interface last
    /// sent it with ``DriveIntent/setBurstLimit(_:)``: ``BurstLimit/off`` until then. With a
    /// limit, a press of the shutter in burst mode takes ``BurstLimit/frameCount`` photos
    /// (``BurstStart/limited``).
    public private(set) var burstLimit = BurstLimit.standard

    /// The photos a second measured at Fast in this session's bursts, by lens: the last whole
    /// burst of three photos or more on each. Not stored. It decides whether Slow is offered
    /// (``offersSlowBurst(on:)``).
    private(set) var measuredFastRates: [Lens.ID: Double] = [:]

    /// Whether the person asked the running burst to stop.
    private var isStopRequestedByPerson = false

    /// The shutter presses that are down, by source, numbered (issue #100). The model records
    /// each press and release here as it arrives, before any work starts.
    var holds = ShutterHolds()

    /// Whether a shutter that starts a held burst is down now: the on-screen shutter in burst
    /// mode or a hardware button. A held burst stops after its first photo once no shutter is
    /// down, also when it came up before the burst began. Each source has its own hold, so a
    /// press and release of a second button doesn't end the first one's burst.
    var isShutterHeld: Bool {
        holds.isAnyHeld
    }

    /// Who began the burst that is about to start or runs.
    private var start = BurstStart.counted

    /// The photos a limited burst that is about to start or runs asked for, or `nil`.
    private var limit: Int?

    /// Whether a press has asked for a burst that hasn't begun yet: the press is handled at once
    /// and the burst starts in a task just after (issue #100), so a second press in between
    /// mustn't start a second burst.
    private(set) var isBurstPrepared = false

    /// The time of the first photo of the running burst.
    private var firstPhotoTime: ContinuousClock.Instant?

    /// The times of the most recent photos of the running burst, up to ``rateWindow`` of them,
    /// oldest first.
    private var recentPhotoTimes: [ContinuousClock.Instant] = []

    /// Waits a number of seconds: between countdown ticks, and between the photos of a Slow
    /// burst.
    let sleep: @Sendable (Double) async throws -> Void

    /// Reads the monotonic clock, to time a burst's photos for its rate.
    let now: @Sendable () -> ContinuousClock.Instant

    /// How many of the most recent photos the running rate is measured over (docs/design/BURST.md,
    /// 3.3): enough to smooth one slow save, few enough to follow a change.
    nonisolated public static let rateWindow = 5

    /// The fewest photos a rate is shown for: with two, one gap would be shown as a rate.
    nonisolated public static let minimumPhotosForRate = 3

    /// The rate at Fast, in photos a second, below which Slow isn't offered on a lens: about 3 a
    /// second (owner decision 3, docs/design/BURST.md, 2026-11-18). Below it, Slow at up to 2 a
    /// second would barely differ from Fast. Measured in this session; no figure is assumed for
    /// a device.
    nonisolated public static let slowBurstMinimumFastRate = 3.0

    /// Creates the model in single mode, at the Fast burst speed.
    ///
    /// - Parameters:
    ///   - clock: The camera model's clock: the countdown counts to a moment of it, and Slow
    ///     photos wait on it.
    ///   - measure: Reads the monotonic clock that times a burst's photos: `clock`'s, unless the
    ///     camera model was made with the older seconds sleep.
    init(clock: NopeClock, measuredBy measure: @escaping @Sendable () -> ContinuousClock.Instant) {
        countdown = Countdown(clock: clock)
        sleep = { try await clock.sleep(seconds: $0) }
        now = measure
    }

    /// Creates the model with a sleep of a number of seconds, as tests written before
    /// ``NopeClock`` pass: Slow photos wait on it directly, and the countdown on a clock stepped by
    /// it (``NopeClock/stepped(by:now:)``).
    ///
    /// - Parameters:
    ///   - sleep: Waits a number of seconds between countdown ticks and between Slow photos.
    ///   - now: Reads the clock that times a burst's photos.
    init(
        sleep: @escaping @Sendable (Double) async throws -> Void,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        countdown = Countdown(clock: .stepped(by: sleep))
        self.sleep = sleep
        self.now = now
    }

    /// Whether the running burst should stop before its next photo: the person asked, or the
    /// shutter that holds it came up after its first photo.
    var isBurstStopRequested: Bool {
        guard let progress = burstProgress else { return false }
        if isStopRequestedByPerson { return true }
        return start == .held && !isShutterHeld && progress.taken >= 1
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

    /// Keeps the person's Burst Limit for the next burst; a running one keeps its count.
    ///
    /// - Parameter limit: The limit.
    func setBurstLimit(_ limit: BurstLimit) {
        burstLimit = limit
    }

    /// Chooses the burst speed for the session, unless a countdown or burst runs.
    ///
    /// - Parameter speed: The speed.
    func setBurstSpeed(_ speed: BurstSpeed) {
        guard !isBusy else { return }
        burstSpeed = speed
    }

    /// Whether Slow is offered on a lens: unless a burst at Fast on it measured under
    /// ``slowBurstMinimumFastRate`` in this session.
    ///
    /// - Parameter lensID: The lens, or `nil` before the camera is ready.
    /// - Returns: `false` only when Fast on that lens is known to be slower than the threshold.
    public func offersSlowBurst(on lensID: Lens.ID?) -> Bool {
        guard let lensID, let rate = measuredFastRates[lensID] else { return true }
        return rate >= Self.slowBurstMinimumFastRate
    }

    /// Keeps the rate a burst at Fast measured on a lens, for ``offersSlowBurst(on:)``.
    ///
    /// - Parameters:
    ///   - rate: The whole burst's photos a second.
    ///   - lensID: The lens it was taken with.
    func recordFastRate(_ rate: Double, on lensID: Lens.ID) {
        measuredFastRates[lensID] = rate
    }

    /// Sets who begins the next burst, which ``beginBurst()`` uses, and marks it as asked for
    /// until it begins or ``abandonPreparedBurst()`` says it won't. A stop asked for in between
    /// (``requestBurstStop()``) applies to it.
    ///
    /// - Parameters:
    ///   - start: Who begins it.
    ///   - limit: The photos a limited burst asks for, for its progress and result; `nil` for
    ///     the others.
    func prepareBurst(start: BurstStart, limit: Int? = nil) {
        self.start = start
        self.limit = limit
        isStopRequestedByPerson = false
        isBurstPrepared = true
    }

    /// Forgets a burst that was asked for and could not begin.
    func abandonPreparedBurst() {
        isBurstPrepared = false
        isStopRequestedByPerson = false
    }

    /// Marks a burst as started.
    func beginBurst() {
        isBurstPrepared = false
        lastBurst = nil
        firstPhotoTime = nil
        recentPhotoTimes = []
        burstProgress = BurstProgress(taken: 0, saved: 0, start: start, limit: limit)
    }

    /// Asks the running burst to stop after the frame being taken.
    func requestBurstStop() {
        guard burstProgress != nil || isBurstPrepared else { return }
        isStopRequestedByPerson = true
    }

    /// Counts a frame taken, at the clock's time now, and updates the running rate.
    func recordTaken() {
        guard let progress = burstProgress else { return }
        let time = now()
        if firstPhotoTime == nil { firstPhotoTime = time }
        recentPhotoTimes.append(time)
        if recentPhotoTimes.count > Self.rateWindow { recentPhotoTimes.removeFirst() }
        burstProgress = progress.with(
            taken: progress.taken + 1,
            rate: .some(Self.rate(photos: recentPhotoTimes.count, first: recentPhotoTimes.first, last: recentPhotoTimes.last)))
    }

    /// Counts a frame saved.
    func recordSaved() {
        burstProgress = burstProgress.map { $0.with(saved: $0.saved + 1) }
    }

    /// Marks the burst as taking no more photos: only the last ones are being saved.
    func beginSaving() {
        burstProgress = burstProgress.map { $0.with(isSaving: true) }
    }

    /// Marks the burst as ended.
    ///
    /// - Parameter end: Why it ended.
    func endBurst(_ end: BurstEnd) {
        let taken = burstProgress?.taken ?? 0
        let last = recentPhotoTimes.last
        let duration = firstPhotoTime.flatMap { first in last.map { $0 - first } } ?? .zero
        lastBurst = BurstResult(
            end: end, saved: burstProgress?.saved ?? 0, taken: taken, start: burstProgress?.start ?? start,
            duration: duration, rate: Self.rate(photos: taken, first: firstPhotoTime, last: last),
            limit: burstProgress?.limit ?? limit)
        burstProgress = nil
        isStopRequestedByPerson = false
    }

    /// Photos a second: the photos less one over the time from the first to the last, or `nil`
    /// under ``minimumPhotosForRate`` photos or without time between them.
    ///
    /// - Parameters:
    ///   - photos: The photos counted.
    ///   - first: The first one's time.
    ///   - last: The last one's time.
    /// - Returns: The rate, or `nil`.
    static func rate(photos: Int, first: ContinuousClock.Instant?, last: ContinuousClock.Instant?) -> Double? {
        guard photos >= minimumPhotosForRate, let first, let last else { return nil }
        let seconds = (last - first) / .seconds(1)
        guard seconds > 0 else { return nil }
        return Double(photos - 1) / seconds
    }
}
