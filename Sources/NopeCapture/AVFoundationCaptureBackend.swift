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
public actor AVFoundationCaptureBackend: CaptureBackend {
    /// Interruptions, heat changes and runtime errors from the hardware.
    public nonisolated let events: AsyncStream<CaptureEvent>

    /// A ``CaptureSessionPreviewSource`` for the app's viewfinder.
    public nonisolated let previewSource: (any CameraPreviewSource)?

    /// The camera calls.
    private let hardware: any CaptureHardware

    /// Camera permission.
    private let authorization: any CameraAuthorizing

    /// The lens identifiers found by the last ``deviceCapabilities()``.
    private var knownLensIDs: Set<Lens.ID> = []

    /// The configuration the session runs with, or `nil` when it is stopped.
    private var activeConfiguration: SessionConfiguration?

    /// Creates a backend from its parts. The app uses ``init()``; tests pass fakes.
    ///
    /// - Parameters:
    ///   - hardware: The camera calls.
    ///   - authorization: Camera permission.
    init(hardware: any CaptureHardware, authorization: any CameraAuthorizing) {
        self.hardware = hardware
        self.authorization = authorization
        events = hardware.events
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
    /// - Parameter request: The lens and format; must match the last ``startSession(_:)``.
    /// - Returns: The photo.
    /// - Throws: `CaptureError.notRunning` if the session isn't configured for this request,
    ///   `CaptureError.blankPicture` if ``PictureCheck`` finds the photo's buffer zero-filled
    ///   (the photo is dropped), or the hardware's error.
    public func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        guard let configuration = activeConfiguration,
            configuration == CapturePolicy.sessionConfiguration(for: request)
        else { throw .notRunning }
        let photo = try await hardware.capture(configuration.photoSettings, metadata: request.metadata)
        guard !PictureCheck.isBlank(photo.pixelSample) else { throw .blankPicture }
        return CapturedPhoto(
            data: photo.data,
            format: request.format,
            lensID: request.lens.id,
            dimensions: photo.dimensions,
            exposureDuration: photo.exposureDuration,
            iso: photo.iso,
            rawImageData: photo.rawImageData
        )
    }
}
