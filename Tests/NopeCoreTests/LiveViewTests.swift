import Foundation
import Testing

@testable import NopeCore

struct FrameAnalysisTests {
    /// A 3 × 2 frame numbered 0 to 5, row by row.
    static let numbered = LumaFrame(width: 3, height: 2, luma: [0, 1, 2, 3, 4, 5], edges: [10, 11, 12, 13, 14, 15])

    @Test func framesTurnAndMirrorLikeTheViewfinder() {
        let turned = Self.numbered.oriented(quarterTurns: 1, mirrored: false)
        #expect(turned.width == 2 && turned.height == 3)
        // Turned clockwise: the bottom-left cell comes to the top-left.
        #expect(turned.luma == [3, 0, 4, 1, 5, 2])
        #expect(turned.edges == [13, 10, 14, 11, 15, 12])
        #expect(Self.numbered.oriented(quarterTurns: 0, mirrored: true).luma == [2, 1, 0, 5, 4, 3])
        #expect(Self.numbered.oriented(quarterTurns: 4, mirrored: false) == Self.numbered)
        #expect(Self.numbered.oriented(quarterTurns: -1, mirrored: false) == Self.numbered.oriented(quarterTurns: 3, mirrored: false))
        #expect(Self.numbered.oriented(quarterTurns: 2, mirrored: false).luma == [5, 4, 3, 2, 1, 0])
    }

    @Test func histogramCountsSharesAndClipping() {
        let luma: [UInt8] = [0, 2, 3, 4, 128, 250, 252, 255]
        let histogram = Histogram(luma: luma)
        #expect(histogram.bins.count == Histogram.binCount)
        #expect(abs(histogram.bins.reduce(0, +) - 1) < 0.000_001)
        #expect(histogram.bins[0] == 0.375)
        #expect(histogram.bins[1] == 0.125)
        #expect(histogram.bins[32] == 0.125)
        #expect(histogram.bins[63] == 0.25)
        #expect(histogram.highlightShare == 0.25)
        #expect(histogram.shadowShare == 0.375)
        #expect(histogram.clipping == ClippingState(highlights: true, shadows: true))

        let midtones = Histogram(luma: [UInt8](repeating: 128, count: 200) + [255])
        #expect(midtones.clipping == ClippingState(highlights: false, shadows: false))
        let empty = Histogram(luma: [])
        #expect(empty.bins.allSatisfy { $0 == 0 })
        #expect(empty.clipping == ClippingState(highlights: false, shadows: false))
    }

    @Test func peakingMarksOnlyTheSharpestEdges() {
        // 100 cells: 5 very sharp, 20 fairly sharp, the rest flat.
        let edges = [UInt8](repeating: 200, count: 5) + [UInt8](repeating: 60, count: 20) + [UInt8](repeating: 0, count: 75)
        let frame = LumaFrame(width: 10, height: 10, luma: [UInt8](repeating: 0, count: 100), edges: edges)
        let map = FocusPeakingMap(frame: frame)
        #expect(map.width == 10 && map.height == 10)
        #expect(map.cells.filter { $0 }.count == 5)
        #expect(map.cells.prefix(5).allSatisfy { $0 })
        #expect(map.hasFocus)

        // A soft scene: its sharpest cells are below the minimum, so nothing is marked.
        let soft = LumaFrame(width: 10, height: 1, luma: [UInt8](repeating: 0, count: 10), edges: [30] + [UInt8](repeating: 0, count: 9))
        #expect(!FocusPeakingMap(frame: soft).hasFocus)
        // A flat scene.
        let flat = LumaFrame(width: 4, height: 1, luma: [0, 0, 0, 0], edges: [0, 0, 0, 0])
        #expect(!FocusPeakingMap(frame: flat).hasFocus)
    }

