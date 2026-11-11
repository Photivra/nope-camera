import Foundation

/// What one capture produces: single-frame Bayer RAW, or the labeled processed fallback.
///
/// ``CameraModel`` chooses it with ``init(for:)``; interfaces only display it (AGENTS.md, "One
/// direction of flow"). Apple ProRAW is never used: it is demosaiced and may combine frames
/// (AGENTS.md, "Honesty").
public enum CaptureFormat: Equatable, Sendable {
    /// Single-frame Bayer RAW, saved as DNG.
    ///
    /// - Parameter pixelFormat: The four-character code of the Bayer pixel format, such as
    ///   `bgg4`.
    case bayerRAW(pixelFormat: String)

    /// The least-processed photo the lens can give without RAW, labeled as processed.
    ///
    /// Present it with the issue #1 wording: "This device can't save unprocessed RAW; this photo
    /// has some device processing."
    case processedFallback(ProcessedFallback)

    /// Chooses the format for a lens: Bayer RAW when the lens has it, otherwise its processed
    /// fallback.
    ///
    /// - Parameter lens: The lens that will take the photo.
    public init(for lens: Lens) {
        if let pixelFormat = lens.bayerRAWFormat {
            self = .bayerRAW(pixelFormat: pixelFormat)
        } else {
            self = .processedFallback(lens.processedFallback)
        }
    }

    /// Whether the photo is single-frame Bayer RAW.
    public var isBayerRAW: Bool {
        if case .bayerRAW = self { return true }
        return false
    }
}
