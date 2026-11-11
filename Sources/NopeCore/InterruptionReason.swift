import Foundation

/// Why the system paused the camera.
///
/// The system resumes the camera by itself when the reason goes away; nope. never restarts it
/// against the system. Each case says how an interface should present it.
public enum InterruptionReason: Equatable, Sendable, CaseIterable {
    /// The app moved to the background. Nothing to show: the screen isn't visible.
    case backgrounded

    /// Another app or a call is using the camera or the microphone.
    ///
    /// Say that the camera is in use by another app or a call, and that it comes back when that
    /// ends.
    case inUseElsewhere

    /// The app shares the screen with other apps (iPad Split View, Slide Over or Stage Manager).
    ///
    /// Say that the camera works only when nope. fills the screen.
    case multitasking

    /// The device is too hot, or under other system pressure, to run the camera.
    ///
    /// Say that the camera is paused to let the device cool down.
    case systemPressure

    /// The system paused the camera for another reason, including one added in a later iOS.
    ///
    /// Say that the camera is paused by the system and will come back.
    case other
}
