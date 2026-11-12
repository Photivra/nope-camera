import CoreGraphics
import Foundation
import ImageIO
import NopeCore

/// Encodes a developed image as HEIF or JPEG with the system encoders, with exactly the
/// metadata it is given.
///
/// The image comes from the RAW developer and carries no metadata of its own, so the file holds
/// only the property dictionary `MetadataPlan` built from the allowlist, plus what ImageIO
/// adds to describe the image itself (checked by the read-back). No thumbnail is embedded
/// (`kCGImageDestinationEmbedThumbnail` is `false`). HEIF uses the system HEIF encoder only
/// (AGENTS.md, "Encoders"); a 16-bit image is written as 10-bit HEIF (`Depth` reads back as 10
/// with ImageIO on macOS 27 and the iOS 27 Simulator).
enum PhotoEncoder {
    /// Encodes an image.
    ///
    /// - Parameters:
    ///   - image: The developed image.
    ///   - settings: The format's encoding settings.
    ///   - properties: The metadata, from `MetadataPlan.properties(for:from:orientation:)`.
    /// - Returns: The file's bytes.
    /// - Throws: `CaptureError.developmentFailed` if the encoder fails.
    static func encode(
        _ image: CGImage, settings: EncodingSettings, properties: [String: Any]
    ) throws(CaptureError) -> Data {
        var options = properties
        options[kCGImageDestinationEmbedThumbnail as String] = false
        for (key, value) in settings.imageDestinationOptions() { options[key] = value }
        return try encode(image, typeIdentifier: settings.typeIdentifier, options: options)
    }

    /// Encodes an image with ImageIO.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - typeIdentifier: The file type, such as `public.heic`.
    ///   - options: The properties and destination options.
    /// - Returns: The file's bytes.
    /// - Throws: `CaptureError.developmentFailed` if ImageIO can't create the file type or
    ///   finish the file.
    static func encode(_ image: CGImage, typeIdentifier: String, options: [String: Any]) throws(CaptureError) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, typeIdentifier as CFString, 1, nil)
        if let destination { CGImageDestinationAddImage(destination, image, options as CFDictionary) }
        guard let destination, CGImageDestinationFinalize(destination) else { throw .developmentFailed }
        return output as Data
    }
}
