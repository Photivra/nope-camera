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

/// Interval shooting: a series of separate photos at a fixed interval, until a number of photos
/// is taken or a time is up (``StopAfter``).
///
/// Each photo is an ordinary single capture; nothing is combined into a video or merged. The
/// timer runs only while a series is running and the app is open (AGENTS.md, "Battery").
public struct IntervalSettings: Equatable, Sendable {
    /// What ends a series: a number of photos, or a time.
    public enum StopAfter: String, Equatable, Sendable, CaseIterable {
        /// The series ends once ``IntervalSettings/count`` photos are taken. The default.
        case numberOfPhotos

        /// The series ends once ``IntervalSettings/duration`` has passed since it started, by the
        /// clock on the wall: the time keeps running while the series is paused, so a series of
        /// one hour started at 8:41 PM ends at 9:41 PM (``IntervalProgress/timeSpan``).
        case time
    }

    /// The intervals the app offers, in seconds: 1 second to 1 hour.
    public static let intervalRange: ClosedRange<Double> = 1...3600

    /// The photo counts the app offers: 2 to 999.
    public static let countRange: ClosedRange<Int> = 2...999

    /// The times a series can run for, in seconds: 1 minute to 24 hours.
    public static let durationRange: ClosedRange<Double> = 60...86_400

    /// The time a series runs for until another is chosen, in seconds: 1 hour.
    public static let standardDuration: Double = 3600

    /// The time from one photo to the next, in seconds.
    public let interval: Double

    /// How many photos the series takes when it stops after a number of photos.
    public let count: Int

    /// What ends the series.
    public let stopAfter: StopAfter

    /// How long the series runs when it stops after a time, in seconds.
    public let duration: Double

    /// The default series: 10 photos, 10 seconds apart.
    public static let standard = IntervalSettings(interval: 10, count: 10)

    /// Creates interval settings, moving each value into its allowed range.
    ///
    /// - Parameters:
    ///   - interval: The time between photos, in seconds.
    ///   - count: The number of photos, used when the series stops after a number of photos.
    ///   - stopAfter: What ends the series. ``StopAfter/numberOfPhotos`` by default.
    ///   - duration: How long the series runs, in seconds, used when it stops after a time.
    ///     ``standardDuration`` by default.
    public init(interval: Double, count: Int, stopAfter: StopAfter = .numberOfPhotos, duration: Double = standardDuration) {
        self.interval = interval.limited(to: Self.intervalRange)
        self.count = Swift.min(Swift.max(count, Self.countRange.lowerBound), Self.countRange.upperBound)
        self.stopAfter = stopAfter
        self.duration = duration.limited(to: Self.durationRange)
    }

    /// The intervals an interface lists, in seconds: 1 second to 1 hour.
    public static let listedIntervals: [Double] = [1, 2, 3, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// The photo counts an interface lists, from 2 to the 999 the app allows.
    public static let listedCounts = [2, 3, 5, 10, 20, 30, 50, 100, 200, 500, 999]

    /// The whole hours an interface lists for the time: 0 to 24.
    public static let listedHours = Array(0...24)

    /// The minutes an interface lists for the time: 0 to 59.
    public static let listedMinutes = Array(0...59)

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

    /// The whole hours of ``duration``, for the time's Hours picker.
    public var durationHours: Int {
        Int(duration) / 3600
    }

    /// The minutes of ``duration`` past its whole hours, for the time's Minutes picker. Seconds
    /// left over (from a preset of another version) are dropped.
    public var durationMinutes: Int {
        Int(duration) % 3600 / 60
    }

    /// Whether the interval is shorter than the time, so a series that stops after a time takes
    /// at least two photos. Always `true` for a series that stops after a number of photos.
    /// ``CameraModel/intervalBlocker`` is ``IntervalBlocker/intervalNotShorterThanTime`` while
    /// it is `false`.
    public var isIntervalShorterThanTime: Bool {
        stopAfter == .numberOfPhotos || interval < duration
    }

    /// The most photos the series can take: ``count``, or for a series that stops after a time,
    /// one photo at the start and one after each whole interval that starts before the time is
    /// up. Each photo also takes time to be taken and saved before the next interval starts
    /// (`ManualControlsModel`), so a timed series usually takes fewer; an interface says "at
    /// most".
    public var maximumPhotoCount: Int {
        switch stopAfter {
        case .numberOfPhotos: count
        case .time: Int((duration / interval).rounded(.up))
        }
    }

    /// These settings with another interval.
    ///
    /// - Parameter interval: The time between photos, in seconds.
    /// - Returns: The settings, each value inside its allowed range.
    public func with(interval: Double) -> IntervalSettings {
        IntervalSettings(interval: interval, count: count, stopAfter: stopAfter, duration: duration)
    }

    /// These settings with another number of photos.
    ///
    /// - Parameter count: The number of photos.
    /// - Returns: The settings, each value inside its allowed range.
    public func with(count: Int) -> IntervalSettings {
        IntervalSettings(interval: interval, count: count, stopAfter: stopAfter, duration: duration)
    }

    /// These settings with another end: a number of photos or a time. The count and the time
    /// are both kept, so switching back finds them as they were.
    ///
    /// - Parameter stopAfter: What ends the series.
    /// - Returns: The settings.
    public func with(stopAfter: StopAfter) -> IntervalSettings {
        IntervalSettings(interval: interval, count: count, stopAfter: stopAfter, duration: duration)
    }

    /// These settings with another time.
    ///
    /// - Parameter duration: How long the series runs, in seconds.
    /// - Returns: The settings, each value inside its allowed range.
    public func with(duration: Double) -> IntervalSettings {
        IntervalSettings(interval: interval, count: count, stopAfter: stopAfter, duration: duration)
    }

    /// These settings with a time of whole hours and minutes, moved into ``durationRange``: no
    /// time becomes 1 minute, and more than 24 hours becomes 24 hours.
    ///
    /// - Parameters:
    ///   - hours: The whole hours.
    ///   - minutes: The minutes.
    /// - Returns: The settings.
    public func with(hours: Int, minutes: Int) -> IntervalSettings {
        with(duration: Double(hours * 3600 + minutes * 60))
    }
}

/// How far a running interval series has got.
public struct IntervalProgress: Equatable, Sendable {
    /// The photos taken so far. A photo is counted only once it is taken and saved; while the
    /// series is paused, nothing is taken or counted.
    public let taken: Int