    @Test func analysisMeasuresOnlyWhatIsNeeded() {
        let frame = SimulatedCaptureBackend.placeholderFrame
        let both = FrameAnalysis(frame: frame, needs: [.histogram, .focusPeaking])
        #expect(both.histogram?.clipping.highlights == true)
        #expect(both.focusPeaking?.hasFocus == true)
        #expect(FrameAnalysis(frame: frame, needs: .histogram).focusPeaking == nil)
        #expect(FrameAnalysis(frame: frame, needs: .focusPeaking).histogram == nil)
        #expect(both.keeping(.histogram)?.focusPeaking == nil)
        #expect(both.keeping(.histogram)?.histogram == both.histogram)
        #expect(both.keeping(.focusPeaking)?.focusPeaking == both.focusPeaking)
        #expect(both.keeping([]) == nil)
    }

    @Test func needsFollowTheOptionsAndTheScreen() {
        var options = OverlayOptions()
        #expect(LiveAnalysisNeeds.needed(for: options, manualControlsShown: true, isCleanView: false).isEmpty)
        options.showsHistogram = true
        options.showsFocusPeaking = true
        #expect(LiveAnalysisNeeds.needed(for: options, manualControlsShown: true, isCleanView: false) == [.histogram, .focusPeaking])
        // The histogram is never shown in full auto or clean view; peaking is.
        #expect(LiveAnalysisNeeds.needed(for: options, manualControlsShown: false, isCleanView: false) == .focusPeaking)
        #expect(LiveAnalysisNeeds.needed(for: options, manualControlsShown: true, isCleanView: true) == .focusPeaking)
    }

    @Test func updateRateFollowsPowerAndHeat() {
        #expect(LiveUpdateRate.interval(isLowPowerMode: false, heat: .nominal) == LiveUpdateRate.normalInterval)
        #expect(LiveUpdateRate.interval(isLowPowerMode: false, heat: .fair) == LiveUpdateRate.normalInterval)
        #expect(LiveUpdateRate.interval(isLowPowerMode: true, heat: .nominal) == LiveUpdateRate.reducedInterval)
        #expect(LiveUpdateRate.interval(isLowPowerMode: false, heat: .serious) == LiveUpdateRate.reducedInterval)
        #expect(LiveUpdateRate.interval(isLowPowerMode: false, heat: .critical) == nil)
    }

