import Foundation

/// Whether nope. may use the camera, as reported by the system.
///
/// A ``CaptureBackend`` reports this value; ``CameraModel`` turns it into a ``CameraState``.
/// Interfaces never read it directly: they render the resulting state.
public enum CameraPermission: Equatable, Sendable, CaseIterable {
    /// The person hasn't been asked yet. Asking shows the system prompt once.
    case notDetermined

    /// The person allowed camera access.
    case authorized

    /// The person declined camera access. Only the Settings app can change it now.
    case denied

    /// Access is blocked by a device policy, such as Screen Time or a configuration profile.
    /// The person may be unable to change it.
    case restricted
}
