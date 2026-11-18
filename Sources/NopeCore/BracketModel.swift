import Foundation
import Observation

/// The order in which a focus bracket's frames are taken (docs/design/BRACKETING.md, section 5).
public enum FocusBracketOrder: String, CaseIterable, Codable, Hashable, Sendable {
    /// From the nearest focus position to the farthest. The default.
    case nearestFirst

    /// From the farthest focus position to the nearest.
    case farthestFirst
}

/// The settings of a focus bracket: a series of separate single-frame photos, each at the next
/// focus position, for stacking in other software (docs/design/BRACKETING.md, section 5).
///
/// Positions are on the lens's own relative scale (`AVCaptureDevice.lensPosition`): 0 is the
/// closest the lens focuses and 1 the farthest. Apple documents that a position "does not
/// correspond to an exact physical distance", so the app never turns one into a distance.
public struct FocusBracketSettings: Codable, Equatable, Hashable, Sendable {
    /// The frame counts the app offers. 50 is the most one burst takes
    /// (``DriveModel/maximumBurstFrames``; decision 12).
    public static let frameCounts = [3, 5, 7, 10, 12, 15, 20, 30, 40, 50]

    /// The frame count a focus bracket starts with.
    public static let defaultFrameCount = 10

    /// The focus bracket an interface offers first: the whole range, 10 frames, nearest first,
    /// focus returned when done.
    public static let standard = FocusBracketSettings(
        nearest: 0, farthest: 1, frameCount: defaultFrameCount, order: .nearestFirst, returnsFocus: true)

    /// The nearest focus position, from 0 to 1, never above ``farthest``.
    public let nearest: Double

    /// The farthest focus position, from 0 to 1, never below ``nearest``.
    public let farthest: Double

    /// The number of frames, one of ``frameCounts``.
    public let frameCount: Int

    /// The order of the frames.
    public let order: FocusBracketOrder

    /// Whether the focus returns to what it was before the bracket (automatic focus, or the
    /// position set by hand) when the bracket ends. Otherwise it stays at the last frame's.
    public let returnsFocus: Bool

    /// Creates focus bracket settings. Each position is moved into 0…1; a nearest position
    /// beyond the farthest swaps the two (docs/design/BRACKETING.md, section 5); a frame count
    /// that isn't offered becomes the nearest one that is.
    ///
    /// - Parameters:
    ///   - nearest: The nearest focus position, from 0 to 1.
    ///   - farthest: The farthest focus position, from 0 to 1.
    ///   - frameCount: The number of frames.
    ///   - order: The order of the frames.
    ///   - returnsFocus: Whether the focus returns to what it was when the bracket ends.
    public init(
        nearest: Double, farthest: Double, frameCount: Int, order: FocusBracketOrder = .nearestFirst,
        returnsFocus: Bool = true
    ) {
        let first = nearest.limited(to: 0...1)
        let second = farthest.limited(to: 0...1)
        self.nearest = Swift.min(first, second)
        self.farthest = Swift.max(first, second)
        self.frameCount = Self.offeredFrameCount(nearestTo: frameCount)
        self.order = order
        self.returnsFocus = returnsFocus
    }

    /// The offered frame count nearest to a number; the smaller of two equally near.
    ///
    /// - Parameter count: Any number of frames.
    /// - Returns: One of ``frameCounts``.
    public static func offeredFrameCount(nearestTo count: Int) -> Int {
        frameCounts.min { abs($0 - count) < abs($1 - count) } ?? defaultFrameCount
    }

    /// The step between neighboring frames on the lens's scale:
    /// (farthest − nearest) ÷ (frames − 1).
    public var step: Double {
        (farthest - nearest) / Double(frameCount - 1)
    }

    /// Whether the settings span the whole range, 0 to 1.
    public var isWholeRange: Bool {
        nearest == 0 && farthest == 1
    }

    /// Each frame's lens position, evenly spaced from ``nearest`` to ``farthest``, in the order
    /// taken. The last position is exactly the end, with no rounding error.
    public var positions: [Double] {
        let nearestFirst = (0..<frameCount).map { index in
            index == frameCount - 1 ? farthest : nearest + Double(index) * step
        }
        return order == .nearestFirst ? nearestFirst : nearestFirst.reversed()
    }

