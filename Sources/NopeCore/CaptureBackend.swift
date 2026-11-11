import Foundation

/// The hardware side of the camera, as seen by ``CameraModel``.
///
/// `NopeCapture` implements it with AVFoundation on a device. Tests, previews and the
/// development build use ``SimulatedCaptureBackend``. Keeping the hardware behind this protocol
/// lets every rule in `NopeCore` be tested without a camera (AGENTS.md, "Full test coverage").
///
/// A backend never decides formats or policies: ``CameraModel`` sends it a ``CaptureRequest``
/// that says which lens and which format to use.
public protocol CaptureBackend: Sendable {
    /// Events the system reports while the camera runs: interruptions, heat and errors.
    ///
    /// ``CameraModel/observeEvents()`` is its only consumer. The stream ends when the backend is
    /// released.
    var events: AsyncStream<CaptureEvent> { get }

    /// The handle the app turns into the live viewfinder, or `nil` when there is no video.
    var previewSource: (any CameraPreviewSource)? { get }

    /// Returns the current camera permission without asking the person.
    ///
    /// - Returns: The permission the system reports right now.
    func currentPermission() async -> CameraPermission

    /// Asks the person for camera access, showing the system prompt if iOS allows it.
    ///
    /// Side effect: may present the system permission prompt, which uses the localized
    /// `NSCameraUsageDescription`.
    ///
    /// - Returns: The permission after the person answers.
    func requestPermission() async -> CameraPermission

    /// Discovers the device's cameras and what each one supports.
    ///
    /// Call it only after access is ``CameraPermission/authorized``.
    ///
    /// - Returns: The capabilities of this device.
    func deviceCapabilities() async -> DeviceCapabilities

    /// Configures the camera for one lens and format, and starts it if it isn't running.
    ///
    /// Calling it again with another lens switches lenses.
    ///
    /// - Parameter request: The lens and format to prepare.
    /// - Throws: ``CaptureError/configurationFailed`` if the lens can't be opened or configured.
    func startSession(_ request: CaptureRequest) async throws(CaptureError)

    /// Stops the camera. Does nothing if it isn't running.
    func stopSession() async

    /// Takes one photo and returns it in memory.
    ///
    /// Side effects: none beyond the capture itself. The photo isn't written to a file or saved.
    ///
    /// - Parameter request: The lens and format; the same as the last ``startSession(_:)``.
    /// - Returns: The photo's file bytes and capture details.
    /// - Throws: ``CaptureError/notRunning`` if the camera isn't running, or
    ///   ``CaptureError/captureFailed`` if the system reports an error or returns no file.
    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto
}
