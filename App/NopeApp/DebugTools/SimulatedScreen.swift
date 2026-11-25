#if DEBUG
// Debug-only: the screen keeper's brightness and times for the UI tests, which can't wait 2 or
// 30 minutes or set the Simulator's brightness. Compiled only in the Debug configuration.

import Foundation
import NopeCore
import UIKit

/// The launch arguments that change the screen keeper for a UI test:
///
/// - `-NopeSimulatedBrightness <0…1>`: the screen's brightness starts at this value and is kept
///   in memory (``Screen``), so a test can start below ``SeriesScreenKeeper/dimmedBrightness``
///   (issue #99). The idle timer is still the system's.
/// - `-NopeKeepScreenOnSeconds <dim>,<lowPowerDim>,<limit>`: Keep Screen On's times, in seconds,
///   instead of ``KeepScreenOnRule/standard``; `<dim>` is used for every Dim After choice but
///   Never (issue #119).
enum SimulatedScreen {
    /// The brightness launch argument.
    static let brightnessArgument = "-NopeSimulatedBrightness"

    /// The times launch argument.
    static let timesArgument = "-NopeKeepScreenOnSeconds"

    /// The value after a launch argument, or `nil`.
    ///
    /// - Parameter argument: The argument.
    private static func value(after argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The screen for the launch arguments, or `nil` to use the system's.
    @MainActor static func screen() -> (any ScreenControlling)? {
        value(after: brightnessArgument).flatMap(Double.init).map(Screen.init(brightness:))
    }

    /// The rule for the launch arguments, or `nil` for the standard times.
    static func rule() -> KeepScreenOnRule? {
        guard let seconds = value(after: timesArgument)?.split(separator: ",").compactMap({ Double($0) }),
            seconds.count == 3
        else { return nil }
        return KeepScreenOnRule(
            dimDelay: .seconds(seconds[0]), lowPowerDimDelay: .seconds(seconds[1]), limit: .seconds(seconds[2]))
    }

    /// A screen whose brightness is kept in memory; the idle timer is the system's.
    @MainActor final class Screen: ScreenControlling {
        /// The brightness, from 0 to 1.
        var brightness: Double

        /// Creates the screen.
        ///
        /// - Parameter brightness: The starting brightness.
        init(brightness: Double) {
            self.brightness = brightness
        }

        /// Whether the idle timer is off (`UIApplication.isIdleTimerDisabled`).
        var isIdleTimerDisabled: Bool {
            get { UIApplication.shared.isIdleTimerDisabled }
            set { UIApplication.shared.isIdleTimerDisabled = newValue }
        }
    }
}
#endif
