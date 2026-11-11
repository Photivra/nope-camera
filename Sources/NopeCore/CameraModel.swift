import Foundation
import Observation

/// The camera's state machine: the single object an interface talks to.
///
/// An interface observes ``state`` and sends ``CameraIntent`` values through ``send(_:)``.
/// The model asks its ``CaptureBackend`` for facts and decides the next state; the interface
/// holds no rules of its own (AGENTS.md, "One direction of flow").
///
/// The model is isolated to the main actor, so an interface can read ``state`` directly.
@MainActor
@Observable
public final class CameraModel {
    /// The current camera state. Interfaces render it; only the model changes it.
    public private(set) var state: CameraState = .starting

    /// The hardware the model asks for permission and capabilities.
    private let backend: any CaptureBackend

    /// Creates a model in the ``CameraState/starting`` state.
    ///
    /// - Parameter backend: The hardware, or a ``SimulatedCaptureBackend`` in tests and previews.
    public init(backend: any CaptureBackend) {
        self.backend = backend
    }

    /// Handles one intent from the interface and updates ``state``.
    ///
    /// - Parameter intent: What the interface asks for.
    ///
    /// Side effect: ``CameraIntent/requestPermission`` may show the system camera prompt.
    public func send(_ intent: CameraIntent) async {
        switch intent {
        case .start:
            await resolve(await backend.currentPermission())
        case .requestPermission:
            await resolve(await backend.requestPermission())
        }
    }

    /// Moves to the state that matches a permission, discovering capabilities when allowed.
    ///
    /// - Parameter permission: The permission the backend just reported.
    private func resolve(_ permission: CameraPermission) async {
        switch permission {
        case .notDetermined:
            state = .needsPermission
        case .denied, .restricted:
            state = .permissionDenied
        case .authorized:
            let capabilities = await backend.deviceCapabilities()
            state = capabilities.hasCamera ? .ready(capabilities) : .unavailable
        }
    }
}
