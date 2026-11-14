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
