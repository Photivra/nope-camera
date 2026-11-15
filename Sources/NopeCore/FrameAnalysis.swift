import Foundation

/// A small grid sampled from one live preview frame: its brightness and its local sharpness.
///
/// The capture adapter samples it from a reduced, preview-sized video frame at a low rate,
/// only while the histogram or focus peaking is shown (AGENTS.md, "Battery"). Privacy rule: the
/// grid stays in memory for one analysis and is never stored, logged or written to a photo
/// (issues #47 and #51).
public struct LumaFrame: Equatable, Sendable {
    /// The number of columns.
    public let width: Int

    /// The number of rows.
    public let height: Int

    /// The brightness (luma, 0 black to 255 white) of each cell, row by row from the top.
    public let luma: [UInt8]

    /// The local sharpness of each cell, 0 (flat) to 255: the brightness differences between the
    /// cell's pixel and its neighbors in the full frame, row by row from the top.
    public let edges: [UInt8]

    /// Creates a frame.
    ///
    /// - Parameters:
    ///   - width: The number of columns.
    ///   - height: The number of rows.
    ///   - luma: The brightness of each cell; `width` × `height` values.
    ///   - edges: The sharpness of each cell; `width` × `height` values.
    public init(width: Int, height: Int, luma: [UInt8], edges: [UInt8]) {
        self.width = width
        self.height = height
        self.luma = luma
        self.edges = edges
    }

    /// The frame turned and mirrored the way the viewfinder shows it.
    ///
    /// Video frames arrive in the sensor's orientation; the viewfinder turns them by its
    /// rotation angle and mirrors the front camera.
    ///
    /// - Parameters:
    ///   - quarterTurns: Clockwise quarter turns, as the viewfinder's rotation angle divided by
    ///     90 degrees.
    ///   - mirrored: Whether the viewfinder mirrors the picture left to right (the front
    ///     camera).
    /// - Returns: The turned frame.
    public func oriented(quarterTurns: Int, mirrored: Bool) -> LumaFrame {
        var frame = self
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            frame = frame.turnedClockwise()
        }
        return mirrored ? frame.mirrored() : frame
    }

    /// The frame turned a quarter turn clockwise.
    private func turnedClockwise() -> LumaFrame {
        // The new row r, column c comes from the old row (height - 1 - c), column r.
        let indices = (0..<width).flatMap { row in (0..<height).map { column in (height - 1 - column) * width + row } }
        return LumaFrame(width: height, height: width, luma: indices.map { luma[$0] }, edges: indices.map { edges[$0] })
    }

    /// The frame mirrored left to right.
    private func mirrored() -> LumaFrame {
        let indices = (0..<height).flatMap { row in (0..<width).map { column in row * width + (width - 1 - column) } }
        return LumaFrame(width: width, height: height, luma: indices.map { luma[$0] }, edges: indices.map { edges[$0] })
    }
}

/// Which highlights and shadows of the live preview are clipped.
public struct ClippingState: Equatable, Sendable {
    /// Whether enough of the preview is at full white to count as clipped highlights.
    public let highlights: Bool

    /// Whether enough of the preview is at full black to count as clipped shadows.
    public let shadows: Bool

    /// Creates a clipping state.
    ///
    /// - Parameters:
    ///   - highlights: Whether the highlights are clipped.
    ///   - shadows: Whether the shadows are clipped.
    public init(highlights: Bool, shadows: Bool) {
        self.highlights = highlights
        self.shadows = shadows
    }
}

/// The brightness histogram of the live preview, with its clipping (issue #47).
///
/// It is measured on the preview, which the device has already processed, not on the RAW: the
/// RAW may hold detail that the preview shows as clipped. Interfaces say so next to it.
public struct Histogram: Equatable, Sendable {
    /// The number of bins.
    public static let binCount = 64

    /// The lowest brightness, 0 to 255, counted as clipped highlights: the top few codes of the
    /// 8-bit preview. A tool setting, checked on a device.
    public static let highlightThreshold: UInt8 = 252

    /// The highest brightness, 0 to 255, counted as clipped shadows.
    public static let shadowThreshold: UInt8 = 3

    /// The share of the picture that must be clipped before it is flagged: 1%, so a few
    /// specular highlights don't flag the whole frame. A tool setting.
    public static let clippedShare = 0.01

