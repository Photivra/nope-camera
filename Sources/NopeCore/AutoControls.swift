import Foundation

/// A request that works in full auto as well as with manual controls, wrapped in
/// ``CameraIntent/auto(_:)``: tap to focus and expose, the focus and exposure lock, exposure
/// compensation, the Close-Up and Far Focus limits, face detection, the fast shutter rule, the
/// close-up suggestion and the focus magnifier.
///
/// None of them changes a manual setting: while a control is set manually, the camera keeps the
/// person's value, and a tap only aims what is still automatic (issue #56, "Manual controls: up
/// to the person").
public enum AutoControlIntent: Equatable, Sendable {
    /// Aim autofocus and auto exposure at a point in the viewfinder (a tap). Autofocus keeps
    /// following that point until the scene changes, then returns to the center
    /// (`AVCaptureDevice.subjectAreaDidChangeNotification`). Clears a lock.
    ///
    /// - Parameter point: The point in the viewfinder, 0 to 1 across and down as drawn.
    case focusAndExpose(at: FramePoint)

    /// Focus and expose at a point once, then lock both (press and hold, or the lock button):
    /// AE/AF lock. The lock stays when the scene changes, until it is unlocked, another point is
    /// tapped, the lens changes, or All Auto.
    ///
    /// - Parameter point: The point in the viewfinder, or `nil` for the point already in use
    ///   (the center when there is none).
    case lockFocusAndExposure(at: FramePoint?)

    /// Return focus and exposure to continuous auto at the center, unlocking them.
    case unlockFocusAndExposure

    /// Set exposure compensation, in EV, moved inside the lens's range (the Exposure control
    /// in full auto). 0 is none.
    case setExposureCompensation(Double)

    /// Move exposure compensation a number of steps along its scale (VoiceOver's adjustable
    /// action and the − and + buttons send ±1).
    case stepExposureCompensation(by: Int)

    /// Limit autofocus to near subjects, or lift the limit (Close-Up). Turning it on lifts the
    /// far limit.
    case setNearFocusLimit(Bool)

    /// Limit autofocus to far subjects, or lift the limit (Far Focus, issue #57). Turning it on
    /// lifts the near limit.
    case setFarFocusLimit(Bool)

    /// Let faces the camera detects steer autofocus and auto exposure (the system's default), or
    /// stop them (issue #57). Applies only while focus or exposure is automatic.
    case setFollowsFaces(Bool)

    /// Choose how fast a shutter full auto prefers.
    case setFastShutter(FastShutter)

    /// Hide the suggestion to switch to the ultra wide lens until the lens changes.
    case dismissCloseUpSuggestion

    /// Show or hide the focus magnifier: an enlarged part of the viewfinder. Preview only: the
    /// photo and the camera's zoom don't change.
    case setMagnifier(Bool)
}

/// How fast a shutter full auto prefers (issue #56). The camera's auto exposure still chooses
/// the shutter and ISO; the app only sets the longest shutter it may use
/// (`AVCaptureDevice.activeMaxExposureDuration`), so it raises ISO instead of slowing the
/// shutter. Manual controls are never changed by it.
public enum FastShutter: String, CaseIterable, Codable, Sendable {
    /// At least 1/(2 × the lens's 35 mm-equivalent focal length), a common rule for a sharp
    /// handheld photo. The default.
    case handheld

    /// At least 1/500 s, to freeze people and pets in motion.
    case freezeMotion

    /// At least 1/1000 s, to freeze fast motion such as insects or sports.
    case freezeFastMotion

    /// The slowest shutter this choice allows on its own, in seconds, or `nil` for
    /// ``handheld``, which depends on the lens.
    public var slowestShutter: Double? {
        switch self {
        case .handheld: nil
        case .freezeMotion: 1.0 / 500.0
        case .freezeFastMotion: 1.0 / 1000.0
        }
    }
}

/// Where autofocus and auto exposure are aimed after a tap, and whether they are locked there.
public struct FocusTarget: Equatable, Sendable {
    /// The tapped point in the viewfinder, as drawn: where an interface draws the focus square.
    public let viewfinderPoint: FramePoint

    /// The same point in the camera's coordinates, as the hardware uses it.
    public let devicePoint: FramePoint

    /// Whether focus and exposure are locked at the point (AE/AF lock).
    public let isLocked: Bool

