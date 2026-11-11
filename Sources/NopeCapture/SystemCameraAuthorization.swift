import AVFoundation
import NopeCore

/// Reads and requests camera permission from the system.
///
/// This is a hardware adapter: requesting access shows a system prompt that a unit test can't
/// answer, so the file is listed in `scripts/coverage-exclusions.txt` and verified on a device.
/// Its status conversion lives in `CameraPermission+AVFoundation.swift`, which is fully tested.
public struct SystemCameraAuthorization: Sendable {
    /// Creates the adapter. It holds no state.
    public init() {}

    /// Returns the current camera permission without asking.
    ///
    /// - Returns: The permission for video capture devices.
    public func currentPermission() -> CameraPermission {
        CameraPermission(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Asks for camera access.
    ///
    /// Side effect: shows the system prompt the first time, with the localized
    /// `NSCameraUsageDescription`. Later calls return the stored answer without a prompt.
    ///
    /// - Returns: The permission after the person answers.
    public func requestPermission() async -> CameraPermission {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return currentPermission()
    }
}
