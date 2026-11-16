import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import NopeCore
@testable import NopeDevelop
@testable import NopeSigning

/// The file compatibility matrix (issue #58): every format and setting the app offers, saved by the
/// real save pipeline (`PhotoSaver` with `RAWDeveloper`, `ImageIOReadBack` and
/// `ContentCredentialsSigner`), and each saved file checked the way another app opens it.
///
/// Every fixture is generated here, never captured, so no one's photos are used (AGENTS.md, "Test
/// files and samples"). Only the camera is replaced: the DNG is written by ``FixtureDNG`` from the
/// replacement metadata `MetadataPlan` builds, as AVFoundation does on a device, and the RAW
/// renderer returns a flat 16-bit Display P3 image with the DNG's properties, as
/// `CoreImageRAWRenderer` does. Each file must:
///
/// - open in ImageIO as its own type with exactly one image;
/// - have the expected orientation, bit depth, size and color profile;
/// - carry exactly its allowlisted tags: no violation, and every value the plan wrote is there;
/// - for a signed file, validate with the C2PA library's reader, with
///   `signingCredential.untrusted` (the anonymous per-photo certificate) the only failure.
///
/// Set `TEST_RUNNER_NOPE_COMPAT_FIXTURES=<directory>` to also write every file there, with a
/// `manifest.tsv`, for the external validators (`scripts/check-file-compat.sh`).
@Suite(.serialized, .timeLimit(.minutes(1)))
struct FileCompatibilityTests {
    @Test(arguments: CompatibilityCase.metadataClasses)
    func metadataSwitchClasses(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.lenses)
    func everyLens(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.fileOptions)
    func everyFileOption(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.sizes)
    func everyCopySizeAndPhotoSize(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.processedFallbacks)
    func processedFallbacks(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.orientations)
    func orientationsAndMirroring(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.locations)
    func locations(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    @Test(arguments: CompatibilityCase.series)
    func bracketBurstAndAstroFrames(_ compatibilityCase: CompatibilityCase) async throws {
        try await CompatibilityRun.check(compatibilityCase)
    }

    /// The matrix covers every option the app offers, so a new option can't be added without a
    /// fixture for it.
    @Test func theMatrixCoversEveryOption() {
        let all = CompatibilityCase.all
        #expect(Set(all.map(\.options.heifQuality)) == Set(CompressionQuality.allCases))
        #expect(Set(all.map(\.options.jpegQuality)) == Set(CompressionQuality.allCases))
        #expect(Set(all.map(\.options.heifBitDepth)) == Set(HEIFBitDepth.allCases))
        #expect(Set(all.map(\.options.colorSpace)) == Set(OutputColorSpace.allCases))
        #expect(Set(all.map(\.options.size)) == Set(OutputSize.allCases))
        // A larger photo size than the default, chosen per lens, only changes a processed
        // fallback (Bayer RAW is always the sensor's binned size; `Lens.photoSizeChoices`).
        #expect(Set(all.filter { $0.photoSize != nil }.compactMap(\.fallback)) == Set(ProcessedFallback.allCases))
        #expect(Set(all.map(\.look)) == Set(DevelopedLook.allCases))
        #expect(Set(all.compactMap(\.fallback)) == Set(ProcessedFallback.allCases))
        #expect(Set(all.map(\.lens.id)) == Set(CompatibilityLens.all.map(\.id)))
        let items = Set(CompatibilityCase.metadataClasses.flatMap(\.metadata.enabledItems))
        #expect(items == Set(MetadataItem.allCases))
        #expect(Set(all.map(\.metadata.signsPhotos)) == [true, false])
        #expect(Set(all.map(\.orientation)) == Set(1...8))
        #expect(Set(all.map(\.mirrored)) == [true, false])
        for format in PhotoFormat.allCases {
            #expect(all.contains { $0.formats.contains(format) && $0.fallback == nil })
        }
        #expect(Set(all.map(\.name)).count == all.count)
    }
}

/// One lens the fixtures describe: the names the system writes for it.
struct CompatibilityLens: Sendable, Hashable {
    let id: Lens.ID
    let uniqueCameraModel: String
    let lensModel: String
    let focalLength: Double
    let fNumber: Double

