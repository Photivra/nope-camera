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
    let pixelSample: [UInt8]?
    private(set) var configurations: [SessionConfiguration] = []
    private(set) var plans: [PhotoSettingsPlan] = []
    private(set) var metadataPlans: [MetadataPlan] = []
    private(set) var stopCount = 0

    init(
        cameras: [CameraDeviceDescription], configureError: CaptureError? = nil, captureError: CaptureError? = nil,
        pixelSample: [UInt8]? = Array(0..<128)
    ) {
        self.cameras = cameras
        self.pixelSample = pixelSample
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

    func capture(_ plan: PhotoSettingsPlan, metadata: MetadataPlan) async throws(CaptureError) -> HardwarePhoto {
        plans.append(plan)
        metadataPlans.append(metadata)
        if let captureError { throw captureError }
        return HardwarePhoto(
            data: Data([0x49, 0x49]), dimensions: PhotoDimensions(width: 4032, height: 3024),
            exposureDuration: 1.0 / 30.0, iso: 400, pixelSample: pixelSample, rawImageData: Data([7]))
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
        var settings = MetadataSettings()
        settings.set(.location, isOn: true)
        let plan = MetadataPlan(settings: settings, appVersion: "0.2.0")
        let request = CaptureRequest(lens: tele, metadata: plan)
        try await backend.startSession(CaptureRequest(lens: tele))
        let photo = try await backend.capturePhoto(request)
        #expect(photo.data == Data([0x49, 0x49]))
        #expect(photo.rawImageData == Data([7]))
        #expect(await hardware.metadataPlans == [plan])
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

    @Test func blankPhotoIsRejected() async throws {
        let hardware = FakeHardware(cameras: Self.cameras, pixelSample: Array(repeating: 0, count: 128))
        let backend = Self.makeBackend(hardware)
        let wide = try await Self.lens(backend, "wide")
        try await backend.startSession(CaptureRequest(lens: wide))
        await #expect(throws: CaptureError.blankPicture) {
            try await backend.capturePhoto(CaptureRequest(lens: wide))
        }
    }

    @Test func photoWithoutAPixelBufferIsKept() async throws {
        let hardware = FakeHardware(cameras: Self.cameras, pixelSample: nil)
        let backend = Self.makeBackend(hardware)
        let tele = try await Self.lens(backend, "tele")
        try await backend.startSession(CaptureRequest(lens: tele))
        let photo = try await backend.capturePhoto(CaptureRequest(lens: tele))
        #expect(photo.lensID == "tele")
    }

    @Test func explicitProcessedFormatOnARAWLensIsConfigured() async throws {
        let hardware = FakeHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        let wide = try await Self.lens(backend, "wide")
        let request = CaptureRequest(lens: wide, format: .processedFallback(.heif))
        try await backend.startSession(request)
        let photo = try await backend.capturePhoto(request)
        #expect(photo.format == .processedFallback(.heif))
        #expect(await hardware.plans == [CapturePolicy.photoSettings(for: .processedFallback(.heif))])
        await #expect(throws: CaptureError.notRunning) {
            try await backend.capturePhoto(CaptureRequest(lens: wide))
        }
    }
}

struct PictureCheckTests {
    @Test func offsetsSpreadOverTheWholeBuffer() {
        let offsets = PictureCheck.sampleOffsets(byteCount: 6400)
        #expect(offsets.count == 2 * PictureCheck.samplePlaces)
        #expect(offsets.first == 0)
        #expect(offsets[1] == 1)
        #expect(offsets.last == 6301)
        #expect(offsets == offsets.sorted())
        #expect(Set(offsets).count == offsets.count)
    }

    @Test func offsetsStayInsideSmallBuffers() {
        #expect(PictureCheck.sampleOffsets(byteCount: 0).isEmpty)
        #expect(PictureCheck.sampleOffsets(byteCount: -4).isEmpty)
        #expect(PictureCheck.sampleOffsets(byteCount: 1) == [0])
        #expect(PictureCheck.sampleOffsets(byteCount: 3) == [0, 1, 2])
        #expect(PictureCheck.sampleOffsets(byteCount: 100).allSatisfy { $0 < 100 })
    }

    @Test func constantFillsAreBlank() {
        #expect(PictureCheck.isBlank(Array(repeating: 0, count: 128)))
        #expect(PictureCheck.isBlank(Array(repeating: 0x10, count: PictureCheck.minimumSampleCount)))
    }

    @Test func noiseIsAPicture() {
        var almostZero = [UInt8](repeating: 0, count: 128)
        almostZero[77] = 1
        #expect(!PictureCheck.isBlank(almostZero))
        #expect(!PictureCheck.isBlank(Array(0..<128)))
    }

    @Test func unknownOrTooSmallIsAPicture() {
        #expect(!PictureCheck.isBlank(nil))
        #expect(!PictureCheck.isBlank([]))
        #expect(!PictureCheck.isBlank(Array(repeating: 0, count: PictureCheck.minimumSampleCount - 1)))
    }
}