    /// Creates a target.
    ///
    /// - Parameters:
    ///   - viewfinderPoint: The tapped point in the viewfinder.
    ///   - devicePoint: The point in the camera's coordinates.
    ///   - isLocked: Whether focus and exposure are locked there.
    public init(viewfinderPoint: FramePoint, devicePoint: FramePoint, isLocked: Bool) {
        self.viewfinderPoint = viewfinderPoint
        self.devicePoint = devicePoint
        self.isLocked = isLocked
    }
}

/// The automatic aids ``DeviceControls/init(settings:lens:assist:)`` adds to the person's
/// settings: the tapped point, the near or far focus limit, face detection and the longest auto
/// exposure.
public struct AssistSettings: Equatable, Sendable {
    /// Where autofocus and auto exposure are aimed, or `nil` for the center.
    public var focusTarget: FocusTarget?

    /// Whether autofocus is limited to near subjects.
    public var nearFocusLimit: Bool

    /// The longest shutter auto exposure may use, in seconds, or `nil` for the camera's own
    /// default.
    public var longestShutter: Double?

    /// Whether autofocus is limited to far subjects. Never on with ``nearFocusLimit``.
    public var farFocusLimit: Bool

    /// Whether faces the camera detects steer autofocus and auto exposure. `true` by default, the
    /// system's own behavior (`AVCaptureDevice.isFaceDrivenAutoFocusEnabled`).
    public var followsFaces: Bool

    /// No aids: the camera's defaults.
    public static let none = AssistSettings()

    /// Creates aids. With no arguments, none.
    ///
    /// - Parameters:
    ///   - focusTarget: The tapped point, or `nil`.
    ///   - nearFocusLimit: Whether autofocus is limited to near subjects.
    ///   - longestShutter: The longest auto exposure in seconds, or `nil`.
    ///   - farFocusLimit: Whether autofocus is limited to far subjects. Ignored while
    ///     `nearFocusLimit` is on.
    ///   - followsFaces: Whether detected faces steer autofocus and auto exposure. Defaults to
    ///     `true`.
    public init(
        focusTarget: FocusTarget? = nil, nearFocusLimit: Bool = false, longestShutter: Double? = nil,
        farFocusLimit: Bool = false, followsFaces: Bool = true
    ) {
        self.focusTarget = focusTarget
        self.nearFocusLimit = nearFocusLimit
        self.longestShutter = longestShutter
        self.farFocusLimit = farFocusLimit && !nearFocusLimit
        self.followsFaces = followsFaces
    }
}

/// The fast shutter rule of full auto, and when to say "Hold it steady or use a tripod"
/// (issue #56).
///
/// Full auto lets the camera's auto exposure choose, but no slower than the shortest shutter
/// that still exposes well, from the shortest of: the ``FastShutter`` choice, and the handheld
/// rule. When even the handheld limit can't expose the scene at the lens's highest ISO, the
/// limit is lifted, so the photo is still exposed well, and the person is told to hold the
/// camera steady.
///
/// The brightness the scene needs is the product of ISO and exposure time corrected by the
/// meter's offset: `ISO × time × 2^(−offset)` (`AVCaptureDevice.exposureTargetOffset` is in EV,
/// negative when the picture is darker than the target). The product doesn't depend on how the
/// camera splits it between ISO and time, so it can be compared with what a limit allows:
/// `highest ISO × limit`. The aperture is fixed on every lens the app uses in full auto.
enum AutoShutter {
    /// How much brighter than needed a limit must be before a lifted limit comes back: half a
    /// stop, so the limit doesn't switch on and off when the light is near the threshold. A
    /// tool setting, chosen to be larger than the meter's frame-to-frame changes (an
    /// assumption, checked on the device: docs/TESTING.md).
    static let returnMargin = pow(2, -0.5)

    /// How much longer than full auto's limit a reading's shutter may be and still count as
    /// taken under that limit: a quarter stop. Auto exposure keeps the shutter within
    /// `AVCaptureDevice.activeMaxExposureDuration`, so a reading clearly longer than the limit
    /// was taken before the camera applied it (after a manual or astro exposure, or on the
    /// previous lens). The margin allows for a reported shutter rounded to the sensor's timing;
    /// its size is an assumption, checked on the device (docs/TESTING.md).
    static let predatesLimitMargin = pow(2, 0.25)

    /// Whether a full-auto reading was taken before the camera applied the limit in use, so it
    /// says nothing about the scene under that limit.
    ///
    /// - Parameters:
    ///   - reading: The reading.
    ///   - limit: The limit in use, in seconds, or `nil` when it is lifted.
    /// - Returns: `true` when the reading's shutter is longer than the limit by more than
    ///   ``predatesLimitMargin``; `false` when the limit is lifted.
    static func predatesLimit(_ reading: ExposureReading, limit: Double?) -> Bool {
        guard let limit else { return false }
        return reading.exposureDuration > limit * predatesLimitMargin
    }

