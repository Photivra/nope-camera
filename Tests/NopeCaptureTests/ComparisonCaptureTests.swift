import AVFoundation
import Foundation
import NopeCore
import Testing

@testable import NopeCapture

/// A fake camera that can also take the comparison shot's second photo (issue #55): every other
/// call goes to a ``FakeHardware``.
actor FakeComparisonHardware: CaptureHardware, ComparisonHardware {
    nonisolated let camera: FakeHardware
    nonisolated var events: AsyncStream<CaptureEvent> { camera.events }
    nonisolated var exposureReadings: AsyncStream<ExposureReading> { camera.exposureReadings }
    nonisolated var previewSource: any CameraPreviewSource { camera.previewSource }
    let comparisonError: CaptureError?
    private(set) var comparisons: [(plan: PhotoSettingsPlan, restoring: PhotoSettingsPlan)] = []

    /// The bytes of every second photo: not a real HEIF; the reader reports what it finds.
    static let heif = Data("phone heif".utf8)

    init(cameras: [CameraDeviceDescription], comparisonError: CaptureError? = nil) {
        camera = FakeHardware(cameras: cameras)
        self.comparisonError = comparisonError
    }

    func discoverCameras() async -> [CameraDeviceDescription] { await camera.discoverCameras() }
    func configure(_ configuration: SessionConfiguration) async throws(CaptureError) { try await camera.configure(configuration) }
    func stop() async { await camera.stop() }
    func capture(_ plan: PhotoSettingsPlan, metadata: MetadataPlan) async throws(CaptureError) -> HardwarePhoto {
        try await camera.capture(plan, metadata: metadata)
    }
    func apply(_ controls: DeviceControls) async throws(CaptureError) { try await camera.apply(controls) }
    func setFocus(lensPosition: Double) async throws(CaptureError) -> Double {
        try await camera.setFocus(lensPosition: lensPosition)
    }
    func setReadingsEnabled(_ enabled: Bool) async { await camera.setReadingsEnabled(enabled) }
    func captureBracket(_ plan: PhotoSettingsPlan, frames: [BracketFrame], metadata: MetadataPlan)
        async throws(CaptureError) -> [HardwarePhoto]
    {
        try await camera.captureBracket(plan, frames: frames, metadata: metadata)
    }
    func setTorch(level: Double?) async -> TorchStatus { await camera.setTorch(level: level) }

    func captureComparison(_ plan: PhotoSettingsPlan, restoring sessionPlan: PhotoSettingsPlan)
        async throws(CaptureError) -> HardwarePhoto
    {
        comparisons.append((plan, sessionPlan))
        if let comparisonError { throw comparisonError }
        return HardwarePhoto(
            data: Self.heif, dimensions: PhotoDimensions(width: 4032, height: 3024), exposureDuration: nil, iso: nil,
            pixelSample: nil)
    }
}

struct ComparisonCaptureTests {
    static let cameras = AVFoundationCaptureBackendTests.cameras