    /// The share of the preview in each bin, from black to white; the shares add up to 1.
    public let bins: [Double]

    /// The share of the preview at or above ``highlightThreshold``.
    public let highlightShare: Double

    /// The share of the preview at or below ``shadowThreshold``.
    public let shadowShare: Double

    /// Creates a histogram.
    ///
    /// - Parameters:
    ///   - bins: The share in each bin, from black to white.
    ///   - highlightShare: The share at or above ``highlightThreshold``.
    ///   - shadowShare: The share at or below ``shadowThreshold``.
    public init(bins: [Double], highlightShare: Double, shadowShare: Double) {
        self.bins = bins
        self.highlightShare = highlightShare
        self.shadowShare = shadowShare
    }

    /// Measures the histogram of a frame's brightness.
    ///
    /// - Parameter luma: The brightness values, 0 to 255.
    /// - Returns: The histogram; all bins 0 for no values.
    public init(luma: [UInt8]) {
        var counts = [Int](repeating: 0, count: Self.binCount)
        var highlights = 0
        var shadows = 0
        for value in luma {
            counts[Int(value) * Self.binCount / 256] += 1
            if value >= Self.highlightThreshold { highlights += 1 }
            if value <= Self.shadowThreshold { shadows += 1 }
        }
        let total = Double(max(luma.count, 1))
        self.init(
            bins: counts.map { Double($0) / total }, highlightShare: Double(highlights) / total,
            shadowShare: Double(shadows) / total)
    }

    /// Which ends are clipped: more than ``clippedShare`` of the preview at either end.
    public var clipping: ClippingState {
        ClippingState(highlights: highlightShare > Self.clippedShare, shadows: shadowShare > Self.clippedShare)
    }
}

/// Which parts of the live preview are in focus: the cells with the sharpest edges (issue #51,
/// "Focus peaking"). Interfaces highlight them over the viewfinder.
public struct FocusPeakingMap: Equatable, Sendable {
    /// The weakest edge, 0 to 255, ever highlighted, so a scene with nothing in focus shows
    /// nothing rather than its least blurry part. A tool setting, checked on a device.
    public static let minimumEdge: UInt8 = 40

    /// The share of the sharpest cells highlighted when the scene has many sharp edges: the top
    /// 10%, so the highlight marks the plane of focus rather than every texture.
    public static let sharpestShare = 0.1

    /// The number of columns.
    public let width: Int

    /// The number of rows.
    public let height: Int

    /// Whether each cell is in focus, row by row from the top.
    public let cells: [Bool]

    /// Creates a map.
    ///
    /// - Parameters:
    ///   - width: The number of columns.
    ///   - height: The number of rows.
    ///   - cells: Whether each cell is in focus; `width` × `height` values.
    public init(width: Int, height: Int, cells: [Bool]) {
        self.width = width
        self.height = height
        self.cells = cells
    }

    /// Finds the in-focus cells of a frame: those at least as sharp as ``minimumEdge`` and among
    /// the sharpest ``sharpestShare``.
    ///
    /// - Parameter frame: The frame.
    public init(frame: LumaFrame) {
        var counts = [Int](repeating: 0, count: 256)
        for edge in frame.edges { counts[Int(edge)] += 1 }
        // The edge strength at which the sharpest share begins.
        let allowed = Int(Double(frame.edges.count) * Self.sharpestShare)
        var seen = 0
        var threshold = 255
        while threshold > 0 && seen + counts[threshold] <= allowed {
            seen += counts[threshold]
            threshold -= 1
        }
        let cutoff = max(threshold + 1, Int(Self.minimumEdge))
        self.init(width: frame.width, height: frame.height, cells: frame.edges.map { Int($0) >= cutoff })
    }

    /// Whether any cell is in focus.
    public var hasFocus: Bool {
        cells.contains(true)
    }
}

/// What the live analysis is asked for. Nothing is analyzed while it is empty.
public struct LiveAnalysisNeeds: OptionSet, Hashable, Sendable {
    /// The value's bits.
    public let rawValue: Int

    /// Creates a value from its bits.
    ///
    /// - Parameter rawValue: The bits.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The histogram and clipping indicators.
    public static let histogram = LiveAnalysisNeeds(rawValue: 1 << 0)

    /// Focus peaking.
    public static let focusPeaking = LiveAnalysisNeeds(rawValue: 1 << 1)

