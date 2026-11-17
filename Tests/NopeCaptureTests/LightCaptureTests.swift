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
        // Before the start the light can't be switched yet: a request for it is pending, never a
        // silent "off" (issue #75), and the hardware isn't asked.
        #expect(await backend.setTorch(level: 0.5) == .pending)
        #expect(await backend.setTorch(level: nil) == .off)
        let wide = try #require(await backend.deviceCapabilities().lens(withID: "wide"))
        try await backend.startSession(CaptureRequest(lens: wide))
        #expect(await backend.setTorch(level: 0.5) == .on(level: 0.5))
        #expect(await backend.setTorch(level: nil) == .off)
        #expect(await hardware.torchRequests == [0.5, nil])
    }

    @Test func hardwareWithoutAnInputAnswersPending() async {
        let hardware = FakeHardware(cameras: [cameraWithLight("wide")])
        #expect(await hardware.setTorch(level: 0.5) == .pending)
        #expect(await hardware.setTorch(level: nil) == .off)
    }

    /// Issue #75: the Light is turned on before the camera has started (its input isn't attached
    /// yet); once the input is attached, the light comes on, or is reported unavailable. It is
    /// never silently turned off.
    @MainActor
    @Test(arguments: [true, false])
    func lightRequestedBeforeTheStartIsAppliedOnceTheInputIsAttached(torchAvailable: Bool) async throws {
        let hardware = FakeHardware(cameras: [cameraWithLight("wide")])
        await hardware.setTorchAvailable(torchAvailable)
        await hardware.holdConfigure()
        let backend = AVFoundationCaptureBackend(
            hardware: hardware, authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
        let model = CameraModel(backend: backend)
        let start = Task { await model.send(.start) }
        // The lens is chosen and the session is being configured: no input is attached yet.
        while await !hardware.isConfigureHeld { await Task.yield() }
        #expect(model.light.supportsTorch)
        #expect(await !hardware.isInputAttached)
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .pending)
        #expect(await backend.setTorch(level: 0.25) == .pending)
        #expect(await hardware.torchRequests.isEmpty)
        // The input is attached and the session starts: the request is applied.
        await hardware.releaseConfigure()
        await start.value
        #expect(model.sessionStatus == .running)
        #expect(model.light.torch == (torchAvailable ? .on(level: LightModel.defaultTorchLevel) : .unavailable))
        #expect(await hardware.torchRequests == [LightModel.defaultTorchLevel])
    }

    /// A failed start turns a waiting light off instead of leaving it waiting (issue #75).
    @MainActor
    @Test func failedStartTurnsAWaitingLightOff() async throws {
        let hardware = FakeHardware(cameras: [cameraWithLight("wide")], configureError: .configurationFailed)
        await hardware.holdConfigure()
        let backend = AVFoundationCaptureBackend(
            hardware: hardware, authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
        let model = CameraModel(backend: backend)
        let start = Task { await model.send(.start) }
        while await !hardware.isConfigureHeld { await Task.yield() }
        await model.send(.light(.setTorch(true)))
        #expect(model.light.torch == .pending)
        await hardware.releaseConfigure()
        await start.value
        #expect(model.sessionStatus == .failed(.configurationFailed))
        #expect(model.light.torch == .off)
        #expect(await hardware.torchRequests.isEmpty)
    }
}
