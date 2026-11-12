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

    /// Stops the session and tears it down, in order: `stopRunning()` on the session queue,
    /// which returns only once the session has completely stopped, then the camera input and
    /// the photo output are removed in one configuration. The next ``configure(_:)`` rebuilds
    /// the session from scratch. Returns after the teardown has finished.
    func stop() async

    /// Takes one photo and writes its file with metadata built from the allowlist.
    ///
    /// The file is flattened with `AVCapturePhoto.fileDataRepresentation(with:)` and a
    /// customizer whose `replacementMetadata(for:)` returns
    /// `MetadataPlan.properties(for:from:orientation:)` for the system's metadata: the header
    /// says the returned dictionary replaces the photo's metadata (`AVCapturePhotoOutput.h`,
    /// `AVCapturePhotoFileDataRepresentationCustomizer`). AVFoundation itself writes the RAW
    /// image data, so the sensor data isn't re-encoded by nope. For a RAW photo the system's
    /// own DNG is also flattened once, only to keep its RAW image data as a reference.
    ///
    /// - Parameters:
    ///   - plan: The photo settings to use.
    ///   - metadata: The plan the file's metadata is built from.
    /// - Returns: The file bytes, the reference RAW image data, a few bytes sampled from the
    ///   photo's pixel buffer, and capture details.
    /// - Throws: `CaptureError.notRunning` if the session isn't running, or
    ///   `CaptureError.captureFailed` if the system reports an error or no file.
    func capture(_ plan: PhotoSettingsPlan, metadata: MetadataPlan) async throws(CaptureError) -> HardwarePhoto
}

/// One photo as the hardware returned it.
struct HardwarePhoto: Equatable, Sendable {
    /// The file bytes from `AVCapturePhoto.fileDataRepresentation(with:)`, with metadata built
    /// from the allowlist.
    let data: Data
    /// For RAW, the RAW image data of the system's own DNG (`MetadataFileReader.rawImageData(ofDNG:)`);
    /// `nil` for a processed photo.
    let rawImageData: Data?
    /// The resolved photo size, in pixels.
    let dimensions: PhotoDimensions
    /// The exposure duration read just before the capture, in seconds.
    let exposureDuration: Double?
    /// The ISO read just before the capture.
    let iso: Double?
    /// The bytes at ``PictureCheck/sampleOffsets(byteCount:)`` of the photo's pixel buffer, or
    /// `nil` when the photo has none (a compressed HEIF or JPEG). Used only to detect a blank
    /// buffer; never stored or logged.
    let pixelSample: [UInt8]?

    /// Creates a photo result.
    ///
    /// - Parameters:
    ///   - data: The file bytes.
    ///   - dimensions: The resolved photo size, in pixels.
    ///   - exposureDuration: The exposure duration before the capture, in seconds.
    ///   - iso: The ISO before the capture.
    ///   - pixelSample: The sampled pixel buffer bytes, or `nil`.
    ///   - rawImageData: The reference RAW image data, or `nil`.
    init(
        data: Data, dimensions: PhotoDimensions, exposureDuration: Double?, iso: Double?, pixelSample: [UInt8]?,
        rawImageData: Data? = nil
    ) {
        self.data = data
        self.rawImageData = rawImageData
        self.dimensions = dimensions
        self.exposureDuration = exposureDuration
        self.iso = iso
        self.pixelSample = pixelSample
    }
}