    /// What the camera screen needs now: the histogram only while it is on and the manual
    /// controls are shown outside clean view (issue #47: never in full auto), and focus peaking
    /// whenever it is on.
    ///
    /// - Parameters:
    ///   - options: The overlay options.
    ///   - manualControlsShown: Whether the manual controls are on.
    ///   - isCleanView: Whether clean view is on.
    /// - Returns: The needs; empty when no overlay that needs video is shown.
    public static func needed(for options: OverlayOptions, manualControlsShown: Bool, isCleanView: Bool)
        -> LiveAnalysisNeeds
    {
        var needs: LiveAnalysisNeeds = []
        if options.showsHistogram && manualControlsShown && !isCleanView { needs.insert(.histogram) }
        if options.showsFocusPeaking { needs.insert(.focusPeaking) }
        return needs
    }
}

/// The result of analyzing one live frame.
public struct FrameAnalysis: Equatable, Sendable {
    /// The histogram, or `nil` when it wasn't asked for.
    public let histogram: Histogram?

    /// The focus peaking map, or `nil` when it wasn't asked for.
    public let focusPeaking: FocusPeakingMap?

    /// Creates an analysis.
    ///
    /// - Parameters:
    ///   - histogram: The histogram, or `nil`.
    ///   - focusPeaking: The focus peaking map, or `nil`.
    public init(histogram: Histogram?, focusPeaking: FocusPeakingMap?) {
        self.histogram = histogram
        self.focusPeaking = focusPeaking
    }

    /// Analyzes a frame for what is needed.
    ///
    /// - Parameters:
    ///   - frame: The frame, as the viewfinder shows it.
    ///   - needs: What to measure.
    public init(frame: LumaFrame, needs: LiveAnalysisNeeds) {
        self.init(
            histogram: needs.contains(.histogram) ? Histogram(luma: frame.luma) : nil,
            focusPeaking: needs.contains(.focusPeaking) ? FocusPeakingMap(frame: frame) : nil)
    }

    /// The analysis without the parts that are no longer needed, or `nil` if nothing is left.
    ///
    /// - Parameter needs: What is needed now.
    public func keeping(_ needs: LiveAnalysisNeeds) -> FrameAnalysis? {
        let kept = FrameAnalysis(
            histogram: needs.contains(.histogram) ? histogram : nil,
            focusPeaking: needs.contains(.focusPeaking) ? focusPeaking : nil)
        return kept.histogram == nil && kept.focusPeaking == nil ? nil : kept
    }
}

/// How often live overlays update, following the battery rules (AGENTS.md, "Battery"): a few
/// times a second, half as often in Low Power Mode or when the device is hot, and not at all at
/// a critical heat level.
public enum LiveUpdateRate {
    /// The normal shortest time between two updates, in seconds: four a second, enough for a
    /// meter or a focus aid a person reads.
    public static let normalInterval = 0.25

    /// The shortest time between two updates in Low Power Mode or at a serious heat level, in
    /// seconds: two a second.
    public static let reducedInterval = 0.5

    /// The shortest time between two updates.
    ///
    /// - Parameters:
    ///   - isLowPowerMode: Whether Low Power Mode is on (`ProcessInfo.isLowPowerModeEnabled`).
    ///   - heat: The device's heat level.
    /// - Returns: The interval in seconds, or `nil` when nothing should update.
    public static func interval(isLowPowerMode: Bool, heat: HeatLevel) -> Double? {
        switch heat {
        case .critical: nil
        case .serious: reducedInterval
        case .nominal, .fair: isLowPowerMode ? reducedInterval : normalInterval
        }
    }
}

/// Lets through at most one event per interval.
public struct RateLimiter: Sendable {
    /// When the last event was let through, in seconds, or `nil` before the first.
    private var lastTime: Double?

    /// Creates a limiter that lets the first event through.
    public init() {}

    /// Whether an event at a time should be let through, and records it if so.
    ///
    /// - Parameters:
    ///   - time: The event's time, in seconds on any steady clock.
    ///   - interval: The shortest time between two events, in seconds, or `nil` to let nothing
    ///     through.
    /// - Returns: `true` for the first event and for each one at least `interval` after the
    ///   last one let through.
    public mutating func shouldPass(at time: Double, interval: Double?) -> Bool {
        guard let interval else { return false }
        if let lastTime, time - lastTime < interval { return false }
        lastTime = time
        return true
    }
}