    /// The four lens kinds the app lists (`Lens.Kind`), with generic names.
    static let all: [CompatibilityLens] = [
        CompatibilityLens(
            id: "ultraWide", uniqueCameraModel: "Fixture back ultra wide camera",
            lensModel: "Fixture back ultra wide camera 2.2mm f/2.2", focalLength: 2.2, fNumber: 2.2),
        CompatibilityLens(
            id: "wide", uniqueCameraModel: "Fixture back camera", lensModel: "Fixture back camera 6.8mm f/1.78",
            focalLength: 6.8, fNumber: 1.78),
        CompatibilityLens(
            id: "telephoto", uniqueCameraModel: "Fixture back telephoto camera",
            lensModel: "Fixture back telephoto camera 15.7mm f/2.8", focalLength: 15.7, fNumber: 2.8),
        CompatibilityLens(
            id: "front", uniqueCameraModel: "Fixture front camera", lensModel: "Fixture front camera 2.7mm f/1.9",
            focalLength: 2.7, fNumber: 1.9),
    ]

    static let wide = all[1]
    static let front = all[3]
}

/// An exposure, as the system's metadata reports it.
struct CompatibilityExposure: Sendable, Hashable {
    /// Seconds.
    let time: Double
    let iso: Int
    /// EV.
    let bias: Double

    static let normal = CompatibilityExposure(time: 0.01, iso: 250, bias: 0)
}

/// One row of the matrix: what is saved, and how.
struct CompatibilityCase: Sendable, CustomTestStringConvertible {
    let name: String
    var metadata = MetadataSettings()
    var formats: Set<PhotoFormat> = [.raw, .heif, .jpeg]
    var look = DevelopedLook.standard
    var options = DevelopedFileOptions()
    /// A processed fallback instead of a Bayer RAW photo.
    var fallback: ProcessedFallback?
    /// The processed fallback's size when the person chose a larger photo size for the lens
    /// (issue #57), or `nil` for the fixture's default size.
    var photoSize: PhotoDimensions?
    var lens = CompatibilityLens.wide
    /// The orientation the system reports, 1 to 8.
    var orientation = 6
    /// Front camera photos saved mirrored (issue #45).
    var mirrored = false
    var location: PhotoLocation?
    var exposure = CompatibilityExposure.normal
    /// The frame's fraction of a second, so frames of a series differ.
    var subsecond = "473"

    var testDescription: String { name }

    /// Every case.
    static var all: [CompatibilityCase] {
        metadataClasses + lenses + fileOptions + sizes + processedFallbacks + orientations + locations + series
    }

    /// A location south of the equator, west of Greenwich and below sea level, so every
    /// reference tag is the non-default one.
    static let location = PhotoLocation(latitude: -33.5, longitude: -70.25, altitude: -4)

    /// Settings with every item on, a name and a copyright.
    static var allOn: MetadataSettings {
        var settings = MetadataSettings()
        for item in MetadataItem.allCases { settings.set(item, isOn: true) }
        settings.ownerName = "A. Person"
        settings.copyrightNotice = "© A. Person"
        return settings
    }

    /// The switch classes: first launch, each item alone, and every item on; signed and unsigned.
    static var metadataClasses: [CompatibilityCase] {
        var classes: [(String, MetadataSettings)] = [("first-launch", MetadataSettings())]
        for item in MetadataItem.allCases {
            var settings = MetadataSettings()
            settings.set(item, isOn: true)
            if item == .nameAndCopyright {
                settings.ownerName = "A. Person"
                settings.copyrightNotice = "© A. Person"
            }
            classes.append(("only-\(item.rawValue)", settings))
        }
        classes.append(("all-on", allOn))
        return classes.flatMap { name, settings in
            [true, false].map { signed in
                var metadata = settings
                metadata.signsPhotos = signed
                var result = CompatibilityCase(name: "class-\(name)-\(signed ? "signed" : "unsigned")", metadata: metadata)
                if settings.isOn(.location) { result.location = location }
                return result
            }
        }
    }

