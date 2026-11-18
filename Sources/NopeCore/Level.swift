import Foundation
import Observation

/// The direction of gravity in the device's own axes, in units of g, as Core Motion reports it
/// (`CMDeviceMotion.gravity`): x toward the right edge of the screen, y toward its top edge, and
/// z out of the screen toward the person. A device held upright in portrait reads about
/// (0, −1, 0); lying flat, screen up, about (0, 0, −1).
public struct GravityVector: Equatable, Sendable {
    /// Toward the right edge of the screen.
    public let x: Double

    /// Toward the top edge of the screen.
    public let y: Double

    /// Out of the screen, toward the person.
    public let z: Double

    /// Creates a vector.
    ///
    /// - Parameters:
    ///   - x: Toward the right edge of the screen, in g.
    ///   - y: Toward the top edge of the screen, in g.
    ///   - z: Out of the screen, in g.
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// What the level shows (issue #40).
public enum LevelState: Equatable, Sendable {
    /// The device is held up, facing the scene.
    ///
    /// - `rotationDegrees`: how far the device is turned clockwise from upright portrait, in
    ///   degrees, −180 to 180. The horizon bar is drawn turned the other way, so it stays on the
    ///   real horizon.
    /// - `tiltDegrees`: how far that is from the nearest upright or sideways position, −45 to 45;
    ///   positive is clockwise.
    /// - `isLevel`: whether the tilt is within the level tolerance.
    case horizon(rotationDegrees: Double, tiltDegrees: Double, isLevel: Bool)

    /// The device points straight down, for a flat-lay photo: a top-down level.
    ///
    /// - `pitchDegrees`: how far the top edge is raised (positive) or lowered, in degrees.
    /// - `rollDegrees`: how far the right edge is raised (positive) or lowered, in degrees.
    /// - `isLevel`: whether both are within the level tolerance.
    case flat(pitchDegrees: Double, rollDegrees: Double, isLevel: Bool)

    /// Whether the device is level.
    public var isLevel: Bool {
        switch self {
        case .horizon(_, _, let isLevel), .flat(_, _, let isLevel): isLevel
        }
    }
}

/// Turns gravity readings into what the level shows, with a little hysteresis so the level
/// state and its haptic don't flicker at the edge of the tolerance.
///
/// The tolerances are tool settings, chosen to match what a person can see on screen: a bar
/// within 1 degree of the horizon looks level on a phone screen.
public struct LevelTracker: Sendable {
    /// The largest tilt that becomes level, in degrees.
    public static let levelTolerance = 1.0

    /// The tilt that ends level once reached, in degrees, a little wider than
    /// ``levelTolerance``.
    public static let releaseTolerance = 1.5

    /// The angle from straight down within which the flat (top-down) level starts, in degrees.
    public static let flatEntryAngle = 25.0

    /// The angle from straight down beyond which the flat level ends, in degrees.
    public static let flatExitAngle = 35.0

    /// The last state, or `nil` before the first reading.
    public private(set) var state: LevelState?

    /// Creates a tracker with no reading yet.
    public init() {}

    /// Applies a gravity reading.
    ///
    /// - Parameter gravity: The reading.
    /// - Returns: The new state.
    @discardableResult
    public mutating func update(_ gravity: GravityVector) -> LevelState {
        let next = isFlat(gravity) ? flatState(gravity) : horizonState(gravity)
        state = next
        return next
    }

    /// Whether the device points down enough for the flat level, using the wider exit angle
    /// while the flat level is already shown.
    ///
    /// - Parameter gravity: The reading.
    private func isFlat(_ gravity: GravityVector) -> Bool {
        let magnitude = (gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z).squareRoot()
        guard magnitude > 0 else { return false }
        // The angle between gravity and the back of the device (−z): 0 when lying screen up.
        let fromDown = acos(min(max(-gravity.z / magnitude, -1), 1)) * 180 / .pi
        if case .flat = state { return fromDown < Self.flatExitAngle }
        return fromDown < Self.flatEntryAngle
    }

    /// The horizon level for a reading.
    ///
    /// - Parameter gravity: The reading.
    private func horizonState(_ gravity: GravityVector) -> LevelState {
        // Upright portrait reads (0, −1): turning the device clockwise by θ reads (sin θ, −cos θ).
        let rotation = atan2(gravity.x, -gravity.y) * 180 / .pi
        let tilt = rotation - 90 * (rotation / 90).rounded()
        return .horizon(rotationDegrees: rotation, tiltDegrees: tilt, isLevel: isWithinTolerance(abs(tilt)))
    }

    /// The flat level for a reading.
    ///
    /// - Parameter gravity: The reading.
    private func flatState(_ gravity: GravityVector) -> LevelState {
        // Raising the top edge tips gravity toward the bottom edge (−y); raising the right edge
        // tips it toward the left edge (−x).
        let pitch = asin(min(max(-gravity.y, -1), 1)) * 180 / .pi
        let roll = asin(min(max(-gravity.x, -1), 1)) * 180 / .pi
        return .flat(pitchDegrees: pitch, rollDegrees: roll, isLevel: isWithinTolerance(max(abs(pitch), abs(roll))))
    }

