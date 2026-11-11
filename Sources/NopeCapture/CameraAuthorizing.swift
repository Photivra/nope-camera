import NopeCore

/// Reads and requests camera permission.
///
/// ``SystemCameraAuthorization`` implements it with AVFoundation; tests use a fake, so
/// ``AVFoundationCaptureBackend`` can be tested without a system prompt.
public protocol CameraAuthorizing: Sendable {
    /// Returns the current camera permission without asking.
    ///
    /// - Returns: The permission the system reports right now.
    func currentPermission() async -> CameraPermission

    /// Asks for camera access.
    ///
    /// Side effect: may show the system prompt.
    ///
    /// - Returns: The permission after the person answers.
    func requestPermission() async -> CameraPermission
}
