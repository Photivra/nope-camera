import Foundation

/// Exposure bracketing: several photos at different exposures from one press of the shutter.
///
/// Every frame is a separate single-frame photo; nothing is merged (AGENTS.md, "Honesty"). The
/// frames are taken with the system's manual exposure bracket
/// (`AVCapturePhotoBracketSettings` with `AVCaptureManualExposureBracketedStillImageSettings`),
/// so each frame's ISO and shutter are set exactly.
public struct BracketSettings: Equatable, Hashable, Sendable {
    /// The frame counts nope. offers: 3, 5 or 7, each up to the lens's
    /// ``Lens/maxBracketedPhotoCount``.
    public static let frameCounts = [3, 5, 7]

    /// The steps between frames nope. offers, in EV: 1/3, 2/3, 1 and 2 stops.
    public static let steps: [Double] = [1.0 / 3.0, 2.0 / 3.0, 1, 2]

    /// The number of frames.
    public let frameCount: Int

    /// The exposure difference between neighboring frames, in EV.
    public let step: Double

    /// Creates bracket settings.
    ///
    /// - Parameters:
    ///   - frameCount: The number of frames, one of ``frameCounts``.
    ///   - step: The difference between neighboring frames in EV, one of ``steps``.
    public init(frameCount: Int, step: Double) {
        self.frameCount = frameCount
        self.step = step
    }

    /// Each frame's exposure relative to the metered one, in EV, darkest first and centered on
    /// 0: for 3 frames 1 EV apart, −1, 0 and +1.
    public var offsets: [Double] {
        let half = Double(frameCount - 1) / 2
        return (0..<frameCount).map { (Double($0) - half) * step }
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

/// Interval shooting: a series of separate photos at a fixed interval.
///
/// Each photo is an ordinary single capture; nothing is combined into a video or merged. The
/// timer runs only while a series is running and nope. is open (AGENTS.md, "Battery").
public struct IntervalSettings: Equatable, Sendable {
    /// The intervals nope. offers, in seconds: 1 second to 1 hour.
    public static let intervalRange: ClosedRange<Double> = 1...3600

    /// The photo counts nope. offers: 2 to 999.
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
}

/// How far a running interval series has got.
public struct IntervalProgress: Equatable, Sendable {
    /// The photos taken (or skipped because the camera was paused) so far.
    public let taken: Int

    /// The photos in the series.
    public let total: Int

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The photos taken so far.
    ///   - total: The photos in the series.
    public init(taken: Int, total: Int) {
        self.taken = taken
        self.total = total
    }
}