    /// A copy with other values.
    ///
    /// - Parameters:
    ///   - nearest: The nearest position, or `nil` to keep it.
    ///   - farthest: The farthest position, or `nil` to keep it.
    ///   - frameCount: The number of frames, or `nil` to keep it.
    ///   - order: The order, or `nil` to keep it.
    ///   - returnsFocus: Whether focus returns when done, or `nil` to keep it.
    /// - Returns: The new settings.
    public func with(
        nearest: Double? = nil, farthest: Double? = nil, frameCount: Int? = nil, order: FocusBracketOrder? = nil,
        returnsFocus: Bool? = nil
    ) -> FocusBracketSettings {
        FocusBracketSettings(
            nearest: nearest ?? self.nearest, farthest: farthest ?? self.farthest,
            frameCount: frameCount ?? self.frameCount, order: order ?? self.order,
            returnsFocus: returnsFocus ?? self.returnsFocus)
    }

    /// Whether a lens can take a focus bracket: its focus can be locked at a lens position
    /// (`AVCaptureDevice.isLockingFocusWithCustomLensPositionSupported`).
    ///
    /// - Parameter lens: A lens.
    /// - Returns: `true` when the lens supports manual focus.
    public static func isAvailable(on lens: Lens) -> Bool {
        lens.manualControls.supportsManualFocus
    }
}

/// A saved photo's place in a focus bracket (``BracketPlace/focus``): the position planned for
/// it and the one the lens reported when the photo was taken.
///
/// Privacy: session values, in memory only; no file holds them.
public struct FocusFramePlace: Equatable, Sendable {
    /// How far, on the lens's 0 to 1 scale, the reported position may differ from the planned
    /// one and still count as at its plan: 0.02. An assumption until the device check D6
    /// (docs/design/BRACKETING.md, section 9) measures how closely a lens reaches a position.
    public static let tolerance = 0.02

    /// The frame's place in the order taken, from 1.
    public let number: Int

    /// The lens position the app asked for.
    public let plannedPosition: Double

    /// The lens position the lens reported after the move.
    public let reportedPosition: Double

    /// Every frame's planned position, in the order taken.
    public let positions: [Double]

    /// The order of the frames.
    public let order: FocusBracketOrder

    /// Creates a place.
    ///
    /// - Parameters:
    ///   - number: The frame's place in the order, from 1.
    ///   - plannedPosition: The position asked for.
    ///   - reportedPosition: The position the lens reported.
    ///   - positions: Every frame's planned position, in the order taken.
    ///   - order: The order of the frames.
    public init(
        number: Int, plannedPosition: Double, reportedPosition: Double, positions: [Double], order: FocusBracketOrder
    ) {
        self.number = number
        self.plannedPosition = plannedPosition
        self.reportedPosition = reportedPosition
        self.positions = positions
        self.order = order
    }

    /// Whether the lens reported a position further from the plan than ``tolerance``. The frame
    /// is still saved (decision 14); an interface shows both values.
    public var isOffPlan: Bool {
        abs(reportedPosition - plannedPosition) > Self.tolerance
    }
}

/// How far a focus bracket has got (``BracketModel/progress``).
public struct FocusBracketProgress: Equatable, Sendable {
    /// The frames taken so far.
    public let taken: Int

    /// The frames saved so far.
    public let saved: Int

    /// The frames in the bracket.
    public let total: Int

    /// The lens position the lens last reported, or `nil` before the first move.
    public let position: Double?

    /// Whether the series is paused: the app left the foreground, or the camera is paused.
    public let isPaused: Bool

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The frames taken.
    ///   - saved: The frames saved.
    ///   - total: The frames in the bracket.
    ///   - position: The last reported position, or `nil`.
    ///   - isPaused: Whether the series is paused.
    public init(taken: Int, saved: Int, total: Int, position: Double? = nil, isPaused: Bool = false) {
        self.taken = taken
        self.saved = saved
        self.total = total
        self.position = position
        self.isPaused = isPaused
    }

    /// The number of the frame being taken now (or next, while paused), from 1, never more than
    /// ``total``.
    public var frameNumber: Int {
        Swift.min(taken + 1, total)
    }

