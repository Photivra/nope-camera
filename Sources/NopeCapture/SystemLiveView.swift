import AVFoundation
import NopeCore
import os

// Hardware adapter: every call here needs a camera, so this file is listed in
// scripts/coverage-exclusions.txt and verified on a device (docs/TESTING.md, "On-device checks").
// Decisions are made in tested files: LumaSampler (which pixels), FrameAnalysis (histogram,
// clipping and peaking), LiveUpdateRate and RateLimiter (how often).

extension SystemCaptureHardware: LiveViewHardware {
    /// The analyses of live frames, while analysis is on.
    var frameAnalyses: AsyncStream<FrameAnalysis> { live.frameAnalyses }

    /// The live readout's values, while they are on.
    var statsReadings: AsyncStream<CameraStatsReading> { live.statsReadings }

    /// Adds, changes or removes the analysis video output, on the session queue.
    ///
    /// - Parameter needs: What to measure; empty removes the output.
    func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async {
        await live.setNeeds(needs)
    }

    /// Starts or stops observing the camera for the live readout, on the session queue.
    ///
    /// - Parameter enabled: Whether to send values.
    func setStatsReadingsEnabled(_ enabled: Bool) async {
        await live.setStatsEnabled(enabled)
    }
}

/// The live view of ``SystemCaptureHardware``: a low-rate frame analysis for the histogram and
/// focus peaking (issues #47 and #51), and the live readout's values (issue #52).
///
/// - **Frame analysis.** An `AVCaptureVideoDataOutput` is in the session only while the histogram
///   or focus peaking is shown. With the `.photo` preset it delivers preview-sized frames
///   ("it is assumed that video data output buffers are being delivered as a preview proxy",
///   `AVCaptureVideoDataOutput.h`, `automaticallyConfiguresOutputBufferDimensions`). Late frames
///   are dropped, every frame between two analyses is returned at once, and an analysis reads
///   only about 160 × 120 pixels (``LumaSampler``), at most four a second (`LiveUpdateRate`).
///   No frame is stored. The photo output and its settings are not touched, so what is captured
///   doesn't change; a device check confirms it (docs/TESTING.md).
/// - **Live readout.** Key-value observation of the attached camera while the readout is shown,
///   at most four values a second. No video is read for it.
///
/// `@unchecked Sendable`: every mutable property is confined to the session `queue`, and the
/// video delegate keeps its own state behind a lock.
final class SystemLiveView: @unchecked Sendable {
    /// The analyses of live frames.
    let frameAnalyses: AsyncStream<FrameAnalysis>

    /// The live readout's values.
    let statsReadings: AsyncStream<CameraStatsReading>

    /// Feeds ``statsReadings``.
    private let statsContinuation: AsyncStream<CameraStatsReading>.Continuation

    /// The capture session, owned by ``SystemCaptureHardware``.
    private let session: AVCaptureSession

    /// The photo output, read for the readout's processing switches and readiness only.
    private let photoOutput: AVCapturePhotoOutput

    /// The session queue every session call runs on.
    private let queue: DispatchQueue

    /// The video output the analysis reads, in the session only while analysis is on.
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Receives the video frames and analyzes some of them.
    private let delegate: FrameAnalysisDelegate

    /// The queue video frames arrive on, apart from the session queue so a slow analysis never
    /// delays a capture.
    private let videoQueue = DispatchQueue(label: "com.photivra.nope.live-analysis")

    /// What the analysis is asked for. Queue-confined.
    private var needs: LiveAnalysisNeeds = []

    /// The attached camera, or `nil`. Queue-confined.
    private var device: AVCaptureDevice?

    /// Whether the readout is on. Queue-confined.
    private var statsEnabled = false

    /// The readout's key-value observations. Queue-confined.
    private var statsObservations: [NSKeyValueObservation] = []

    /// Limits the readout to four values a second. Touched from key-value observation callbacks,
    /// which may arrive on any thread, so it is locked.
    private let statsLimiter = OSAllocatedUnfairLock(initialState: RateLimiter())

