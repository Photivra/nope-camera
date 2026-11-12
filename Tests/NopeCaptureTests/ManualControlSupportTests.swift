import AVFoundation
import NopeCore
import Testing

@testable import NopeCapture

struct ManualControlSupportTests {
    static let everything = ManualControlSupport(
        customExposure: true, continuousAutoExposure: true, lockedExposure: true, shutterPriority: true,
        isoPriority: true, aperturePriority: true, exposureBiasRange: -8...8, continuousAutoFocus: true,
        lockedFocus: true, lensPositionFocus: true, customWhiteBalance: true, exposureRegion: true)

    @Test func everyAnswerBecomesACapability() {
        let capabilities = Self.everything.capabilities
        #expect(capabilities.supportsManualExposure)
        #expect(capabilities.supportsShutterPriority)
        #expect(capabilities.supportsISOPriority)
        #expect(capabilities.supportsAperturePriority)
        #expect(capabilities.exposureCompensationRange == -8...8)
        #expect(capabilities.supportsExposureLock)
        #expect(capabilities.supportsAutoFocus)
        #expect(capabilities.supportsFocusLock)
        #expect(capabilities.supportsManualFocus)
        #expect(capabilities.supportsManualWhiteBalance)
        #expect(capabilities.meteringModes == [.center, .spot, .wholeFrame])
    }

    @Test func meteringAndCompensationNeedAutoExposure() {
        #expect(ManualControlSupport.none.capabilities == .none)
        let noRegion = ManualControlSupport(
            customExposure: false, continuousAutoExposure: true, lockedExposure: false, shutterPriority: false,
            isoPriority: false, aperturePriority: false, exposureBiasRange: 0...0, continuousAutoFocus: false,
            lockedFocus: false, lensPositionFocus: false, customWhiteBalance: false, exposureRegion: false)
        #expect(noRegion.capabilities.meteringModes == [.center])
        #expect(noRegion.capabilities.exposureCompensationRange == nil)
    }

    @Test func catalogCopiesTheCapabilities() {
        let camera = CameraDeviceDescription(
            uniqueID: "wide", deviceType: .wideAngle, position: .back, isVirtual: false, rawPixelFormats: [],
            supportsHEVC: true, isoRange: 50...800, exposureDurationRange: 0.001...1, aperture: .fixed(1.8),
            maxBracketedPhotoCount: 3, photoDimensions: [], fieldOfViewDegrees: 70, manualControls: Self.everything)
        #expect(LensCatalog.lenses(from: [camera]).first?.manualControls == Self.everything.capabilities)
    }

    @Test func meteringRegions() {
        #expect(MeteringRegion.region(for: .center, minimumWidth: 0.1, minimumHeight: 0.1) == nil)
        #expect(
            MeteringRegion.region(for: .wholeFrame, minimumWidth: 0.1, minimumHeight: 0.1)
                == MeteringRegion(x: 0, y: 0, width: 1, height: 1))
        #expect(
            MeteringRegion.region(for: .spot, minimumWidth: 0.2, minimumHeight: 0.5)
                == MeteringRegion(x: 0.4, y: 0.25, width: 0.2, height: 0.5))
        #expect(
            MeteringRegion.region(for: .spot, minimumWidth: -1, minimumHeight: 3)
                == MeteringRegion(x: 0.5, y: 0, width: 0, height: 1))
    }

    @Test func gainsStayInTheCamerasRange() {
        let gains = WhiteBalanceGains(red: 0.5, green: 2, blue: 9)
        #expect(gains.limited(toMaximum: 4) == WhiteBalanceGains(red: 1, green: 2, blue: 4))
        #expect(gains.limited(toMaximum: 0) == WhiteBalanceGains(red: 1, green: 1, blue: 1))
    }

    @Test func throttleSendsFourReadingsASecond() {
        var throttle = ReadingThrottle()
        let sent = [10, 10.1, 10.25, 10.4, 11].map { throttle.shouldSend(at: $0) }
        #expect(sent == [true, false, true, false, true])
    }

    @Test func bracketSettingsForRAW() {
        let plan = PhotoSettingsPlan(rawPixelFormat: 0x6267_6734, processedFormat: nil, switches: .leastProcessing)
        let frames = [BracketFrame(iso: 100, exposureDuration: 0.01), BracketFrame(iso: 200, exposureDuration: 0.02)]
        let settings = PhotoSettingsFactory.makeBracketSettings(
            for: plan, frames: frames, maxPhotoDimensions: PhotoDimensions(width: 4032, height: 3024))
        #expect(settings.rawPhotoPixelFormatType == 0x6267_6734)
        #expect(settings.processedFileType == nil)
        #expect(settings.photoQualityPrioritization == .speed)
        #expect(!settings.isLensStabilizationEnabled)
        #expect(!settings.isConstantColorEnabled)
        #expect(!settings.isAutoContentAwareDistortionCorrectionEnabled)
        #expect(settings.maxPhotoDimensions.width == 4032)
        let bracketed = settings.bracketedSettings.compactMap { $0 as? AVCaptureManualExposureBracketedStillImageSettings }
        #expect(bracketed.map(\.iso) == [100, 200])
        #expect(bracketed.map { $0.exposureDuration.seconds } == [0.01, 0.02])
    }

    @Test func bracketSettingsForTheFallback() {
        let frames = [BracketFrame(iso: 100, exposureDuration: 0.01)]
        for (format, fileType) in [(ProcessedFallback?.some(.jpeg), AVFileType.jpg), (nil, .heic)] {
            let plan = PhotoSettingsPlan(rawPixelFormat: nil, processedFormat: format, switches: .leastProcessing)
            let settings = PhotoSettingsFactory.makeBracketSettings(for: plan, frames: frames, maxPhotoDimensions: nil)
            #expect(settings.rawPhotoPixelFormatType == 0)
            #expect(settings.processedFileType == fileType)
            #expect(settings.bracketedSettings.count == 1)
        }
    }
}
