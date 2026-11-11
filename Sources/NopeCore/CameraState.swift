import Foundation

/// Everything an interface needs to draw the camera screen, at one moment.
///
/// ``CameraModel`` owns the current state; interfaces read it and never change it directly.
/// Each case lists how an interface should present it.
public enum CameraState: Equatable, Sendable {
    /// The camera is starting: permission and capabilities are being checked.
    ///
    /// Present a neutral placeholder. Don't ask for anything yet.
    case starting

    /// The person hasn't decided about camera access yet.
    ///
    /// Explain why nope. needs the camera and offer one button that sends
    /// ``CameraIntent/requestPermission``.
    case needsPermission

    /// Camera access was declined or is restricted.
    ///
    /// Explain that access can be turned on in the Settings app. Don't ask again: iOS won't show
    /// the prompt a second time.
    case permissionDenied

    /// Access is allowed but the device has no camera nope. can use, such as the Simulator.
    ///
    /// Say so plainly; there is nothing to retry.
    case unavailable

    /// The camera is ready, with the device's capabilities.
    ///
    /// Render only what the capabilities say the device supports.
    case ready(DeviceCapabilities)
}
