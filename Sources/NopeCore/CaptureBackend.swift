import Foundation

/// The hardware side of the camera, as seen by ``CameraModel``.
///
/// `NopeCapture` implements it with AVFoundation on a device. Tests, previews and the
/// development build use ``SimulatedCaptureBackend``. Keeping the hardware behind this protocol
/// lets every rule in `NopeCore` be tested without a camera (AGENTS.md, "Full test coverage").
public protocol CaptureBackend: Sendable {
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
}
