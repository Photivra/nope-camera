#if DEBUG
// Debug-only: how long a pinch's lens label stays, for the UI tests' accessibility audits of the
// label (docs/design/pinch-lens.md, section 11, UI test 9). Release builds use 0.8 seconds.

import Foundation
import NopeCore

/// Reads `-NopeSimulatedPinchLabelSeconds <seconds>` from the launch arguments.
enum SimulatedPinch {
    /// The launch argument: `-NopeSimulatedPinchLabelSeconds`.
    static let argument = "-NopeSimulatedPinchLabelSeconds"

    /// How long the lens label stays after a pinch: the launch argument's seconds, or the app's
    /// own time (`LensPinchSwitcher.labelSeconds`) without it.
    static var labelSeconds: Double {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
            let seconds = Double(arguments[index + 1]), seconds > 0
        else { return LensPinchSwitcher.labelSeconds }
        return seconds
    }
}
#endif