    /// Creates the live view for a session.
    ///
    /// - Parameters:
    ///   - session: The capture session.
    ///   - photoOutput: The photo output.
    ///   - queue: The session queue.
    ///   - rotation: The viewfinder's rotation, which the analysis follows.
    init(session: AVCaptureSession, photoOutput: AVCapturePhotoOutput, queue: DispatchQueue, rotation: PreviewRotation) {
        self.session = session
        self.photoOutput = photoOutput
        self.queue = queue
        let (analyses, analysesContinuation) = AsyncStream.makeStream(
            of: FrameAnalysis.self, bufferingPolicy: .bufferingNewest(1))
        frameAnalyses = analyses
        (statsReadings, statsContinuation) = AsyncStream.makeStream(
            of: CameraStatsReading.self, bufferingPolicy: .bufferingNewest(1))
        delegate = FrameAnalysisDelegate(continuation: analysesContinuation, rotation: rotation)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Full-range luma (0 to 255) when offered; otherwise the device's own format, whose
        // video range LumaPlane converts.
        let fullRange = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        if videoOutput.availableVideoPixelFormatTypes.contains(fullRange) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: fullRange]
        }
        videoOutput.setSampleBufferDelegate(delegate, queue: videoQueue)
    }

    deinit {
        statsObservations.forEach { $0.invalidate() }
        delegate.finish()
        statsContinuation.finish()
    }

    /// Asks the analysis for something else, adding or removing the video output, on `queue`.
    ///
    /// - Parameter needs: What to measure.
    func setNeeds(_ needs: LiveAnalysisNeeds) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.needs = needs
                self.delegate.update(needs: needs)
                if self.device != nil {
                    self.session.beginConfiguration()
                    self.updateVideoOutput()
                    self.session.commitConfiguration()
                }
                continuation.resume()
            }
        }
    }

    /// Adds the video output while analysis is on and a camera is attached, and removes it
    /// otherwise. Call only on `queue`, inside a configuration transaction.
    func updateVideoOutput() {
        let isAttached = session.outputs.contains(videoOutput)
        let isNeeded = !needs.isEmpty && device != nil
        if isNeeded && !isAttached {
            guard session.canAddOutput(videoOutput) else { return }
            session.addOutput(videoOutput)
            // The analysis turns and mirrors its small grid itself, to match the viewfinder.
            if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        } else if !isNeeded && isAttached {
            session.removeOutput(videoOutput)
        }
    }

    /// Follows a newly attached camera, or none. Call only on `queue`.
    ///
    /// - Parameter device: The attached camera, or `nil` after the teardown.
    func cameraDidChange(_ device: AVCaptureDevice?) {
        self.device = device
        delegate.update(mirrored: device?.position == .front)
        observeStats()
    }

    /// Starts or stops the readout, on `queue`.
    ///
    /// - Parameter enabled: Whether to send values.
    func setStatsEnabled(_ enabled: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.statsEnabled = enabled
                self.observeStats()
                continuation.resume()
            }
        }
    }

    /// Observes the attached camera while the readout is on, and stops observing otherwise.
    /// Call only on `queue`.
    ///
    /// Any of the exposure offset (which changes as the meter updates), the lens position, the
    /// focus activity, the torch or the system pressure triggers one reading of every value, at
    /// most four times a second.
    private func observeStats() {
        statsObservations.forEach { $0.invalidate() }
        statsObservations = []
        guard statsEnabled, let device else { return }
        let send: @Sendable (AVCaptureDevice) -> Void = { [weak self] device in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard statsLimiter.withLock({ $0.shouldPass(at: now, interval: LiveUpdateRate.normalInterval) }) else {
                return
            }
            statsContinuation.yield(Self.reading(of: device, photoOutput: photoOutput))
        }
        statsObservations = [
            device.observe(\.exposureTargetOffset, options: [.initial]) { device, _ in send(device) },
            device.observe(\.lensPosition) { device, _ in send(device) },
            device.observe(\.isAdjustingFocus) { device, _ in send(device) },
            device.observe(\.torchLevel) { device, _ in send(device) },
            device.observe(\.systemPressureState) { device, _ in send(device) },
        ]
    }

    /// Everything the readout shows that the camera and the photo output report now.
    ///
    /// - Parameters:
    ///   - device: The attached camera.
    ///   - photoOutput: The photo output.
    private static func reading(of device: AVCaptureDevice, photoOutput: AVCapturePhotoOutput) -> CameraStatsReading {
        let gains = device.deviceWhiteBalanceGains
        let maximum = device.maxWhiteBalanceGain
        // Converting gains outside 1...maxWhiteBalanceGain raises an exception (AVCaptureDevice.h).
        let inRange = [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy { $0 >= 1 && $0 <= maximum }
        var whiteBalance: WhiteBalance?
        if inRange {
            let values = device.temperatureAndTintValues(for: gains)
            whiteBalance = WhiteBalance(temperature: Double(values.temperature), tint: Double(values.tint))
        }
        return CameraStatsReading(
            iso: Double(device.iso), exposureDuration: device.exposureDuration.seconds,
            exposureBias: Double(device.exposureTargetBias), exposureOffset: Double(device.exposureTargetOffset),
            aperture: Double(device.lensAperture), exposureMode: exposureMode(device.exposureMode),
            lensPosition: Double(device.lensPosition), focusMode: focusMode(device.focusMode),
            isAdjustingFocus: device.isAdjustingFocus,
            focusRange: device.isAutoFocusRangeRestrictionSupported ? focusRange(device.autoFocusRangeRestriction) : nil,
            whiteBalance: whiteBalance,
            gains: WhiteBalanceGainsReading(
                red: Double(gains.redGain), green: Double(gains.greenGain), blue: Double(gains.blueGain)),
            whiteBalanceMode: device.whiteBalanceMode == .locked ? .locked : .auto,
            zoomFactor: Double(device.videoZoomFactor), processingOn: processingOn(device: device, photoOutput: photoOutput),
            isReadyToCapture: photoOutput.captureReadiness == .ready,
            systemPressure: pressure(device.systemPressureState.level),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            torchLevel: device.hasTorch ? Double(device.torchLevel) : nil)
    }

    /// The processing features that are on, as the camera and the photo output report them.
    ///
    /// - Parameters:
    ///   - device: The attached camera.
    ///   - photoOutput: The photo output.
    private static func processingOn(device: AVCaptureDevice, photoOutput: AVCapturePhotoOutput) -> Set<ProcessingFeature> {
        var on: Set<ProcessingFeature> = []
        if photoOutput.maxPhotoQualityPrioritization != .speed { on.insert(.qualityPrioritization) }
        if photoOutput.isAppleProRAWEnabled { on.insert(.appleProRAW) }
        if photoOutput.isZeroShutterLagEnabled { on.insert(.zeroShutterLag) }
        if photoOutput.isResponsiveCaptureEnabled { on.insert(.responsiveCapture) }
        if photoOutput.isAutoDeferredPhotoDeliveryEnabled { on.insert(.deferredDelivery) }
        if photoOutput.isConstantColorEnabled { on.insert(.constantColor) }
        if photoOutput.isContentAwareDistortionCorrectionEnabled { on.insert(.contentAwareDistortionCorrection) }
        if device.isGeometricDistortionCorrectionEnabled { on.insert(.geometricDistortionCorrection) }
        return on
    }

    /// Converts the exposure mode.
    ///
    /// - Parameter mode: The camera's mode.
    private static func exposureMode(_ mode: AVCaptureDevice.ExposureMode) -> ExposureModeReading {
        switch mode {
        case .locked: .locked
        case .custom: .custom
        default: .auto
        }
    }

    /// Converts the focus mode.
    ///
    /// - Parameter mode: The camera's mode.
    private static func focusMode(_ mode: AVCaptureDevice.FocusMode) -> FocusModeReading {
        switch mode {
        case .locked: .locked
        case .autoFocus: .auto
        default: .continuousAuto
        }
    }

    /// Converts the autofocus range restriction.
    ///
    /// - Parameter restriction: The camera's restriction.
    private static func focusRange(_ restriction: AVCaptureDevice.AutoFocusRangeRestriction) -> FocusRangeReading {
        switch restriction {
        case .near: .near
        case .far: .far
        default: .none
        }
    }

    /// Converts the system pressure level. A level added in a later iOS reads as serious.
    ///
    /// - Parameter level: The camera's pressure level.
    private static func pressure(_ level: AVCaptureDevice.SystemPressureState.Level) -> SystemPressureReading {
        switch level {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        case .shutdown: .shutdown
        default: .serious
        }
    }
}

