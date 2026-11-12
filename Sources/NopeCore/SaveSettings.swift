import Foundation

/// What nope. saves for each photo: the file formats, the developed look and the metadata
/// choices.
///
/// ``CameraModel/saveSettings`` holds the current value. The format rule from issue #1,
/// "Formats", lives here: RAW plus HEIF by default, any combination of RAW, HEIF and JPEG, and
/// never none. A lens without Bayer RAW always saves its labeled processed fallback instead.
public struct SaveSettings: Equatable, Codable, Sendable {
    /// The formats saved for a photo taken with a Bayer RAW lens. Never empty.
    public private(set) var formats: Set<PhotoFormat>

    /// The metadata choices, including the signature switch.
    public var metadata: MetadataSettings

    /// How HEIF and JPEG are developed from the RAW: ``DevelopedLook/standard`` (the default)
    /// or ``DevelopedLook/flat``. Never affects the RAW.
    public var developedLook: DevelopedLook

    /// The settings on first launch: RAW plus HEIF, ``MetadataSettings/init()``, and the
    /// standard look.
    public init() {
        formats = PhotoFormat.defaultSelection
        metadata = MetadataSettings()
        developedLook = .standard
    }

    /// Selects or deselects a format. Deselecting the last selected format does nothing, so at
    /// least one format is always saved.
    ///
    /// - Parameters:
    ///   - format: The format.
    ///   - isSelected: Whether it is saved.
    /// - Returns: `false` if the change was refused because it would leave no format.
    @discardableResult
    public mutating func setFormat(_ format: PhotoFormat, isSelected: Bool) -> Bool {
        if isSelected {
            formats.insert(format)
            return true
        }
        guard formats != [format] else { return false }
        formats.remove(format)
        return true
    }
}
