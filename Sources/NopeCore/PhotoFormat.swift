import Foundation

/// A file format the app can save.
///
/// The raw values are stable, so settings that store a format can be saved and read back.
///
/// The default is RAW only (owner decision, issue #80): HEIF and JPEG copies are optional.
public enum PhotoFormat: String, Equatable, Hashable, Sendable, CaseIterable, Codable {
    /// Single-frame Bayer RAW, saved as DNG.
    case raw
    /// HEIF developed by the app from the RAW, 10 bits per channel.
    case heif
    /// JPEG developed by the app from the RAW, at maximum quality.
    case jpeg

    /// The formats selected when the app is first installed, and by Factory Defaults: RAW only
    /// (issue #80). Settings a person has saved keep their own selection.
    public static let defaultSelection: Set<PhotoFormat> = [.raw]

    /// Whether the app develops this format itself from the RAW, rather than saving sensor data.
    ///
    /// Developed formats never use the phone's own processing pipeline (issue #1, "Formats").
    public var isDevelopedFromRAW: Bool {
        self != .raw
    }
}
