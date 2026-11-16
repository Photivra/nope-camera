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
/// with ImageIO on macOS 27 and the iOS 27 Simulator). A smaller copy (`OutputSize`) is drawn
/// at its size before encoding, and its EXIF pixel dimensions are set to that size.
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
        let prepared = try prepare(image, for: settings)
        var options = settings.size == .full ? properties : resized(properties, to: prepared)
        options[kCGImageDestinationEmbedThumbnail as String] = false
        for (key, value) in settings.imageDestinationOptions() { options[key] = value }
        return try encode(prepared, typeIdentifier: settings.typeIdentifier, options: options)
    }

    /// The properties with the EXIF pixel dimensions, where present, set to a smaller copy's
    /// size, so the file never states the RAW's size for fewer pixels.
    ///
    /// - Parameters:
    ///   - properties: The metadata from `MetadataPlan`.
    ///   - image: The image that is encoded.
    /// - Returns: The properties for the encoder.
    static func resized(_ properties: [String: Any], to image: CGImage) -> [String: Any] {
        guard var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return properties }
        var result = properties
        if exif[kCGImagePropertyExifPixelXDimension as String] != nil {
            exif[kCGImagePropertyExifPixelXDimension as String] = image.width
        }
        if exif[kCGImagePropertyExifPixelYDimension as String] != nil {
            exif[kCGImagePropertyExifPixelYDimension as String] = image.height
        }
        result[kCGImagePropertyExifDictionary as String] = exif
        return result
    }

    /// Converts an image to the depth, color space and size the settings ask for, or returns it
    /// unchanged when it already has them.
    ///
    /// Core Graphics converts colors when it draws into a context of another color space
    /// (Quartz 2D Programming Guide, "Color and Color Spaces"), so an sRGB file gets sRGB colors,
    /// not Display P3 values relabeled. A smaller copy is scaled in the same draw. The pixels are
    /// otherwise unchanged; this is encoding, not development.
    ///
    /// - Parameters:
    ///   - image: The developed image, 16 bits per channel in Display P3.
    ///   - settings: The encoding settings.
    /// - Returns: The image to encode.
    /// - Throws: `CaptureError.developmentFailed` if the conversion fails.
    static func prepare(_ image: CGImage, for settings: EncodingSettings) throws(CaptureError) -> CGImage {
        let size = settings.size.dimensions(of: PhotoDimensions(width: image.width, height: image.height))
        return try prepare(
            image, bitsPerComponent: settings.imageBitsPerComponent, colorSpaceName: settings.colorSpaceName, size: size)
    }

    /// Converts an image to a depth, a named color space and a size, or returns it unchanged
    /// when it already has them.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - bits: The bits per component, 8 or 16.
    ///   - colorSpaceName: A Core Graphics color space name, such as `CGColorSpace.sRGB`.
    ///   - size: The size to draw it at, or `nil` for its own size.
    /// - Returns: The image to encode.
    /// - Throws: `CaptureError.developmentFailed` if the color space or the conversion fails.
    static func prepare(
        _ image: CGImage, bitsPerComponent bits: Int, colorSpaceName: CFString, size: PhotoDimensions? = nil
    ) throws(CaptureError) -> CGImage {
        guard let target = CGColorSpace(name: colorSpaceName) else { throw .developmentFailed }
        let size = size ?? PhotoDimensions(width: image.width, height: image.height)
        if image.bitsPerComponent == bits, image.colorSpace?.name == target.name, image.width == size.width,
            image.height == size.height
        {
            return image
        }
        guard let converted = draw(image, bitsPerComponent: bits, in: target, size: size) else { throw .developmentFailed }
        return converted
    }

    /// Draws an image into a new bitmap, which converts its colors to the bitmap's color space
    /// and scales it to the bitmap's size with high-quality interpolation.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - bits: The bitmap's bits per component, 8 or 16; any other value gives `nil`.
    ///   - space: The bitmap's color space.
    ///   - size: The bitmap's size.
    /// - Returns: The converted image, or `nil` if Core Graphics can't make the bitmap.
    private static func draw(
        _ image: CGImage, bitsPerComponent bits: Int, in space: CGColorSpace, size: PhotoDimensions
    ) -> CGImage? {
        let byteOrder = bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: bits, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | byteOrder)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context?.makeImage()
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
