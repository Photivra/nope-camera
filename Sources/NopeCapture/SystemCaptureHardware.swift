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
        preview = CaptureSessionPreviewSource(session: session)
        previewSource = preview
        observeNotifications()
        continuation.yield(.heat(HeatLevel(ProcessInfo.processInfo.thermalState)))
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        continuation.finish()
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
    func capture(_ plan: PhotoSettingsPlan) async throws(CaptureError) -> HardwarePhoto {
        _ = try await CaptureReadiness.waitUntilReady(
            timeout: Self.readinessTimeoutSeconds, interval: Self.readinessPollSeconds
        ) {
            await self.perform { CaptureReadiness(self.photoOutput.captureReadiness) }
        }
        let result: Result<HardwarePhoto, CaptureError> = await withCheckedContinuation { continuation in
            queue.async { self.startCapture(plan) { continuation.resume(returning: $0) } }
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
            fieldOfViewDegrees: Double(format.videoFieldOfView)
        )
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
    ///   - completion: Called once with the photo or the error.
    private func startCapture(
        _ plan: PhotoSettingsPlan, completion: @escaping @Sendable (Result<HardwarePhoto, CaptureError>) -> Void
    ) {
        guard session.isRunning, let device = currentInput?.device else {
            completion(.failure(.notRunning))
            return
        }
        applyCaptureRotation()
        let settings = PhotoSettingsFactory.makeSettings(for: plan, maxPhotoDimensions: appliedMaxDimensions)
        let id = settings.uniqueID
        let delegate = PhotoCaptureDelegate(
            exposureDuration: device.exposureDuration.seconds, iso: Double(device.iso)
        ) { result in
            self.queue.async { self.captureDelegates[id] = nil }
            completion(result)
        }
        captureDelegates[id] = delegate
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
    /// rotate pixels (`AVCaptureSession.h`, `videoRotationAngle`); Orientation is a locked
    /// metadata item (docs/PRIVACY.md). Call only on `queue`.
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

/// Receives one capture's callbacks and reports the photo once the capture finishes.
///
/// `@unchecked Sendable`: AVFoundation calls the delegate methods one after another for a
/// capture, and `result` is only touched in them.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    /// The camera's exposure duration just before the capture, in seconds.
    private let exposureDuration: Double
    /// The camera's ISO just before the capture.
    private let iso: Double
    /// Called once with the result.
    private let completion: @Sendable (Result<HardwarePhoto, CaptureError>) -> Void
    /// The result so far; a failure until a photo with file data arrives.
    private var result: Result<HardwarePhoto, CaptureError> = .failure(.captureFailed)

    /// Creates a delegate for one capture.
    ///
    /// - Parameters:
    ///   - exposureDuration: The exposure duration before the capture, in seconds.
    ///   - iso: The ISO before the capture.
    ///   - completion: Called once with the result.
    init(
        exposureDuration: Double, iso: Double,
        completion: @escaping @Sendable (Result<HardwarePhoto, CaptureError>) -> Void
    ) {
        self.exposureDuration = exposureDuration
        self.iso = iso
        self.completion = completion
    }

    /// Keeps the photo's file bytes, or records the failure. Privacy: the bytes stay in memory.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            result = .failure(.captureFailed)
            return
        }
        let size = photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
        result = .success(
            HardwarePhoto(
                data: data, dimensions: PhotoDimensions(width: Int(size.width), height: Int(size.height)),
                exposureDuration: exposureDuration, iso: iso, pixelSample: photo.pixelBuffer.flatMap(Self.sample)))
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

    /// Reports the result when the whole capture has finished.
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        if error != nil { result = .failure(.captureFailed) }
        completion(result)
    }
}
