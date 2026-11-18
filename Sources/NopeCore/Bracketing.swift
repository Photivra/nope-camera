import Foundation

/// Exposure bracketing: several photos at different exposures from one press of the shutter.
///
/// Every frame is a separate single-frame photo; nothing is merged (AGENTS.md, "Honesty"). The
/// frames are taken with the system's manual exposure bracket
/// (`AVCapturePhotoBracketSettings` with `AVCaptureManualExposureBracketedStillImageSettings`),
/// so each frame's ISO and shutter are set exactly.
public struct BracketSettings: Equatable, Hashable, Sendable {
    /// The frame counts the app offers: 3, 5 or 7, each up to the lens's
    /// ``Lens/maxBracketedPhotoCount``.
    public static let frameCounts = [3, 5, 7]

    /// The steps between frames the app offers, in EV: 1/3, 2/3, 1 and 2 stops.
    public static let steps: [Double] = [1.0 / 3.0, 2.0 / 3.0, 1, 2]

    /// The bracket an interface offers first: 3 frames, 1 EV apart, darkest first
    /// (docs/design/BRACKETING.md, section 4).
    public static let standard = BracketSettings(frameCount: 3, step: 1)

    /// The number of frames.
    public let frameCount: Int

    /// The exposure difference between neighboring frames, in EV.
    public let step: Double

    /// The order the frames are taken and saved in. ``BracketOrder/darkestFirst`` by default,
    /// the order of every earlier version.
    public let order: BracketOrder

    /// Creates bracket settings.
    ///
    /// - Parameters:
    ///   - frameCount: The number of frames, one of ``frameCounts``.
    ///   - step: The difference between neighboring frames in EV, one of ``steps``.
    ///   - order: The order of the frames.
    public init(frameCount: Int, step: Double, order: BracketOrder = .darkestFirst) {
        self.frameCount = frameCount
        self.step = step
        self.order = order
    }

    /// Each frame's exposure relative to the metered one, in EV, centered on 0, in the order the
    /// frames are taken (``order``): for 3 frames 1 EV apart, −1, 0, +1 darkest first; 0, −1, +1
    /// metered first; +1, 0, −1 brightest first.
    public var offsets: [Double] {
        let half = Double(frameCount - 1) / 2
        let darkestFirst = (0..<frameCount).map { (Double($0) - half) * step }
        return order.arranged(darkestFirst)
    }

    /// A copy with another value.
    ///
    /// - Parameters:
    ///   - frameCount: The number of frames, or `nil` to keep it.
    ///   - step: The step in EV, or `nil` to keep it.
    ///   - order: The order, or `nil` to keep it.
    /// - Returns: The new settings.
    public func with(frameCount: Int? = nil, step: Double? = nil, order: BracketOrder? = nil) -> BracketSettings {
        BracketSettings(frameCount: frameCount ?? self.frameCount, step: step ?? self.step, order: order ?? self.order)
    }

    /// The frame counts a lens can take.
    ///
    /// - Parameter lens: The lens.
    /// - Returns: The members of ``frameCounts`` up to the lens's limit; empty when it can't
    ///   bracket.
    public static func frameCounts(for lens: Lens) -> [Int] {
        frameCounts.filter { $0 <= lens.maxBracketedPhotoCount }
    }
}

/// The order in which a bracket's frames are taken and saved (docs/design/BRACKETING.md,
/// section 4). The system takes the frames in the order of the request's array
/// (`AVCapturePhotoBracketSettings`), so an order is only the order of the frames asked for.
public enum BracketOrder: String, CaseIterable, Codable, Hashable, Sendable {
    /// From the darkest frame to the brightest: −1, 0, +1. The order of every earlier version.
    case darkestFirst

    /// The metered frame first, then outward, darker before brighter: 0, −1, +1, −2, +2.
    case meteredFirst

    /// From the brightest frame to the darkest: +1, 0, −1.
    case brightestFirst

