import CoreGraphics
import Foundation
import ImageIO
import NopeCore
import Testing

@testable import NopeDevelop

/// The last-photo thumbnail (issue #36) and the size and depth the read-back reports for the
/// details (issue #53).
extension ImageIOTests {
    struct ThumbnailTests {
        /// Encodes the test image, turned by an orientation tag when given.
        static func encoded(_ format: PhotoFormat, orientation: Int = 1) throws -> Data {
            let settings = try #require(EncodingSettings(format: format))
            return try PhotoEncoder.encode(
                try testImage(width: 320, height: 240), settings: settings,
                properties: MetadataPlan().properties(for: format, from: [:], orientation: orientation))
        }

        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func aThumbnailIsSmallAndUpright(format: PhotoFormat) throws {
            let thumbnailer = ImageIOThumbnailer()
            let thumbnail = try #require(thumbnailer.thumbnail(of: PhotoFile(format: format, data: try Self.encoded(format))))
            #expect(thumbnail.width == ImageIOThumbnailer.defaultMaximumPixelSize)
            // 240 × 156 / 320 = 117; the HEIF encoder may round the decoded size by a pixel.
            #expect(abs(thumbnail.height - 117) <= 1, "\(thumbnail.height)")
            #expect(thumbnail.rgba.count == thumbnail.width * thumbnail.height * 4)
            // Orientation 6 (turned 90 degrees clockwise) makes the thumbnail portrait.
            let turned = try #require(
                thumbnailer.thumbnail(of: PhotoFile(format: format, data: try Self.encoded(format, orientation: 6))))
            #expect(turned.width < turned.height)
            // The fill color survives: the test image is opaque.
            #expect(thumbnail.rgba[3] == 255)
        }

        @Test func aSmallerSizeCanBeAskedFor() throws {
            let thumbnail = try #require(
                ImageIOThumbnailer(maximumPixelSize: 40).thumbnail(of: PhotoFile(format: .jpeg, data: try Self.encoded(.jpeg))))
            #expect(thumbnail.width == 40 && thumbnail.height == 30)
        }

        /// The Last Photo viewer's preview of a 12-megapixel photo, as the app wires it: a
        /// 3072 × 2304 JPEG with no metadata from the photo, decoded upright to sRGB pixels at its
        /// own size or smaller.
        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func aPreviewOfATwelveMegapixelPhoto(format: PhotoFormat) throws {
            let settings = try #require(EncodingSettings(format: format))
            let data = try PhotoEncoder.encode(
                try testImage(width: 4032, height: 3024), settings: settings,
                properties: MetadataPlan().properties(for: format, from: [:], orientation: 6))
            let previewer = ImageIOPreviewer()
            let preview = try #require(previewer.preview(of: PhotoFile(format: format, data: data)))
            // Orientation 6 turns the photo upright: portrait.
            #expect(preview.height == SessionPhotos.previewMaximumPixelSize)
            #expect(abs(preview.width - 2304) <= 1, "\(preview.width)")
            // A JPEG with nothing from the photo: the encoder writes only the image's own size and
            // color space (EXIF ColorSpace and pixel dimensions, mirrored in XMP), and no GPS,
            // TIFF, dates or device.
            let source = try #require(CGImageSourceCreateWithData(preview.data as CFData, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
            #expect(properties[kCGImagePropertyTIFFDictionary as String] == nil)
            let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            let ownSize: Set<String> = ["ColorSpace", "PixelXDimension", "PixelYDimension"]
            #expect(Set(exif.keys).isSubset(of: ownSize), "\(exif.keys.sorted())")
            let xmp = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap(CGImageMetadataCopyTags) as? [CGImageMetadataTag] ?? []
            let xmpNames = Set(xmp.compactMap { CGImageMetadataTagCopyName($0) as String? })
            #expect(xmpNames.isSubset(of: ownSize), "\(xmpNames.sorted())")
            // Decoded at its own size, or smaller when asked; never larger.
            let full = try #require(previewer.decode(preview, maximumPixelSize: nil))
            #expect(full.width == preview.width && full.height == preview.height)
            #expect(full.rgba.count == full.width * full.height * PhotoThumbnail.bytesPerPixel)
            let small = try #require(previewer.decode(preview, maximumPixelSize: 1200))
            #expect(max(small.width, small.height) == 1200)
            let capped = try #require(previewer.decode(preview, maximumPixelSize: 9000))
            #expect(capped.height == preview.height)
        }

        @Test func anUnreadablePreviewIsNotDecoded() throws {
            let previewer = ImageIOPreviewer(maximumPixelSize: 64)
            #expect(previewer.maximumPixelSize == 64)
            #expect(ImageIOPreviewer.quality == 0.9)
            #expect(previewer.preview(of: PhotoFile(format: .raw, data: Data([1, 2, 3]))) == nil)
            let broken = try #require(PhotoPreview(width: 4, height: 3, data: Data([1, 2, 3])))
            #expect(previewer.decode(broken, maximumPixelSize: nil) == nil)
        }

        @Test func anUnreadableFileHasNoThumbnail() {
            #expect(ImageIOThumbnailer().thumbnail(of: PhotoFile(format: .raw, data: Data([1, 2, 3]))) == nil)
        }

        @Test(arguments: [(PhotoFormat.heif, 10), (.jpeg, 8)])
        func theReadBackReportsTheSizeAndDepth(format: PhotoFormat, depth: Int) throws {
            let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: try Self.encoded(format)))
            #expect(readBack.image == ImageProperties(pixelWidth: 320, pixelHeight: 240, depth: depth))
        }

        @Test func missingPropertiesAreNil() {
            #expect(ImageIOReadBack.imageProperties(of: [:]) == ImageProperties(pixelWidth: nil, pixelHeight: nil, depth: nil))
        }
    }
}
