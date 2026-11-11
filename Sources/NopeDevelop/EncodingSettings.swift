import Foundation
import ImageIO
import NopeCore
import UniformTypeIdentifiers

/// How nope. encodes a developed photo with the system encoders.
///
/// Values follow issue #1, "Formats": HEIF at 10 bits per channel and JPEG at maximum quality.
/// HEIF is written only with the system HEIF encoder; nope. never bundles an encoder
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
    /// HEIF quality isn't decided yet, so HEIF uses the system default until it is measured.
    public let lossyCompressionQuality: Double?

    /// Creates the encoding settings for a developed format.
    ///
    /// - Parameter format: The format to encode.
    /// - Returns: `nil` for `PhotoFormat.raw`, which is saved as the camera's DNG
    ///   and never re-encoded.
    public init?(format: PhotoFormat) {
        switch format {
        case .raw:
            return nil
        case .heif:
            self.init(format: format, type: .heic, bitsPerChannel: 10, quality: nil)
        case .jpeg:
            self.init(format: format, type: .jpeg, bitsPerChannel: 8, quality: Self.maximumJPEGQuality)
        }
    }

    /// Stores the resolved values.
    ///
    /// - Parameters:
    ///   - format: The format to encode.
    ///   - type: The file type for ImageIO.
    ///   - bitsPerChannel: Bits per color channel.
    ///   - quality: The lossy compression quality, or `nil` for the encoder default.
    private init(format: PhotoFormat, type: UTType, bitsPerChannel: Int, quality: Double?) {
        self.format = format
        self.typeIdentifier = type.identifier
        self.bitsPerChannel = bitsPerChannel
        self.lossyCompressionQuality = quality
    }

    /// The options dictionary for `CGImageDestinationAddImage(_:_:_:)`.
    ///
    /// - Returns: The lossy compression quality when one is set; otherwise an empty dictionary.
    public func imageDestinationOptions() -> [String: Double] {
        guard let lossyCompressionQuality else { return [:] }
        return [kCGImageDestinationLossyCompressionQuality as String: lossyCompressionQuality]
    }
}
