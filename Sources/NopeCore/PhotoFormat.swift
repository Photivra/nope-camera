import Foundation

/// A file format nope. can save.
///
/// The defaults follow issue #1, "Formats": RAW plus HEIF.
public enum PhotoFormat: Equatable, Hashable, Sendable, CaseIterable {
    /// Single-frame Bayer RAW, saved as DNG.
    case raw
    /// HEIF developed by nope. from the RAW, 10 bits per channel.
    case heif
    /// JPEG developed by nope. from the RAW, at maximum quality.
    case jpeg

    /// The formats selected when the app is first installed: RAW and HEIF.
    public static let defaultSelection: Set<PhotoFormat> = [.raw, .heif]

    /// Whether nope. develops this format itself from the RAW, rather than saving sensor data.
    ///
    /// Developed formats never use the phone's own processing pipeline (issue #1, "Formats").
    public var isDevelopedFromRAW: Bool {
        self != .raw
    }
}
