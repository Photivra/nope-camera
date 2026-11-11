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
