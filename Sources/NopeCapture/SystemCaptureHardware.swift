import AVFoundation
import NopeCore
import os

// Hardware adapter: every call here needs a camera, so this file is listed in
// scripts/coverage-exclusions.txt and verified on a device (docs/TESTING.md, "On-device checks").
// Decisions are made in tested files: LensCatalog (which cameras), CapturePolicy (which
// switches), PhotoSettingsFactory (which photo settings) and CaptureReadiness (when to capture).

extension AVFoundationCaptureBackend {
    /// Creates the backend for the device's cameras, with the system permission prompt.
    public init() {
        self.init(hardware: SystemCaptureHardware(), authorization: SystemCameraAuthorization())
    }
}

/// The AVFoundation implementation of ``CaptureHardware``: one `AVCaptureSession` with one
/// camera input and one photo output, configured on a private serial queue.
///
/// It owns the app's only capture session: lens switches replace the camera input inside one
/// configuration transaction on the same session, and ``stop()`` tears the session down in a
/// fixed order before anything else may configure it (docs/TESTING.md, "Black frames": after
/// the earlier Debug tag check built its own session per lens, the camera service delivered
/// blank frames to every app session until the phone was restarted).
///
/// Setup order: the `.photo` preset, camera input and photo output are committed first, so
/// the camera's active format is the photo format; then the output's processing switches and
/// an explicit `maxPhotoDimensions` from that format are committed before `startRunning()`, as
/// `AVCapturePhotoOutput.h` recommends for settings that reconfigure the pipeline; then the
/// photo settings are prepared (`setPreparedPhotoSettingsArray`), because RAW captures need
/// extra buffers; and each capture waits for `captureReadiness` to be `.ready`.
///
/// `@unchecked Sendable`: every mutable property and every session call is confined to
/// `queue`.
final class SystemCaptureHardware: CaptureHardware, @unchecked Sendable {
    /// The physical camera types nope. uses. Virtual multi-camera devices are never used.
    private static let physicalDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]

    /// The longest wait for the photo output to become ready, in seconds. A tool setting: the
    /// output accepts requests when not ready, just more slowly.
    private static let readinessTimeoutSeconds = 2.0

    /// How often to check readiness, in seconds.
    private static let readinessPollSeconds = 0.02

    /// The longest wait for `setPreparedPhotoSettingsArray` to finish, in seconds. Preparing is
    /// optional (`AVCapturePhotoOutput.h`), so configuration continues after it.
    private static let prepareTimeoutSeconds = 5.0

    /// Interruptions, heat changes and runtime errors.
    let events: AsyncStream<CaptureEvent>

    /// The session, for the app's preview layer.
    let previewSource: any CameraPreviewSource

    /// The same preview source, typed, for its rotation.
    private let preview: CaptureSessionPreviewSource

    /// Feeds ``events``.
    private let continuation: AsyncStream<CaptureEvent>.Continuation

    /// What the camera is using now, while readings are on.
    let exposureReadings: AsyncStream<ExposureReading>

    /// Feeds ``exposureReadings``.
    private let readingsContinuation: AsyncStream<ExposureReading>.Continuation

    /// Whether readings are on. Queue-confined.
    private var readingsEnabled = false

    /// The key-value observations of the attached camera while readings are on. Queue-confined.
    private var readingObservations: [NSKeyValueObservation] = []

    /// Limits readings to four a second. Touched from key-value observation callbacks, which
    /// may arrive on any thread, so it is locked.
    private let throttle = OSAllocatedUnfairLock(initialState: ReadingThrottle())

    /// The capture session.
    private let session = AVCaptureSession()

    /// The photo output.
    private let photoOutput = AVCapturePhotoOutput()

    /// The serial queue every session call runs on, because `startRunning()` blocks.
    private let queue = DispatchQueue(label: "com.photivra.nope.capture")

    /// The current camera input. Queue-confined.
    private var currentInput: AVCaptureDeviceInput?

    /// The photo output's `maxPhotoDimensions` as last applied. Queue-confined.
    private var appliedMaxDimensions: PhotoDimensions?

    /// Delegates of captures in progress, keyed by settings `uniqueID`; the photo output keeps
    /// only a weak reference to its delegate. Queue-confined.
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]

    /// Notification observer tokens, removed on deinit.
    private var observers: [any NSObjectProtocol] = []

    /// Logs failures without values (AGENTS.md, "Logs mark every value private").
    private let logger = Logger(subsystem: "com.photivra.nope", category: "Capture")

    /// Creates the hardware adapter and starts observing interruptions, runtime errors and the
    /// thermal state.
    init() {
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        (exposureReadings, readingsContinuation) = AsyncStream.makeStream(of: ExposureReading.self)
        preview = CaptureSessionPreviewSource(session: session)
        previewSource = preview
        observeNotifications()
        continuation.yield(.heat(HeatLevel(ProcessInfo.processInfo.thermalState)))
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        readingObservations.forEach { $0.invalidate() }
        continuation.finish()
        readingsContinuation.finish()
    }

    // MARK: - CaptureHardware

    /// Lists the physical cameras, attaching each one to read its photo format and RAW formats.
    func discoverCameras() async -> [CameraDeviceDescription] {
        await perform {
            AVCaptureDevice.DiscoverySession(
                deviceTypes: Self.physicalDeviceTypes, mediaType: .video, position: .unspecified
            ).devices.compactMap(self.describe)
        }
    }

    /// Configures, starts and prepares the session for one camera.
    func configure(_ configuration: SessionConfiguration) async throws(CaptureError) {
        let result: Result<Void, CaptureError> = await withCheckedContinuation { continuation in
            queue.async {
                do throws(CaptureError) {
                    try self.apply(configuration)
                } catch {
                    continuation.resume(returning: .failure(error))
                    return
                }
                self.prepare(configuration.photoSettings) { continuation.resume(returning: .success(())) }
            }
        }
        try result.get()
    }

    /// Stops the session and tears it down, strictly in order, on `queue`.
    ///
    /// 1. `stopRunning()`, which "is synchronous and blocks until the receiver has completely
    ///    stopped running" (`AVCaptureSession.h`), so nothing below overlaps a running session.
    /// 2. The camera input and the photo output are removed in one configuration transaction.
    ///
    /// The method returns only after both steps, because the caller awaits `perform`. The next
    /// ``configure(_:)`` re-adds the input and output with the full setup order. This is the
    /// only way a session is taken down: nope. never creates a second session, and never
    /// starts one while another is still stopping (docs/TESTING.md, "Black frames").
    func stop() async {
        await perform { self.tearDown() }
    }

    /// Waits until the output is ready, then takes one photo.
    func capture(_ plan: PhotoSettingsPlan, metadata: MetadataPlan) async throws(CaptureError) -> HardwarePhoto {
        _ = try await CaptureReadiness.waitUntilReady(
            timeout: Self.readinessTimeoutSeconds, interval: Self.readinessPollSeconds
        ) {
            await self.perform { CaptureReadiness(self.photoOutput.captureReadiness) }
        }
        let result: Result<HardwarePhoto, CaptureError> = await withCheckedContinuation { continuation in
            queue.async { self.startCapture(plan, metadata: metadata) { continuation.resume(returning: $0) } }
        }
        return try result.get()
    }

    /// Sets exposure, focus, white balance and metering on the attached camera, on `queue`.
    func apply(_ controls: DeviceControls) async throws(CaptureError) {
        let result: Result<Void, CaptureError> = await perform { self.applyControls(controls) }
        try result.get()
    }

    /// Starts or stops the readings, on `queue`.
    func setReadingsEnabled(_ enabled: Bool) async {
        await perform {
            self.readingsEnabled = enabled
            self.observeReadings()
        }
    }

    /// Waits until the output is ready, then takes a manual exposure bracket.
    func captureBracket(
        _ plan: PhotoSettingsPlan, frames: [BracketFrame], metadata: MetadataPlan
    ) async throws(CaptureError)
        -> [HardwarePhoto]
    {
        _ = try await CaptureReadiness.waitUntilReady(
            timeout: Self.readinessTimeoutSeconds, interval: Self.readinessPollSeconds
        ) {
            await self.perform { CaptureReadiness(self.photoOutput.captureReadiness) }
        }
        let result: Result<[HardwarePhoto], CaptureError> = await withCheckedContinuation { continuation in
            queue.async {
                guard self.session.isRunning, let device = self.currentInput?.device else {
                    continuation.resume(returning: .failure(.notRunning))
                    return
                }
                let settings = PhotoSettingsFactory.makeBracketSettings(
                    for: plan, frames: frames, maxPhotoDimensions: self.appliedMaxDimensions)
                self.startCapture(settings, device: device, plan: plan, metadata: metadata) {
                    continuation.resume(returning: $0)
                }
            }
        }
        return try result.get()
    }

    // MARK: - Queue-confined work

    /// Stops the session, waits for it to stop, then removes every input and output. Call only
    /// on `queue`.
    private func tearDown() {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        currentInput = nil
        appliedMaxDimensions = nil
        observeReadings()
    }

    /// Runs work on `queue` and returns its result.
    ///
    /// - Parameter work: The work, which may call the session.
    private func perform<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Attaches a camera with the `.photo` preset and the photo output, Apple ProRAW off.
    /// Does nothing if the camera is already attached.
    ///
    /// - Parameter device: The camera.
    /// - Returns: `false` if the session refused the camera or the output.
    private func attach(_ device: AVCaptureDevice) -> Bool {
        if currentInput?.device.uniqueID == device.uniqueID, session.outputs.contains(photoOutput) {
            return true
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        currentInput = input
        observeReadings()
        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { return false }
            session.addOutput(photoOutput)
        }
        // ProRAW is demosaiced and may be multi-frame; only Bayer RAW is listed (AGENTS.md).
        photoOutput.isAppleProRAWEnabled = false
        return true
    }

    /// Describes one camera after attaching it. Returns `nil` for virtual devices and cameras
    /// the session refuses.
    ///
    /// - Parameter device: A camera from the discovery session.
    private func describe(_ device: AVCaptureDevice) -> CameraDeviceDescription? {
        guard !device.isVirtualDevice, attach(device) else { return nil }
        let format = device.activeFormat
        return CameraDeviceDescription(
            uniqueID: device.uniqueID,
            deviceType: .init(device.deviceType),
            position: .init(device.position),
            isVirtual: device.isVirtualDevice,
            rawPixelFormats: photoOutput.availableRawPhotoPixelFormatTypes.map {
                .init(code: $0, isBayer: AVCapturePhotoOutput.isBayerRAWPixelFormat($0))
            },
            supportsHEVC: photoOutput.availablePhotoCodecTypes.contains(.hevc),
            isoRange: Double(format.minISO)...Double(max(format.minISO, format.maxISO)),
            exposureDurationRange: format.minExposureDuration.seconds...max(
                format.minExposureDuration.seconds, format.maxExposureDuration.seconds),
            aperture: Self.aperture(of: device),
            maxBracketedPhotoCount: photoOutput.maxBracketedCapturePhotoCount,
            photoDimensions: format.supportedMaxPhotoDimensions.map {
                PhotoDimensions(width: Int($0.width), height: Int($0.height))
            },
            fieldOfViewDegrees: Double(format.videoFieldOfView),
            manualControls: Self.manualSupport(of: device)
        )
    }

    /// The camera's answers about manual control, for its active (photo) format.
    ///
    /// - Parameter device: An attached camera.
    private static func manualSupport(of device: AVCaptureDevice) -> ManualControlSupport {
        var shutterPriority = false
        var isoPriority = false
        var aperturePriority = false
        if #available(iOS 27.0, *) {
            let format = device.activeFormat
            shutterPriority = format.supportsExposureModeCustom(
                lensAperture: AVCaptureDevice.autoLensAperture, duration: AVCaptureDevice.currentExposureDuration,
                iso: AVCaptureDevice.autoISO)
            isoPriority = format.supportsExposureModeCustom(
                lensAperture: AVCaptureDevice.autoLensAperture, duration: AVCaptureDevice.autoExposureDuration,
                iso: AVCaptureDevice.currentISO)
            aperturePriority =
                format.maxLensAperture > format.minLensAperture
                && format.supportsExposureModeCustom(
                    lensAperture: AVCaptureDevice.currentLensAperture, duration: AVCaptureDevice.autoExposureDuration,
                    iso: AVCaptureDevice.autoISO)
        }
        var exposureRegion = false
        if #available(iOS 26.0, *) { exposureRegion = device.isExposureRectOfInterestSupported }
        return ManualControlSupport(
            customExposure: device.isExposureModeSupported(.custom),
            continuousAutoExposure: device.isExposureModeSupported(.continuousAutoExposure),
            lockedExposure: device.isExposureModeSupported(.locked),
            shutterPriority: shutterPriority,
            isoPriority: isoPriority,
            aperturePriority: aperturePriority,
            exposureBiasRange: Double(device.minExposureTargetBias)...Double(
                max(device.minExposureTargetBias, device.maxExposureTargetBias)),
            continuousAutoFocus: device.isFocusModeSupported(.continuousAutoFocus),
            lockedFocus: device.isFocusModeSupported(.locked),
            lensPositionFocus: device.isLockingFocusWithCustomLensPositionSupported,
            customWhiteBalance: device.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            exposureRegion: exposureRegion)
    }

    /// Applies controls to the attached camera. Call only on `queue`.
    ///
    /// Every value was checked against the lens in `NopeCore`; each is limited again to the
    /// active format's own range here, because an out-of-range value raises an Objective-C
    /// exception (`AVCaptureDevice.h`), and a priority combination is set only when the format
    /// reports it supported.
    ///
    /// - Parameter controls: The controls.
    /// - Returns: `.notRunning` without a camera, `.configurationFailed` if it can't be locked.
    private func applyControls(_ controls: DeviceControls) -> Result<Void, CaptureError> {
        guard let device = currentInput?.device else { return .failure(.notRunning) }
        do {
            try device.lockForConfiguration()
        } catch {
            logger.error("Capture: the camera could not be locked for manual controls")
            return .failure(.configurationFailed)
        }
        defer { device.unlockForConfiguration() }
        applyMetering(controls.metering, to: device)
        applyExposure(controls.exposure, to: device)
        applyFocus(controls.focus, to: device)
        applyWhiteBalance(controls.whiteBalance, to: device)
        return .success(())
    }

    /// Sets the metering region. Call only on `queue`, with the camera locked.
    ///
    /// - Parameters:
    ///   - metering: The metering mode.
    ///   - device: The camera.
    private func applyMetering(_ metering: MeteringMode, to device: AVCaptureDevice) {
        if #available(iOS 26.0, *), device.isExposureRectOfInterestSupported {
            let minimum = device.minExposureRectOfInterestSize
            if let region = MeteringRegion.region(
                for: metering, minimumWidth: Double(minimum.width), minimumHeight: Double(minimum.height))
            {
                device.exposureRectOfInterest = CGRect(
                    x: region.x, y: region.y, width: region.width, height: region.height)
                return
            }
        }
        // Setting the point resets the region to its default size (AVCaptureDevice.h).
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
    }

    /// Sets the exposure. Call only on `queue`, with the camera locked.
    ///
    /// - Parameters:
    ///   - exposure: The exposure.
    ///   - device: The camera.
    private func applyExposure(_ exposure: DeviceControls.Exposure, to device: AVCaptureDevice) {
        switch exposure {
        case .automatic(let compensation):
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            setBias(compensation, on: device)
        case .locked:
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        case .custom(let iso, let duration, let aperture, let compensation):
            guard device.isExposureModeSupported(.custom) else { return }
            let format = device.activeFormat
            if #available(iOS 27.0, *) {
                let isoValue = Self.iso(iso, format: format)
                let durationValue = Self.duration(duration, format: format)
                let apertureValue = Self.aperture(aperture, format: format)
                guard format.supportsExposureModeCustom(lensAperture: apertureValue, duration: durationValue, iso: isoValue)
                else {
                    logger.error("Capture: the camera does not support this exposure combination")
                    return
                }
                device.setExposureModeCustom(
                    lensAperture: apertureValue, duration: durationValue, iso: isoValue, completionHandler: nil)
                setBias(compensation, on: device)
            } else if case .value = iso, case .value = duration {
                // Before iOS 27 only fixed ISO and duration exist; NopeCore asks for nothing else.
                device.setExposureModeCustom(
                    duration: Self.duration(duration, format: format), iso: Self.iso(iso, format: format),
                    completionHandler: nil)
            }
        }
    }

    /// Sets the exposure bias, limited to the camera's range.
    ///
    /// - Parameters:
    ///   - compensation: The bias, in EV.
    ///   - device: The camera, locked.
    private func setBias(_ compensation: Double, on device: AVCaptureDevice) {
        let bias = min(max(Float(compensation), device.minExposureTargetBias), device.maxExposureTargetBias)
        device.setExposureTargetBias(bias, completionHandler: nil)
    }

    /// The ISO argument for a parameter, limited to the format's range.
    ///
    /// - Parameters:
    ///   - parameter: The ISO parameter.
    ///   - format: The active format.
    private static func iso(_ parameter: DeviceControls.Parameter, format: AVCaptureDevice.Format) -> Float {
        switch parameter {
        case .value(let iso): return min(max(Float(iso), format.minISO), format.maxISO)
        case .current: return AVCaptureDevice.currentISO
        case .auto:
            if #available(iOS 27.0, *) { return AVCaptureDevice.autoISO }
            return AVCaptureDevice.currentISO
        }
    }

    /// The duration argument for a parameter, limited to the format's range.
    ///
    /// - Parameters:
    ///   - parameter: The duration parameter, in seconds.
    ///   - format: The active format.
    private static func duration(_ parameter: DeviceControls.Parameter, format: AVCaptureDevice.Format) -> CMTime {
        switch parameter {
        case .value(let seconds):
            let time = CMTime(seconds: seconds, preferredTimescale: PhotoSettingsFactory.durationTimescale)
            return CMTimeClampToRange(
                time, range: CMTimeRange(start: format.minExposureDuration, end: format.maxExposureDuration))
        case .current: return AVCaptureDevice.currentExposureDuration
        case .auto:
            if #available(iOS 27.0, *) { return AVCaptureDevice.autoExposureDuration }
            return AVCaptureDevice.currentExposureDuration
        }
    }

    /// The aperture argument for a parameter, limited to the format's range (iOS 27).
    ///
    /// - Parameters:
    ///   - parameter: The aperture parameter, as an f-number.
    ///   - format: The active format.
    @available(iOS 27.0, *)
    private static func aperture(_ parameter: DeviceControls.Parameter, format: AVCaptureDevice.Format) -> Float {
        switch parameter {
        case .value(let fNumber): min(max(Float(fNumber), format.minLensAperture), format.maxLensAperture)
        case .current: AVCaptureDevice.currentLensAperture
        case .auto: AVCaptureDevice.autoLensAperture
        }
    }

    /// Sets the focus. Call only on `queue`, with the camera locked.
    ///
    /// - Parameters:
    ///   - focus: The focus.
    ///   - device: The camera.
    private func applyFocus(_ focus: DeviceControls.Focus, to device: AVCaptureDevice) {
        switch focus {
        case .automatic:
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        case .locked:
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        case .lensPosition(let position):
            guard device.isLockingFocusWithCustomLensPositionSupported else { return }
            device.setFocusModeLocked(lensPosition: Float(min(max(position, 0), 1)), completionHandler: nil)
        }
    }

    /// Sets the white balance. Call only on `queue`, with the camera locked.
    ///
    /// - Parameters:
    ///   - whiteBalance: The white balance.
    ///   - device: The camera.
    private func applyWhiteBalance(_ whiteBalance: DeviceControls.WhiteBalanceControl, to device: AVCaptureDevice) {
        switch whiteBalance {
        case .automatic:
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        case .fixed(let balance):
            guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
            let gains = device.deviceWhiteBalanceGains(
                for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(balance.temperature), tint: Float(balance.tint)))
            let limited = WhiteBalanceGains(
                red: Double(gains.redGain), green: Double(gains.greenGain), blue: Double(gains.blueGain)
            ).limited(toMaximum: Double(device.maxWhiteBalanceGain))
            device.setWhiteBalanceModeLocked(
                with: AVCaptureDevice.WhiteBalanceGains(
                    redGain: Float(limited.red), greenGain: Float(limited.green), blueGain: Float(limited.blue)),
                completionHandler: nil)
        }
    }

    /// Observes the attached camera while readings are on, and stops observing otherwise. Call
    /// only on `queue`.
    ///
    /// The exposure offset changes as the meter updates, and the lens position as the lens
    /// moves; either triggers a reading of every value, sent at most four times a second
    /// (``ReadingThrottle``). Nothing is observed while readings are off.
    private func observeReadings() {
        readingObservations.forEach { $0.invalidate() }
        readingObservations = []
        guard readingsEnabled, let device = currentInput?.device else { return }
        let send: @Sendable (AVCaptureDevice) -> Void = { [throttle, readingsContinuation] device in
            let now = ProcessInfo.processInfo.systemUptime
            guard throttle.withLock({ $0.shouldSend(at: now) }) else { return }
            readingsContinuation.yield(Self.reading(of: device))
        }
        readingObservations = [
            device.observe(\.exposureTargetOffset, options: [.initial]) { device, _ in send(device) },
            device.observe(\.lensPosition) { device, _ in send(device) },
        ]
    }

    /// What a camera is using now.
    ///
    /// - Parameter device: The camera.
    /// - Returns: The reading.
    private static func reading(of device: AVCaptureDevice) -> ExposureReading {
        let gains = WhiteBalanceGains(
            red: Double(device.deviceWhiteBalanceGains.redGain), green: Double(device.deviceWhiteBalanceGains.greenGain),
            blue: Double(device.deviceWhiteBalanceGains.blueGain))
        // Converting gains outside 1...maxWhiteBalanceGain raises an exception (AVCaptureDevice.h).
        let inRange = gains == gains.limited(toMaximum: Double(device.maxWhiteBalanceGain))
        var whiteBalance: WhiteBalance?
        if inRange {
            let values = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            whiteBalance = WhiteBalance(temperature: Double(values.temperature), tint: Double(values.tint))
        }
        return ExposureReading(
            iso: Double(device.iso), exposureDuration: device.exposureDuration.seconds,
            exposureOffset: Double(device.exposureTargetOffset), lensPosition: Double(device.lensPosition),
            aperture: Double(device.lensAperture), whiteBalance: whiteBalance)
    }


    /// The camera's aperture: the iOS 27 range and recommended stops where available,
    /// otherwise the fixed `lensAperture`.
    ///
    /// - Parameter device: An attached camera.
    private static func aperture(of device: AVCaptureDevice) -> ApertureRange {
        if #available(iOS 27.0, *) {
            let format = device.activeFormat
            let stops = format.recommendedLensApertureStops.map { Double($0) }
            let minimum = Double(format.minLensAperture)
            let maximum = Double(format.maxLensAperture)
            if minimum > 0, maximum >= minimum {
                return ApertureRange(
                    minimumFNumber: minimum, maximumFNumber: maximum, recommendedStops: stops.isEmpty ? [minimum] : stops)
            }
        }
        return .fixed(Double(device.lensAperture))
    }

    /// Applies a configuration: attaches the camera, commits the photo output's switches and
    /// photo size, locks the camera's zoom and distortion correction, and starts the session.
    ///
    /// - Parameter configuration: What to apply.
    /// - Throws: `CaptureError.configurationFailed` on any refusal, or if the session neither
    ///   runs nor is interrupted after `startRunning()`.
    private func apply(_ configuration: SessionConfiguration) throws(CaptureError) {
        guard let device = AVCaptureDevice(uniqueID: configuration.deviceID), attach(device) else {
            logger.error("Capture: the camera could not be attached")
            throw .configurationFailed
        }
        followRotation(of: device)
        let switches = configuration.switches
        session.beginConfiguration()
        photoOutput.isAppleProRAWEnabled = switches.appleProRAW && photoOutput.isAppleProRAWSupported
        photoOutput.maxPhotoQualityPrioritization = switches.qualityPrioritization
        // Responsive capture requires zero shutter lag, so it is set first.
        photoOutput.isResponsiveCaptureEnabled = switches.responsiveCapture && photoOutput.isResponsiveCaptureSupported
        photoOutput.isZeroShutterLagEnabled = switches.zeroShutterLag && photoOutput.isZeroShutterLagSupported
        if photoOutput.isAutoDeferredPhotoDeliverySupported {
            photoOutput.isAutoDeferredPhotoDeliveryEnabled = switches.deferredDelivery
        }
        if photoOutput.isConstantColorSupported { photoOutput.isConstantColorEnabled = switches.constantColor }
        if photoOutput.isContentAwareDistortionCorrectionSupported {
            photoOutput.isContentAwareDistortionCorrectionEnabled = switches.contentAwareDistortionCorrection
        }
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        if let chosen = supported.first(where: {
            Int($0.width) == configuration.maxPhotoDimensions?.width
                && Int($0.height) == configuration.maxPhotoDimensions?.height
        }) ?? supported.first {
            photoOutput.maxPhotoDimensions = chosen
            appliedMaxDimensions = PhotoDimensions(width: Int(chosen.width), height: Int(chosen.height))
        }
        session.commitConfiguration()

        do {
            try device.lockForConfiguration()
        } catch {
            logger.error("Capture: the camera could not be locked for configuration")
            throw .configurationFailed
        }
        // Bayer RAW requires a zoom factor of 1.0 (AVCapturePhotoOutput.h, "Bayer RAW rules").
        device.videoZoomFactor = CGFloat(switches.videoZoomFactor)
        if device.isGeometricDistortionCorrectionSupported {
            device.isGeometricDistortionCorrectionEnabled = switches.geometricDistortionCorrection
        }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()

        if !session.isRunning { session.startRunning() }
        guard session.isRunning || session.isInterrupted else {
            logger.error("Capture: the session did not start")
            throw .configurationFailed
        }
    }

    /// Prepares the photo output for a plan, then calls `done` once, when preparation finishes,
    /// immediately if the session isn't running (preparation waits for `startRunning()`), or
    /// after ``prepareTimeoutSeconds``.
    ///
    /// - Parameters:
    ///   - plan: The photo settings to prepare.
    ///   - done: Called once, on any queue.
    private func prepare(_ plan: PhotoSettingsPlan, done: @escaping @Sendable () -> Void) {
        guard session.isRunning else {
            done()
            return
        }
        let finished = OSAllocatedUnfairLock(initialState: false)
        let finishOnce: @Sendable () -> Void = {
            let first = finished.withLock { wasFinished in
                defer { wasFinished = true }
                return !wasFinished
            }
            if first { done() }
        }
        let settings = PhotoSettingsFactory.makeSettings(for: plan, maxPhotoDimensions: appliedMaxDimensions)
        photoOutput.setPreparedPhotoSettingsArray([settings]) { [logger] prepared, _ in
            if !prepared { logger.error("Capture: photo settings were not prepared") }
            finishOnce()
        }
        queue.asyncAfter(deadline: .now() + Self.prepareTimeoutSeconds, execute: finishOnce)
    }

    /// Starts one capture and reports its result.
    ///
    /// - Parameters:
    ///   - plan: The photo settings.
    ///   - metadata: The plan the file's metadata is built from.
    ///   - completion: Called once with the photo or the error.
    private func startCapture(
        _ plan: PhotoSettingsPlan, metadata: MetadataPlan, completion: @escaping @Sendable (Result<HardwarePhoto, CaptureError>) -> Void
    ) {
        guard session.isRunning, let device = currentInput?.device else {
            completion(.failure(.notRunning))
            return
        }
        let settings = PhotoSettingsFactory.makeSettings(for: plan, maxPhotoDimensions: appliedMaxDimensions)
        startCapture(settings, device: device, plan: plan, metadata: metadata) { result in
            completion(result.flatMap { photos in photos.first.map { .success($0) } ?? .failure(.captureFailed) })
        }
    }

    /// Starts a capture with prepared settings (one photo, or a bracket) and reports every photo
    /// it delivers. Call only on `queue`.
    ///
    /// - Parameters:
    ///   - settings: The photo or bracket settings.
    ///   - device: The attached camera.
    ///   - plan: The photo settings plan, which gives the file format.
    ///   - metadata: The plan each file's metadata is built from.
    ///   - completion: Called once with the photos or the error.
    private func startCapture(
        _ settings: AVCapturePhotoSettings, device: AVCaptureDevice, plan: PhotoSettingsPlan, metadata: MetadataPlan,
        completion: @escaping @Sendable (Result<[HardwarePhoto], CaptureError>) -> Void
    ) {
        let id = settings.uniqueID
        let delegate = PhotoCaptureDelegate(
            exposureDuration: device.exposureDuration.seconds, iso: Double(device.iso), metadata: metadata,
            format: CapturePolicy.fileFormat(of: plan)
        ) { result in
            self.queue.async { self.captureDelegates[id] = nil }
            completion(result)
        }
        captureDelegates[id] = delegate
        // Every photo, single or bracketed, gets the current capture angle.
        applyCaptureRotation()
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    /// Points the preview rotation at the camera now in the session, on the main queue, in the
    /// order cameras are configured.
    ///
    /// - Parameter device: The attached camera.
    private func followRotation(of device: AVCaptureDevice) {
        let deviceID = device.uniqueID
        let rotation = preview.rotation
        DispatchQueue.main.async { MainActor.assumeIsolated { rotation.use(deviceID: deviceID) } }
    }

    /// Sets the photo output's rotation to the coordinator's capture angle, so the photo is
    /// upright. Privacy: the photo output records the angle as the Exif orientation and doesn't
    /// rotate pixels (`AVCaptureSession.h`, `videoRotationAngle`). The value reaches the saved
    /// DNG through `AVCapturePhoto.metadata`, which `MetadataPlan.properties(for:from:orientation:)`
    /// copies because Orientation is a locked item (docs/PRIVACY.md). Call only on `queue`.
    private func applyCaptureRotation() {
        guard let angle = preview.rotation.captureAngle, let connection = photoOutput.connection(with: .video),
            connection.isVideoRotationAngleSupported(angle)
        else { return }
        connection.videoRotationAngle = angle
    }

    /// Reports interruptions, their end, runtime errors and thermal state changes as events.
    private func observeNotifications() {
        let center = NotificationCenter.default
        let continuation = continuation
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) {
                let raw = $0.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                continuation.yield(.interrupted(InterruptionReason(reason)))
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) {
                _ in continuation.yield(.interruptionEnded)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { _ in
                continuation.yield(.failed)
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in
                continuation.yield(.heat(HeatLevel(ProcessInfo.processInfo.thermalState)))
            },
        ]
    }
}

