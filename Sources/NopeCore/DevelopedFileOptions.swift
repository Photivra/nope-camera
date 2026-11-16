import Foundation

/// How the HEIF and JPEG copies the app develops from the RAW are encoded: compression, HEIF bit
/// depth, color space and size (issue #57, "File").
///
/// Owner principle (issue #57): anything about the file that the device lets an app control is
/// the person's to choose, behind the advanced options, with the defaults working on their own.
/// The defaults are the encoding the app has always used: HEIF at the system encoder's own
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

    /// The size of both copies. Stored as an optional so options saved before it existed still
    /// decode; read ``size``.
    private var storedSize: OutputSize?

    /// The size of both copies, as a fraction of the RAW's width and height.
    /// ``OutputSize/full`` by default: the RAW's own size, as before this option existed.
    public var size: OutputSize {
        get { storedSize ?? .full }
        set { storedSize = newValue == .full ? nil : newValue }
    }

    /// The defaults: the encoding the app used before these options existed.
    public init() {
        heifQuality = .systemDefault
        jpegQuality = .maximum
        heifBitDepth = .ten
        colorSpace = .displayP3
        storedSize = nil
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

/// The size of the developed copies, as a fraction of the RAW's width and height (issue #57,
/// "Downscaled size").
///
/// A smaller copy is for sharing or saving space; the RAW always keeps every pixel. The encoder
/// draws the developed image into a smaller bitmap with Core Graphics' high-quality
/// interpolation, so the copy's exact size is known and its EXIF `PixelXDimension` and
/// `PixelYDimension` match it. A fraction, rather than a pixel count, keeps the choice the same
/// on every lens and never enlarges a photo.
public enum OutputSize: String, CaseIterable, Codable, Hashable, Sendable {
    /// The RAW's own width and height. The default.
    case full
    /// Half the width and height: a quarter of the pixels (about 3 MP from a 12 MP RAW).
    case half
    /// A quarter of the width and height: a sixteenth of the pixels (about 0.75 MP from 12 MP).
    case quarter

    /// The fraction of the width and height the copy keeps: 1, 0.5 or 0.25.
    public var scale: Double {
        switch self {
        case .full: 1
        case .half: 0.5
        case .quarter: 0.25
        }
    }

    /// The size of a copy of an image.
    ///
    /// - Parameter size: The developed image's size, in pixels.
    /// - Returns: Each side times ``scale``, rounded, and at least 1 pixel.
    public func dimensions(of size: PhotoDimensions) -> PhotoDimensions {
        PhotoDimensions(width: scaled(size.width), height: scaled(size.height))
    }

    /// One side times ``scale``, rounded, and at least 1.
    ///
    /// - Parameter side: A side, in pixels.
    /// - Returns: The scaled side, in pixels.
    private func scaled(_ side: Int) -> Int {
        max(1, Int((Double(side) * scale).rounded()))
    }
}
