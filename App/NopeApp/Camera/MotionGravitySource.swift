import CoreMotion
import NopeCore

/// The level's gravity readings from Core Motion (`CMMotionManager` device motion), for
/// `NopeUI`'s level (issue #40).
///
/// Device motion needs no permission prompt. Updates run only while a stream from
/// ``gravityUpdates()`` is read, that is while the level is shown, at
/// ``updateInterval``, and stop when the stream ends (AGENTS.md, "Battery"). Privacy rule: the
/// readings are used on screen only; never written to a photo, stored or logged.
struct MotionGravitySource: GravitySource {
    /// The time between two readings, in seconds: 20 a second, smooth enough for a level that
    /// follows the hand without drawing more often than the screen needs.
    static let updateInterval = 1.0 / 20.0

    /// Starts device motion updates and returns their gravity vectors.
    ///
    /// - Returns: The readings; the stream ends at once on a device without device motion.
    func gravityUpdates() -> AsyncStream<GravityVector> {
        AsyncStream { continuation in
            let updates = MotionUpdates()
            guard updates.manager.isDeviceMotionAvailable else {
                continuation.finish()
                return
            }
            updates.manager.deviceMotionUpdateInterval = Self.updateInterval
            updates.manager.startDeviceMotionUpdates(to: updates.queue) { motion, _ in
                guard let gravity = motion?.gravity else { return }
                continuation.yield(GravityVector(x: gravity.x, y: gravity.y, z: gravity.z))
            }
            continuation.onTermination = { _ in updates.stop() }
        }
    }
}

/// One stream's motion manager and the queue its updates arrive on.
///
/// `@unchecked Sendable`: the manager is started once when the stream is made and stopped once,
/// on its own serial update queue, when the stream ends.
private final class MotionUpdates: @unchecked Sendable {
    /// The motion manager.
    let manager = CMMotionManager()

    /// The serial queue updates arrive on.
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// Stops the updates, on the update queue.
    func stop() {
        queue.addOperation { self.manager.stopDeviceMotionUpdates() }
    }
}
