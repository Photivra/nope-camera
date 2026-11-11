import Foundation

/// How hot the device is, as the system reports it.
///
/// ``CameraModel`` pauses the camera at ``critical`` and resumes it below that level: Apple asks
/// apps to reduce their work immediately in the critical state
/// ([ProcessInfo.ThermalState.critical](https://developer.apple.com/documentation/foundation/processinfo/thermalstate/critical)).
public enum HeatLevel: Equatable, Comparable, Sendable, CaseIterable {
    /// Normal.
    case nominal
    /// Slightly elevated.
    case fair
    /// High; the system may reduce performance.
    case serious
    /// Critical; nope. pauses the camera until the device cools down.
    case critical

    /// Whether the camera must pause at this level: `true` only for ``critical``.
    public var requiresPause: Bool {
        self == .critical
    }
}
