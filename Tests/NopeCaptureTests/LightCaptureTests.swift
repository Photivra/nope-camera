import AVFoundation
import NopeCore
import Testing

@testable import NopeCapture

/// Builds a camera description with a flash and a torch.
func cameraWithLight(
    _ id: String, _ position: CameraDeviceDescription.Position = .back, flashModes: [FlashMode] = [.off, .auto, .on]
) -> CameraDeviceDescription {
    CameraDeviceDescription(
        uniqueID: id, deviceType: .wideAngle, position: position, isVirtual: false,
        rawPixelFormats: [.init(code: 0x6267_6734, isBayer: true)], supportsHEVC: true, isoRange: 50...12800,
        exposureDurationRange: 0.000014...1, aperture: .fixed(1.78), maxBracketedPhotoCount: 8,
        photoDimensions: [PhotoDimensions(width: 4032, height: 3024)], fieldOfViewDegrees: 70,
        flashModes: flashModes, hasTorch: true)
}

struct LightCaptureTests {
    @Test(arguments: [
        (AVCaptureDevice.FlashMode.off, FlashMode.off), (.auto, .auto), (.on, .on),
    ])
    func flashModesMapBothWays(system: AVCaptureDevice.FlashMode, mode: FlashMode) {
        #expect(FlashMode(system) == mode)
        #expect(mode.captureFlashMode == system)
    }

    @Test func unknownFlashModeIsDropped() throws {
        let future = try #require(AVCaptureDevice.FlashMode(rawValue: 99))
        #expect(FlashMode(future) == nil)
    }

    @Test func catalogKeepsRearLightsAndDropsTheFrontFlash() throws {
        let lenses = LensCatalog.lenses(from: [cameraWithLight("wide"), cameraWithLight("front", .front)])
        let wide = try #require(lenses.first { $0.id == "wide" })
        let front = try #require(lenses.first { $0.id == "front" })
        #expect(wide.flashModes == [.off, .auto, .on])
        #expect(wide.hasTorch)
        #expect(front.flashModes.isEmpty)
        #expect(front.hasTorch)
        let plain = LensCatalog.lenses(from: [camera("ultra", .ultraWide)])
        #expect(plain.first?.flashModes == [])
        #expect(plain.first?.hasTorch == false)
    }

    @Test(arguments: FlashMode.allCases)
    func photoPlanTakesTheFlashOnly(mode: FlashMode) throws {
        let plan = try #require(CapturePolicy.photoSettings(for: .bayerRAW(pixelFormat: "bgg4")))
        let withFlash = CapturePolicy.photoSettings(plan, flashMode: mode)
        #expect(withFlash.rawPixelFormat == plan.rawPixelFormat)
        #expect(withFlash.processedFormat == plan.processedFormat)
        #expect(withFlash.switches.flashMode == mode.captureFlashMode)
        // Nothing else changes with the flash.
        #expect(withFlash.switches.withFlashMode(.off) == ProcessingSwitches.leastProcessing)
        let settings = PhotoSettingsFactory.makeSettings(for: withFlash, maxPhotoDimensions: nil)
        #expect(settings.flashMode == mode.captureFlashMode)
        #expect(settings.rawFileType == .dng)
    }

    @Test func bracketSettingsNeverUseTheFlash() throws {
        let plan = try #require(CapturePolicy.photoSettings(for: .bayerRAW(pixelFormat: "bgg4")))
        let settings = PhotoSettingsFactory.makeBracketSettings(
            for: CapturePolicy.photoSettings(plan, flashMode: .on),
            frames: [BracketFrame(iso: 100, exposureDuration: 0.01)], maxPhotoDimensions: nil)
        #expect(settings.flashMode == .off)
    }

    @Test func singlePhotoUsesTheRequestFlashAndTheSessionDoesNot() async throws {
        let hardware = FakeHardware(cameras: [cameraWithLight("wide")])
        let backend = AVFoundationCaptureBackend(
            hardware: hardware, authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
        let wide = try #require(await backend.deviceCapabilities().lens(withID: "wide"))
        try await backend.startSession(CaptureRequest(lens: wide))
        _ = try await backend.capturePhoto(CaptureRequest(lens: wide, flashMode: .auto))
        #expect(await hardware.configurations.first?.photoSettings.switches.flashMode == .off)
        #expect(await hardware.plans.last?.switches.flashMode == .auto)
    }

    @Test func torchNeedsARunningSession() async throws {
        let hardware = FakeHardware(cameras: [cameraWithLight("wide")])
        let backend = AVFoundationCaptureBackend(
            hardware: hardware, authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
        #expect(await backend.setTorch(level: 0.5) == .off)
        let wide = try #require(await backend.deviceCapabilities().lens(withID: "wide"))
        try await backend.startSession(CaptureRequest(lens: wide))
        #expect(await backend.setTorch(level: 0.5) == .on(level: 0.5))
        #expect(await backend.setTorch(level: nil) == .off)
        #expect(await hardware.torchRequests == [0.5, nil])
    }
}