    /// Every lens, with every item on, signed.
    static var lenses: [CompatibilityCase] {
        CompatibilityLens.all.map { lens in
            CompatibilityCase(name: "lens-\(lens.id)", metadata: allOn, lens: lens, location: location)
        }
    }

    /// Every compression, HEIF bit depth, color space and look, signed. The JPEG takes the same
    /// compression as the HEIF, so each JPEG encoding is covered too.
    static var fileOptions: [CompatibilityCase] {
        var cases: [CompatibilityCase] = []
        for quality in CompressionQuality.allCases {
            for depth in HEIFBitDepth.allCases {
                for space in OutputColorSpace.allCases {
                    for look in DevelopedLook.allCases {
                        var options = DevelopedFileOptions()
                        options.heifQuality = quality
                        options.jpegQuality = quality
                        options.heifBitDepth = depth
                        options.colorSpace = space
                        cases.append(
                            CompatibilityCase(
                                name: "options-\(quality.rawValue)-\(depth.rawValue)bit-\(space.rawValue)-\(look.rawValue)",
                                formats: [.heif, .jpeg], look: look, options: options))
                    }
                }
            }
        }
        return cases
    }

    /// Every copy size, for the HEIF and JPEG with every item on, signed and unsigned; and the
    /// processed fallback HEIF and JPEG at a larger, non-square photo size, as a lens without
    /// Bayer RAW gives when the person chooses its larger size.
    static var sizes: [CompatibilityCase] {
        var cases: [CompatibilityCase] = []
        for size in OutputSize.allCases {
            for signed in [true, false] {
                var options = DevelopedFileOptions()
                options.size = size
                var metadata = allOn
                metadata.signsPhotos = signed
                cases.append(
                    CompatibilityCase(
                        name: "size-\(size.rawValue)-\(signed ? "signed" : "unsigned")", metadata: metadata, options: options,
                        location: location))
            }
        }
        for fallback in ProcessedFallback.allCases {
            cases.append(
                CompatibilityCase(
                    name: "photo-size-large-fallback-\(fallback == .heif ? "heif" : "jpeg")", metadata: allOn, fallback: fallback,
                    photoSize: PhotoDimensions(width: 512, height: 384), location: location))
        }
        return cases
    }

    /// The processed fallback HEIF and JPEG, first launch and every item on, signed and unsigned.
    static var processedFallbacks: [CompatibilityCase] {
        ProcessedFallback.allCases.flatMap { fallback in
            [("first-launch", MetadataSettings()), ("all-on", allOn)].flatMap { name, settings in
                [true, false].map { signed in
                    var metadata = settings
                    metadata.signsPhotos = signed
                    let fallbackName = fallback == .heif ? "heif" : "jpeg"
                    return CompatibilityCase(
                        name: "fallback-\(fallbackName)-\(name)-\(signed ? "signed" : "unsigned")", metadata: metadata,
                        fallback: fallback, location: settings.isOn(.location) ? location : nil)
                }
            }
        }
    }

    /// Every orientation, as taken and mirrored (front camera), for the RAW and its copies, and
    /// mirrored processed fallbacks.
    static var orientations: [CompatibilityCase] {
        var cases: [CompatibilityCase] = []
        for orientation in 1...8 {
            for mirrored in [false, true] {
                cases.append(
                    CompatibilityCase(
                        name: "orientation-\(orientation)\(mirrored ? "-mirrored" : "")",
                        lens: mirrored ? .front : .wide, orientation: orientation, mirrored: mirrored))
            }
        }
        for fallback in ProcessedFallback.allCases {
            cases.append(
                CompatibilityCase(
                    name: "orientation-6-mirrored-fallback-\(fallback == .heif ? "heif" : "jpeg")", fallback: fallback,
                    lens: .front, mirrored: true))
        }
        return cases
    }