    /// Puts offsets listed darkest first into this order.
    ///
    /// - Parameter darkestFirst: The offsets in EV, from the darkest to the brightest.
    /// - Returns: The same offsets in this order.
    func arranged(_ darkestFirst: [Double]) -> [Double] {
        switch self {
        case .darkestFirst:
            darkestFirst
        case .brightestFirst:
            darkestFirst.reversed()
        case .meteredFirst:
            // Stable: equally distant offsets keep their darkest-first order, darker first.
            darkestFirst.enumerated()
                .sorted { (abs($0.element), $0.offset) < (abs($1.element), $1.offset) }
                .map(\.element)
        }
    }
}

/// The kind of a bracket. Release 1.0.0 takes exposure brackets only; the type is named on the
/// card and in a photo's details so that nothing changes when another kind arrives
/// (docs/design/BRACKETING.md, decision 5).
public enum BracketType: String, Equatable, Hashable, Sendable {
    /// Frames at different exposures.
    case exposure
}

/// One frame of a bracket, with the exact exposure the camera is asked for.
public struct BracketFrame: Equatable, Sendable {
    /// The ISO.
    public let iso: Double

    /// The exposure duration, in seconds.
    public let exposureDuration: Double

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - iso: The ISO.
    ///   - exposureDuration: The exposure duration, in seconds.
    public init(iso: Double, exposureDuration: Double) {
        self.iso = iso
        self.exposureDuration = exposureDuration
    }

    /// Plans the frames of a bracket around a base exposure, within the lens's ranges.
    ///
    /// Each frame changes the exposure by its offset: first by changing the parameter the person
    /// didn't set (the shutter when ISO is set, otherwise ISO when the shutter is set, otherwise
    /// the shutter), then by the other parameter for whatever the first can't reach. A frame
    /// beyond both limits gets the nearest exposure the lens can give.
    ///
    /// - Parameters:
    ///   - offsets: Each frame's offset in EV (``BracketSettings/offsets``).
    ///   - base: The base ISO and exposure duration.
    ///   - shutterFirst: Whether to change the shutter before ISO.
    ///   - isoRange: The lens's ISO range.
    ///   - durationRange: The lens's exposure duration range, in seconds.
    /// - Returns: One frame per offset, in the same order.
    public static func plan(
        offsets: [Double], base: BracketFrame, shutterFirst: Bool, isoRange: ClosedRange<Double>,
        durationRange: ClosedRange<Double>
    ) -> [BracketFrame] {
        offsets.map { offset in
            let factor = pow(2, offset)
            if shutterFirst {
                let duration = (base.exposureDuration * factor).limited(to: durationRange)
                let remaining = factor * base.exposureDuration / duration
                return BracketFrame(iso: (base.iso * remaining).limited(to: isoRange), exposureDuration: duration)
            }
            let iso = (base.iso * factor).limited(to: isoRange)
            let remaining = factor * base.iso / iso
            return BracketFrame(
                iso: iso, exposureDuration: (base.exposureDuration * remaining).limited(to: durationRange))
        }
    }
}

/// One frame of a planned bracket as an interface lists it (docs/design/BRACKETING.md,
/// section 4, "The Frames"): its number, the offset asked for, the offset the lens can really
/// give, and the exposure the camera is asked for.
///
/// A frame beyond the lens's ISO and shutter ranges gets the nearest exposure the lens can give
/// (``BracketFrame/plan(offsets:base:shutterFirst:isoRange:durationRange:)``); ``isLimited`` marks
/// it so an interface can say so before the photo is taken.
public struct BracketFramePlan: Equatable, Sendable {
    /// Which way a limited frame falls short.
    public enum Limit: Equatable, Sendable {
        /// The lens can't make the frame as bright as asked.
        case brightest

        /// The lens can't make the frame as dark as asked.
        case darkest
    }

    /// How far, in EV, the offset reached may differ from the one asked for and still count as
    /// reached: the planning multiplies and clamps floating-point values, so a reached frame can
    /// differ by a rounding error. A hundredth of a stop is far below any step the app offers
    /// (the smallest is 1/3 EV).
    static let tolerance = 0.01

    /// The frame's place in the order it is taken, counted from 1.
    public let number: Int

