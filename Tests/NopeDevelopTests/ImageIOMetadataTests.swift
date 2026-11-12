import CoreGraphics
import CoreImage
import Foundation
import ImageIO
@testable import NopeCore
import Testing

@testable import NopeDevelop

/// A small 16-bit Display P3 image, as the RAW renderer returns.
func testImage(width: Int = 32, height: Int = 24) throws -> CGImage {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
    context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

/// Every test that encodes or decodes with ImageIO runs one at a time, with a time limit. In CI
/// these tests stalled when they ran in parallel (the cause isn't isolated yet; locally they pass
/// either way), so they run serially, and a hang fails fast instead of stopping the whole run.
@Suite(.serialized, .timeLimit(.minutes(1)))
enum ImageIOTests {}

/// Every ImageIO key in the catalog is the value of ImageIO's own constant.
extension ImageIOTests {
    struct ImageIOKeyNameTests {
        @Test func dictionaryNamesMatchImageIO() {
            #expect(MetadataField.tiff == kCGImagePropertyTIFFDictionary as String)
            #expect(MetadataField.exif == kCGImagePropertyExifDictionary as String)
            #expect(MetadataField.exifAux == kCGImagePropertyExifAuxDictionary as String)
            #expect(MetadataField.dng == kCGImagePropertyDNGDictionary as String)
            #expect(MetadataField.gps == kCGImagePropertyGPSDictionary as String)
            #expect(MetadataField.makerApple == kCGImagePropertyMakerAppleDictionary as String)
            #expect(MetadataField.iptc == kCGImagePropertyIPTCDictionary as String)
        }

        @Test func everyCatalogKeyIsAnImageIOConstant() {
            let constants: Set<String> = [
                kCGImagePropertyOrientation, kCGImagePropertyTIFFCompression, kCGImagePropertyTIFFPhotometricInterpretation,
                kCGImagePropertyTIFFXResolution, kCGImagePropertyTIFFYResolution, kCGImagePropertyTIFFResolutionUnit,
                kCGImagePropertyTIFFTileWidth, kCGImagePropertyTIFFTileLength, kCGImagePropertyTIFFOrientation,
                kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware,
                kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFCopyright,
                kCGImagePropertyTIFFHostComputer,
                kCGImagePropertyExifVersion, kCGImagePropertyExifComponentsConfiguration, kCGImagePropertyExifFlashPixVersion,
                kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension,
                kCGImagePropertyExifCFAPattern, kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized,
                kCGImagePropertyExifSubsecTime, kCGImagePropertyExifSubsecTimeOriginal, kCGImagePropertyExifSubsecTimeDigitized,
                kCGImagePropertyExifOffsetTime, kCGImagePropertyExifOffsetTimeOriginal, kCGImagePropertyExifOffsetTimeDigitized,
                kCGImagePropertyExifLensSpecification, kCGImagePropertyExifLensMake, kCGImagePropertyExifLensModel,
                kCGImagePropertyExifExposureTime, kCGImagePropertyExifFNumber, kCGImagePropertyExifExposureProgram,
                kCGImagePropertyExifISOSpeedRatings, kCGImagePropertyExifSensitivityType, kCGImagePropertyExifShutterSpeedValue,
                kCGImagePropertyExifApertureValue, kCGImagePropertyExifBrightnessValue, kCGImagePropertyExifExposureBiasValue,
                kCGImagePropertyExifMaxApertureValue, kCGImagePropertyExifMeteringMode, kCGImagePropertyExifFlash,
                kCGImagePropertyExifFocalLength, kCGImagePropertyExifSubjectArea, kCGImagePropertyExifSensingMethod,
                kCGImagePropertyExifSceneType, kCGImagePropertyExifExposureMode, kCGImagePropertyExifWhiteBalance,
                kCGImagePropertyExifFocalLenIn35mmFilm, kCGImagePropertyExifSceneCaptureType,
                kCGImagePropertyExifAuxLensInfo, kCGImagePropertyExifAuxLensModel,
                kCGImagePropertyDNGVersion, kCGImagePropertyDNGBackwardVersion, kCGImagePropertyDNGUniqueCameraModel,
                kCGImagePropertyDNGCFAPlaneColor, kCGImagePropertyDNGCFALayout, kCGImagePropertyDNGBlackLevelRepeatDim,
                kCGImagePropertyDNGBlackLevel, kCGImagePropertyDNGWhiteLevel, kCGImagePropertyDNGDefaultCropOrigin,
                kCGImagePropertyDNGDefaultCropSize, kCGImagePropertyDNGColorMatrix1, kCGImagePropertyDNGColorMatrix2,
                kCGImagePropertyDNGAsShotNeutral, kCGImagePropertyDNGBaselineExposure,
                kCGImagePropertyDNGCalibrationIlluminant1, kCGImagePropertyDNGCalibrationIlluminant2,
                kCGImagePropertyDNGActiveArea, kCGImagePropertyDNGNoiseReductionApplied, kCGImagePropertyDNGNoiseProfile,
                kCGImagePropertyDNGOpcodeList1, kCGImagePropertyDNGOpcodeList2, kCGImagePropertyDNGOpcodeList3,
                kCGImagePropertyDNGLensInfo, kCGImagePropertyIPTCByline, kCGImagePropertyIPTCCopyrightNotice,
            ].reduce(into: []) { $0.insert($1 as String) }
            for field in MetadataField.catalog {
                for key in field.imageIOKeys {
                    #expect(constants.contains(key.key), "\(field.name): \(key)")
                }
            }
        }
    }

}

extension ImageIOTests {
    struct ImageIOReadBackTests {
        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func encodedFilesReadBackCleanForTheFirstLaunchPlan(format: PhotoFormat) throws {
            let plan = MetadataPlan()
            let source: [String: Any] = [
                "{Exif}": ["ExposureTime": 0.01, "DateTimeOriginal": "2026:11:12 00:11:51"], "{TIFF}": ["Make": "Apple"],
            ]
            let settings = try #require(EncodingSettings(format: format))
            let data = try PhotoEncoder.encode(
                try testImage(), settings: settings, properties: plan.properties(for: format, from: source, orientation: 1))
            let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: data))
            let violations = MetadataVerifier.violations(
                in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
            #expect(violations.isEmpty, "\(violations)")
            #expect(readBack.imageIOKeys.contains(ImageIOKey(nil, "Orientation")))
            #expect(!readBack.imageIOKeys.contains(ImageIOKey("{Exif}", "ExposureTime")))
            #expect(!readBack.imageIOKeys.contains(ImageIOKey("{TIFF}", "Make")))
        }

        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func everyCustomItemReadsBackClean(format: PhotoFormat) throws {
            var settings = MetadataSettings()
            for item in MetadataItem.allCases where item != .location && item != .makerNotes { settings.set(item, isOn: true) }
            settings.ownerName = "A. Person"
            settings.copyrightNotice = "A. Person"
            let plan = MetadataPlan(settings: settings, appVersion: "0.2.0")
            let source: [String: Any] = [
                "{Exif}": [
                    "ExposureTime": 0.01, "FNumber": 1.78, "ISOSpeedRatings": [250], "DateTimeOriginal": "2026:11:12 00:11:51",
                    "SubsecTimeOriginal": "473", "OffsetTimeOriginal": "-05:00", "LensModel": "back camera",
                ] as [String: Any],
                "{TIFF}": ["Make": "Apple", "Model": "iPhone", "Software": "27.2.1", "DateTime": "2026:11:12 00:11:51"],
            ]
            let encoding = try #require(EncodingSettings(format: format))
            let data = try PhotoEncoder.encode(
                try testImage(), settings: encoding, properties: plan.properties(for: format, from: source, orientation: 1))
            let readBack = try ImageIOReadBack().readBack(PhotoFile(format: format, data: data))
            let violations = MetadataVerifier.violations(
                in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
            #expect(violations.isEmpty, "\(violations)")
            #expect(readBack.imageIOKeys.contains(ImageIOKey("{TIFF}", "Software")))
        }

        @Test func aFileThatIsntItsFormatIsRejected() throws {
            let jpeg = try PhotoEncoder.encode(try testImage(), typeIdentifier: "public.jpeg", options: [:])
            #expect(throws: CaptureError.metadataNotAllowed) { try ImageIOReadBack().readBack(PhotoFile(format: .heif, data: jpeg)) }
            #expect(throws: CaptureError.metadataNotAllowed) { try ImageIOReadBack().readBack(PhotoFile(format: .raw, data: Data([1, 2]))) }
        }

        @Test func aFileWithTwoImagesIsRejected() throws {
            let output = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(output, "public.heic" as CFString, 2, nil))
            CGImageDestinationAddImage(destination, try testImage(), nil)
            CGImageDestinationAddImage(destination, try testImage(), nil)
            #expect(CGImageDestinationFinalize(destination))
            #expect(throws: CaptureError.metadataNotAllowed) {
                try ImageIOReadBack().readBack(PhotoFile(format: .heif, data: output as Data))
            }
        }

        /// ImageIO can't write DNG, which is why a DNG's metadata is written by AVFoundation's
        /// replacement metadata instead (docs/ARCHITECTURE.md, "From capture to Photos").
        @Test func imageIOCantWriteDNG() {
            let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            #expect(!types.contains("com.adobe.raw-image"))
            #expect(types.contains("public.heic") && types.contains("public.jpeg"))
            #expect(CGImageDestinationCreateWithData(NSMutableData(), "com.adobe.raw-image" as CFString, 1, nil) == nil)
        }

        @Test func keysAreFlattenedAndSorted() {
            let keys = ImageIOReadBack.keys(of: ["Depth": 8, "{Exif}": ["B": 1, "A": 2], "Orientation": 1])
            #expect(keys == [ImageIOKey(nil, "Depth"), ImageIOKey(nil, "Orientation"), ImageIOKey("{Exif}", "A"), ImageIOKey("{Exif}", "B")])
            #expect(ImageIOReadBack.expectedType(of: .raw) == "com.adobe.raw-image")
        }
    }

}