    /// A copy with other values.
    func with(taken: Int? = nil, saved: Int? = nil, position: Double? = nil, isPaused: Bool? = nil) -> FocusBracketProgress {
        FocusBracketProgress(
            taken: taken ?? self.taken, saved: saved ?? self.saved, total: total, position: position ?? self.position,
            isPaused: isPaused ?? self.isPaused)
    }
}

/// Where the focus is after a focus bracket.
public enum FocusAfterBracket: Equatable, Sendable {
    /// Back to automatic focus.
    case automatic

    /// Back to the position set by hand before the bracket.
    case returned(Double)

    /// It stays at the last frame's position (Return Focus When Done off).
    case stays(Double)
}

/// How the last focus bracket ended (``BracketModel/lastRun``).
public struct FocusBracketResult: Equatable, Sendable {
    /// Why it ended: ``BurstEnd/limitReached`` when every frame was taken.
    public let end: BurstEnd

    /// The photos saved.
    public let saved: Int

    /// The frames in the bracket.
    public let total: Int

    /// The frames whose reported focus was more than ``FocusFramePlace/tolerance`` from the plan.
    public let offPlan: Int

    /// Where the focus is now.
    public let focusAfter: FocusAfterBracket

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - end: Why it ended.
    ///   - saved: The photos saved.
    ///   - total: The frames in the bracket.
    ///   - offPlan: The frames not at their planned focus.
    ///   - focusAfter: Where the focus is now.
    public init(end: BurstEnd, saved: Int, total: Int, offPlan: Int, focusAfter: FocusAfterBracket) {
        self.end = end
        self.saved = saved
        self.total = total
        self.offPlan = offPlan
        self.focusAfter = focusAfter
    }

    /// Whether every frame was taken and saved.
    public var isFinished: Bool {
        end == .limitReached && saved == total
    }
}

/// An end of the focus range (docs/design/BRACKETING.md, section 5, "Setting the range on the
/// picture").
public enum FocusRangeEnd: Equatable, Sendable {
    /// Nearest Focus.
    case nearest

    /// Farthest Focus.
    case farthest
}

/// An end of the focus range being set on the picture (``BracketModel/rangeEditing``).
public struct FocusRangeEditing: Equatable, Sendable {
    /// Which end is being set.
    public let end: FocusRangeEnd

    /// The position chosen with the slider or the buttons, from 0 to 1.
    public let value: Double

    /// Whether a tap on the picture focused there, so the value follows the lens's reported
    /// position (``CameraModel/focusRangeValue``).
    public let followsLens: Bool

    /// Creates the state.
    ///
    /// - Parameters:
    ///   - end: Which end is being set.
    ///   - value: The chosen position.
    ///   - followsLens: Whether the value follows the lens.
    public init(end: FocusRangeEnd, value: Double, followsLens: Bool = false) {
        self.end = end
        self.value = value
        self.followsLens = followsLens
    }
}

/// A request about bracketing, sent as ``CameraIntent/bracket(_:)``.
public enum BracketIntent: Equatable, Sendable {
    /// Turn Bracket on with the session's type (``BracketModel/type``), or off. On a lens that
    /// can take only one type, that type is turned on.
    case setOn(Bool)

    /// Choose the type. With Bracket on, the other type is turned off and this one on. Focus is
    /// ignored on a lens whose focus can't be set, Exposure on one that can't take an exposure
    /// bracket.
    case setType(BracketType)

    /// Choose the focus bracket's settings. Ignored while it runs.
    case setFocus(FocusBracketSettings)

    /// Choose the focus bracket's start delay, or `nil` for none. Ignored while it runs.
    case setFocusStartDelay(SelfTimerDelay?)

    /// Set the focus range back to the whole range, 0 to 1.
    case useWholeRange

    /// Start setting an end of the focus range on the picture: the lens moves to that end's
    /// position, and the camera's automatic controls hold until the setting ends.
    case beginSettingRange(FocusRangeEnd)

    /// Move the lens to a position while setting an end of the range, from 0 to 1, rounded to
    /// hundredths.
    case setRangeValue(Double)

    /// Focus once at a point of the picture while setting an end of the range; the value then
    /// follows the lens.
    case focusRange(at: FramePoint)

    /// End setting the range: `true` keeps the value as that end (Set), `false` leaves the range
    /// as it was (Cancel). Focus returns to what it was before.
    case finishSettingRange(keeps: Bool)

