import Foundation

/// A request an interface sends to ``CameraModel``.
///
/// Intents are the only way an interface changes the camera. They carry no business rules: the
/// model decides what each one means.
public enum CameraIntent: Equatable, Sendable {
    /// Check permission and capabilities, then start the camera with the default lens. Send it
    /// once when the camera screen appears.
    case start

    /// Ask the person for camera access. Send it only from ``CameraState/needsPermission``,
    /// in response to a button the person pressed. When access is allowed, the camera starts.
    case requestPermission

    /// Switch to another lens. Send it when the person picks a lens.
    ///
    /// - Parameter id: The ``Lens/id`` of a lens in the ready state's capabilities. An unknown
    ///   identifier, or the lens already selected, is ignored.
    case selectLens(Lens.ID)

    /// Take one photo with the selected lens, in the format the model chose. Send it from the
    /// shutter button, the volume buttons or the Camera Control. Ignored while the camera isn't
    /// running or a photo is already being taken.
    case capture

    /// Change a manual or pro control: see ``ManualControlIntent``. Ignored while manual
    /// controls are off, except ``ManualControlIntent/setEnabled(_:)``.
    case manual(ManualControlIntent)

    /// Turn clean view on or off. Clean view hides every control that isn't essential, leaving
    /// the viewfinder and the shutter; it never changes a setting.
    case setCleanView(Bool)
}
