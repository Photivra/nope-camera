#if DEBUG
// Debug-only: lets a debug run (the tag check or the camera probe) start from a normal Home
// Screen launch, so it can be compared with a launch by `devicectl` (docs/TESTING.md,
// "Black frames"). Compiled only in the Debug configuration.

import Foundation

/// Chooses which debug run, if any, this launch performs.
///
/// A run starts either from its own launch argument (`-NopeTagCheck`, `-NopeCameraProbe`) or,
/// once, from a run armed by an earlier launch with `-NopeArmDebugRun <run>`: that launch shows
/// a message and stores the run; the next launch from the Home Screen performs it and clears it.
enum DebugRunLaunch {
    /// A debug run.
    enum Run: String {
        /// The metadata tag check (``TagCheckScreen``).
        case tagCheck = "tagcheck"
        /// The camera probe (``CameraProbeScreen``).
        case probe
    }

    /// The launch argument that arms a run for the next launch: `-NopeArmDebugRun`.
    static let armArgument = "-NopeArmDebugRun"

    /// The `UserDefaults` key holding the armed run. Debug builds only; holds no user data.
    private static let pendingKey = "NopePendingDebugRun"

    /// What this launch does.
    enum Decision: Equatable {
        /// Stored `run` for the next launch; the screen says to open the app from the Home Screen.
        case armed(Run)
        /// Perform `run` now.
        case perform(Run)
        /// Show the camera screen.
        case none
    }

    /// The decision for this process, made once: arming stores the run, and a stored run is
    /// cleared when it is performed.
    static let decision: Decision = decide(
        arguments: ProcessInfo.processInfo.arguments, defaults: .standard)

    /// Decides from the launch arguments and the stored run.
    static func decide(arguments: [String], defaults: UserDefaults) -> Decision {
        if let index = arguments.firstIndex(of: armArgument), index + 1 < arguments.count,
            let run = Run(rawValue: arguments[index + 1])
        {
            defaults.set(run.rawValue, forKey: pendingKey)
            return .armed(run)
        }
        if arguments.contains(TagCheckLaunch.argument) { return .perform(.tagCheck) }
        if arguments.contains(CameraProbeLaunch.argument) { return .perform(.probe) }
        if let stored = defaults.string(forKey: pendingKey), let run = Run(rawValue: stored) {
            defaults.removeObject(forKey: pendingKey)
            return .perform(run)
        }
        return .none
    }
}
#endif
