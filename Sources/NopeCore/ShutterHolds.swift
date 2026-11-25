import Foundation

/// Which shutter a press came from (issue #100): the on-screen shutter, or a hardware shutter
/// button (the volume buttons or the Camera Control, issue #37). Each has its own hold, so a
/// press and release of one doesn't end a burst the other holds.
public enum ShutterSource: CaseIterable, Hashable, Sendable {
    /// The shutter on the screen.
    case onScreen

    /// A volume button or the Camera Control.
    case hardware
}

/// Which shutter presses are down now, by source, with each press numbered (issue #100;
/// `docs/plans/1.0.0-finish.md`, section 4.2).
///
/// A source numbers its presses in order, from 1, and a release carries the number of its press.
/// A press or release that arrives late is recognized by its number:
/// - a press whose number is not above the latest press of its source is old, and is dropped;
/// - a release of an earlier press than the latest is old, and is dropped: it can't end the hold
///   of the press that came after it;
/// - a release that arrives before its press is kept, so the press counts as already released
///   when it arrives, and no hold is left behind.
///
/// A caller that doesn't number its presses passes `nil`: its press is the next number, and its
/// release ends its latest press.
struct ShutterHolds: Equatable {
    /// What a press is, once its number is checked.
    enum Press: Equatable {
        /// A new press. `isReleased` is `true` when its release arrived first.
        case new(number: Int, isReleased: Bool)

        /// An old or repeated press, dropped.
        case stale
    }

    /// What a release is, once its number is checked.
    enum Release: Equatable {
        /// It ends the latest press of its source (also when that press already ended).
        case current

        /// It arrived before its press, which will count as released.
        case early

        /// The release of an earlier press than the latest, dropped.
        case stale
    }

    /// The number of the latest press of each source, or none.
    private var latestPress: [ShutterSource: Int] = [:]

    /// The number of the latest press of each source that has ended, or none.
    private var latestRelease: [ShutterSource: Int] = [:]

    /// Creates the holds with no press yet from any source.
    init() {}

    /// Whether a press of this source is down.
    ///
    /// - Parameter source: The shutter.
    func isHeld(_ source: ShutterSource) -> Bool {
        latestPress[source, default: 0] > latestRelease[source, default: 0]
    }

    /// Whether any shutter is down.
    var isAnyHeld: Bool {
        ShutterSource.allCases.contains(where: isHeld)
    }

    /// Records a press.
    ///
    /// - Parameters:
    ///   - number: The press's number from its source, or `nil` for the next one.
    ///   - source: The shutter.
    /// - Returns: Whether it is a new press, and whether it is already released.
    mutating func press(_ number: Int?, from source: ShutterSource) -> Press {
        let latest = latestPress[source, default: 0]
        let number = number ?? latest + 1
        guard number > latest else { return .stale }
        latestPress[source] = number
        return .new(number: number, isReleased: latestRelease[source, default: 0] >= number)
    }

    /// Records a release, or a cancelled press.
    ///
    /// - Parameters:
    ///   - number: The number of the press it ends, or `nil` for the latest press.
    ///   - source: The shutter.
    /// - Returns: Whether it ends the latest press, comes before its press, or is old.
    mutating func release(_ number: Int?, from source: ShutterSource) -> Release {
        let latest = latestPress[source, default: 0]
        let number = number ?? latest
        guard number >= latest else { return .stale }
        latestRelease[source] = max(latestRelease[source, default: 0], number)
        return number == latest ? .current : .early
    }

    /// Ends every press that is down, as if each came up: the app left the active state
    /// (issue #101).
    mutating func releaseAll() {
        for source in ShutterSource.allCases {
            latestRelease[source] = max(latestRelease[source, default: 0], latestPress[source, default: 0])
        }
    }
}