    /// The handheld rule: 1/(2 × 35 mm-equivalent focal length) seconds, inside the lens's
    /// shutter range.
    ///
    /// - Parameter lens: The lens.
    /// - Returns: The slowest handheld-safe shutter in seconds, or `nil` when the lens reports
    ///   no focal length or no shutter range.
    static func handheldLimit(for lens: Lens) -> Double? {
        guard let focalLength = lens.equivalentFocalLength, focalLength > 0, let range = lens.exposureDurationRange
        else { return nil }
        return (1 / (2 * focalLength)).limited(to: range)
    }

    /// The limits full auto tries, shortest first: the fast shutter choice, then the handheld
    /// rule. Each is inside the lens's shutter range.
    ///
    /// - Parameters:
    ///   - lens: The lens.
    ///   - fastShutter: The person's choice.
    /// - Returns: The limits; empty when the lens reports no shutter range.
    static func limits(for lens: Lens, fastShutter: FastShutter) -> [Double] {
        guard let range = lens.exposureDurationRange else { return [] }
        let chosen = fastShutter.slowestShutter.map { $0.limited(to: range) }
        let handheld = handheldLimit(for: lens)
        return [chosen, handheld].compactMap(\.self).sorted().reduce(into: []) { limits, limit in
            if limits.last != limit { limits.append(limit) }
        }
    }

    /// The longest shutter full auto allows for a reading.
    ///
    /// - Parameters:
    ///   - reading: What the camera is using now.
    ///   - lens: The lens.
    ///   - fastShutter: The person's choice.
    ///   - current: The limit in use now, or `nil` when it is lifted.
    /// - Returns: The first limit the scene is bright enough for, or `nil` to lift the limit
    ///   (too dark, or a lens without an ISO range or shutter limits).
    static func longestShutter(
        for reading: ExposureReading, lens: Lens, fastShutter: FastShutter, current: Double?
    ) -> Double? {
        guard let highestISO = lens.isoRange?.upperBound else { return nil }
        let needed = reading.iso * reading.exposureDuration * pow(2, -reading.exposureOffset)
        return limits(for: lens, fastShutter: fastShutter).first { limit in
            // Coming back to a limit after it was lifted past it needs the margin.
            let wasLiftedPast = current.map { $0 > limit } ?? true
            return needed <= highestISO * limit * (wasLiftedPast ? returnMargin : 1)
        }
    }

    /// How many stops slower than the handheld rule a lens that reports stabilization
    /// (``Lens/reportsStabilization``) is taken to hold steady, for the steady hint: 2. A
    /// provisional value until device check S2 sets it (docs/TESTING.md; decision 12 of
    /// docs/design/device-feedback-1.0.md).
    static let stabilizationAllowance = 2.0

    /// The steady limit of a lens: the handheld rule moved by the lens's stabilization,
    /// `1/(2 × focal length) × 2^allowance`, inside the lens's shutter range. The allowance is
    /// ``stabilizationAllowance`` on a lens that reports stabilization and 0 on any other.
    ///
    /// - Parameter lens: The lens.
    /// - Returns: The slowest shutter in seconds the lens is taken to hold by hand, or `nil`
    ///   when the lens reports no focal length or no shutter range.
    static func steadyLimit(for lens: Lens) -> Double? {
        guard let focalLength = lens.equivalentFocalLength, focalLength > 0, let range = lens.exposureDurationRange
        else { return nil }
        let allowance = lens.reportsStabilization ? stabilizationAllowance : 0
        return (pow(2, allowance) / (2 * focalLength)).limited(to: range)
    }

    /// Whether "Hold it steady or use a tripod." shows after a reading in full auto, with a
    /// margin so it doesn't flicker (docs/design/device-feedback-1.0.md, section 4).
    ///
    /// - Parameters:
    ///   - duration: The shutter the camera is using, in seconds.
    ///   - limit: The lens's ``steadyLimit(for:)``.
    ///   - isShown: Whether the hint shows now.
    /// - Returns: `true` when the shutter is slower than the limit; `false` when it is at least
    ///   ``returnMargin`` (half a stop) faster; otherwise `isShown`, unchanged.
    static func showsSteadyHint(shutter duration: Double, limit: Double, isShown: Bool) -> Bool {
        if duration > limit { return true }
        if duration <= limit * returnMargin { return false }
        return isShown
    }
}

