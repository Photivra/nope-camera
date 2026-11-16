import CoreGraphics
import Foundation
import ImageIO
@testable import NopeCore
import Testing

@testable import NopeDevelop

/// The Standard File Tags (owner decision 2026-11-16) through the system encoders: what ImageIO
/// keeps of them in each format and color space, and that the read-back accepts them.
extension ImageIOTests {
    struct StandardFileTagsEncodingTests {
        static func encoded(_ format: PhotoFormat, space: OutputColorSpace, standardTags: Bool) throws -> Data {
            var metadata = MetadataSettings()
            metadata.set(.location, isOn: true)
            metadata.writesStandardFileTags = standardTags
            var plan = MetadataPlan(settings: metadata)
            plan.location = PhotoLocation(latitude: -33.5, longitude: -70.25, altitude: nil)
            var options = DevelopedFileOptions()
            options.colorSpace = space
            let settings = try #require(EncodingSettings(format: format, options: options))
            let data = try PhotoEncoder.encode(
                try testImage(), settings: settings, properties: plan.properties(for: format, from: [:], orientation: 1))
            let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: data))
            let violations = MetadataVerifier.violations(
                in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
            #expect(violations.isEmpty, "\(format) \(space) \(standardTags): \(violations)")
            return data
        }

        static func tags(_ data: Data) throws -> Set<UInt16> {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            var tags: Set<UInt16> = []
            let exif = properties["{Exif}"] as? [String: Any] ?? [:]
            if exif["ComponentsConfiguration"] != nil { tags.insert(0x9101) }
            if exif["FlashPixVersion"] != nil { tags.insert(0xA000) }
            if exif["ColorSpace"] != nil { tags.insert(0xA001) }
            if (properties["{GPS}"] as? [String: Any])?["GPSVersion"] != nil { tags.insert(0x0000) }
            return tags
        }

        /// Measured on the iOS 27.2 Simulator: ImageIO keeps every value except `ColorSpace` in a
        /// Display P3 JPEG, which it drops.
        @Test(arguments: [PhotoFormat.heif, .jpeg], OutputColorSpace.allCases)
        func theTagsArriveAndPassTheReadBack(format: PhotoFormat, space: OutputColorSpace) throws {
            let on = try Self.tags(Self.encoded(format, space: space, standardTags: true))
            var expected: Set<UInt16> = [0x9101, 0xA000, 0x0000, 0xA001]
            if format == .jpeg, space == .displayP3 { expected.remove(0xA001) }
            #expect(on == expected, "\(format) \(space): \(on.sorted())")
            let off = try Self.tags(Self.encoded(format, space: space, standardTags: false))
            #expect(off.isSubset(of: [0x9101, 0xA000, 0xA001]), "\(format) \(space): \(off.sorted())")
            #expect(!off.contains(0x0000))
        }

        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func anSRGBCopySaysSRGB(format: PhotoFormat) throws {
            let data = try Self.encoded(format, space: .sRGB, standardTags: true)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            #expect((properties["{Exif}"] as? [String: Any])?["ColorSpace"] as? Int == 1)
        }

        @Test func colorSpaceTaggingChangesOnlyAnExistingValueOfAnSRGBCopy() {
            let tagged: [String: Any] = ["{Exif}": ["ColorSpace": 0xFFFF]]
            #expect((PhotoEncoder.colorSpaceTagged(tagged, as: .sRGB)["{Exif}"] as? [String: Any])?["ColorSpace"] as? Int == 1)
            #expect(
                (PhotoEncoder.colorSpaceTagged(tagged, as: .displayP3)["{Exif}"] as? [String: Any])?["ColorSpace"] as? Int
                    == 0xFFFF)
            let none: [String: Any] = ["{Exif}": ["ExifVersion": [2, 3, 2]]]
            #expect((PhotoEncoder.colorSpaceTagged(none, as: .sRGB)["{Exif}"] as? [String: Any])?["ColorSpace"] == nil)
            #expect(PhotoEncoder.colorSpaceTagged([:], as: .sRGB).isEmpty)
        }
    }
}
