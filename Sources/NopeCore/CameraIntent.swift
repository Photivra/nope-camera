import Foundation

/// A request an interface sends to ``CameraModel``.
///
/// Intents are the only way an interface changes the camera. They carry no business rules: the
/// model decides what each one means.
public enum CameraIntent: Equatable, Sendable {
    /// Check permission and capabilities. Send it once when the camera screen appears.
    case start

    /// Ask the person for camera access. Send it only from ``CameraState/needsPermission``,
    /// in response to a button the person pressed.
    case requestPermission
}
