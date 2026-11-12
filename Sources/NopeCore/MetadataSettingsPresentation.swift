import Foundation

extension MetadataItem {
    /// Whether settings offer a switch for the item yet.
    ///
    /// Location needs its own explanation and the system location prompt, and the name and
    /// copyright need text entry; neither flow is built, so those switches aren't shown and the
    /// items stay off. Interfaces show a switch only where this is `true`.
    public var isOfferedInSettings: Bool {
        switch self {
        case .location, .nameAndCopyright: false
        default: true
        }
    }

    /// The items whose switches settings show, in display order.
    public static var offeredInSettings: [MetadataItem] {
        allCases.filter(\.isOfferedInSettings)
    }
}

/// A metadata item every file keeps, because the photo can't be opened or shown correctly
/// without it.
///
/// Each case is a row of the "Locked" table in `docs/PRIVACY.md`. None of them identify the
/// person or link their photos. Interfaces show them as locked, each with its explanation.
public enum LockedMetadataItem: String, CaseIterable, Sendable, Hashable {
    /// Image size, bit depth, compression and data layout.
    case imageLayout
    /// The color filter pattern: which pixels are red, green and blue.
    case colorFilterPattern
    /// Black and white levels.
    case blackAndWhiteLevels
    /// Color matrices and the as-shot white balance.
    case colorCalibration
    /// The DNG version.
    case dngVersion
    /// Orientation.
    case orientation
    /// The color profile of HEIF and JPEG files.
    case colorProfile
}
