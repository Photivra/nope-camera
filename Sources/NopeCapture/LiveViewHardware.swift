import Foundation
import NopeCore

/// The hardware calls behind ``AVFoundationCaptureBackend``'s live view: the low-rate frame
/// analysis and the live readout's values. A separate protocol from ``CaptureHardware``, so a
/// fake without a live view needs nothing extra.
///
/// ``SystemCaptureHardware`` implements it and is verified on a device.
protocol LiveViewHardware: Sendable {
    /// The analyses of live frames, while analysis is on.
    var frameAnalyses: AsyncStream<FrameAnalysis> { get }

    /// The live readout's values, while they are on.
    var statsReadings: AsyncStream<CameraStatsReading> { get }

    /// Adds, changes or removes the video output that the analysis reads.
    ///
    /// - Parameter needs: What to measure; empty removes the output.
    func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async

    /// Starts or stops observing the attached camera for the live readout.
    ///
    /// - Parameter enabled: Whether to send values.
    func setStatsReadingsEnabled(_ enabled: Bool) async
}

extension AVFoundationCaptureBackend: LiveViewBackend {
    /// An empty stream that has already ended, for hardware without a live view.
    private nonisolated static var endedAnalyses: AsyncStream<FrameAnalysis> {
        AsyncStream { $0.finish() }
    }

    /// The live frame analyses from the hardware; a stream that ends at once if the hardware has
    /// no live view.
    public nonisolated var frameAnalyses: AsyncStream<FrameAnalysis> {
        liveHardware?.frameAnalyses ?? Self.endedAnalyses
    }

    /// The live readout's values from the hardware; a stream that ends at once if the hardware
    /// has no live view.
    public nonisolated var statsReadings: AsyncStream<CameraStatsReading> {
        liveHardware?.statsReadings ?? AsyncStream { $0.finish() }
    }

    /// Starts, changes or stops the live frame analysis.
    ///
    /// - Parameter needs: What to measure; empty stops it.
    public func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async {
        await liveHardware?.setFrameAnalysis(needs)
    }

    /// Turns the live readout's values on or off.
    ///
    /// - Parameter enabled: Whether to send values.
    public func setStatsReadingsEnabled(_ enabled: Bool) async {
        await liveHardware?.setStatsReadingsEnabled(enabled)
    }
}