/// A renderer that returns a fixed image, or fails.
struct FakeRenderer: RAWRendering {
    let image: CGImage?
    let properties: [String: Any]

    func render(_ dng: Data, look: DevelopedLook) throws(CaptureError) -> RenderedRAW {
        guard let image else { throw .developmentFailed }
        return RenderedRAW(image: image, properties: properties)
    }
}

extension FakeRenderer: @unchecked Sendable {}

extension ImageIOTests {
    struct RAWDeveloperTests {
        static let raw = PhotoFile(format: .raw, data: Data([0x49, 0x49]))

        @Test(arguments: [PhotoFormat.heif, .jpeg])
        func developsAnUprightFileWithAllowlistedMetadata(format: PhotoFormat) async throws {
            var settings = MetadataSettings()
            settings.set(.exposureSettings, isOn: true)
            let plan = MetadataPlan(settings: settings)
            let source: [String: Any] = [
                "Orientation": 6, "{Exif}": ["ExposureTime": 0.01], "{TIFF}": ["Make": "Apple", "Orientation": 6],
                "{DNG}": ["UniqueCameraModel": "iPhone17,2 back camera"],
            ]
            let developer = RAWDeveloper(renderer: FakeRenderer(image: try testImage(), properties: source))
            let file = try await developer.develop(Self.raw, to: format, look: .standard, metadata: plan)
            #expect(file.format == format)
            let source2 = try #require(CGImageSourceCreateWithData(file.data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source2, 0, nil) as? [String: Any])
            #expect(properties["Orientation"] as? Int == 1)
            #expect((properties["{Exif}"] as? [String: Any])?["ExposureTime"] as? Double == 0.01)
            #expect((properties["{TIFF}"] as? [String: Any])?["Make"] == nil)
            if format == .heif { #expect(properties["Depth"] as? Int == 10) }
            let readBack = try ImageIOReadBack().readBack(file)
            #expect(
                MetadataVerifier.violations(in: readBack, allowlist: plan.allowlist(for: format, signed: false), expectedRawImageData: nil)
                    .isEmpty)
        }