    /// Location on (with and without an altitude), and off with a location available.
    static var locations: [CompatibilityCase] {
        var on = MetadataSettings()
        on.set(.location, isOn: true)
        return [
            CompatibilityCase(name: "location-on", metadata: on, location: location),
            CompatibilityCase(
                name: "location-on-no-altitude", metadata: on,
                location: PhotoLocation(latitude: 48.85, longitude: 2.35, altitude: nil)),
            CompatibilityCase(name: "location-off", location: location),
        ]
    }

    /// Frames of a bracket (−2, 0, +2 EV), a burst and an Astro run, with exposure settings on so
    /// each frame's values are in its files.
    static var series: [CompatibilityCase] {
        var settings = MetadataSettings()
        for item in [MetadataItem.exposureSettings, .dateAndTime, .subSecondTime] { settings.set(item, isOn: true) }
        var cases: [CompatibilityCase] = []
        for (index, bias) in [-2.0, 0, 2].enumerated() {
            cases.append(
                CompatibilityCase(
                    name: "bracket-\(index + 1)", metadata: settings,
                    exposure: CompatibilityExposure(time: 0.01 * pow(2, bias), iso: 250, bias: bias),
                    subsecond: "\(100 + index)"))
        }
        for frame in 1...3 {
            cases.append(
                CompatibilityCase(name: "burst-\(frame)", metadata: settings, subsecond: "\(200 + frame * 100)"))
        }
        for frame in 1...3 {
            cases.append(
                CompatibilityCase(
                    name: "astro-\(frame)", metadata: settings,
                    exposure: CompatibilityExposure(time: 10, iso: 3200, bias: 0), subsecond: "\(frame)"))
        }
        return cases
    }

    /// The metadata the system reports for the photo, as `AVCapturePhoto.metadata` does: what
    /// `MetadataPlan` copies allowlisted values from. Generic values, no device's.
    var systemMetadata: [String: Any] {
        let date = "2026:11:14 10:00:00"
        return [
            "Orientation": orientation,
            "{TIFF}": [
                "Make": "Fixture", "Model": "Fixture phone", "Software": "27.2", "DateTime": date,
                "HostComputer": "Fixture phone", "Orientation": orientation,
            ] as [String: Any],
            "{Exif}": [
                "ExposureTime": exposure.time, "FNumber": lens.fNumber, "ISOSpeedRatings": [exposure.iso],
                "ExposureBiasValue": exposure.bias, "ExposureProgram": 2, "MeteringMode": 5, "Flash": 16,
                "FocalLength": lens.focalLength, "FocalLenIn35mmFilm": 24, "WhiteBalance": 0, "ExposureMode": 0,
                "SceneCaptureType": 0, "SensingMethod": 2, "BrightnessValue": 3.25, "DateTimeOriginal": date,
                "DateTimeDigitized": date, "SubsecTimeOriginal": subsecond, "SubsecTimeDigitized": subsecond,
                "OffsetTimeOriginal": "-05:00", "OffsetTimeDigitized": "-05:00", "LensMake": "Fixture",
                "LensModel": lens.lensModel,
                "LensSpecification": [lens.focalLength, lens.focalLength, lens.fNumber, lens.fNumber],
            ] as [String: Any],
            "{DNG}": [
                "DNGVersion": [1, 6, 0, 0], "DNGBackwardVersion": [1, 4, 0, 0],
                "UniqueCameraModel": lens.uniqueCameraModel,
                "ColorMatrix1": [0.75, -0.25, -0.05, -0.4, 1.2, 0.2, -0.05, 0.15, 0.6],
                "ColorMatrix2": [0.7, -0.2, -0.1, -0.45, 1.25, 0.2, -0.1, 0.2, 0.55], "AsShotNeutral": [0.5, 1, 0.7],
                "CalibrationIlluminant1": 17, "CalibrationIlluminant2": 21, "BaselineExposure": 0.25,
                "BlackLevel": 528, "WhiteLevel": 4095,
                "LensInfo": [lens.focalLength, lens.focalLength, lens.fNumber, lens.fNumber],
            ] as [String: Any],
            "{MakerApple}": ["1": 14] as [String: Any],
        ]
    }
}

/// A renderer standing in for `CoreImageRAWRenderer`, which needs a camera DNG: it returns a flat
/// 256 × 256, 16-bit Display P3 image and the DNG's own ImageIO properties, as the real one does.
struct FixtureRenderer: RAWRendering {
    func render(_ dng: Data, look: DevelopedLook) throws(CaptureError) -> RenderedRAW {
        guard let source = CGImageSourceCreateWithData(dng as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let image = CompatibilityRun.image()
        else { throw .developmentFailed }
        return RenderedRAW(image: image, properties: properties)
    }
}

/// Keeps what the pipeline adds to Photos.
final class RecordingLibrary: PhotoLibrary, @unchecked Sendable {
    private let lock = NSLock()
    private var added: [PhotoLibraryAsset] = []
    var files: [PhotoFile] { lock.withLock { added.flatMap { [$0.primary] + ($0.alternate.map { [$0] } ?? []) } } }
    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) { lock.withLock { added += assets } }
}

/// Runs one case through the save pipeline and checks every file it saves.
enum CompatibilityRun {
    static let appVersion = "0.2.0"

