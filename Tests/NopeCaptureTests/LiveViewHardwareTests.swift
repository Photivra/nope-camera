import Foundation
import NopeCore
import Testing

@testable import NopeCapture

/// A fake camera with a live view that records what it is asked for.
actor FakeLiveHardware: CaptureHardware, LiveViewHardware {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let exposureReadings: AsyncStream<ExposureReading>
    nonisolated let previewSource: any CameraPreviewSource = SimulatedPreviewSource()
    nonisolated let frameAnalyses: AsyncStream<FrameAnalysis>
    nonisolated let statsReadings: AsyncStream<CameraStatsReading>
    nonisolated let analysesContinuation: AsyncStream<FrameAnalysis>.Continuation
    nonisolated let statsContinuation: AsyncStream<CameraStatsReading>.Continuation
    private(set) var needsRequests: [LiveAnalysisNeeds] = []
    private(set) var statsSwitches: [Bool] = []

    init() {
        (events, _) = AsyncStream.makeStream(of: CaptureEvent.self)
        (exposureReadings, _) = AsyncStream.makeStream(of: ExposureReading.self)
        (frameAnalyses, analysesContinuation) = AsyncStream.makeStream(of: FrameAnalysis.self)
        (statsReadings, statsContinuation) = AsyncStream.makeStream(of: CameraStatsReading.self)
    }

    func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async { needsRequests.append(needs) }
    func setStatsReadingsEnabled(_ enabled: Bool) async { statsSwitches.append(enabled) }

    func discoverCameras() async -> [CameraDeviceDescription] { [] }
    func configure(_ configuration: SessionConfiguration) async throws(CaptureError) {}
    func stop() async {}
    func capture(_ plan: PhotoSettingsPlan, metadata: MetadataPlan) async throws(CaptureError) -> HardwarePhoto {
        throw .captureFailed
    }
    func apply(_ controls: DeviceControls) async throws(CaptureError) {}
    func setReadingsEnabled(_ enabled: Bool) async {}
    func captureBracket(_ plan: PhotoSettingsPlan, frames: [BracketFrame], metadata: MetadataPlan)
        async throws(CaptureError) -> [HardwarePhoto]
    { [] }
}

struct LiveViewBackendTests {
    @Test func backendForwardsToTheHardwaresLiveView() async {
        let hardware = FakeLiveHardware()
        let backend = AVFoundationCaptureBackend(hardware: hardware, authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
        await backend.setFrameAnalysis(.focusPeaking)
        await backend.setStatsReadingsEnabled(true)
        #expect(await hardware.needsRequests == [.focusPeaking])
        #expect(await hardware.statsSwitches == [true])

        let analysis = SimulatedCaptureBackend.placeholderAnalysis(for: .focusPeaking)
        hardware.analysesContinuation.yield(analysis)
        hardware.analysesContinuation.finish()
        hardware.statsContinuation.yield(SimulatedCaptureBackend.placeholderStats)
        hardware.statsContinuation.finish()
        var analyses: [FrameAnalysis] = []
        for await item in backend.frameAnalyses { analyses.append(item) }
        var stats: [CameraStatsReading] = []
        for await item in backend.statsReadings { stats.append(item) }
        #expect(analyses == [analysis])
        #expect(stats == [SimulatedCaptureBackend.placeholderStats])
    }

    @Test func hardwareWithoutALiveViewSendsNothing() async {
        let backend = AVFoundationCaptureBackend(hardware: FakeHardware(cameras: []), authorization: FakeAuthorization(current: .authorized, afterRequest: .authorized))
        await backend.setFrameAnalysis(.histogram)
        await backend.setStatsReadingsEnabled(true)
        var count = 0
        for await _ in backend.frameAnalyses { count += 1 }
        for await _ in backend.statsReadings { count += 1 }
        #expect(count == 0)
    }
}

struct LumaSamplerTests {
    /// A plane whose pixels are given by a function of their position, with padding at the end
    /// of each row; it records every offset read.
    final class Recorder: @unchecked Sendable {
        var offsets: [Int] = []
    }

    static func plane(
        width: Int, height: Int, padding: Int = 3, isVideoRange: Bool = false, recorder: Recorder = Recorder(),
        pixel: @escaping (Int, Int) -> UInt8
    ) -> LumaPlane {
        let bytesPerRow = width + padding
        return LumaPlane(width: width, height: height, bytesPerRow: bytesPerRow, isVideoRange: isVideoRange) { offset in
            recorder.offsets.append(offset)
            return pixel(offset % bytesPerRow, offset / bytesPerRow)
        }
    }

    @Test func samplesAGridWithinThePlane() {
        let recorder = Recorder()
        let plane = Self.plane(width: 1920, height: 1440, recorder: recorder) { x, _ in UInt8(x * 255 / 1919) }
        let frame = LumaSampler.sample(plane)
        #expect(frame.width == 160 && frame.height == 120)
        #expect(frame.luma.count == 160 * 120 && frame.edges.count == 160 * 120)
        // A smooth ramp: dark on the left, bright on the right, and no sharp edges.
        #expect(frame.luma.first! < 10 && frame.luma[159] > 245)
        #expect(frame.edges.allSatisfy { $0 < 5 })
        let lastPixel = 1439 * plane.bytesPerRow + 1919
        #expect(recorder.offsets.allSatisfy { $0 >= 0 && $0 <= lastPixel && $0 % plane.bytesPerRow < 1920 })
    }

    @Test func sharpEdgesAreFoundAtFullResolution() {
        // A one-pixel checkerboard: very sharp everywhere.
        let frame = LumaSampler.sample(Self.plane(width: 640, height: 480) { x, y in (x + y) % 2 == 0 ? 0 : 255 })
        #expect(frame.edges.allSatisfy { $0 == 255 })
    }

    @Test func videoRangeIsStretchedToFullRange() {
        let black = LumaSampler.sample(Self.plane(width: 8, height: 8, isVideoRange: true) { _, _ in 16 })
        #expect(black.luma.allSatisfy { $0 == 0 })
        let white = LumaSampler.sample(Self.plane(width: 8, height: 8, isVideoRange: true) { _, _ in 240 })
        #expect(white.luma.allSatisfy { $0 == 255 })
        let below = LumaSampler.sample(Self.plane(width: 8, height: 8, isVideoRange: true) { _, _ in 4 })
        #expect(below.luma.allSatisfy { $0 == 0 })
    }

    @Test func smallPlanesStayInBoundsAndTinyOnesAreEmpty() {
        let small = LumaSampler.sample(Self.plane(width: 6, height: 3) { _, _ in 9 })
        #expect(small.width == 4 && small.height == 2)
        #expect(small.luma.allSatisfy { $0 == 9 })
        #expect(LumaSampler.sample(Self.plane(width: 2, height: 9) { _, _ in 0 }).width == 0)
        #expect(LumaSampler.sample(Self.plane(width: 9, height: 2) { _, _ in 0 }).height == 0)
        #expect(LumaSampler.position(of: 0, count: 4, length: 6) == 1)
        #expect(LumaSampler.position(of: 3, count: 4, length: 6) == 4)
    }
}
