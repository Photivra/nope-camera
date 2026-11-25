#if DEBUG
// Debug-only: a press of a hardware shutter button (a volume button or the Camera Control),
// which the Simulator can't make and XCTest can't press. Compiled only in the Debug configuration.

import Foundation
import NopeCore
import notify

/// Sends a hardware shutter button's press and release to the camera model each time the UI
/// test posts ``notificationName``, while the app was launched with ``argument``. They go
/// through the same entry as the system's capture events (`CameraModel.shutter(_:from:press:)`,
/// from ``ShutterSource/hardware``). The test posts the name with `notify_post`; the Simulator
/// delivers it to every process on the simulated device.
@MainActor
enum SimulatedHardwareButton {
    /// The launch argument: `-NopeSimulatedHardwareButton`.
    static let argument = "-NopeSimulatedHardwareButton"

    /// The notification a UI test posts for one press and release. The UI tests use the same
    /// string (`PhotoViewerUITests.swift`).
    static let notificationName = "com.photivra.nope.debug.simulatedHardwareButton"

    /// Whether the current process was launched with ``argument``.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Sends a press and a release for each notification, for as long as the task runs.
    ///
    /// - Parameter model: The camera model.
    static func run(model: CameraModel) async {
        guard isRequested else { return }
        let presses = AsyncStream<Void> { continuation in
            var token: Int32 = 0
            let status = notify_register_dispatch(notificationName, &token, .main) { _ in continuation.yield() }
            guard status == UInt32(NOTIFY_STATUS_OK) else {
                continuation.finish()
                return
            }
            let registered = token
            continuation.onTermination = { _ in notify_cancel(registered) }
        }
        for await _ in presses {
            model.shutter(.pressed, from: .hardware)
            model.shutter(.released, from: .hardware)
        }
    }
}
#endif