/// Receives the analysis video output's frames, lets through a few a second, and analyzes them.
///
/// `@unchecked Sendable`: frames arrive one at a time on the video queue, and the state set from
/// the session queue is behind a lock.
final class FrameAnalysisDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// What the analysis needs, whether the viewfinder mirrors, and when the last frame was let
    /// through.
    private struct State {
        /// What to measure.
        var needs: LiveAnalysisNeeds = []
        /// Whether the viewfinder mirrors the picture (the front camera).
        var mirrored = false
        /// Limits the analyses.
        var limiter = RateLimiter()
    }

    /// The state, set from the session queue and read on the video queue.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Feeds the analyses.
    private let continuation: AsyncStream<FrameAnalysis>.Continuation

    /// The viewfinder's rotation, whose angle the analysis follows.
    private let rotation: PreviewRotation

    /// Creates the delegate.
    ///
    /// - Parameters:
    ///   - continuation: Feeds the analyses.
    ///   - rotation: The viewfinder's rotation.
    init(continuation: AsyncStream<FrameAnalysis>.Continuation, rotation: PreviewRotation) {
        self.continuation = continuation
        self.rotation = rotation
    }

    /// Changes what is measured.
    ///
    /// - Parameter needs: What to measure.
    func update(needs: LiveAnalysisNeeds) {
        state.withLock { $0.needs = needs }
    }

    /// Changes whether the viewfinder mirrors the picture.
    ///
    /// - Parameter mirrored: Whether it mirrors.
    func update(mirrored: Bool) {
        state.withLock { $0.mirrored = mirrored }
    }

    /// Ends the analyses.
    func finish() {
        continuation.finish()
    }

    /// Analyzes a frame if one is due, and returns at once otherwise.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        let interval = LiveUpdateRate.interval(
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            heat: HeatLevel(ProcessInfo.processInfo.thermalState))
        let due = state.withLock { state -> (LiveAnalysisNeeds, Bool)? in
            guard !state.needs.isEmpty, state.limiter.shouldPass(at: now, interval: interval) else { return nil }
            return (state.needs, state.mirrored)
        }
        guard let (needs, mirrored) = due, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let frame = Self.sample(pixelBuffer) else { return }
        let quarterTurns = Int(((rotation.previewAngle ?? 0) / 90).rounded())
        continuation.yield(FrameAnalysis(frame: frame.oriented(quarterTurns: quarterTurns, mirrored: mirrored), needs: needs))
    }

    /// Samples the brightness plane of a frame.
    ///
    /// Privacy rule: the pixels are read in place for this one analysis; nothing is copied
    /// whole, stored or logged.
    ///
    /// - Parameter pixelBuffer: The frame.
    /// - Returns: The sampled grid, or `nil` for a frame without a planar luma plane.
    private static func sample(_ pixelBuffer: CVPixelBuffer) -> LumaFrame? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let fullRange = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let videoRange = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard format == fullRange || format == videoRange else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let plane = LumaPlane(
            width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0), height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0), isVideoRange: format == videoRange
        ) { offset in
            // LumaSampler reads only offsets inside the plane (tested), so each read is in bounds.
            base.load(fromByteOffset: offset, as: UInt8.self)
        }
        return LumaSampler.sample(plane)
    }
}
