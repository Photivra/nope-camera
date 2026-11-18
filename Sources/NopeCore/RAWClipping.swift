import Foundation

/// One color of a Bayer RAW sensor's color filter.
public enum CFAColor: String, CaseIterable, Equatable, Sendable {
    /// Red.
    case red = "R"
    /// Green.
    case green = "G"
    /// Blue.
    case blue = "B"
}

/// How much of a RAW photo is clipped: the photosites at or near the white level (highlights
/// that the sensor recorded as full) and at or near the black level (shadows with no signal
/// above the sensor's zero), per color of the color filter (issue #53).
///
/// The capture adapter counts every photosite of the RAW's active area in the photo's own
/// sensor buffer (`AVCapturePhoto.pixelBuffer`) at capture time, against the black and white
/// levels of the camera's DNG. Nothing is estimated: a photo whose buffer can't be read that way
/// gets a ``RAWClippingResult/notMeasured(_:)`` with the reason instead.
///
/// Definition: a highlight photosite is one at or above the white level less ``margin`` of the
/// range between the black and white levels; a shadow photosite is one at or below the black
/// level plus the same margin. The sensor may saturate a little below the white level the DNG
/// records, so this counts what the file says is full, not what the sensor did.
///
/// Privacy: counts only, kept in memory with the photo's details; never logged or stored.
public struct RAWClipping: Equatable, Sendable {
    /// The counts for one color of the color filter.
    public struct Channel: Equatable, Sendable {
        /// The color.
        public let color: CFAColor
        /// How many photosites of this color were counted.
        public let photosites: Int
        /// How many are clipped highlights.
        public let highlights: Int
        /// How many are clipped shadows.
        public let shadows: Int

        /// Creates a channel's counts.
        ///
        /// - Parameters:
        ///   - color: The color.
        ///   - photosites: The photosites counted.
        ///   - highlights: The clipped highlights.
        ///   - shadows: The clipped shadows.
        public init(color: CFAColor, photosites: Int, highlights: Int, shadows: Int) {
            self.color = color
            self.photosites = photosites
            self.highlights = highlights
            self.shadows = shadows
        }

        /// The share of this color's photosites that are clipped highlights, 0 to 1.
        public var highlightShare: Double { RAWClipping.share(highlights, of: photosites) }

        /// The share of this color's photosites that are clipped shadows, 0 to 1.
        public var shadowShare: Double { RAWClipping.share(shadows, of: photosites) }
    }

    /// How near the white or black level a photosite counts as clipped: 0.5% of the range
    /// between the two levels. A choice, not a platform value: near enough to the levels that
    /// the photosite holds no usable detail, wide enough to include values a step or two off
    /// the level.
    public static let margin = 0.005

    /// The counts per color, in red, green, blue order; a color the filter doesn't have is left
    /// out.
    public let channels: [Channel]

    /// Creates the counts.
    ///
    /// - Parameter channels: The counts per color.
    public init(channels: [Channel]) {
        self.channels = channels
    }

    /// Every photosite counted.
    public var photosites: Int { channels.reduce(0) { $0 + $1.photosites } }

    /// Every clipped highlight.
    public var highlights: Int { channels.reduce(0) { $0 + $1.highlights } }

    /// Every clipped shadow.
    public var shadows: Int { channels.reduce(0) { $0 + $1.shadows } }

    /// The share of all photosites that are clipped highlights, 0 to 1.
    public var highlightShare: Double { Self.share(highlights, of: photosites) }

    /// The share of all photosites that are clipped shadows, 0 to 1.
    public var shadowShare: Double { Self.share(shadows, of: photosites) }

    /// A count as a share of a total, or 0 for an empty total.
    ///
    /// - Parameters:
    ///   - count: The count.
    ///   - total: The total.
    /// - Returns: The share, 0 to 1.
    static func share(_ count: Int, of total: Int) -> Double {
        total > 0 ? Double(count) / Double(total) : 0
    }
}

/// The RAW clipping of one photo, or why it wasn't measured.
public enum RAWClippingResult: Equatable, Sendable {
    /// Measured from the photo's sensor buffer.
    case measured(RAWClipping)
    /// Not measured, for this reason.
    case notMeasured(RAWClippingFailure)
}

/// Why a photo's RAW clipping wasn't measured.
public enum RAWClippingFailure: Equatable, Sendable, CaseIterable {
    /// The photo had no sensor buffer to read, or it held no photosites.
    case noSamples
    /// The sensor buffer's layout isn't one the app reads (only single-plane 16-bit Bayer
    /// buffers with a known color filter pattern are).
    case unsupportedLayout
    /// The camera's DNG has no usable size, black level or white level, or describes them in a
    /// way the app doesn't apply (a linearization table, per-row or per-column black levels).
    case levelsUnreadable
    /// The sensor buffer and the camera's DNG differ in size.
    case sizeMismatch
    /// The sensor buffer's values don't fit the DNG's levels, so they can't be compared.
    case scaleMismatch
}
