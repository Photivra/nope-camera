import Foundation
import NopeCore

/// The camera calls that need hardware, behind a protocol so ``AVFoundationCaptureBackend``
/// can be tested with a fake (AGENTS.md, "Full test coverage").
///
/// ``SystemCaptureHardware`` implements it with AVFoundation and is verified on a device.
/// Every decision (which lens, which format, which processing switches) is made before a call
/// reaches the hardware, in ``CapturePolicy``.
protocol CaptureHardware: Sendable {
    /// Interruptions, heat changes and runtime errors.
    var events: AsyncStream<CaptureEvent> { get }

    /// The handle the app turns into the live viewfinder.
    var previewSource: any CameraPreviewSource { get }

    /// Lists every camera with its photo format and RAW formats.
    ///
    /// Side effect: briefly attaches each camera to the capture session to read its formats.
    ///
    /// - Returns: The cameras, including any virtual ones, which ``LensCatalog`` drops.
    func discoverCameras() async -> [CameraDeviceDescription]

    /// Configures the session for one camera, starts it if needed, and prepares the photo
    /// output for the planned photo settings.
    ///
    /// - Parameter configuration: What to configure.
    /// - Throws: `CaptureError.configurationFailed` if the camera can't be opened,
    ///   added or locked, or the session doesn't start.
    func configure(_ configuration: SessionConfiguration) async throws(CaptureError)

    /// Stops the session.
    func stop() async

    /// Takes one photo.
    ///
    /// - Parameter plan: The photo settings to use.
    /// - Returns: The file bytes and capture details.
    /// - Throws: `CaptureError.notRunning` if the session isn't running, or
    ///   `CaptureError.captureFailed` if the system reports an error or no file.
    func capture(_ plan: PhotoSettingsPlan) async throws(CaptureError) -> HardwarePhoto
}

/// One photo as the hardware returned it.
struct HardwarePhoto: Equatable, Sendable {
    /// The file bytes from `AVCapturePhoto.fileDataRepresentation()`.
    let data: Data
    /// The resolved photo size, in pixels.
    let dimensions: PhotoDimensions
    /// The exposure duration read just before the capture, in seconds.
    let exposureDuration: Double?
    /// The ISO read just before the capture.
    let iso: Double?

    /// Creates a photo result.
    ///
    /// - Parameters:
    ///   - data: The file bytes.
    ///   - dimensions: The resolved photo size, in pixels.
    ///   - exposureDuration: The exposure duration before the capture, in seconds.
    ///   - iso: The ISO before the capture.
    init(data: Data, dimensions: PhotoDimensions, exposureDuration: Double?, iso: Double?) {
        self.data = data
        self.dimensions = dimensions
        self.exposureDuration = exposureDuration
        self.iso = iso
    }
}