/// Receives one capture's callbacks (one photo, or every frame of a bracket) and reports the photo once the capture finishes.
///
/// `@unchecked Sendable`: AVFoundation calls the delegate methods one after another for a
/// capture, and `result` is only touched in them.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    /// The camera's exposure duration just before the capture, in seconds.
    private let exposureDuration: Double
    /// The camera's ISO just before the capture.
    private let iso: Double
    /// The plan the file's metadata is built from.
    private let metadata: MetadataPlan
    /// The format of the file, which chooses its allowlist.
    private let format: PhotoFormat
    /// Called once with the result.
    private let completion: @Sendable (Result<[HardwarePhoto], CaptureError>) -> Void
    /// The photos delivered so far: one, or one per bracket frame.
    private var photos: [HardwarePhoto] = []
    /// Whether any photo failed.
    private var failed = false

    /// Creates a delegate for one capture.
    ///
    /// - Parameters:
    ///   - exposureDuration: The exposure duration before the capture, in seconds.
    ///   - iso: The ISO before the capture.
    ///   - metadata: The plan the file's metadata is built from.
    ///   - format: The file's format.
    ///   - completion: Called once with the result.
    init(
        exposureDuration: Double, iso: Double, metadata: MetadataPlan, format: PhotoFormat,
        completion: @escaping @Sendable (Result<[HardwarePhoto], CaptureError>) -> Void
    ) {
        self.exposureDuration = exposureDuration
        self.iso = iso
        self.metadata = metadata
        self.format = format
        self.completion = completion
    }

    /// Writes the photo's file with metadata built from the allowlist, keeps the reference RAW
    /// image data, or records the failure.
    ///
    /// Privacy rule: the file is flattened with ``MetadataCustomizer``, so its metadata is the
    /// dictionary `MetadataPlan` built from the allowlist, never the system's full metadata
    /// with known tags deleted (AGENTS.md, "Build metadata from the allowlist"). For RAW, the
    /// system's own DNG is flattened too, only to copy its RAW image data as the reference the
    /// read-back compares with; that DNG is dropped at once. The bytes stay in memory. A bracket
    /// frame reports the exposure it was asked for; a single photo the exposure read before the
    /// capture.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let customizer = MetadataCustomizer(properties: metadata.properties(for: format, from: photo.metadata))
        guard error == nil, let data = photo.fileDataRepresentation(with: customizer) else {
            failed = true
            return
        }
        let rawImageData = photo.isRawPhoto ? photo.fileDataRepresentation().flatMap(MetadataFileReader.rawImageData(ofDNG:)) : nil
        let size = photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
        let frame = photo.bracketSettings as? AVCaptureManualExposureBracketedStillImageSettings
        photos.append(
            HardwarePhoto(
                data: data, dimensions: PhotoDimensions(width: Int(size.width), height: Int(size.height)),
                exposureDuration: frame.map { $0.exposureDuration.seconds } ?? exposureDuration,
                iso: frame.map { Double($0.iso) } ?? iso, pixelSample: photo.pixelBuffer.flatMap(Self.sample),
                rawImageData: rawImageData))
    }

    /// Reads the bytes at ``PictureCheck/sampleOffsets(byteCount:)`` from the buffer's first
    /// plane (the whole buffer for RAW), for the blank-picture check. `AVCapturePhoto.pixelBuffer`
    /// holds the RAW samples of a RAW photo and is `nil` for a compressed one.
    ///
    /// Privacy: the 128 bytes stay in memory for one comparison and are never stored or logged.
    ///
    /// - Parameter pixelBuffer: The photo's pixel buffer.
    /// - Returns: The sampled bytes, or `nil` if the buffer has no base address.
    private static func sample(_ pixelBuffer: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        let base = isPlanar ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) : CVPixelBufferGetBaseAddress(pixelBuffer)
        guard let base else { return nil }
        let byteCount =
            isPlanar
            ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer)
        // Every offset is below byteCount (PictureCheck, tested), so each read is in bounds.
        return PictureCheck.sampleOffsets(byteCount: byteCount).map { base.load(fromByteOffset: $0, as: UInt8.self) }
    }

    /// Reports the result when the whole capture has finished: every photo, or a failure if any
    /// photo failed or none arrived.
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        completion(error == nil && !failed && !photos.isEmpty ? .success(photos) : .failure(.captureFailed))
    }
}

/// Supplies the metadata a photo's file is written with.
///
/// `AVCapturePhotoOutput.h` documents `replacementMetadata(for:)`: "To replace metadata, pass a
/// replacement dictionary", and the dictionary takes keys from `ImageIO/CGImageProperties.h`.
/// The dictionary is `MetadataPlan.properties(for:from:orientation:)`, built from the
/// allowlist. Whether AVFoundation adds anything beyond it is checked on every file by the
/// read-back, and on a device by the tag check (docs/TESTING.md).
final class MetadataCustomizer: NSObject, AVCapturePhotoFileDataRepresentationCustomizer {
    /// The replacement metadata. Built once and never mutated.
    private let properties: [String: Any]

    /// Creates a customizer.
    ///
    /// - Parameter properties: The metadata to write.
    init(properties: [String: Any]) {
        self.properties = properties
    }

    /// Returns the allowlisted metadata, which replaces the photo's own.
    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        properties
    }
}
