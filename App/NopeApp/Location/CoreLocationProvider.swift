import CoreLocation
import NopeCore

/// The device's location for photo tagging (issue #43), with Core Location.
///
/// A thin adapter behind `LocationProviding`; the rules (ask only when the person turns
/// Location on, follow the location only while the camera runs) are in `LocationTagging`, which
/// is fully tested. Core Location needs a device and a person to answer its prompt, so this is
/// verified on a device (docs/TESTING.md, "Location").
///
/// Privacy rule (AGENTS.md, "No network"; docs/PRIVACY.md, "Location"): only "while using the
/// app" access is asked for (`requestWhenInUseAuthorization()`); there is no background location
/// mode. The location stays on the device and is written only into the person's own photos.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    /// The manager, used for access only. Created on the main thread, so its delegate is called
    /// there (`CLLocationManager` documentation, "Receiving data from location services").
    private let manager = CLLocationManager()

    /// Callers waiting for the person to answer the location prompt.
    private var waiting: [CheckedContinuation<LocationAccess, Never>] = []

    /// Creates the provider.
    override init() {
        super.init()
        manager.delegate = self
    }

    /// The current access, without asking.
    func currentAccess() async -> LocationAccess {
        Self.access(manager.authorizationStatus)
    }

    /// Asks for "while using the app" access if the person hasn't been asked yet.
    ///
    /// Side effects: may show the system location prompt.
    func requestAccess() async -> LocationAccess {
        guard manager.authorizationStatus == .notDetermined else { return Self.access(manager.authorizationStatus) }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// The device's locations while the stream is iterated, from `CLLocationUpdate.liveUpdates()`,
    /// which delivers updates only while its loop runs and stops when the iterating task is
    /// cancelled (`CLLocationUpdate` documentation). A location without a valid position is
    /// skipped; an altitude without a valid vertical accuracy is left out.
    nonisolated func locations() -> AsyncStream<PhotoLocation> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        guard let location = update.location, location.horizontalAccuracy >= 0 else { continue }
                        continuation.yield(
                            PhotoLocation(
                                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil))
                    }
                } catch {
                    // The updates ended; the photo is saved without a location.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Answers the callers waiting for the prompt once the person has decided.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard status != .notDetermined else { return }
            let callers = waiting
            waiting = []
            for caller in callers { caller.resume(returning: Self.access(status)) }
        }
    }

    /// The access for a Core Location authorization status.
    ///
    /// - Parameter status: The status.
    /// - Returns: The matching access; "always" counts as allowed, though the app never asks for it.
    private static func access(_ status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }
}
