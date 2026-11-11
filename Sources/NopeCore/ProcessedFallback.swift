import Foundation

/// The least-processed format a lens without Bayer RAW can give.
///
/// The camera processes these photos, so the interface labels them (issue #1, "No-RAW
/// fallback").
public enum ProcessedFallback: Equatable, Sendable, CaseIterable {
    /// HEIF, encoded by the system at speed prioritization.
    case heif
    /// JPEG, for a lens that offers no HEIF encoding.
    case jpeg
}
