#if DEBUG
// Debug-only: the simulated location service the UI tests use. Compiled only in the Debug
// configuration; Release builds always use Core Location.

import Foundation
import NopeCore

/// Chooses a simulated location service for a UI test launch, so the Location switch can be
/// tested without the system prompt.
///
/// With `-NopeSimulatedCamera <scenario>`, location access starts "not asked" and is allowed when
/// asked. Add `-NopeSimulatedLocation denied` to have it declined.
enum SimulatedLocationLaunch {
    /// The launch argument: `-NopeSimulatedLocation`.
    static let argument = "-NopeSimulatedLocation"

    /// The simulated service for a UI test launch, or `nil` without a camera scenario.
    static func provider() -> (any LocationProviding)? {
        guard SimulatedCameraLaunch.scenario != nil else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        let denies = arguments.firstIndex(of: argument).map { $0 + 1 < arguments.count && arguments[$0 + 1] == "denied" }
        return SimulatedLocationProvider(declines: denies ?? false)
    }
}

/// A location service that answers the prompt at once and reports one fixed place.
actor SimulatedLocationProvider: LocationProviding {
    /// A fixed place, in the sea off the coast of Null Island, so it names no one's home.
    static let place = PhotoLocation(latitude: 0.5, longitude: 0.5, altitude: nil)

    /// Whether the simulated person declines access.
    private let declines: Bool

    /// The current access.
    private var access: LocationAccess = .notDetermined

    /// Creates the service.
    ///
    /// - Parameter declines: Whether access is declined when asked.
    init(declines: Bool) {
        self.declines = declines
    }

    /// The current access.
    func currentAccess() async -> LocationAccess {
        access
    }

    /// Answers the simulated prompt.
    func requestAccess() async -> LocationAccess {
        if access == .notDetermined { access = declines ? .denied : .allowed }
        return access
    }

    /// One location, then nothing until the stream is cancelled.
    nonisolated func locations() -> AsyncStream<PhotoLocation> {
        AsyncStream { continuation in continuation.yield(Self.place) }
    }
}
#endif