    static func makeBackend(_ hardware: any CaptureHardware) -> AVFoundationCaptureBackend {
        AVFoundationCaptureBackend(
            hardware: hardware, authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
    }

    @Test func theSecondPhotoUsesTheQualitySettingAndRestoresTheSessionsPlan() async throws {
        let hardware = FakeComparisonHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        let wide = try await AVFoundationCaptureBackendTests.lens(backend, "wide")
        let request = CaptureRequest(lens: wide, flashMode: .on)
        try await backend.startSession(CaptureRequest(lens: wide))
        let photo = try await backend.captureComparison(request)
        #expect(photo.data == FakeComparisonHardware.heif)
        #expect(photo.format == .heif)
        #expect(photo.dimensions == PhotoDimensions(width: 4032, height: 3024))
        #expect(photo.metadata == MetadataFileReader.read(FakeComparisonHardware.heif, format: .heif).inventory)
        let comparison = try #require(await hardware.comparisons.first)
        #expect(comparison.plan == CapturePolicy.comparisonPlan(for: request))
        #expect(comparison.plan.switches.qualityPrioritization == .quality)
        #expect(comparison.plan.switches.flashMode == .on)
        #expect(comparison.restoring == CapturePolicy.sessionConfiguration(for: request)?.photoSettings)
    }

    @Test func theSecondPhotoNeedsAMatchingRunningSession() async throws {
        let hardware = FakeComparisonHardware(cameras: Self.cameras)
        let backend = Self.makeBackend(hardware)
        let wide = try await AVFoundationCaptureBackendTests.lens(backend, "wide")
        let tele = try await AVFoundationCaptureBackendTests.lens(backend, "tele")
        await #expect(throws: CaptureError.notRunning) { try await backend.captureComparison(CaptureRequest(lens: wide)) }
        try await backend.startSession(CaptureRequest(lens: wide))
        await #expect(throws: CaptureError.notRunning) { try await backend.captureComparison(CaptureRequest(lens: tele)) }
        #expect(await hardware.comparisons.isEmpty)
    }

    @Test func hardwareWithoutTheSecondPhotoFails() async throws {
        let backend = Self.makeBackend(FakeHardware(cameras: Self.cameras))
        let wide = try await AVFoundationCaptureBackendTests.lens(backend, "wide")
        try await backend.startSession(CaptureRequest(lens: wide))
        await #expect(throws: CaptureError.captureFailed) { try await backend.captureComparison(CaptureRequest(lens: wide)) }
    }

    @Test func reportsTheHardwaresError() async throws {
        let hardware = FakeComparisonHardware(cameras: Self.cameras, comparisonError: .captureFailed)
        let backend = Self.makeBackend(hardware)
        let wide = try await AVFoundationCaptureBackendTests.lens(backend, "wide")
        try await backend.startSession(CaptureRequest(lens: wide))
        await #expect(throws: CaptureError.captureFailed) { try await backend.captureComparison(CaptureRequest(lens: wide)) }
    }

    @Test(arguments: [
        (ProcessedFallback.heif, ProcessedFallback.heif), (.jpeg, .jpeg),
    ])
    func theSecondPhotoMatchesAFallbackLensesFormat(fallback: ProcessedFallback, expected: ProcessedFallback) {
        let lens = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, processedFallback: fallback)
        let plan = CapturePolicy.comparisonPlan(for: CaptureRequest(lens: lens))
        #expect(plan.processedFormat == expected)
        #expect(plan.rawPixelFormat == nil)
        #expect(plan.switches.flashMode == .off)
    }

    @Test func aRAWLensesSecondPhotoIsAHEIF() {
        let lens = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")
        #expect(CapturePolicy.comparisonPlan(for: CaptureRequest(lens: lens)).processedFormat == .heif)
    }

    @Test func phoneProcessingChangesOnlyThePrioritization() {
        let phone = ProcessingSwitches.phoneProcessing
        #expect(phone.qualityPrioritization == .quality)
        #expect(phone == ProcessingSwitches.leastProcessing.withQualityPrioritization(.quality))
    }
}

extension ProcessingSwitches {
    /// The same switches with another prioritization, for comparing two sets in tests.
    fileprivate func withQualityPrioritization(_ value: AVCapturePhotoOutput.QualityPrioritization) -> ProcessingSwitches {
        ProcessingSwitches(
            qualityPrioritization: value, appleProRAW: appleProRAW, zeroShutterLag: zeroShutterLag,
            responsiveCapture: responsiveCapture, deferredDelivery: deferredDelivery, constantColor: constantColor,
            contentAwareDistortionCorrection: contentAwareDistortionCorrection,
            geometricDistortionCorrection: geometricDistortionCorrection, videoZoomFactor: videoZoomFactor,
            flashMode: flashMode)
    }
}
