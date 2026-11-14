import Foundation

/// A request that works in full auto as well as with manual controls, wrapped in
/// ``CameraIntent/auto(_:)``: tap to focus and expose, the focus and exposure lock, exposure
/// compensation, the Close-Up focus limit, the fast shutter rule, the close-up suggestion and
/// the focus magnifier.
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

    /// Limit autofocus to near subjects, or lift the limit (Close-Up).
    case setNearFocusLimit(Bool)

    /// Choose how fast a shutter full auto prefers.
    case setFastShutter(FastShutter)

    /// Hide the suggestion to switch to the ultra wide lens until the lens changes.
    case dismissCloseUpSuggestion

    /// Show or hide the focus magnifier: an enlarged part of the viewfinder. Preview only: the
    /// photo and the camera's zoom don't change.
    case setMagnifier(Bool)
}

/// How fast a shutter full auto prefers (issue #56). The camera's auto exposure still chooses
/// the shutter and ISO; nope. only sets the longest shutter it may use
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
/// settings: the tapped point, the near focus limit and the longest auto exposure.
public struct AssistSettings: Equatable, Sendable {
    /// Where autofocus and auto exposure are aimed, or `nil` for the center.
    public var focusTarget: FocusTarget?

    /// Whether autofocus is limited to near subjects.
    public var nearFocusLimit: Bool

    /// The longest shutter auto exposure may use, in seconds, or `nil` for the camera's own
    /// default.
    public var longestShutter: Double?

    /// No aids: the camera's defaults.
    public static let none = AssistSettings()

    /// Creates aids. With no arguments, none.
    ///
    /// - Parameters:
    ///   - focusTarget: The tapped point, or `nil`.
    ///   - nearFocusLimit: Whether autofocus is limited to near subjects.
    ///   - longestShutter: The longest auto exposure in seconds, or `nil`.
    public init(focusTarget: FocusTarget? = nil, nearFocusLimit: Bool = false, longestShutter: Double? = nil) {
        self.focusTarget = focusTarget
        self.nearFocusLimit = nearFocusLimit
        self.longestShutter = longestShutter
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
/// `highest ISO × limit`. The aperture is fixed on every lens nope. uses in full auto.
enum AutoShutter {
    /// How much brighter than needed a limit must be before a lifted limit comes back: half a
    /// stop, so the limit doesn't switch on and off when the light is near the threshold. A
    /// tool setting, chosen to be larger than the meter's frame-to-frame changes (an
    /// assumption, checked on the device: docs/TESTING.md).
    static let returnMargin = pow(2, -0.5)

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

    /// Whether a shutter is slow enough to risk blur from hand shake, for the hint in manual
    /// controls.
    ///
    /// - Parameters:
    ///   - duration: The shutter in use or chosen, in seconds.
    ///   - lens: The lens.
    /// - Returns: `true` when it is longer than ``handheldLimit(for:)``; `false` without a limit.
    static func risksBlur(_ duration: Double, on lens: Lens) -> Bool {
        guard let limit = handheldLimit(for: lens) else { return false }
        return duration > limit
    }
}

/// Notices when the subject seems closer than the lens can focus: the lens stays at its nearest
/// position while autofocus keeps searching (issue #51, "Close-up assist").
///
/// It only suggests the ultra wide lens; nope. never switches lenses on its own. The thresholds
/// are assumptions to check on the device (docs/TESTING.md, "Close-up focus aids"):
/// `lensPosition` is relative (0 is the nearest the lens can focus), not a distance.
struct CloseUpDetector: Equatable, Sendable {
    /// How near the nearest position the lens must be, on the 0-to-1 relative scale.
    static let nearestPosition = 0.05

    /// How many readings in a row must find the lens there: two seconds at four readings a
    /// second (``ExposureReading`` rate).
    static let requiredReadings = 8

    /// Readings in a row with the lens at its nearest position.
    private var readingsAtNearest = 0

    /// Whether autofocus searched during that run.
    private var searched = false

    /// Creates a detector with no readings.
    init() {}

    /// Records a reading.
    ///
    /// - Parameter reading: The camera's reading.
    /// - Returns: Whether the subject seems too close: the lens stayed at its nearest position
    ///   for ``requiredReadings`` readings in a row, and autofocus searched during them.
    mutating func record(_ reading: ExposureReading) -> Bool {
        guard reading.lensPosition <= Self.nearestPosition else {
            self = CloseUpDetector()
            return false
        }
        readingsAtNearest += 1
        searched = searched || reading.isAdjustingFocus
        return searched && readingsAtNearest >= Self.requiredReadings
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
