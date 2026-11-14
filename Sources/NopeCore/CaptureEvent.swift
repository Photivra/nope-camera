import Foundation

/// Something that happened to the camera outside nope.'s control, reported by a
/// ``CaptureBackend`` through ``CaptureBackend/events``.
///
/// ``CameraModel`` turns events into ``SessionStatus`` values; interfaces never read events.
public enum CaptureEvent: Equatable, Sendable {
    /// The system paused the camera.
    case interrupted(InterruptionReason)

    /// The system resumed the camera after an interruption.
    case interruptionEnded

    /// The device's heat level changed, or was read for the first time.
    case heat(HeatLevel)

    /// The camera stopped because of an error, such as a media services reset.
    case failed

    /// The scene changed substantially, for example the camera moved
    /// (`AVCaptureDevice.subjectAreaDidChangeNotification`). Sent only while a tapped point is
    /// being followed, so autofocus can return to the center.
    case subjectAreaChanged

    /// The system made the torch unavailable or turned it off, for example because the device
    /// is too hot (`AVCaptureDevice.isTorchAvailable`).
    case torchUnavailable
}
