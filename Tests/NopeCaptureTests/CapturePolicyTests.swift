import AVFoundation
import NopeCore
import Testing

@testable import NopeCapture

struct CapturePolicyTests {
    static let sizes = [PhotoDimensions(width: 8064, height: 6048), PhotoDimensions(width: 4032, height: 3024)]
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", photoDimensions: sizes)

    @Test func everySwitchIsLeastProcessing() {
        let switches = ProcessingSwitches.leastProcessing
        #expect(switches.qualityPrioritization == .speed)
        #expect(!switches.appleProRAW)
        #expect(!switches.zeroShutterLag)
        #expect(!switches.responsiveCapture)
        #expect(!switches.deferredDelivery)
        #expect(!switches.constantColor)
        #expect(!switches.contentAwareDistortionCorrection)
        #expect(!switches.geometricDistortionCorrection)
        #expect(switches.videoZoomFactor == 1.0)
        #expect(switches.flashMode == .off)
    }

    @Test func rawSessionIsRAWOnlyAtTheSmallestSize() throws {
        let configuration = try #require(CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: Self.wide)))
        #expect(configuration.deviceID == "wide")
        #expect(configuration.maxPhotoDimensions == PhotoDimensions(width: 4032, height: 3024))
        #expect(configuration.switches == .leastProcessing)
        #expect(configuration.photoSettings.rawPixelFormat == 0x6267_6734)
        #expect(configuration.photoSettings.processedFormat == nil)
        #expect(configuration.photoSettings.switches == .leastProcessing)
    }

    @Test func fallbackSessionHasOneProcessedFormat() throws {
        let tele = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, processedFallback: .jpeg)
        let configuration = try #require(CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: tele)))
        #expect(configuration.maxPhotoDimensions == nil)
        #expect(configuration.photoSettings.rawPixelFormat == nil)
        #expect(configuration.photoSettings.processedFormat == .jpeg)
    }

    /// Issue #57: the request's photo size is configured when the lens reports it.
    @Test func aChosenPhotoSizeIsUsedOnlyWhenTheLensReportsIt() throws {
        let front = Lens(id: "front", kind: .front, bayerRAWFormat: nil, photoDimensions: Self.sizes)
        let large = try #require(CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: front, photoSize: Self.sizes[0])))
        #expect(large.maxPhotoDimensions == Self.sizes[0])
        let unknown = try #require(
            CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: front, photoSize: PhotoDimensions(width: 2, height: 1))))
        #expect(unknown.maxPhotoDimensions == Self.sizes[1])
    }

    @Test func fileFormatFollowsThePlan() throws {
        let raw = try #require(CapturePolicy.photoSettings(for: .bayerRAW(pixelFormat: "bgg4")))
        #expect(CapturePolicy.fileFormat(of: raw) == .raw)
        #expect(CapturePolicy.fileFormat(of: try #require(CapturePolicy.photoSettings(for: .processedFallback(.heif)))) == .heif)
        #expect(CapturePolicy.fileFormat(of: try #require(CapturePolicy.photoSettings(for: .processedFallback(.jpeg)))) == .jpeg)
    }

    /// Issue #96: a photo is taken only with the camera its plan was made for, so a lens change
    /// that reconfigured the session while the photo waited fails the photo instead of sending
    /// its settings to another camera.
    @Test func aPlanMatchesOnlyItsOwnCamera() throws {
        let lens = Lens(id: "wide-id", kind: .wide, bayerRAWFormat: "bgg4")
        let configuration = try #require(CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: lens)))
        #expect(configuration.photoSettings.deviceID == "wide-id")
        let withFlash = CapturePolicy.photoSettings(configuration.photoSettings, flashMode: .on)
        #expect(withFlash.deviceID == "wide-id")
        #expect(CapturePolicy.camera("wide-id", matches: withFlash))
        #expect(!CapturePolicy.camera("tele-id", matches: withFlash))
        // A plan not tied to a camera never matches.
        let untied = try #require(CapturePolicy.photoSettings(for: .processedFallback(.heif)))
        #expect(untied.deviceID == nil)
        #expect(!CapturePolicy.camera("wide-id", matches: untied))
        #expect(CapturePolicy.comparisonPlan(for: CaptureRequest(lens: lens)).deviceID == "wide-id")
    }

    @Test func invalidRAWCodeHasNoConfiguration() {
        let lens = Lens(id: "bad", kind: .wide, bayerRAWFormat: "not a code")
        #expect(CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: lens)) == nil)
    }
}

struct PhotoSettingsFactoryTests {
    static let size = PhotoDimensions(width: 4032, height: 3024)

    @Test func rawSettingsAreRAWOnlyDNG() throws {
        let plan = try #require(CapturePolicy.photoSettings(for: .bayerRAW(pixelFormat: "bgg4")))
        let settings = PhotoSettingsFactory.makeSettings(for: plan, maxPhotoDimensions: Self.size)
        #expect(settings.rawPhotoPixelFormatType == 0x6267_6734)
        #expect(settings.rawFileType == .dng)
        #expect(settings.processedFileType == nil)
        #expect(settings.format == nil)
        #expect(settings.photoQualityPrioritization == .speed)
        #expect(settings.flashMode == .off)
        #expect(!settings.isAutoContentAwareDistortionCorrectionEnabled)
        #expect(!settings.isConstantColorEnabled)
        #expect(settings.maxPhotoDimensions.width == 4032 && settings.maxPhotoDimensions.height == 3024)
    }

    @Test(arguments: [(ProcessedFallback.heif, AVVideoCodecType.hevc, AVFileType.heic), (.jpeg, .jpeg, .jpg)])
    func fallbackSettingsHaveOneCodec(fallback: ProcessedFallback, codec: AVVideoCodecType, fileType: AVFileType)
        throws
    {
        let plan = try #require(CapturePolicy.photoSettings(for: .processedFallback(fallback)))
        let settings = PhotoSettingsFactory.makeSettings(for: plan, maxPhotoDimensions: nil)
        #expect(settings.rawPhotoPixelFormatType == 0)
        #expect(settings.processedFileType == fileType)
        #expect(settings.format?[AVVideoCodecKey] as? AVVideoCodecType == codec)
        #expect(settings.photoQualityPrioritization == .speed)
    }

    @Test func emptyPlanFallsBackToHEIF() {
        let plan = PhotoSettingsPlan(rawPixelFormat: nil, processedFormat: nil, switches: .leastProcessing)
        let settings = PhotoSettingsFactory.makeSettings(for: plan, maxPhotoDimensions: nil)
        #expect(settings.processedFileType == .heic)
    }
}
