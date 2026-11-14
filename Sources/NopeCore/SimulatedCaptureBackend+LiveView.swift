import Foundation

extension SimulatedCaptureBackend: LiveViewBackend {
    /// The size of the simulated preview grid: 30 × 40 cells, a 4:3 frame held upright, as the
    /// viewfinder shows it.
    static let placeholderFrameSize = (width: 30, height: 40)

    /// A simulated preview frame: a left-to-right brightness ramp whose brightest columns are
    /// clipped white, with a sharp vertical edge down the middle. It is analyzed like a real
    /// frame, so the histogram flags clipped highlights and focus peaking marks the edge.
    public static var placeholderFrame: LumaFrame {
        let (width, height) = placeholderFrameSize
        var luma: [UInt8] = []
        var edges: [UInt8] = []
        for _ in 0..<height {
            for column in 0..<width {
                luma.append(UInt8(min(255, column * 255 / (width - 4))))
                edges.append(column == width / 2 ? 200 : 0)
            }
        }
        return LumaFrame(width: width, height: height, luma: luma, edges: edges)
    }

    /// The analysis sent when analysis is asked for: ``placeholderFrame``, analyzed for the
    /// needs.
    ///
    /// - Parameter needs: What was asked for.
    public static func placeholderAnalysis(for needs: LiveAnalysisNeeds) -> FrameAnalysis {
        FrameAnalysis(frame: placeholderFrame, needs: needs)
    }

    /// The values sent when the live readout is turned on: those of ``placeholderReading``, in
    /// auto, with every processing feature off, ready, and no pressure.
    public static let placeholderStats = CameraStatsReading(
        iso: 100, exposureDuration: 1.0 / 120.0, exposureBias: 0, exposureOffset: 0, aperture: 1.8,
        exposureMode: .auto, lensPosition: 0.5, focusMode: .continuousAuto, isAdjustingFocus: false,
        focusRange: FocusRangeReading.none, whiteBalance: WhiteBalance(temperature: 5200),
        gains: WhiteBalanceGainsReading(red: 1.9, green: 1, blue: 1.7), whiteBalanceMode: .auto, zoomFactor: 1,
        processingOn: [], isReadyToCapture: true, systemPressure: .nominal, isLowPowerMode: false, torchLevel: nil)

    /// Sends ``placeholderAnalysis(for:)`` when analysis is asked for; nothing when it stops.
    ///
    /// - Parameter needs: What to measure.
    public func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async {
        if !needs.isEmpty { analysesContinuation.yield(Self.placeholderAnalysis(for: needs)) }
    }

    /// Sends ``placeholderStats`` when the readout is turned on.
    ///
    /// - Parameter enabled: Whether the readout is on.
    public func setStatsReadingsEnabled(_ enabled: Bool) async {
        if enabled { statsContinuation.yield(Self.placeholderStats) }
    }
}