    /// The photos in the series, or `nil` for a series that stops after a time.
    public let total: Int?

    /// Whether the series is paused: the app is out of the foreground or the camera is paused
    /// (an interruption, heat, or starting again). It continues when both are back.
    public let isPaused: Bool

    /// When a series that stops after a time started and when it ends, or `nil` for a series
    /// that stops after a number of photos. The end is fixed when the series starts: the time
    /// keeps running while the series is paused (``IntervalSettings/StopAfter/time``).
    public let timeSpan: ClosedRange<Date>?

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - taken: The photos taken so far.
    ///   - total: The photos in the series, or `nil` for a series that stops after a time.
    ///   - isPaused: Whether the series is paused.
    ///   - timeSpan: When a series that stops after a time started and ends, or `nil`.
    public init(taken: Int, total: Int?, isPaused: Bool = false, timeSpan: ClosedRange<Date>? = nil) {
        self.taken = taken
        self.total = total
        self.isPaused = isPaused
        self.timeSpan = timeSpan
    }

    /// The time left of a series that stops after a time, in seconds, never less than 0, or
    /// `nil` for a series that stops after a number of photos.
    ///
    /// - Parameter now: The current time.
    /// - Returns: The seconds until the end, or `nil`.
    public func secondsLeft(at now: Date) -> Double? {
        timeSpan.map { Swift.max($0.upperBound.timeIntervalSince(now), 0) }
    }

    /// How much of the series is done, from 0 to 1: by time for a series that stops after a
    /// time, otherwise by the photos taken.
    ///
    /// - Parameter now: The current time.
    /// - Returns: The share done.
    public func fractionDone(at now: Date) -> Double {
        if let timeSpan {
            let length = timeSpan.upperBound.timeIntervalSince(timeSpan.lowerBound)
            return (now.timeIntervalSince(timeSpan.lowerBound) / Swift.max(length, 1)).limited(to: 0...1)
        }
        return (Double(taken) / Double(Swift.max(total ?? 1, 1))).limited(to: 0...1)
    }

    /// This progress, marked as paused or running.
    ///
    /// - Parameter isPaused: Whether the series is paused.
    /// - Returns: The progress.
    func with(isPaused: Bool) -> IntervalProgress {
        IntervalProgress(taken: taken, total: total, isPaused: isPaused, timeSpan: timeSpan)
    }

    /// This progress with another count of photos taken, running.
    ///
    /// - Parameter taken: The photos taken so far.
    /// - Returns: The progress.
    func with(taken: Int) -> IntervalProgress {
        IntervalProgress(taken: taken, total: total, timeSpan: timeSpan)
    }
}

/// How the last interval series ended (``ManualControlsModel/lastIntervalEnd``).
public enum IntervalEnd: Equatable, Sendable {
    /// It took its number of photos, or its time was up.
    case finished

    /// It ended early: it was stopped, the camera stopped for good, or a photo couldn't be taken
    /// or saved (the camera says why).
    case stopped
}
