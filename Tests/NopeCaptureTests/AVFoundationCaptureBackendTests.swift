import Foundation
import NopeCore
import Testing

@testable import NopeCapture

/// A fake camera that records configurations and returns scripted photos.
actor FakeHardware: CaptureHardware {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let previewSource: any CameraPreviewSource = SimulatedPreviewSource()
    nonisolated let continuation: AsyncStream<CaptureEvent>.Continuation
    let cameras: [CameraDeviceDescription]
    let configureError: CaptureError?
    let captureError: CaptureError?
    private(set) var configurations: [SessionConfiguration] = []
    private(set) var plans: [PhotoSettingsPlan] = []
    private(set) var stopCount = 0

    init(cameras: [CameraDeviceDescription], configureError: CaptureError? = nil, captureError: CaptureError? = nil) {
        self.cameras = cameras
        self.configureError = configureError
        self.captureError = captureError
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
    }

    func discoverCameras() async -> [CameraDeviceDescription] { cameras }

    func configure(_ configuration: SessionConfiguration) async throws(CaptureError) {
        configurations.append(configuration)
        if let configureError { throw configureError }
    }

    func stop() async { stopCount += 1 }

    func capture(_ plan: PhotoSettingsPlan) async throws(CaptureError) -> HardwarePhoto {
        plans.append(plan)
        if let captureError { throw captureError }
        return HardwarePhoto(
            data: Data([0x49, 0x49]), dimensions: PhotoDimensions(width: 4032, height: 3024),
            exposureDuration: 1.0 / 30.0, iso: 400)
    }
}

/// A fake permission source.
struct FakeAuthorization: CameraAuthorizing {
    let current: CameraPermission
    let afterRequest: CameraPermission
    func currentPermission() async -> CameraPermission { current }
    func requestPermission() async -> CameraPermission { afterRequest }
}

struct AVFoundationCaptureBackendTests {
    static let cameras = [camera("wide", .wideAngle), camera("tele", .telephoto, raw: [], hevc: true)]

    static func makeBackend(_ hardware: FakeHardware) -> AVFoundationCaptureBackend {
        AVFoundationCaptureBackend(
            hardware: hardware, authorization: FakeAuthorization(current: .notDetermined, afterRequest: .authorized))
    }

    static func lens(_ backend: AVFoundationCaptureBackend, _ id: String) async throws -> Lens {
        try #require(await backend.deviceCapabilities().lens(withID: id))
    }

    @Test func permissionComesFromTheAuthorization() async {
        let backend = Self.makeBackend(FakeHardware(cameras: []))
        #expect(await backend.currentPermission() == .notDetermined)
        #expect(await backend.requestPermission() == .authorized)
    }

    @Test func passesThroughEventsAndPreview() async {
        let hardware = FakeHardware(cameras: [])
        let backend = Self.makeBackend(hardware)
        #expect(backend.previewSource is SimulatedPreviewSource)
        hardware.continuation.yield(.heat(.fair))
        hardware.continuation.finish()
        var received: [CaptureEvent] = []
        for await event in backend.events { received.append(event) }
        #expect(received == [.heat(.fair)])
    }

    @Test func capabilitiesComeFromTheCatalog() async {
        let backend = Self.makeBackend(FakeHardware(cameras: Self.cameras))
        let capabilities = await backend.deviceCapabilities()
        #expect(capabilities.lenses.map(\.id) == ["wide", "tele"])
        #expect(capabilities.lens(withID: "tele")?.supportsBayerRAW == false)
    }

    @Test func startConfiguresTheHardware() async throws {
        let hardware = FakeHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        let wide = try await Self.lens(backend, "wide")
        try await backend.startSession(CaptureRequest(lens: wide))
        #expect(await hardware.configurations == [CapturePolicy.sessionConfiguration(for: CaptureRequest(lens: wide))])
    }

    @Test func startRejectsUnknownLensesAndInvalidFormats() async {
        let hardware = FakeHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        _ = await backend.deviceCapabilities()
        let unknown = Lens(id: "missing", kind: .wide, bayerRAWFormat: "bgg4")
        let invalid = Lens(id: "wide", kind: .wide, bayerRAWFormat: "invalid")
        for lens in [unknown, invalid] {
            await #expect(throws: CaptureError.configurationFailed) {
                try await backend.startSession(CaptureRequest(lens: lens))
            }
        }
        #expect(await hardware.configurations.isEmpty)
    }

    @Test func startReportsHardwareFailure() async throws {
        let hardware = FakeHardware(cameras: Self.cameras, configureError: .configurationFailed)
        let backend = Self.makeBackend(hardware)
        let wide = try await Self.lens(backend, "wide")
        await #expect(throws: CaptureError.configurationFailed) {
            try await backend.startSession(CaptureRequest(lens: wide))
        }
        await #expect(throws: CaptureError.notRunning) {
            try await backend.capturePhoto(CaptureRequest(lens: wide))
        }
    }

    @Test func captureReturnsThePhotoInMemory() async throws {
        let hardware = FakeHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        let tele = try await Self.lens(backend, "tele")
        let request = CaptureRequest(lens: tele)
        try await backend.startSession(request)
        let photo = try await backend.capturePhoto(request)
        #expect(photo.data == Data([0x49, 0x49]))
        #expect(photo.format == .processedFallback(.heif))
        #expect(photo.lensID == "tele")
        #expect(photo.dimensions == PhotoDimensions(width: 4032, height: 3024))
        #expect(photo.exposureDuration == 1.0 / 30.0)
        #expect(photo.iso == 400)
        #expect(await hardware.plans == [CapturePolicy.photoSettings(for: .processedFallback(.heif))])
    }

    @Test func captureNeedsAMatchingRunningSession() async throws {
        let hardware = FakeHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        let wide = try await Self.lens(backend, "wide")
        let tele = try await Self.lens(backend, "tele")
        await #expect(throws: CaptureError.notRunning) {
            try await backend.capturePhoto(CaptureRequest(lens: wide))
        }
        try await backend.startSession(CaptureRequest(lens: wide))
        await #expect(throws: CaptureError.notRunning) {
            try await backend.capturePhoto(CaptureRequest(lens: tele))
        }
        await backend.stopSession()
        #expect(await hardware.stopCount == 1)
        await #expect(throws: CaptureError.notRunning) {
            try await backend.capturePhoto(CaptureRequest(lens: wide))
        }
        #expect(await hardware.plans.isEmpty)
    }

    @Test func captureReportsHardwareFailure() async throws {
        let hardware = FakeHardware(cameras: Self.cameras, captureError: .captureFailed)
        let backend = Self.makeBackend(hardware)
        let wide = try await Self.lens(backend, "wide")
        try await backend.startSession(CaptureRequest(lens: wide))
        await #expect(throws: CaptureError.captureFailed) {
            try await backend.capturePhoto(CaptureRequest(lens: wide))
        }
    }
}