/// Notices when the subject seems closer than the lens can focus: autofocus searched, and the
/// lens then stays at, or keeps coming back to, its nearest position (issue #51, "Close-up
/// assist").
///
/// It only suggests the ultra wide lens; the app never switches lenses on its own. It judges by
/// time, not by a count of readings, because the readings come only when something changes
/// (``ExposureReading``; at most four a second). It allows for what autofocus does on a real
/// device: the search is often seen only while the lens moves into the near band, and autofocus
/// may search again for a moment once there.
///
/// Every threshold is an assumption until the device checks (docs/TESTING.md, "Close-up focus
/// aids", check C1): `lensPosition` is relative (0 is the nearest the lens can focus), not a
/// distance.
struct CloseUpDetector: Equatable, Sendable {
    /// How near the nearest position the lens must be, on the 0-to-1 relative scale.
    static let nearestPosition = 0.05

    /// How far back the detector looks: 2.5 seconds.
    static let window = Duration.milliseconds(2500)

    /// How much of ``window`` the lens must spend in the near band: 2 seconds, so a short search
    /// out of the band and back doesn't start the count again.
    static let requiredNearTime = Duration.seconds(2)

    /// How long a search counts after it was last seen: 4 seconds, enough for ``requiredNearTime``
    /// after a search seen on the way into the near band.
    static let searchMemory = Duration.seconds(4)

    /// One reading's time and whether the lens was in the near band.
    private struct Sample: Equatable, Sendable {
        /// When the reading arrived.
        let time: ContinuousClock.Instant

        /// Whether the lens was at its nearest position.
        let isNear: Bool
    }

    /// The readings in ``window``, and the last one before it, whose state holds at its start.
    private var samples: [Sample] = []

    /// When autofocus was last seen searching, or `nil`.
    private var lastSearch: ContinuousClock.Instant?

    /// Whether the detector reported a close subject at the last reading.
    private var isReporting = false

    /// Creates a detector with no readings.
    init() {}

    /// Records a reading.
    ///
    /// - Parameters:
    ///   - reading: The camera's reading.
    ///   - time: When it arrived.
    /// - Returns: Whether the subject seems too close: the lens was in the near band for
    ///   ``requiredNearTime`` of the last ``window``, and autofocus searched within
    ///   ``searchMemory`` when this began. Once reported, it stays reported while the lens keeps
    ///   to the near band that long.
    mutating func record(_ reading: ExposureReading, at time: ContinuousClock.Instant) -> Bool {
        if reading.isAdjustingFocus { lastSearch = time }
        samples.append(Sample(time: time, isNear: reading.lensPosition <= Self.nearestPosition))
        let start = time - Self.window
        if let firstInside = samples.firstIndex(where: { $0.time >= start }), firstInside > 1 {
            samples.removeFirst(firstInside - 1)
        }
        guard Self.nearTime(of: samples, from: start, to: time) >= Self.requiredNearTime else {
            isReporting = false
            return false
        }
        if !isReporting, let lastSearch, time - lastSearch <= Self.searchMemory { isReporting = true }
        return isReporting
    }

    /// How long the lens was in the near band between two times: each reading's state holds
    /// until the next one.
    ///
    /// - Parameters:
    ///   - samples: The readings, oldest first.
    ///   - start: The start of the span.
    ///   - end: The end of the span, the time of the last reading.
    /// - Returns: The time in the near band.
    private static func nearTime(of samples: [Sample], from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Duration {
        var total = Duration.zero
        for (index, sample) in samples.enumerated() where sample.isNear {
            let until = index + 1 < samples.count ? samples[index + 1].time : end
            let from = max(sample.time, start)
            if until > from { total += until - from }
        }
        return total
    }
}

extension FramePoint {
    /// The point in the unmagnified viewfinder under a point in the magnified one.
    ///
    /// The focus magnifier draws the viewfinder scaled around an anchor; a tap on it lands on
    /// `anchor + (point − anchor) / scale` of the real viewfinder.
    ///
    /// - Parameters:
    ///   - scale: The magnification, greater than 0.
    ///   - anchor: The point the magnifier is centered on.
    /// - Returns: The point in the unmagnified viewfinder.
    public func unmagnified(scale: Double, anchor: FramePoint) -> FramePoint {
        FramePoint(x: anchor.x + (x - anchor.x) / scale, y: anchor.y + (y - anchor.y) / scale)
    }
}