    /// The offset asked for, in EV, relative to the base exposure.
    public let requestedOffset: Double

    /// The offset the frame really has, in EV, within the lens's ranges.
    public let offset: Double

    /// The ISO and exposure duration the camera is asked for.
    public let frame: BracketFrame

    /// For a limited frame, the number of the first frame (in the order taken) with the same
    /// exposure: the lens can't go brighter (or darker) than that frame. `nil` when the frame is
    /// not limited.
    public let limitingFrameNumber: Int?

    /// Creates a frame plan.
    ///
    /// - Parameters:
    ///   - number: The frame's place in the order, from 1.
    ///   - requestedOffset: The offset asked for, in EV.
    ///   - offset: The offset reached, in EV.
    ///   - frame: The exposure asked for.
    ///   - limitingFrameNumber: The first frame with the same exposure, for a limited frame.
    public init(number: Int, requestedOffset: Double, offset: Double, frame: BracketFrame, limitingFrameNumber: Int?) {
        self.number = number
        self.requestedOffset = requestedOffset
        self.offset = offset
        self.frame = frame
        self.limitingFrameNumber = limitingFrameNumber
    }

    /// Whether the lens can't give the offset asked for.
    public var isLimited: Bool {
        abs(offset - requestedOffset) > Self.tolerance
    }

    /// Which way the frame falls short, or `nil` when it isn't limited.
    public var limit: Limit? {
        guard isLimited else { return nil }
        return requestedOffset > offset ? .brightest : .darkest
    }

    /// Plans every frame of a bracket around a base exposure, within the lens's ranges, and
    /// marks the frames the lens can't give.
    ///
    /// - Parameters:
    ///   - offsets: Each frame's offset in EV, in the order taken (``BracketSettings/offsets``).
    ///   - base: The base ISO and exposure duration.
    ///   - shutterFirst: Whether to change the shutter before ISO.
    ///   - isoRange: The lens's ISO range.
    ///   - durationRange: The lens's exposure duration range, in seconds.
    /// - Returns: One plan per offset, in the same order.
    public static func plan(
        offsets: [Double], base: BracketFrame, shutterFirst: Bool, isoRange: ClosedRange<Double>,
        durationRange: ClosedRange<Double>
    ) -> [BracketFramePlan] {
        let frames = BracketFrame.plan(
            offsets: offsets, base: base, shutterFirst: shutterFirst, isoRange: isoRange, durationRange: durationRange)
        let baseExposure = base.iso * base.exposureDuration
        let reached = frames.map { log2($0.iso * $0.exposureDuration / baseExposure) }
        return zip(offsets, zip(frames, reached)).enumerated().map { index, values in
            let (requested, (frame, offset)) = values
            let isLimited = abs(offset - requested) > tolerance
            // The first frame with this exposure; a frame that is the first one names itself.
            let first = reached.prefix(index).firstIndex { abs($0 - offset) <= tolerance } ?? index
            return BracketFramePlan(
                number: index + 1, requestedOffset: requested, offset: offset, frame: frame,
                limitingFrameNumber: isLimited ? first + 1 : nil)
        }
    }
}

/// How far an exposure bracket has got while it is taken and saved
/// (``CameraModel/bracketProgress``).
public struct BracketProgress: Equatable, Sendable {
    /// The frames the camera has returned. The system takes all frames in one request, so this is
    /// 0 while the request runs and ``total`` once it returns.
    public let taken: Int

    /// The frames saved to Photos so far.
    public let saved: Int

    /// The frames in the bracket.
    public let total: Int

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The frames taken.
    ///   - saved: The frames saved.
    ///   - total: The frames in the bracket.
    public init(taken: Int, saved: Int, total: Int) {
        self.taken = taken
        self.saved = saved
        self.total = total
    }

    /// Whether the frames are still being taken (the request hasn't returned).
    public var isTaking: Bool {
        taken < total
    }
}

