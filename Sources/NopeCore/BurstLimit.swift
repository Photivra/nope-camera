import Foundation

/// How many photos one press takes in Burst (Burst Limit, issue #121,
/// `docs/design/finish-1.0.md`, section 5): Off, the default, or 3, 5, 10, 20 or 50.
///
/// With the limit Off, a tap takes one photo and holding takes photos until the shutter comes
/// up, as before the setting existed. With a limit, a tap or a hold of the shutter (on screen or
/// a hardware button), assistive activation and Start Burst start a burst that runs to the count
/// even after the finger lifts (``BurstStart/limited``), and a second press stops it after the
/// photo being taken (owner decisions, 2026-11-21). Every photo taken is saved; low storage and
/// the camera stopping still end it early.
///
/// An interface sends the setting with ``DriveIntent/setBurstLimit(_:)`` when the camera screen
/// appears and whenever it changes; ``DriveModel/burstLimit`` holds it, and the burst's progress
/// and result carry the count (``BurstProgress/limit``, ``BurstResult/limit``).
///
/// What the setting doesn't change:
/// - Siri and Shortcuts keep their own photo count (``PhotoShortcut/count``).
/// - The Apple Watch shutter stays as it is (owner decision 9). Today it takes one photo in
///   Burst: `WatchCommandServer` sends ``PhotoShortcut`` with a count of 1, which takes a single
///   photo, or the exposure bracket on in the manual controls, whatever the drive mode.
/// - Drive mode still starts in Single at every launch.
///
/// Stored by its raw value, which never changes once released (``NopeSettings/burstLimit``).
public enum BurstLimit: String, CaseIterable, Codable, Sendable {
    /// No limit: a tap takes one photo, a hold takes photos until it ends. The default.
    case off
    /// 3 photos a press.
    case three
    /// 5 photos a press.
    case five
    /// 10 photos a press.
    case ten
    /// 20 photos a press.
    case twenty
    /// 50 photos a press, the most a burst takes (``DriveModel/maximumBurstFrames``).
    case fifty

    /// The default: Off, so a burst works as before the setting existed.
    public static let standard = BurstLimit.off

    /// How many photos one press takes, never more than ``DriveModel/maximumBurstFrames``, or
    /// `nil` for ``off``.
    public var frameCount: Int? {
        let count: Int? =
            switch self {
            case .off: nil
            case .three: 3
            case .five: 5
            case .ten: 10
            case .twenty: 20
            case .fifty: 50
            }
        return count.map { min($0, DriveModel.maximumBurstFrames) }
    }
}