    @Test func rateLimiterLetsOneEventThroughPerInterval() {
        var limiter = RateLimiter()
        do { let passed = limiter.shouldPass(at: 10, interval: 0.25); #expect(passed) }
        do { let passed = limiter.shouldPass(at: 10.1, interval: 0.25); #expect(!passed) }
        do { let passed = limiter.shouldPass(at: 10.25, interval: 0.25); #expect(passed) }
        do { let passed = limiter.shouldPass(at: 20, interval: nil); #expect(!passed) }
    }

    @Test func statsListTheProcessingThatIsOff() {
        var stats = SimulatedCaptureBackend.placeholderStats
        #expect(stats.processingOff == ProcessingFeature.allCases)
        stats.processingOn = [.zeroShutterLag]
        #expect(!stats.processingOff.contains(.zeroShutterLag))
        #expect(stats.processingOff.count == ProcessingFeature.allCases.count - 1)
    }
}

/// A live-view backend that records what it is asked for and lets a test send analyses and
/// readout values.
actor ScriptedLiveBackend: LiveViewBackend {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil
    nonisolated let frameAnalyses: AsyncStream<FrameAnalysis>
    nonisolated let statsReadings: AsyncStream<CameraStatsReading>
    private nonisolated let analysesContinuation: AsyncStream<FrameAnalysis>.Continuation
    private nonisolated let statsContinuation: AsyncStream<CameraStatsReading>.Continuation

    private(set) var needsRequests: [LiveAnalysisNeeds] = []
    private(set) var statsSwitches: [Bool] = []

    /// Yields when a held ``setFrameAnalysis(_:)`` is waiting (``holdNextFrameAnalysis()``).
    nonisolated let analysisHeld: AsyncStream<Void>
    private nonisolated let heldContinuation: AsyncStream<Void>.Continuation
    private var holdsNextFrameAnalysis = false
    private var heldFrameAnalysis: CheckedContinuation<Void, Never>?

    init() {
        (events, _) = AsyncStream.makeStream(of: CaptureEvent.self)
        (frameAnalyses, analysesContinuation) = AsyncStream.makeStream(of: FrameAnalysis.self)
        (statsReadings, statsContinuation) = AsyncStream.makeStream(of: CameraStatsReading.self)
        (analysisHeld, heldContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// Makes the next ``setFrameAnalysis(_:)`` record its needs, then wait for
    /// ``releaseFrameAnalysis()``.
    func holdNextFrameAnalysis() { holdsNextFrameAnalysis = true }

    /// Lets a held ``setFrameAnalysis(_:)`` return.
    func releaseFrameAnalysis() {
        heldFrameAnalysis?.resume()
        heldFrameAnalysis = nil
    }

    nonisolated func send(_ analysis: FrameAnalysis) { analysesContinuation.yield(analysis) }
    nonisolated func send(_ stats: CameraStatsReading) { statsContinuation.yield(stats) }
    nonisolated func finish() {
        analysesContinuation.finish()
        statsContinuation.finish()
    }

    func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async {
        needsRequests.append(needs)
        guard holdsNextFrameAnalysis else { return }
        holdsNextFrameAnalysis = false
        await withCheckedContinuation { continuation in
            heldFrameAnalysis = continuation
            heldContinuation.yield()
        }
    }
    func setStatsReadingsEnabled(_ enabled: Bool) async { statsSwitches.append(enabled) }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { .none }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) {}
    func stopSession() async {}
    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto { throw .captureFailed }
}

@MainActor
struct LiveViewModelTests {
    @Test func needsAreForwardedOnceAndStaleAnalysesAreTrimmed() async {
        let backend = ScriptedLiveBackend()
        let model = LiveViewModel(backend: backend)
        #expect(model.isSupported)
        await model.setNeeds([.histogram, .focusPeaking])
        await model.setNeeds([.histogram, .focusPeaking])
        #expect(await backend.needsRequests == [[.histogram, .focusPeaking]])

        let analysis = FrameAnalysis(frame: SimulatedCaptureBackend.placeholderFrame, needs: [.histogram, .focusPeaking])
        backend.send(analysis)
        backend.finish()
        await model.observeAnalyses()
        #expect(model.analysis == analysis)

        await model.setNeeds(.histogram)
        #expect(model.analysis?.focusPeaking == nil)
        #expect(model.analysis?.histogram != nil)
        await model.setNeeds([])
        #expect(model.analysis == nil)
        #expect(await backend.needsRequests == [[.histogram, .focusPeaking], .histogram, []])
    }

    @Test func analysesArrivingAfterAChangeKeepOnlyWhatIsNeeded() async {
        let backend = ScriptedLiveBackend()
        let model = LiveViewModel(backend: backend)
        await model.setNeeds(.focusPeaking)
        backend.send(FrameAnalysis(frame: SimulatedCaptureBackend.placeholderFrame, needs: [.histogram, .focusPeaking]))
        backend.finish()
        await model.observeAnalyses()
        #expect(model.analysis?.histogram == nil)
        #expect(model.analysis?.focusPeaking != nil)
    }

    @Test func statsArriveOnlyWhileTheReadoutIsOn() async {
        let backend = ScriptedLiveBackend()
        let model = LiveViewModel(backend: backend)
        await model.setShowsStats(true)
        await model.setShowsStats(true)
        #expect(model.showsStats)
        backend.send(SimulatedCaptureBackend.placeholderStats)
        backend.finish()
        await model.observeStats()
        #expect(model.stats == SimulatedCaptureBackend.placeholderStats)
        await model.setShowsStats(false)
        #expect(model.stats == nil)
        #expect(await backend.statsSwitches == [true, false])
    }

    @Test func statsSentWhileTheReadoutIsOffAreIgnored() async {
        let backend = ScriptedLiveBackend()
        let model = LiveViewModel(backend: backend)
        backend.send(SimulatedCaptureBackend.placeholderStats)
        backend.finish()
        await model.observeStats()
        #expect(model.stats == nil)
    }

    /// A layout change replaces the overlays with a new copy, and the old copy's disappearance
    /// can arrive after the new copy appeared and asked for the same aids (which changed
    /// nothing): the aids stay on until the last copy goes.
    @Test func aReplacedInterfaceLeavingDoesNotStopTheAids() async {
        let backend = ScriptedLiveBackend()
        let model = LiveViewModel(backend: backend)
        model.interfaceDidAppear()
        await model.setNeeds(.histogram)
        await model.setShowsStats(true)
        // The new copy appears and asks for the same, then the old copy disappears.
        model.interfaceDidAppear()
        await model.setNeeds(.histogram)
        await model.setShowsStats(true)
        await model.interfaceDidDisappear()
        #expect(model.needs == .histogram)
        #expect(model.showsStats)
        #expect(await backend.needsRequests == [.histogram])
        #expect(await backend.statsSwitches == [true])

        // The last copy leaving stops both.
        await model.interfaceDidDisappear()
        #expect(model.needs == [])
        #expect(!model.showsStats)
        #expect(await backend.needsRequests == [.histogram, []])
        #expect(await backend.statsSwitches == [true, false])
    }

    /// The last copy of the overlays leaves, and a new copy appears and asks for its aids while
    /// the analysis is being stopped: the new copy keeps them.
    @Test func anInterfaceAppearingWhileTheLastOneLeavesKeepsItsAids() async {
        let backend = ScriptedLiveBackend()
        let model = LiveViewModel(backend: backend)
        model.interfaceDidAppear()
        await model.setNeeds(.histogram)
        await model.setShowsStats(true)
        await backend.holdNextFrameAnalysis()
        let leaving = Task { await model.interfaceDidDisappear() }
        var held = backend.analysisHeld.makeAsyncIterator()
        _ = await held.next()
        model.interfaceDidAppear()
        await model.setNeeds(.histogram)
        await model.setShowsStats(true)
        await backend.releaseFrameAnalysis()
        await leaving.value
        #expect(model.needs == .histogram)
        #expect(model.showsStats)
        #expect(await backend.needsRequests == [.histogram, [], .histogram])
        #expect(await backend.statsSwitches == [true])
    }

    @Test func withoutALiveViewNothingIsAskedOrObserved() async {
        let model = LiveViewModel(backend: nil)
        #expect(!model.isSupported)
        await model.setNeeds(.histogram)
        await model.setShowsStats(true)
        await model.observeAnalyses()
        await model.observeStats()
        #expect(model.analysis == nil)
        #expect(model.stats == nil)
        #expect(model.needs == .histogram)
    }

    @Test func cameraModelHasALiveViewForALiveBackend() async {
        let simulated = SimulatedCaptureBackend(permission: .authorized)
        let model = CameraModel(backend: simulated)
        #expect(model.live.isSupported)
        await model.live.setNeeds([.histogram, .focusPeaking])
        await model.live.setShowsStats(true)
        await model.live.setNeeds([])
        await simulated.setStatsReadingsEnabled(false)
        simulated.finishEvents()
        await model.live.observeAnalyses()
        await model.live.observeStats()
        #expect(model.live.analysis == nil)
        #expect(model.live.stats == SimulatedCaptureBackend.placeholderStats)
        #expect(!CameraModel(backend: ScriptedBackend(capabilities: .none)).live.isSupported)
    }

    @Test func simulatedBackendSendsAnAnalysisOnlyWhenAsked() async {
        let simulated = SimulatedCaptureBackend(permission: .authorized)
        await simulated.setFrameAnalysis([])
        await simulated.setFrameAnalysis(.histogram)
        simulated.finishEvents()
        var analyses: [FrameAnalysis] = []
        for await analysis in simulated.frameAnalyses { analyses.append(analysis) }
        #expect(analyses == [SimulatedCaptureBackend.placeholderAnalysis(for: .histogram)])
        #expect(SimulatedCaptureBackend.placeholderFrame.width == 30)
    }
}
