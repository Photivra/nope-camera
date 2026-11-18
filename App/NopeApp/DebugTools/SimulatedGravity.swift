#if DEBUG
// Debug-only: gravity readings for the UI tests, because the Simulator has no motion sensors.
// Compiled only in the Debug configuration.

import Foundation
import NopeCore

/// A ``GravitySource`` that sends a fixed reading, or a tilted reading and then a level one,
/// chosen with the launch argument
/// `-NopeSimulatedGravity <tilted|level|flat|becomesLevel|becomesFlatLevel>`.
///
/// `becomesLevel` and `becomesFlatLevel` send the tilted reading, then the level one
/// ``levelAfterSeconds`` later, so a UI test sees the level become level (the moment of its
/// tap, docs/design/level-haptic.md).
struct SimulatedGravity: GravitySource {
    /// The launch argument: `-NopeSimulatedGravity`.
    static let argument = "-NopeSimulatedGravity"

    /// How long the tilted reading of a sequence lasts before the level one, in seconds: long
    /// enough for a test to read and audit the tilted state, or to open a sheet first.
    static let levelAfterSeconds = 8.0

    /// Upright, turned about 5 degrees clockwise.
    static let tilted = GravityVector(x: 0.087, y: -0.996, z: 0)

    /// Upright and level.
    static let level = GravityVector(x: 0, y: -1, z: 0)

    /// Pointing straight down, level.
    static let flat = GravityVector(x: 0, y: 0, z: -1)

    /// Pointing down with the top edge raised about 5 degrees: the top-down level, not level.
    static let flatTilted = GravityVector(x: 0, y: -0.087, z: -0.996)

    /// The first reading it sends.
    let reading: GravityVector

    /// The reading it sends ``levelAfterSeconds`` after the first, or `nil` to send only one.
    var laterReading: GravityVector?

    /// The simulated source from the launch arguments, or `nil` without the argument.
    static func fromLaunchArguments() -> SimulatedGravity? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "level": return SimulatedGravity(reading: level)
        case "flat": return SimulatedGravity(reading: flat)
        case "becomesLevel": return SimulatedGravity(reading: tilted, laterReading: level)
        case "becomesFlatLevel": return SimulatedGravity(reading: flatTilted, laterReading: flat)
        default: return SimulatedGravity(reading: tilted)
        }
    }

    /// Sends the reading, and the later one after its pause, then keeps the stream open until it
    /// is no longer read, as the motion sensors would.
    func gravityUpdates() -> AsyncStream<GravityVector> {
        AsyncStream { continuation in
            continuation.yield(reading)
            guard let laterReading else { return }
            let task = Task {
                try? await Task.sleep(for: .seconds(Self.levelAfterSeconds))
                guard !Task.isCancelled else { return }
                continuation.yield(laterReading)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
