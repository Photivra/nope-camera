import CoreGraphics
import Foundation
import ImageIO
@testable import NopeCore
import Testing
import UniformTypeIdentifiers

@testable import NopeDevelop

/// Every file option (issue #57) and the location fields (issue #43), encoded with ImageIO and
/// opened again: a setting that makes a file that doesn't open isn't offered.
extension ImageIOTests {
    struct FileOptionsEncodingTests {
        /// Every combination of the options.
        static var allOptions: [DevelopedFileOptions] {
            var result: [DevelopedFileOptions] = []
            for heif in CompressionQuality.allCases {
                for jpeg in CompressionQuality.allCases {
                    for depth in HEIFBitDepth.allCases {
                        for space in OutputColorSpace.allCases {
                            var options = DevelopedFileOptions()
                            options.heifQuality = heif
                            options.jpegQuality = jpeg
                            options.heifBitDepth = depth
                            options.colorSpace = space
                            result.append(options)
                        }
                    }
                }
            }
            return result
        }

        @Test func settingsFollowTheOptions() throws {
            #expect(EncodingSettings(format: .raw, options: DevelopedFileOptions()) == nil)
            for options in Self.allOptions {
                let heif = try #require(EncodingSettings(format: .heif, options: options))
                #expect(heif.typeIdentifier == UTType.heic.identifier)
                #expect(heif.bitsPerChannel == options.heifBitDepth.rawValue)
                #expect(heif.lossyCompressionQuality == options.heifQuality.lossyCompressionQuality)
                #expect(heif.colorSpace == options.colorSpace)
                #expect(heif.imageBitsPerComponent == (options.heifBitDepth == .eight ? 8 : 16))
                let jpeg = try #require(EncodingSettings(format: .jpeg, options: options))
                #expect(jpeg.bitsPerChannel == 8)
                #expect(jpeg.imageBitsPerComponent == 16)
                #expect(jpeg.lossyCompressionQuality == options.jpegQuality.lossyCompressionQuality)
            }
            // The defaults are the earlier encoding, so `init(format:)` matches them.
            #expect(EncodingSettings(format: .heif) == EncodingSettings(format: .heif, options: DevelopedFileOptions()))
            #expect(EncodingSettings(format: .jpeg)?.colorSpaceName == CGColorSpace.displayP3)
        }

