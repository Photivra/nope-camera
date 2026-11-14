import Foundation

/// How the HEIF and JPEG copies nope. develops from the RAW are encoded: compression, HEIF bit
/// depth and color space (issue #57, "File").
///
/// Owner principle (issue #57): anything about the file that the device lets an app control is
/// the person's to choose, behind the advanced options, with the defaults working on their own.
/// The defaults are the encoding nope. has always used: HEIF at the system encoder's own
/// quality and 10 bits per channel, JPEG at maximum quality, both in Display P3. None of the
/// options change the RAW, the metadata or the signature, and every combination is encoded and
/// opened again by the unit tests (`NopeDevelopTests`), because a setting that makes a file
/// that doesn't open isn't offered.
///
/// ``SaveSettings/fileOptions`` holds the choice; `NopeDevelop` turns it into ImageIO options.
public struct DevelopedFileOptions: Equatable, Codable, Hashable, Sendable {
    /// The compression of the HEIF copy. ``CompressionQuality/systemDefault`` by default.
    public var heifQuality: CompressionQuality
    /// The compression of the JPEG copy. ``CompressionQuality/maximum`` by default.
    public var jpegQuality: CompressionQuality
    /// The bits per color channel of the HEIF copy. ``HEIFBitDepth/ten`` by default. JPEG is
    /// always 8 bits per channel: the format has no other depth in ImageIO.
    public var heifBitDepth: HEIFBitDepth
    /// The color space of both copies. ``OutputColorSpace/displayP3`` by default.
    public var colorSpace: OutputColorSpace

    /// The defaults: the encoding nope. used before these options existed.
    public init() {
        heifQuality = .systemDefault
        jpegQuality = .maximum
        heifBitDepth = .ten
        colorSpace = .displayP3
    }

    /// Whether every option is at its default.
    public var isDefault: Bool {
        self == DevelopedFileOptions()
    }

    /// The compression chosen for a developed format.
    ///
    /// - Parameter format: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    /// - Returns: The format's quality; ``CompressionQuality/maximum`` for RAW, which is never
    ///   re-encoded.
    public func quality(for format: PhotoFormat) -> CompressionQuality {
        switch format {
        case .heif: heifQuality
        case .jpeg: jpegQuality
        case .raw: .maximum
        }
    }
}

/// The lossy compression quality of a developed copy.
///
/// The values are ImageIO's `kCGImageDestinationLossyCompressionQuality`, which Apple documents
/// as 0.0 to 1.0, where 1.0 is maximum image quality
/// ([documentation](https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality)).
public enum CompressionQuality: String, CaseIterable, Codable, Hashable, Sendable {
    /// No quality is passed, so the system encoder uses its own default.
    case systemDefault
    /// Maximum quality (1.0): the largest files.
    case maximum
    /// High quality (0.9).
    case high
    /// Medium quality (0.7): smaller files, with visible compression in fine detail.
    case medium

    /// The value for `kCGImageDestinationLossyCompressionQuality`, or `nil` for the encoder's
    /// default.
    public var lossyCompressionQuality: Double? {
        switch self {
        case .systemDefault: nil
        case .maximum: 1.0
        case .high: 0.9
        case .medium: 0.7
        }
    }
}

/// The bits per color channel of the developed HEIF.
public enum HEIFBitDepth: Int, CaseIterable, Codable, Hashable, Sendable {
    /// 8 bits per channel: smaller files that every viewer opens.
    case eight = 8
    /// 10 bits per channel: smoother gradients. The default.
    case ten = 10
}

/// The color space the developed copies are encoded in.
public enum OutputColorSpace: String, CaseIterable, Codable, Hashable, Sendable {
    /// Display P3, the color space the camera reports. The default.
    case displayP3
    /// sRGB, for sites and screens that show only sRGB. Colors outside sRGB are clipped to it.
    case sRGB
}
