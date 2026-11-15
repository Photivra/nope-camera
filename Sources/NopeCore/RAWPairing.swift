import Foundation

/// Which processed copy Photos keeps together with the RAW when RAW, HEIF and JPEG are all
/// saved (issue #50).
///
/// A Photos asset holds one main resource and one alternate (`PHAssetResourceType.photo` and
/// `.alternatePhoto`), so a RAW can be paired with only one processed copy; the other one is
/// saved as its own asset. The choice changes nothing about how each file is developed, what
/// metadata it carries, or how it is signed. ``SaveSettings/rawPairing`` holds it.
public enum RAWPairing: String, CaseIterable, Codable, Hashable, Sendable {
    /// The HEIF is paired with the RAW and the JPEG is its own photo. The default.
    case heif
    /// The JPEG is paired with the RAW and the HEIF is its own photo, for sharing to places
    /// that accept JPEG only.
    case jpeg

    /// The format of the paired copy.
    public var format: PhotoFormat {
        switch self {
        case .heif: .heif
        case .jpeg: .jpeg
        }
    }
}
