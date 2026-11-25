import AVFoundation
import NopeCore
import Testing

@testable import NopeCapture

struct ManualControlSupportTests {
    static let everything = ManualControlSupport(
        customExposure: true, continuousAutoExposure: true, lockedExposure: true, shutterPriority: true,
        isoPriority: true, aperturePriority: true, exposureBiasRange: -8...8, continuousAutoFocus: true,
        lockedFocus: true, lensPositionFocus: true, customWhiteBalance: true, exposureRegion: true, focusPoint: true,
        exposurePoint: true, focusRangeRestriction: true)

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
        #expect(capabilities.supportsFocusPoint)
        #expect(capabilities.supportsExposurePoint)
        #expect(capabilities.supportsNearFocusLimit)
    }

    @Test func pointsAndTheRangeNeedTheAutoModes() {
        let fixedFocus = ManualControlSupport(
            customExposure: false, continuousAutoExposure: false, lockedExposure: false, shutterPriority: false,
            isoPriority: false, aperturePriority: false, exposureBiasRange: 0...0, continuousAutoFocus: false,
            lockedFocus: false, lensPositionFocus: false, customWhiteBalance: false, exposureRegion: false,
            focusPoint: true, exposurePoint: true, focusRangeRestriction: true)
        #expect(!fixedFocus.capabilities.supportsFocusPoint)
        #expect(!fixedFocus.capabilities.supportsExposurePoint)
        #expect(!fixedFocus.capabilities.supportsNearFocusLimit)
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
        let step1 = throttle.decide(at: 10)
        #expect(step1 == .send)
        // Held back: one more is scheduled for the end of the interval, then nothing more.
        let step2 = throttle.decide(at: 10.1)
        #expect(Self.isLater(step2, delay: 0.15, ticket: 0))
        let step3 = throttle.decide(at: 10.2)
        #expect(step3 == .drop)
        // A reading sent before the scheduled one is due makes it unnecessary.
        let step4 = throttle.decide(at: 10.25)
        #expect(step4 == .send)
        let step5 = throttle.sendsLater(0, at: 10.26)
        #expect(!step5)
        let step6 = throttle.decide(at: 10.4)
        #expect(Self.isLater(step6, delay: 0.1, ticket: 1))
        let step7 = throttle.decide(at: 11)
        #expect(step7 == .send)
        let step8 = throttle.sendsLater(1, at: 11.01)
        #expect(!step8)
    }

    /// Whether a decision schedules a reading for later, after about a delay, with a ticket.
    static func isLater(_ decision: ReadingThrottle.Decision, delay: Double, ticket: Int) -> Bool {
        guard case .later(let actual, let actualTicket) = decision else { return false }
        return abs(actual - delay) < 1e-9 && actualTicket == ticket
    }

    @Test func theLastReadingIsSentOnceThingsSettle() {
        // The lens stops at its nearest position inside an interval: without the scheduled
        // reading, its last position would never be sent (docs/design/device-feedback-1.0.md,
        // section 6).
        var throttle = ReadingThrottle()
        let first = throttle.decide(at: 5)
        #expect(first == .send)
        guard case .later(let delay, let ticket) = throttle.decide(at: 5.05) else {
            Issue.record("expected a reading for later")
            return
        }
        #expect(abs(delay - 0.2) < 1e-9)
        let scheduledIsSent = throttle.sendsLater(ticket, at: 5.25)
        #expect(scheduledIsSent)
        // Sent once only, and it counts as the last reading sent.
        let sentAgain = throttle.sendsLater(ticket, at: 5.26)
        #expect(!sentAgain)
        let next = throttle.decide(at: 5.3)
        #expect(next != .send)
        #expect(ReadingThrottle.interval == 0.25)
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