    /// Whether a tilt counts as level: within ``levelTolerance``, or within ``releaseTolerance``
    /// while already level.
    ///
    /// - Parameter tilt: The tilt's size, in degrees.
    private func isWithinTolerance(_ tilt: Double) -> Bool {
        tilt <= (state?.isLevel == true ? Self.releaseTolerance : Self.levelTolerance)
    }
}

/// Decides when the level gives its tap: the moment it becomes level, as the person moves the
/// device (docs/design/level-haptic.md, sections 2 and 4).
///
/// The rule is kept here, out of the interface, so it is tested to full coverage; an interface
/// only plays the tap (and says "Level" to VoiceOver) when ``update(_:at:isHeldBack:)`` answers
/// `true`.
///
/// - One tap each time the level goes from not level to level. None while it stays level, and
///   none on leaving it. Changing between the horizon and the top-down level while level
///   throughout is not a new entry.
/// - No tap for the first reading after the level appears, even if it is already level: the tap
///   marks a change the person made, not the level being switched on.
/// - At least ``minimumInterval`` between taps. An entry sooner than that is dropped, never
///   played late.
/// - No tap while taps are held back (``CameraModel/holdsBackLevelTap``, or a sheet over the
///   camera). An entry while held back is dropped too, so when the cause ends with the device
///   still level, nothing plays.
///
/// ```swift
/// if rule.update(level.state, at: .now, isHeldBack: model.holdsBackLevelTap) { taps += 1 }
/// ```
public struct LevelTapRule: Sendable {
    /// The shortest time between two taps: a steady hand near the edge of the tolerance can
    /// leave and re-enter level several times a second.
    public static let minimumInterval: Duration = .seconds(1)

    /// Whether the last reading was level, or `nil` before the first reading.
    private var wasLevel: Bool?

    /// When the last tap was played, or `nil` before the first.
    private var lastTap: ContinuousClock.Instant?

    /// Creates a rule with no reading yet.
    public init() {}

    /// Applies the level's state, and says whether to tap now.
    ///
    /// - Parameters:
    ///   - state: What the level shows, or `nil` when there are no readings (the level was
    ///     switched off or its readings ended). `nil` resets the rule, so the next reading counts
    ///     as the first.
    ///   - time: The time of the reading, from a monotonic clock.
    ///   - isHeldBack: Whether taps are held back now (a capture, a series, the camera not
    ///     running, a sheet over the camera, or the app not active).
    /// - Returns: `true` when the level has just become level and a tap is allowed.
    public mutating func update(_ state: LevelState?, at time: ContinuousClock.Instant, isHeldBack: Bool) -> Bool {
        guard let state else {
            wasLevel = nil
            lastTap = nil
            return false
        }
        let previous = wasLevel
        wasLevel = state.isLevel
        guard previous == false, state.isLevel, !isHeldBack else { return false }
        if let lastTap, time - lastTap < Self.minimumInterval { return false }
        lastTap = time
        return true
    }
}

extension CameraModel {
    /// Whether the level's tap is held back now (docs/design/level-haptic.md, section 4): while
    /// a photo is being taken (a bracket and a long exposure included), during a burst or a
    /// self-timer countdown, for the whole of an interval series (running or paused), while Astro
    /// or a focus bracket runs (paused included), and whenever the camera isn't running.
    ///
    /// The Taptic Engine moves the device, so a tap is kept away from exposures and series; with
    /// the camera not running there is no live picture to level. An interface also holds the tap
    /// back while a sheet covers the camera or the app isn't active, which the model can't see.
    public var holdsBackLevelTap: Bool {
        captureStatus == .capturing || drive.isBusy || manual.intervalProgress != nil || astro.isRunning
            || bracketing.isRunning || sessionStatus != .running
    }
}

/// Where the level's gravity readings come from: Core Motion on a device, a fixed reading in UI
/// tests. The app target supplies it; `NopeCore` doesn't import Core Motion.
///
/// Battery rule (AGENTS.md, "Battery"): motion updates run only while a stream from
/// ``gravityUpdates()`` is being read, that is while the level is shown, and stop when it ends.
public protocol GravitySource: Sendable {
    /// Starts motion updates and returns them as a stream. The updates stop when the stream is
    /// no longer read (its task is cancelled) or the stream ends.
    ///
    /// - Returns: Gravity readings, a few dozen a second at most. The stream ends at once on a
    ///   device without motion sensors.
    func gravityUpdates() -> AsyncStream<GravityVector>
}

/// The level shown over the viewfinder: reads a ``GravitySource`` while the level is shown and
/// publishes ``state``.
///
/// Privacy rule: the device's attitude is used on screen only. It is never written to a photo,
/// stored or logged (issue #40).
///
/// ```swift
/// .task { await level.run(source) }   // only while the level is shown
/// ```
@MainActor
@Observable
public final class LevelModel {
    /// What the level shows, or `nil` while there is no reading.
    public private(set) var state: LevelState?

    /// The tracker that turns readings into states.
    private var tracker = LevelTracker()

    /// Creates a model with no reading.
    public init() {}

    /// Applies the source's readings until its stream ends or the calling task is cancelled,
    /// then clears ``state``.
    ///
    /// - Parameter source: Where the readings come from.
    public func run(_ source: any GravitySource) async {
        for await gravity in source.gravityUpdates() {
            state = tracker.update(gravity)
        }
        tracker = LevelTracker()
        state = nil
    }
}