    /// The fixture's size: the DNG's, and the processed fallback's by default.
    static let defaultSize = PhotoDimensions(width: Int(FixtureDNG.size), height: Int(FixtureDNG.size))

    /// A flat 16-bit Display P3 image, 256 × 256 by default, as the RAW renderer returns.
    ///
    /// - Parameter size: The image's size.
    static func image(size: PhotoDimensions = defaultSize) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
            let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 16, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        else { return nil }
        context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    /// The plan the capture backend builds for the photo (`CameraModel` sets the mirroring and
    /// location of each capture).
    static func capturePlan(for compatibilityCase: CompatibilityCase) -> MetadataPlan {
        var plan = MetadataPlan(settings: compatibilityCase.metadata, appVersion: appVersion)
        plan.mirrorsHorizontally = compatibilityCase.mirrored
        plan.location = compatibilityCase.location
        return plan
    }

    /// The photo the camera returns, with its metadata written from the capture plan.
    static func capturedPhoto(for compatibilityCase: CompatibilityCase) throws -> CapturedPhoto {
        let plan = capturePlan(for: compatibilityCase)
        let dimensions = compatibilityCase.photoSize ?? defaultSize
        if let fallback = compatibilityCase.fallback {
            // The fallback is the system's own processed file, written with the replacement
            // metadata; here the system encoder writes the same dictionary.
            let format: PhotoFormat = fallback == .heif ? .heif : .jpeg
            let settings = try #require(EncodingSettings(format: format))
            let data = try PhotoEncoder.encode(
                try #require(image(size: dimensions)), settings: settings,
                properties: plan.properties(for: format, from: compatibilityCase.systemMetadata))
            return CapturedPhoto(
                data: data, format: .processedFallback(fallback), lensID: compatibilityCase.lens.id, dimensions: dimensions,
                exposureDuration: compatibilityCase.exposure.time, iso: Double(compatibilityCase.exposure.iso))
        }
        let dng = try FixtureDNG.make(properties: plan.properties(for: .raw, from: compatibilityCase.systemMetadata))
        return CapturedPhoto(
            data: dng, format: .bayerRAW(pixelFormat: "bgg4"), lensID: compatibilityCase.lens.id, dimensions: dimensions,
            exposureDuration: compatibilityCase.exposure.time, iso: Double(compatibilityCase.exposure.iso),
            rawImageData: MetadataFileReader.rawImageData(ofDNG: dng))
    }

