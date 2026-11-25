import CoreGraphics
import Foundation
import ImageIO
import NopeCore

/// Makes the last-photo thumbnail from a saved file with ImageIO, in memory (issue #36).
///
/// `CGImageSourceCreateThumbnailAtIndex` decodes the file at a small size, turned upright by its
/// orientation tag (`kCGImageSourceCreateThumbnailWithTransform`). The image is always made from
/// the full image (`kCGImageSourceCreateThumbnailFromImageAlways`): the app's files embed no
/// thumbnail. The result is drawn into an sRGB RGBA bitmap, the layout `PhotoThumbnail`
/// describes.
///
/// Privacy: nothing is cached or written to disk (`kCGImageSourceShouldCache` is off); the
/// pixels stay in memory (AGENTS.md, "Photos never linger").
public struct ImageIOThumbnailer: PhotoThumbnailing {
    /// The longest side of the thumbnail, in pixels: the 52-point slot at 3× scale.
    public static let defaultMaximumPixelSize = 156

    /// The longest side of the thumbnail, in pixels.
    public let maximumPixelSize: Int

    /// Creates a thumbnailer.
    ///
    /// - Parameter maximumPixelSize: The longest side of the thumbnail, in pixels.
    public init(maximumPixelSize: Int = Self.defaultMaximumPixelSize) {
        self.maximumPixelSize = maximumPixelSize
    }

    /// Makes a thumbnail.
    ///
    /// - Parameter file: A saved DNG, HEIF or JPEG.
    /// - Returns: The thumbnail, upright, or `nil` if ImageIO can't decode the file.
    public func thumbnail(of file: PhotoFile) -> PhotoThumbnail? {
        Self.pixels(of: file.data, maximumPixelSize: maximumPixelSize)
    }

    /// Decodes an image at a reduced size, upright, and draws it into an 8-bit sRGB RGBA bitmap,
    /// without caching. The drawn image is a new image with none of the file's properties, in a
    /// form ImageIO's JPEG encoder takes: encoding the decoded image of a 10-bit HEIF directly
    /// failed (`ThumbnailTests`, iOS 27.2 Simulator), and the drawn one encodes.
    ///
    /// - Parameters:
    ///   - data: A DNG, HEIF or JPEG file's bytes.
    ///   - maximumPixelSize: The longest side, in pixels.
    /// - Returns: The image, or `nil` if ImageIO can't decode the data.
    static func drawnImage(of data: Data, maximumPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * PhotoThumbnail.bytesPerPixel, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Decodes an image at a reduced size into the layout `PhotoThumbnail` describes. The
    /// bitmap context owns its memory, and the pixels are copied out through the image it makes,
    /// so no pointer is handled here.
    ///
    /// - Parameters:
    ///   - data: A DNG, HEIF or JPEG file's bytes.
    ///   - maximumPixelSize: The longest side, in pixels.
    /// - Returns: The pixels, or `nil` if ImageIO can't decode the data.
    static func pixels(of data: Data, maximumPixelSize: Int) -> PhotoThumbnail? {
        guard let image = drawnImage(of: data, maximumPixelSize: maximumPixelSize) else { return nil }
        return image.dataProvider?.data.flatMap { PhotoThumbnail(width: image.width, height: image.height, rgba: $0 as Data) }
    }
}