    /// Stop a running focus bracket after the current frame, or its countdown.
    case stop
}

/// Bracketing beyond the exposure bracket that ``ManualControlsModel/bracket`` holds: the chosen
/// type, the focus bracket's settings and its progress (docs/design/BRACKETING.md, section 8).
///
/// ``CameraModel`` owns one as ``CameraModel/bracketing``; an interface reads it and sends
/// ``BracketIntent`` values. Nothing here is stored between launches, except through a preset.
@MainActor
@Observable
public final class BracketModel {
    /// The type Bracket turns on, and the type Bracket Settings shows. Exposure at first.
    public private(set) var type = BracketType.exposure

    /// The focus bracket's settings, for the session.
    public private(set) var focus = FocusBracketSettings.standard

    /// The focus bracket's start delay, or `nil` for none. 3 seconds at first (decision 7).
    public private(set) var focusStartDelay: SelfTimerDelay? = .threeSeconds

    /// Whether the focus bracket is on: a press of the shutter takes it.
    public private(set) var isFocusOn = false

    /// The running focus bracket, or `nil`. The countdown before it is ``DriveModel/countdown``.
    public private(set) var progress: FocusBracketProgress?

    /// The settings of the running focus bracket, or `nil` when none runs. They may differ from
    /// ``focus``: Take Bracket can ask for other frames or the whole range.
    public private(set) var running: FocusBracketSettings?

    /// How the last focus bracket ended, or `nil`. Cleared when the next one starts.
    public private(set) var lastRun: FocusBracketResult?

    /// The end of the focus range being set on the picture, or `nil`.
    public private(set) var rangeEditing: FocusRangeEditing?

    /// Whether the person asked the running bracket to stop.
    private(set) var isStopRequested = false

    /// Creates the model: Exposure, the standard focus bracket, off.
    init() {}

    /// Whether a focus bracket is running (or paused).
    public var isRunning: Bool {
        progress != nil
    }

    /// Records the type.
    ///
    /// - Parameter type: The type.
    func setType(_ type: BracketType) {
        self.type = type
    }

    /// Records the focus settings.
    ///
    /// - Parameter settings: The settings.
    func setFocus(_ settings: FocusBracketSettings) {
        focus = settings
    }

    /// Records the start delay.
    ///
    /// - Parameter delay: The delay, or `nil`.
    func setFocusStartDelay(_ delay: SelfTimerDelay?) {
        focusStartDelay = delay
    }

    /// Records the focus bracket as on or off.
    ///
    /// - Parameter isOn: Whether it is on.
    func setFocusOn(_ isOn: Bool) {
        isFocusOn = isOn
    }

    /// Records the range being set, or `nil`.
    ///
    /// - Parameter editing: The state.
    func setRangeEditing(_ editing: FocusRangeEditing?) {
        rangeEditing = editing
    }

    /// Marks a run as started.
    ///
    /// - Parameter settings: The bracket being taken.
    func beginRun(_ settings: FocusBracketSettings) {
        isStopRequested = false
        lastRun = nil
        running = settings
        progress = FocusBracketProgress(taken: 0, saved: 0, total: settings.frameCount)
    }

    /// Asks the running bracket to stop after the current frame.
    func requestStop() {
        isStopRequested = true
    }

    /// Records the position the lens reported for the frame being taken.
    ///
    /// - Parameter position: The reported position.
    func recordPosition(_ position: Double) {
        progress = progress?.with(position: position)
    }

    /// Counts a frame taken.
    func recordTaken() {
        progress = progress.map { $0.with(taken: $0.taken + 1) }
    }

    /// Counts a frame saved.
    func recordSaved() {
        progress = progress.map { $0.with(saved: $0.saved + 1) }
    }

    /// Records the series as paused or not.
    ///
    /// - Parameter isPaused: Whether it is paused.
    func setPaused(_ isPaused: Bool) {
        progress = progress?.with(isPaused: isPaused)
    }

    /// Marks the run as ended.
    ///
    /// - Parameter result: How it ended.
    func endRun(_ result: FocusBracketResult) {
        lastRun = result
        progress = nil
        running = nil
        isStopRequested = false
    }
}