    /// Saves the case with the real pipeline and checks every saved file.
    static func check(_ compatibilityCase: CompatibilityCase) async throws {
        let library = RecordingLibrary()
        let saver = PhotoSaver(
            developer: RAWDeveloper(renderer: FixtureRenderer()),
            signer: ContentCredentialsSigner(
                keyProvider: SimulatorSoftwareKeyProvider(), generator: ClaimGenerator(version: appVersion)),
            reader: ImageIOReadBack(), library: library, appVersion: appVersion)
        var settings = SaveSettings()
        for format in PhotoFormat.allCases { settings.setFormat(format, isSelected: true) }
        for format in PhotoFormat.allCases where !compatibilityCase.formats.contains(format) {
            settings.setFormat(format, isSelected: false)
        }
        settings.metadata = compatibilityCase.metadata
        settings.developedLook = compatibilityCase.look
        settings.fileOptions = compatibilityCase.options
        settings.mirrorsFrontCamera = compatibilityCase.mirrored

        let photo = try capturedPhoto(for: compatibilityCase)
        let saved: SavedPhoto
        do {
            saved = try await saver.save(photo, settings: settings)
        } catch {
            try await diagnose(photo, case: compatibilityCase, settings: settings)
            throw error
        }
        let signed = compatibilityCase.metadata.signsPhotos
        #expect(saved.signature == (signed ? .signed : .unsigned(.turnedOff)), "\(compatibilityCase.name)")

        let files = library.files
        let expectedFormats: Set<PhotoFormat> =
            compatibilityCase.fallback.map { [$0 == .heif ? .heif : .jpeg] } ?? compatibilityCase.formats
        #expect(Set(files.map(\.format)) == expectedFormats, "\(compatibilityCase.name)")
        #expect(files.count == expectedFormats.count, "\(compatibilityCase.name)")
        let rawProperties = try photo.format.isBayerRAW ? imageIOProperties(of: photo.data) : [:]
        for file in files {
            let written = try writtenProperties(for: file, photo: photo, rawProperties: rawProperties, case: compatibilityCase)
            try FileCheck.check(file, case: compatibilityCase, written: written, signed: signed)
            try FixtureExport.write(file, case: compatibilityCase, signed: signed)
        }
    }

    /// Records why a photo wasn't saved: each unsigned file's read-back violations.
    static func diagnose(_ photo: CapturedPhoto, case compatibilityCase: CompatibilityCase, settings: SaveSettings)
        async throws
    {
        let plan = MetadataPlan(settings: compatibilityCase.metadata, appVersion: appVersion)
        var files = [PhotoFile(format: photo.format.isBayerRAW ? .raw : .heif, data: photo.data)]
        if photo.format.isBayerRAW {
            for format in [PhotoFormat.heif, .jpeg] where compatibilityCase.formats.contains(format) {
                files.append(
                    try await RAWDeveloper(renderer: FixtureRenderer()).develop(
                        files[0], to: format, look: settings.developedLook, options: settings.fileOptions, metadata: plan))
            }
        }
        for file in files {
            guard let readBack = try? ImageIOReadBack().readBack(file) else {
                Issue.record("\(compatibilityCase.name) \(file.format): ImageIO doesn't open it as one \(file.format)")
                continue
            }
            let violations = MetadataVerifier.violations(
                in: readBack, allowlist: plan.allowlist(for: file.format, signed: false),
                expectedRawImageData: photo.rawImageData)
            Issue.record("\(compatibilityCase.name) \(file.format): \(violations)")
        }
    }

