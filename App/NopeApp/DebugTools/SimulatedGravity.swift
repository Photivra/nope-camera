#if DEBUG
// Debug-only: a fixed gravity reading for the UI tests, because the Simulator has no motion
// sensors. Compiled only in the Debug configuration.

import Foundation
import NopeCore

/// A ``GravitySource`` that sends one fixed reading, chosen with the launch argument
/// `-NopeSimulatedGravity <tilted|level|flat>`.
struct SimulatedGravity: GravitySource {
    /// The launch argument: `-NopeSimulatedGravity`.
    static let argument = "-NopeSimulatedGravity"

    /// The reading it sends.
    let reading: GravityVector

    /// The simulated source from the launch arguments, or `nil` without the argument.
    static func fromLaunchArguments() -> SimulatedGravity? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "level": return SimulatedGravity(reading: GravityVector(x: 0, y: -1, z: 0))
        case "flat": return SimulatedGravity(reading: GravityVector(x: 0, y: 0, z: -1))
        // Upright, turned about 5 degrees clockwise.
        default: return SimulatedGravity(reading: GravityVector(x: 0.087, y: -0.996, z: 0))
        }
    }

    /// Sends the reading once, then keeps the stream open until it is no longer read, as the
    /// motion sensors would.
    func gravityUpdates() -> AsyncStream<GravityVector> {
        AsyncStream { continuation in
            continuation.yield(reading)
        }
    }
}
#endif