        @Test func failuresAreDevelopmentFailures() async throws {
            let failing = RAWDeveloper(renderer: FakeRenderer(image: nil, properties: [:]))
            await #expect(throws: CaptureError.developmentFailed) {
                try await failing.develop(Self.raw, to: .heif, look: .flat, metadata: MetadataPlan())
            }
            let working = RAWDeveloper(renderer: FakeRenderer(image: try testImage(), properties: [:]))
            await #expect(throws: CaptureError.developmentFailed) {
                try await working.develop(Self.raw, to: .raw, look: .standard, metadata: MetadataPlan())
            }
            #expect(throws: CaptureError.developmentFailed) {
                try PhotoEncoder.encode(try testImage(), typeIdentifier: "org.example.none", options: [:])
            }
            _ = RAWDeveloper()
        }
    }
}

/// Opt-in check with a real DNG, which can't be committed (docs/TESTING.md, "Developed looks").
/// Run the unit tests with `TEST_RUNNER_NOPE_TEST_DNG=/path/to/photo.dng`. It proves the flat
/// look has no tone curve: doubling the exposure doubles every mid-tone value in linear light,
/// while the standard look's curve bends them.
extension ImageIOTests {
    struct DevelopedLookTests {
        /// The DNG to use, from the environment.
        static let dngPath = ProcessInfo.processInfo.environment["NOPE_TEST_DNG"]