    /// What the pipeline asked to be written into a file.
    static func writtenProperties(
        for file: PhotoFile, photo: CapturedPhoto, rawProperties: [String: Any], case compatibilityCase: CompatibilityCase
    ) throws -> [String: Any] {
        let capture = capturePlan(for: compatibilityCase)
        if compatibilityCase.fallback != nil {
            return capture.properties(for: file.format, from: compatibilityCase.systemMetadata)
        }
        if file.format == .raw { return capture.properties(for: .raw, from: compatibilityCase.systemMetadata) }
        return MetadataPlan(settings: compatibilityCase.metadata, appVersion: appVersion).properties(
            for: file.format, from: rawProperties, orientation: RAWDeveloper.uprightOrientation)
    }

    /// A file's ImageIO properties.
    static func imageIOProperties(of data: Data) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }
}

/// The checks every saved file must pass.
enum FileCheck {
    /// The orientation ImageIO must report for a file.
    static func expectedOrientation(of file: PhotoFile, case compatibilityCase: CompatibilityCase) -> Int {
        if file.format != .raw && compatibilityCase.fallback == nil { return RAWDeveloper.uprightOrientation }
        let orientation = compatibilityCase.orientation
        return compatibilityCase.mirrored ? MetadataPlan.mirroredOrientation(orientation) : orientation
    }

    /// The bits per channel ImageIO must report for a file.
    static func expectedDepth(of file: PhotoFile, case compatibilityCase: CompatibilityCase) -> Int {
        switch file.format {
        case .raw: 16
        case .jpeg: 8
        case .heif:
            compatibilityCase.fallback == nil ? compatibilityCase.options.heifBitDepth.rawValue : HEIFBitDepth.ten.rawValue
        }
    }

    /// The size a HEIF or JPEG must decode at: the fallback's photo size, or the RAW's size
    /// scaled by the copy size.
    static func expectedSize(of file: PhotoFile, case compatibilityCase: CompatibilityCase) -> PhotoDimensions {
        guard compatibilityCase.fallback == nil else { return compatibilityCase.photoSize ?? CompatibilityRun.defaultSize }
        return compatibilityCase.options.size.dimensions(of: CompatibilityRun.defaultSize)
    }

    /// The color space a HEIF or JPEG must decode in.
    static func expectedColorSpace(of file: PhotoFile, case compatibilityCase: CompatibilityCase) -> CFString {
        compatibilityCase.fallback == nil && compatibilityCase.options.colorSpace == .sRGB
            ? CGColorSpace.sRGB : CGColorSpace.displayP3
    }