/// A saved photo's place in its bracket (``SavedPhoto/bracket``), for the Last Photo viewer and
/// "What's in This Photo" (docs/design/BRACKETING.md, section 4, "The result").
///
/// Privacy: these are the session's values, held in memory with the saved photo until the app
/// closes. They are never written to a file, so the metadata allowlist doesn't change.
public struct BracketPlace: Equatable, Sendable {
    /// The kind of bracket.
    public let type: BracketType

    /// This frame: its number, the offsets asked for and reached, and its planned exposure.
    public let frame: BracketFramePlan

    /// The frames in the bracket.
    public let count: Int

    /// Every frame's offset asked for, in EV, in the order taken.
    public let offsets: [Double]

    /// The order of the frames.
    public let order: BracketOrder

    /// Creates a place.
    ///
    /// - Parameters:
    ///   - type: The kind of bracket.
    ///   - frame: This frame's plan.
    ///   - count: The frames in the bracket.
    ///   - offsets: Every frame's offset asked for, in the order taken.
    ///   - order: The order of the frames.
    public init(type: BracketType, frame: BracketFramePlan, count: Int, offsets: [Double], order: BracketOrder) {
        self.type = type
        self.frame = frame
        self.count = count
        self.offsets = offsets
        self.order = order
    }
}

/// Interval shooting: a series of separate photos at a fixed interval.
///
/// Each photo is an ordinary single capture; nothing is combined into a video or merged. The
/// timer runs only while a series is running and the app is open (AGENTS.md, "Battery").
public struct IntervalSettings: Equatable, Sendable {
    /// The intervals the app offers, in seconds: 1 second to 1 hour.
    public static let intervalRange: ClosedRange<Double> = 1...3600

    /// The photo counts the app offers: 2 to 999.
    public static let countRange: ClosedRange<Int> = 2...999

    /// The time from one photo to the next, in seconds.
    public let interval: Double

    /// How many photos the series takes.
    public let count: Int

    /// The default series: 10 photos, 10 seconds apart.
    public static let standard = IntervalSettings(interval: 10, count: 10)

    /// Creates interval settings, moving each value into its allowed range.
    ///
    /// - Parameters:
    ///   - interval: The time between photos, in seconds.
    ///   - count: The number of photos.
    public init(interval: Double, count: Int) {
        self.interval = interval.limited(to: Self.intervalRange)
        self.count = Swift.min(Swift.max(count, Self.countRange.lowerBound), Self.countRange.upperBound)
    }

    /// The intervals an interface lists, in seconds: 1 second to 1 hour.
    public static let listedIntervals: [Double] = [1, 2, 3, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// The photo counts an interface lists, from 2 to the 999 the app allows.
    public static let listedCounts = [2, 3, 5, 10, 20, 30, 50, 100, 200, 500, 999]

    /// The intervals to list for these settings: ``listedIntervals``, with ``interval`` added in
    /// order when it isn't one of them (a value set from Siri, Shortcuts or a preset), so a
    /// picker always shows the value in use.
    public var intervalChoices: [Double] {
        Self.listedIntervals.contains(interval) ? Self.listedIntervals : (Self.listedIntervals + [interval]).sorted()
    }

    /// The photo counts to list for these settings: ``listedCounts``, with ``count`` added in
    /// order when it isn't one of them.
    public var countChoices: [Int] {
        Self.listedCounts.contains(count) ? Self.listedCounts : (Self.listedCounts + [count]).sorted()
    }
}

/// How far a running interval series has got.
public struct IntervalProgress: Equatable, Sendable {
    /// The photos taken so far. A photo is counted only once it is taken and saved; while the
    /// series is paused, nothing is taken or counted.
    public let taken: Int

    /// The photos in the series.
    public let total: Int

    /// Whether the series is paused: the app is out of the foreground or the camera is paused
    /// (an interruption, heat, or starting again). It continues when both are back.
    public let isPaused: Bool

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The photos taken so far.
    ///   - total: The photos in the series.
    ///   - isPaused: Whether the series is paused.
    public init(taken: Int, total: Int, isPaused: Bool = false) {
        self.taken = taken
        self.total = total
        self.isPaused = isPaused
    }
}