        /// The median ratio of mid-tone values (green channel, linear Display P3) between a
        /// render at +1 EV and one at 0 EV.
        static func exposureRatio(_ dng: Data, look: DevelopedLook) throws -> Float {
            let linear = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
            let context = CIContext(options: [.workingColorSpace: linear])
            func render(exposure: Float) throws -> [Float] {
                let filter = try #require(CIRAWFilter(imageData: dng, identifierHint: "com.adobe.raw-image"))
                CoreImageRAWRenderer.configure(filter, look: look)
                filter.exposure = exposure
                filter.scaleFactor = 0.125
                let image = try #require(filter.outputImage)
                let width = Int(image.extent.width), height = Int(image.extent.height)
                var pixels = [Float](repeating: 0, count: width * height * 4)
                context.render(
                    image, toBitmap: &pixels, rowBytes: width * 16, bounds: image.extent, format: .RGBAf, colorSpace: linear)
                return pixels
            }
            let base = try render(exposure: 0), brighter = try render(exposure: 1)
            let ratios = stride(from: 1, to: base.count, by: 4).filter { base[$0] > 0.005 && base[$0] < 0.2 }
                .map { brighter[$0] / base[$0] }.sorted()
            return try #require(ratios.isEmpty ? nil : ratios[ratios.count / 2])
        }

        @Test(.enabled(if: dngPath != nil))
        func flatIsLinearAndStandardHasACurve() throws {
            let dng = try Data(contentsOf: URL(fileURLWithPath: try #require(Self.dngPath)))
            let flat = try Self.exposureRatio(dng, look: .flat)
            let standard = try Self.exposureRatio(dng, look: .standard)
            #expect(abs(flat - 2) < 0.05, "flat: \(flat)")
            #expect(abs(standard - 2) > 0.1, "standard: \(standard)")
        }
    }
}
