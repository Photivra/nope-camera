import Foundation
import NopeCore

/// The real `CaptureBackend`: the device's cameras through AVFoundation.
///
/// It discovers physical cameras only, publishes their capabilities as plain values, and
/// captures single-frame Bayer RAW, or the labeled processed fallback on a lens without Bayer
/// RAW. Each photo's file is written with metadata built from the request's allowlist plan and
/// returned in memory; nothing is written to disk or saved here (`PhotoSaver` saves it).
///
/// The decisions live here and in ``LensCatalog`` and ``CapturePolicy``, all tested with fakes.
/// The calls that need a camera are in ``SystemCaptureHardware``, which is excluded from the
/// coverage gate and verified on a device (docs/TESTING.md).
///
/// Create it with ``init()`` in the app target.
public actor AVFoundationCaptureBackend: ManualCaptureBackend, LightCaptureBackend {
    /// Interruptions, heat changes and runtime errors from the hardware.
    public nonisolated let events: AsyncStream<CaptureEvent>

    /// What the camera is using now, while readings are on.
    public nonisolated let exposureReadings: AsyncStream<ExposureReading>

    /// A ``CaptureSessionPreviewSource`` for the app's viewfinder.
    public nonisolated let previewSource: (any CameraPreviewSource)?

    /// The camera calls.
    private let hardware: any CaptureHardware

    /// The live view calls, or `nil` when the hardware has none.
    nonisolated let liveHardware: (any LiveViewHardware)?

    /// The comparison shot's camera call (issue #55), or `nil` when the hardware has none.
    nonisolated let comparisonHardware: (any ComparisonHardware)?

    /// Camera permission.
    private let authorization: any CameraAuthorizing

    /// The lens identifiers found by the last ``deviceCapabilities()``.
    private var knownLensIDs: Set<Lens.ID> = []

    /// The configuration the session runs with, or `nil` when it is stopped.
    private(set) var activeConfiguration: SessionConfiguration?

    /// Creates a backend from its parts. The app uses ``init()``; tests pass fakes.
    ///
    /// - Parameters:
    ///   - hardware: The camera calls.
    ///   - authorization: Camera permission.
    init(hardware: any CaptureHardware, authorization: any CameraAuthorizing) {
        self.hardware = hardware
        self.authorization = authorization
        liveHardware = hardware as? any LiveViewHardware
        comparisonHardware = hardware as? any ComparisonHardware
        events = hardware.events
        exposureReadings = hardware.exposureReadings
        previewSource = hardware.previewSource
    }

    /// Returns the current camera permission without asking.
    public func currentPermission() async -> CameraPermission {
        await authorization.currentPermission()
    }

    /// Asks for camera access. Side effect: may show the system prompt.
    public func requestPermission() async -> CameraPermission {
        await authorization.requestPermission()
    }

    /// Discovers the physical cameras and their capabilities.
    ///
    /// Side effect: briefly attaches each camera to the session to read its formats.
    ///
    /// - Returns: The lenses ``LensCatalog`` builds from the cameras found.
    public func deviceCapabilities() async -> DeviceCapabilities {
        let lenses = LensCatalog.lenses(from: await hardware.discoverCameras())
        knownLensIDs = Set(lenses.map(\.id))
        return DeviceCapabilities(lenses: lenses)
    }

    /// Configures the session for the request's lens and format, and starts it.
    ///
    /// - Parameter request: The lens and format.
    /// - Throws: `CaptureError.configurationFailed` if the lens wasn't discovered, the format is
    ///   invalid, or the hardware can't be configured.
    public func startSession(_ request: CaptureRequest) async throws(CaptureError) {
        guard knownLensIDs.contains(request.lens.id),
            let configuration = CapturePolicy.sessionConfiguration(for: request)
        else { throw .configurationFailed }
        activeConfiguration = nil
        try await hardware.configure(configuration)
        activeConfiguration = configuration
    }

    /// Stops the session and tears it down; returns once the hardware has finished
    /// (``CaptureHardware/stop()``).
    public func stopSession() async {
        activeConfiguration = nil
        await hardware.stop()
    }

    /// Takes one photo, in memory only, and rejects it if its pixel buffer is blank.
    ///
    /// - Parameter request: The lens and format; must match the last ``startSession(_:)``. Its
    ///   flash mode applies to this photo only.
    /// - Returns: The photo.
    /// - Throws: `CaptureError.notRunning` if the session isn't configured for this request,
    ///   `CaptureError.blankPicture` if ``PictureCheck`` finds the photo's buffer zero-filled
    ///   (the photo is dropped), or the hardware's error.
    public func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        guard let configuration = activeConfiguration,
            configuration == CapturePolicy.sessionConfiguration(for: request)
        else { throw .notRunning }
        let plan = CapturePolicy.photoSettings(configuration.photoSettings, flashMode: request.flashMode)
        let photo = try await hardware.capture(plan, metadata: request.metadata)
        guard !PictureCheck.isBlank(photo.pixelSample) else { throw .blankPicture }
        return CapturedPhoto(
            data: photo.data,
            format: request.format,
            lensID: request.lens.id,
            dimensions: photo.dimensions,
            exposureDuration: photo.exposureDuration,
            iso: photo.iso,
            rawImageData: photo.rawImageData,
            rawClipping: photo.rawClipping
        )
    }

    /// Sets exposure, focus, white balance and metering on the running camera.
    ///
    /// - Parameter controls: The controls, already checked against the lens.
    /// - Throws: `CaptureError.notRunning` if the session isn't configured, or the hardware's
    ///   error.
    public func applyControls(_ controls: DeviceControls) async throws(CaptureError) {
        guard activeConfiguration != nil else { throw .notRunning }
        try await hardware.apply(controls)
    }

    /// Locks focus at a lens position and returns the position the camera reports once it is
    /// applied: the step before each frame of a focus bracket.
    ///
    /// - Parameter lensPosition: The position, from 0 to 1.
    /// - Returns: The reported position.
    /// - Throws: `CaptureError.notRunning` if the camera isn't running, or
    ///   `CaptureError.configurationFailed` if its focus can't be locked at a position.
    public func setFocus(lensPosition: Double) async throws(CaptureError) -> Double {
        guard activeConfiguration != nil else { throw .notRunning }
        return try await hardware.setFocus(lensPosition: lensPosition)
    }

    /// Turns the camera's readings on or off.
    ///
    /// - Parameter enabled: Whether to send readings.
    public func setExposureReadingsEnabled(_ enabled: Bool) async {
        await hardware.setReadingsEnabled(enabled)
    }

    /// Takes a manual exposure bracket, in memory only, and rejects it if any frame is blank.
    ///
    /// - Parameters:
    ///   - request: The lens and format; must match the last ``startSession(_:)``.
    ///   - frames: Each frame's ISO and exposure duration, from 1 to the lens's
    ///     `maxBracketedPhotoCount`.
    /// - Returns: One photo per frame, in order, each a separate single-frame photo.
    /// - Throws: `CaptureError.notRunning` if the session isn't configured for this request,
    ///   `CaptureError.captureFailed` for an invalid frame count or a missing photo,
    ///   `CaptureError.blankPicture` if any frame is blank (all are dropped), or the hardware's
    ///   error.
    public func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError)
        -> [CapturedPhoto]
    {
        guard let configuration = activeConfiguration,
            configuration == CapturePolicy.sessionConfiguration(for: request)
        else { throw .notRunning }
        guard !frames.isEmpty, frames.count <= request.lens.maxBracketedPhotoCount else { throw .captureFailed }
        let photos = try await hardware.captureBracket(
            configuration.photoSettings, frames: frames, metadata: request.metadata)
        guard photos.count == frames.count else { throw .captureFailed }
        guard !photos.contains(where: { PictureCheck.isBlank($0.pixelSample) }) else { throw .blankPicture }
        return photos.map { photo in
            CapturedPhoto(
                data: photo.data,
                format: request.format,
                lensID: request.lens.id,
                dimensions: photo.dimensions,
                exposureDuration: photo.exposureDuration,
                iso: photo.iso,
                rawImageData: photo.rawImageData,
                rawClipping: photo.rawClipping
            )
        }
    }

    /// Turns the running lens's torch on at a level, or off.
    ///
    /// - Parameter level: The brightness, from just above 0 to 1, or `nil` for off.
    /// - Returns: The light's state. While the session isn't configured (before a start, or
    ///   while it is reconfigured), a request for the light is `TorchStatus.pending`, never a
    ///   silent `TorchStatus.off` (issue #75); `LightModel` applies it after the start.
    public func setTorch(level: Double?) async -> TorchStatus {
        guard activeConfiguration != nil else { return level == nil ? .off : .pending }
        return await hardware.setTorch(level: level)
    }
}