    /// Checks one file.
    static func check(
        _ file: PhotoFile, case compatibilityCase: CompatibilityCase, written: [String: Any], signed: Bool
    ) throws {
        let label = "\(compatibilityCase.name) \(file.format)"
        // Opens as its own type with one image.
        #expect(ImageIOType.read(file.data) == ImageIOType(type: ImageIOType.of(file.format), count: 1), "\(label)")
        let properties = try CompatibilityRun.imageIOProperties(of: file.data)
        #expect(
            properties["Orientation"] as? Int == expectedOrientation(of: file, case: compatibilityCase),
            "\(label): orientation \(String(describing: properties["Orientation"]))")
        #expect(
            properties["Depth"] as? Int == expectedDepth(of: file, case: compatibilityCase),
            "\(label): depth \(String(describing: properties["Depth"]))")
        if file.format != .raw {
            // ImageIO can't decode a hand-built DNG's pixels (docs/TESTING.md), so the image is
            // decoded for HEIF and JPEG only.
            let source = try #require(CGImageSourceCreateWithData(file.data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "\(label)")
            let size = expectedSize(of: file, case: compatibilityCase)
            #expect(image.width == size.width && image.height == size.height, "\(label): \(image.width) × \(image.height)")
            // EXIF pixel dimensions, where the file has them, state the pixels it holds.
            let exif = properties["{Exif}"] as? [String: Any]
            for (key, side) in [("PixelXDimension", size.width), ("PixelYDimension", size.height)] {
                if let value = exif?[key] as? Int { #expect(value == side, "\(label): \(key) \(value)") }
            }
            let space = expectedColorSpace(of: file, case: compatibilityCase)
            #expect(image.colorSpace?.name == space, "\(label): \(String(describing: image.colorSpace?.name))")
            #expect(properties["ProfileName"] is String, "\(label): no color profile")
        }

        // Exactly the allowlisted tags: nothing extra (the fail-closed read-back) and nothing the
        // plan wrote missing.
        let plan = MetadataPlan(settings: compatibilityCase.metadata, appVersion: CompatibilityRun.appVersion)
        let readBack = try ImageIOReadBack().readBack(file)
        let violations = MetadataVerifier.violations(
            in: readBack, allowlist: plan.allowlist(for: file.format, signed: signed),
            expectedRawImageData: file.format == .raw ? readBack.file.rawImageData : nil)
        #expect(violations.isEmpty, "\(label): \(violations)")
        let present = Set(readBack.file.inventory.tags.map { MetadataAllowlist.TagID($0.directory, $0.tag) })
        let missing = writtenTags(written).subtracting(present)
        #expect(missing.isEmpty, "\(label): written but not in the file: \(missing.sorted { $0.tag < $1.tag })")

        // A signed file validates; an unsigned one has no manifest.
        let kind = SignableFile(file)
        #expect((file.contentCredentials != nil) == signed, "\(label)")
        if signed {
            let report = Report(try validate(file.data, as: kind))
            #expect(report.state == "Valid", "\(label): \(report.json)")
            #expect(report.codes("failure") == ["signingCredential.untrusted"], "\(label): \(report.codes("failure"))")
            #expect(report.codes("success").contains("\(hashCode(for: kind)).match"), "\(label)")
        }
    }

    /// The tag each non-empty value of a property dictionary is written as, from the catalog.
    ///
    /// The tag reader's inventory is compared, not ImageIO's keys: ImageIO leaves out some tags
    /// that are in the file, such as an empty `Make` in a DNG, and `OffsetTimeOriginal` in a DNG
    /// without `DateTimeOriginal` (iOS 27.2 Simulator, 2026-11-14).
    static func writtenTags(_ properties: [String: Any]) -> Set<MetadataAllowlist.TagID> {
        var tags: Set<MetadataAllowlist.TagID> = []
        for key in ImageIOReadBack.keys(of: properties) {
            guard let value = MetadataPlan.value(of: key, in: properties), (value as? String) != "" else { continue }
            guard let field = MetadataField.catalog.first(where: { $0.imageIOKeys.contains(key) }) else { continue }
            tags.insert(MetadataAllowlist.TagID(field.directory, field.tag))
        }
        return tags
    }
}

/// Writes the fixtures for the external validators, when asked.
enum FixtureExport {
    /// The directory, from `TEST_RUNNER_NOPE_COMPAT_FIXTURES`, or `nil` to write nothing.
    static let directory = ProcessInfo.processInfo.environment["NOPE_COMPAT_FIXTURES"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }

    static let lock = NSLock()

    /// Writes one file and its row of `manifest.tsv`: name, format, signed, device-processed.
    static func write(_ file: PhotoFile, case compatibilityCase: CompatibilityCase, signed: Bool) throws {
        guard let directory else { return }
        let fileExtension = switch file.format {
        case .raw: "dng"
        case .heif: "heic"
        case .jpeg: "jpg"
        }
        let name = "\(compatibilityCase.name).\(fileExtension)"
        try lock.withLock {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.data.write(to: directory.appendingPathComponent(name))
            let manifest = directory.appendingPathComponent("manifest.tsv")
            let row = Data("\(name)\t\(file.format.rawValue)\t\(signed)\t\(file.isProcessedByDevice)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: manifest) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: row)
            } else {
                try row.write(to: manifest)
            }
        }
    }
}
