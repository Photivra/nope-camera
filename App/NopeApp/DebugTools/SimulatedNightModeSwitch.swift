#if DEBUG
// Debug-only: switches Night Mode from outside the app's screens, as Siri, a shortcut or the
// Control Center control do, which XCTest can't use. Compiled only in the Debug configuration.

import Foundation
import NopeCore

/// Switches Night Mode on or off at set times after launch, through ``NopeSettings``, as the
/// Set Night Mode action does: `-NopeSimulatedNightModeSwitch <seconds>[,<seconds>…]`, each
/// counted from the switch before (the first from launch). The UI tests use it to switch Night
/// Mode while a search is in progress in Settings (issue #88, decision 7).
@MainActor
enum SimulatedNightModeSwitch {
    /// The launch argument: `-NopeSimulatedNightModeSwitch`.
    static let argument = "-NopeSimulatedNightModeSwitch"

    /// The delays from the launch arguments; empty without the argument.
    static var delays: [Double] {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return [] }
        return arguments[index + 1].split(separator: ",").compactMap { Double($0) }
    }

    /// Switches Night Mode after each delay, for as long as the task runs.
    ///
    /// - Parameter settings: The app's settings.
    static func run(settings: NopeSettings) async {
        for delay in delays {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            settings.setNightMode(!settings.isNightModeOn)
        }
    }
}
#endif
