import CoreGraphics
import Foundation
import ImageIO
import NopeCore
import UniformTypeIdentifiers

/// How the app encodes a developed photo with the system encoders.
///
/// The defaults follow issue #1, "Formats": HEIF at 10 bits per channel and JPEG at maximum
/// quality, in Display P3. The person may choose others (`DevelopedFileOptions`, issue #57).
/// HEIF is written only with the system HEIF encoder; the app never bundles an encoder
/// (AGENTS.md, "Encoders").
public struct EncodingSettings: Equatable, Sendable {
    /// JPEG's maximum quality for `kCGImageDestinationLossyCompressionQuality`.
    ///
    /// Apple documents the value range as 0.0 to 1.0, where 1.0 is maximum image quality:
    /// [kCGImageDestinationLossyCompressionQuality](https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality).
    public static let maximumJPEGQuality = 1.0

    /// The format these settings encode.
    public let format: PhotoFormat

    /// The uniform type identifier passed to `CGImageDestinationCreateWithData`.
    public let typeIdentifier: String

    /// Bits per color channel in the encoded file.
    public let bitsPerChannel: Int

    /// The lossy compression quality, from 0.0 to 1.0, or `nil` to use the encoder's default.
    ///
    /// By default HEIF uses the system encoder's default and JPEG the maximum; the person can
    /// choose another (`DevelopedFileOptions`, issue #57).
    public let lossyCompressionQuality: Double?

    /// The color space the image is encoded in.
    public let colorSpace: OutputColorSpace

    /// The size of the encoded image, as a fraction of the developed image's.
    /// `OutputSize.full` unless the person chose a smaller copy (`DevelopedFileOptions`).
    public let size: OutputSize

    /// Creates the default encoding settings for a developed format: HEIF at 10 bits and the
    /// encoder's quality, JPEG at maximum quality, both in Display P3.
    ///
    /// - Parameter format: The format to encode.
    /// - Returns: `nil` for `PhotoFormat.raw`, which is saved as the camera's DNG
    ///   and never re-encoded.
    public init?(format: PhotoFormat) {
        self.init(format: format, options: DevelopedFileOptions())
    }

    /// Creates the encoding settings for a developed format with the person's options.
    ///
    /// - Parameters:
    ///   - format: The format to encode.
    ///   - options: The compression, HEIF bit depth, color space and size.
    /// - Returns: `nil` for `PhotoFormat.raw`, which is saved as the camera's DNG and never
    ///   re-encoded.
    public init?(format: PhotoFormat, options: DevelopedFileOptions) {
        let quality = options.quality(for: format).lossyCompressionQuality
        switch format {
        case .raw:
            return nil
        case .heif:
            self.init(
                format: format, type: .heic, bitsPerChannel: options.heifBitDepth.rawValue, quality: quality,
                colorSpace: options.colorSpace, size: options.size)
        case .jpeg:
            self.init(
                format: format, type: .jpeg, bitsPerChannel: 8, quality: quality, colorSpace: options.colorSpace,
                size: options.size)
        }
    }

    /// Stores the resolved values.
    ///
    /// - Parameters:
    ///   - format: The format to encode.
    ///   - type: The file type for ImageIO.
    ///   - bitsPerChannel: Bits per color channel.
    ///   - quality: The lossy compression quality, or `nil` for the encoder default.
    ///   - colorSpace: The color space to encode in.
    ///   - size: The size of the encoded image.
    private init(
        format: PhotoFormat, type: UTType, bitsPerChannel: Int, quality: Double?, colorSpace: OutputColorSpace,
        size: OutputSize
    ) {
        self.format = format
        self.typeIdentifier = type.identifier
        self.bitsPerChannel = bitsPerChannel
        self.lossyCompressionQuality = quality
        self.colorSpace = colorSpace
        self.size = size
    }

    /// The bits per component of the image handed to the encoder: 8 for an 8-bit HEIF, and
    /// otherwise the renderer's 16, as before these options existed. ImageIO writes a 16-bit
    /// image as a 10-bit HEIF (see `PhotoEncoder`) and as an 8-bit JPEG, the format's only depth.
    var imageBitsPerComponent: Int {
        format == .heif && bitsPerChannel == 8 ? 8 : 16
    }

    /// The Core Graphics name of ``colorSpace``.
    var colorSpaceName: CFString {
        switch colorSpace {
        case .displayP3: CGColorSpace.displayP3
        case .sRGB: CGColorSpace.sRGB
        }
    }

    /// The options dictionary for `CGImageDestinationAddImage(_:_:_:)`.
    ///
    /// - Returns: The lossy compression quality when one is set; otherwise an empty dictionary.
    public func imageDestinationOptions() -> [String: Double] {
        guard let lossyCompressionQuality else { return [:] }
        return [kCGImageDestinationLossyCompressionQuality as String: lossyCompressionQuality]
    }
}
