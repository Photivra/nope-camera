import Foundation

/// Whether the camera is running, and if not, why.
///
/// ``CameraModel/sessionStatus`` holds it while ``CameraModel/state`` is
/// ``CameraState/ready(_:)``. Each case says how an interface should present it.
public enum SessionStatus: Equatable, Sendable {
    /// The camera hasn't started yet. Show the viewfinder area empty, without a message.
    case stopped

    /// The camera is starting or switching lenses. Keep the shutter disabled.
    case starting

    /// The camera is running. Enable the shutter.
    case running

    /// The system paused the camera. Show the reason's message; it comes back by itself.
    case interrupted(InterruptionReason)

    /// nope. paused the camera because the device is too hot. Say so; it resumes when the
    /// device cools down.
    case pausedForHeat

    /// The camera couldn't start or stopped with an error. Show the error's message.
    case failed(CaptureError)

    /// The camera runs and delivers frames, but they are blank (zero-filled), even after
    /// nope. restarted it once. Seen on iOS when the system camera service is stuck; restarting
    /// the device clears it (docs/TESTING.md, "Black frames").
    ///
    /// Say: "The camera isn't sending a picture. Restarting your iPhone usually fixes this."
    /// Keep the shutter disabled. Selecting another lens tries again.
    case noPicture

    /// Whether a photo can be taken now: `true` only while ``running``.
    public var canCapture: Bool {
        self == .running
    }
}