        /// One HEIF and one JPEG for each quality, bit depth and color space: each opens as one
        /// image of its format, passes the read-back, and has the chosen depth and color space.
        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func everyCombinationOpensAndPassesTheReadBack(format: PhotoFormat) throws {
            let plan = MetadataPlan()
            var seen: Set<String> = []
            for options in Self.allOptions {
                let settings = try #require(EncodingSettings(format: format, options: options))
                // JPEG ignores the HEIF options, so test each distinct JPEG encoding once.
                let id = "\(settings.lossyCompressionQuality ?? -1) \(settings.bitsPerChannel) \(settings.colorSpace)"
                guard seen.insert(id).inserted else { continue }
                let data = try PhotoEncoder.encode(
                    try testImage(), settings: settings, properties: plan.properties(for: format, from: [:], orientation: 1))
                let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: data))
                let violations = MetadataVerifier.violations(
                    in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
                #expect(violations.isEmpty, "\(id): \(violations)")
                let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
                let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "\(id)")
                #expect(image.width == 32 && image.height == 24)
                let expectedSpace = options.colorSpace == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3
                #expect(image.colorSpace?.name == expectedSpace, "\(id): \(String(describing: image.colorSpace?.name))")
                let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
                if format == .heif {
                    #expect(properties["Depth"] as? Int == settings.bitsPerChannel, "\(id)")
                } else {
                    #expect(properties["Depth"] as? Int == 8, "\(id)")
                }
            }
            #expect(seen.count == (format == .heif ? 16 : 8))
        }

        @Test func preparingConvertsOnlyWhenNeeded() throws {
            let image = try testImage()
            #expect(try PhotoEncoder.prepare(image, bitsPerComponent: 16, colorSpaceName: CGColorSpace.displayP3) === image)
            let srgb = try PhotoEncoder.prepare(image, bitsPerComponent: 16, colorSpaceName: CGColorSpace.sRGB)
            #expect(srgb !== image)
            #expect(srgb.colorSpace?.name == CGColorSpace.sRGB)
            #expect(srgb.bitsPerComponent == 16)
            let eight = try PhotoEncoder.prepare(image, bitsPerComponent: 8, colorSpaceName: CGColorSpace.displayP3)
            #expect(eight.bitsPerComponent == 8)
            #expect(eight.colorSpace?.name == CGColorSpace.displayP3)
            #expect(throws: CaptureError.developmentFailed) {
                try PhotoEncoder.prepare(image, bitsPerComponent: 16, colorSpaceName: "org.example.none" as CFString)
            }
            #expect(throws: CaptureError.developmentFailed) {
                try PhotoEncoder.prepare(image, bitsPerComponent: 3, colorSpaceName: CGColorSpace.sRGB)
            }
        }

        /// Every copy size, for HEIF and JPEG: the file opens at the scaled size, passes the
        /// read-back, and its EXIF pixel dimensions state the scaled size.
        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func everyCopySizeOpensAtItsSize(format: PhotoFormat) throws {
            var settings = MetadataSettings()
            settings.set(.exposureSettings, isOn: true)
            let plan = MetadataPlan(settings: settings)
            let source: [String: Any] = ["{Exif}": ["PixelXDimension": 32, "PixelYDimension": 24, "ISOSpeedRatings": [100]]]
            for size in OutputSize.allCases {
                var options = DevelopedFileOptions()
                options.size = size
                let encoding = try #require(EncodingSettings(format: format, options: options))
                #expect(encoding.size == size)
                let data = try PhotoEncoder.encode(
                    try testImage(), settings: encoding, properties: plan.properties(for: format, from: source, orientation: 1))
                let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: data))
                let violations = MetadataVerifier.violations(
                    in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
                #expect(violations.isEmpty, "\(size): \(violations)")
                let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
                let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
                let expected = size.dimensions(of: PhotoDimensions(width: 32, height: 24))
                #expect(image.width == expected.width && image.height == expected.height, "\(size)")
                let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
                let exif = try #require(properties["{Exif}"] as? [String: Any])
                #expect(exif["PixelXDimension"] as? Int == expected.width, "\(size)")
                #expect(exif["PixelYDimension"] as? Int == expected.height, "\(size)")
            }
        }

        @Test func resizingLeavesPropertiesWithoutPixelDimensionsAlone() throws {
            let image = try testImage()
            let none: [String: Any] = ["{TIFF}": ["Orientation": 1]]
            #expect(PhotoEncoder.resized(none, to: image).keys.sorted() == ["{TIFF}"])
            let other = PhotoEncoder.resized(["{Exif}": ["ISOSpeedRatings": [100]]], to: image)
            let exif = try #require(other["{Exif}"] as? [String: Any])
            #expect(exif.keys.sorted() == ["ISOSpeedRatings"])
            let smaller = try PhotoEncoder.prepare(
                image, bitsPerComponent: 16, colorSpaceName: CGColorSpace.displayP3, size: PhotoDimensions(width: 16, height: 12))
            #expect(smaller.width == 16 && smaller.height == 12)
        }

        @Test func theDeveloperUsesTheOptions() async throws {
            var options = DevelopedFileOptions()
            options.heifBitDepth = .eight
            options.colorSpace = .sRGB
            let developer = RAWDeveloper(renderer: FakeRenderer(image: try testImage(), properties: [:]))
            let file = try await developer.develop(
                RAWDeveloperTests.raw, to: .heif, look: .standard, options: options, metadata: MetadataPlan())
            let source = try #require(CGImageSourceCreateWithData(file.data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            #expect(properties["Depth"] as? Int == 8)
            #expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.colorSpace?.name == CGColorSpace.sRGB)
            await #expect(throws: CaptureError.developmentFailed) {
                try await developer.develop(
                    RAWDeveloperTests.raw, to: .raw, look: .standard, options: options, metadata: MetadataPlan())
            }
        }
    }

    /// Issue #43: a HEIF or JPEG with a location carries exactly the allowlisted GPS tags, and
    /// passes the read-back.
    struct LocationEncodingTests {
        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func aLocationIsWrittenAsTheAllowlistedTagsOnly(format: PhotoFormat) throws {
            var settings = MetadataSettings()
            settings.set(.location, isOn: true)
            var plan = MetadataPlan(settings: settings)
            plan.location = PhotoLocation(latitude: -33.5, longitude: 151.25, altitude: -4)
            let encoding = try #require(EncodingSettings(format: format))
            let data = try PhotoEncoder.encode(
                try testImage(), settings: encoding, properties: plan.properties(for: format, from: [:], orientation: 1))
            let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: data))
            let violations = MetadataVerifier.violations(
                in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
            #expect(violations.isEmpty, "\(violations)")
            let gpsTags = Set(readBack.file.inventory.tags.filter { $0.directory == .gps }.map(\.tag))
            #expect(gpsTags.isSubset(of: Set(MetadataField.gpsFields.map(\.tag))), "\(gpsTags)")
            #expect(gpsTags.isSuperset(of: [0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006]), "\(gpsTags)")

            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            let gps = try #require(properties["{GPS}"] as? [String: Any])
            #expect(gps["LatitudeRef"] as? String == "S")
            #expect(abs((gps["Latitude"] as? Double ?? 0) - 33.5) < 0.000_1)
            #expect(gps["LongitudeRef"] as? String == "E")
            #expect(abs((gps["Longitude"] as? Double ?? 0) - 151.25) < 0.000_1)
            #expect(gps["AltitudeRef"] as? Int == 1)
            #expect(abs((gps["Altitude"] as? Double ?? 0) - 4) < 0.000_1)

            // With the switch off, no GPS directory at all, even with a location in the plan.
            var off = MetadataPlan()
            off.location = plan.location
            let plain = try PhotoEncoder.encode(
                try testImage(), settings: encoding, properties: off.properties(for: format, from: [:], orientation: 1))
            let plainBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: plain))
            #expect(!plainBack.file.inventory.tags.contains { $0.directory == .gps })
            #expect(!plainBack.imageIOKeys.contains { $0.dictionary == "{GPS}" })
        }
    }
}
