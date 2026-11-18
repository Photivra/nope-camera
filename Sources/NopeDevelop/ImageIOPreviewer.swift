import CoreGraphics
import Foundation
import ImageIO
import NopeCore

/// Makes and decodes the Last Photo viewer's compressed previews with ImageIO, in memory
/// (`PhotoPreview`; docs/design/BUILD-SPEC.md, 3.14).
///
/// A preview is the saved file decoded at a reduced size, upright, and drawn into a new 8-bit
/// sRGB image (`ImageIOThumbnailer.drawnImage(of:maximumPixelSize:)`), then encoded as a JPEG
/// with the system encoder. The JPEG carries nothing from the photo (no GPS, TIFF, dates,
/// device or Content Credentials) and no embedded thumbnail; the encoder writes only what
/// describes the image itself: its size, the sRGB profile, and EXIF `ColorSpace` and pixel
/// dimensions (checked in `ThumbnailTests`). Decoding draws it into an sRGB RGBA bitmap, at a smaller size when asked.
///
/// Privacy: nothing is cached or written to disk (`kCGImageSourceShouldCache` is off, and the
/// destination writes to memory); the bytes stay in memory (AGENTS.md, "Photos never linger").
public struct ImageIOPreviewer: PhotoPreviewing {
    /// The JPEG quality, from 0 to 1: 0.9 (`kCGImageDestinationLossyCompressionQuality`). An
    /// assumption that it shows no visible artifacts at the viewer's zoom; to be checked on a
    /// device with the size it gives (docs/TESTING.md).
    public static let quality = 0.9

    /// The JPEG type identifier, `public.jpeg` (Uniform Type Identifiers, `UTType.jpeg`).
    static let jpegType = "public.jpeg"

    /// The longest side of a preview, in pixels.
    public let maximumPixelSize: Int

    /// Creates a previewer.
    ///
    /// - Parameter maximumPixelSize: The longest side of a preview, in pixels.
    public init(maximumPixelSize: Int = SessionPhotos.previewMaximumPixelSize) {
        self.maximumPixelSize = maximumPixelSize
    }

    /// Makes a compressed preview of a saved file.
    ///
    /// - Parameter file: A saved DNG, HEIF or JPEG.
    /// - Returns: The preview, or `nil` if ImageIO can't decode the file or encode the JPEG.
    public func preview(of file: PhotoFile) -> PhotoPreview? {
        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: Self.quality,
            kCGImageDestinationEmbedThumbnail as String: false,
        ]
        guard let image = ImageIOThumbnailer.drawnImage(of: file.data, maximumPixelSize: maximumPixelSize),
            let data = try? PhotoEncoder.encode(image, typeIdentifier: Self.jpegType, options: options)
        else { return nil }
        return PhotoPreview(width: image.width, height: image.height, data: data)
    }

    /// Decodes a preview into sRGB RGBA pixels.
    ///
    /// - Parameters:
    ///   - preview: The preview.
    ///   - maximumPixelSize: The longest side to decode to, in pixels, or `nil` for the
    ///     preview's own size.
    /// - Returns: The pixels, or `nil` if the data can't be decoded.
    public func decode(_ preview: PhotoPreview, maximumPixelSize: Int?) -> PhotoThumbnail? {
        let side = min(maximumPixelSize ?? preview.longestSide, preview.longestSide)
        return ImageIOThumbnailer.pixels(of: preview.data, maximumPixelSize: side)
    }
}
