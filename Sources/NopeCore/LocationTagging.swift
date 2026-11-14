import Foundation
import Observation

/// Whether nope. may use the device's location.
public enum LocationAccess: Equatable, Sendable {
    /// The person hasn't been asked yet.
    case notDetermined
    /// The person declined, or turned location off for nope. or for the whole device.
    case denied
    /// A restriction, such as Screen Time or a device profile, doesn't allow it.
    case restricted
    /// Allowed while nope. is in use.
    case allowed

    /// Whether a location can be read.
    public var isAllowed: Bool {
        self == .allowed
    }
}

/// The device's location service, behind a protocol so ``LocationTagging`` is tested with a
/// fake. The app implements it with Core Location.
///
/// Privacy rule (issue #43; AGENTS.md, "No network"): the location is read on the device and
/// written only into the person's own photos. Nothing is sent anywhere, and only "while using
/// the app" access is ever asked for.
public protocol LocationProviding: Sendable {
    /// The current access, without asking.
    func currentAccess() async -> LocationAccess

    /// Asks for "while using the app" access if the person hasn't been asked yet, and returns
    /// the access afterwards.
    ///
    /// Side effects: may show the system location prompt (the localized
    /// `NSLocationWhenInUseUsageDescription`).
    func requestAccess() async -> LocationAccess

    /// The device's locations, as they arrive. Updates run only while the sequence is iterated
    /// and stop as soon as the iterating task is cancelled (AGENTS.md, "Battery").
    func locations() -> AsyncStream<PhotoLocation>
}

/// Location tagging for photos (issue #43): asks for access when the person turns Location on,
/// follows the location only while the camera is running, and gives each photo the latest one.
///
/// The rules live here, so any interface only calls these methods:
///
/// - Location is off by default (``MetadataItem/location``). ``turnOn(in:)`` asks for access
///   first and turns the switch on only if access is allowed.
/// - Location updates run only while the switch is on, access is allowed and the camera is
///   running (``update(isOn:cameraIsRunning:)``). They stop otherwise, and the last location is
///   forgotten, so a photo never gets a location from an earlier session.
/// - A photo taken before the first location arrives is saved without a location.
///
/// ```swift
/// let tagging = LocationTagging(provider: provider)
/// await tagging.turnOn(in: settings)
/// await tagging.update(isOn: settings.metadata.isOn(.location), cameraIsRunning: true)
/// model.location = tagging
/// ```
@MainActor
@Observable
public final class LocationTagging {
    /// Whether nope. may use the location, as last read.
    public private(set) var access: LocationAccess = .notDetermined

    /// The latest location while updates run, or `nil`.
    public private(set) var latestLocation: PhotoLocation?

    /// Whether location updates are running.
    public var isUpdating: Bool {
        updates != nil
    }

    /// The location service.
    private let provider: any LocationProviding

    /// The task that reads location updates, while they run.
    private var updates: Task<Void, Never>?

    /// Creates location tagging with no updates running.
    ///
    /// - Parameter provider: The device's location service, or a fake in tests.
    public init(provider: any LocationProviding) {
        self.provider = provider
    }

    /// Reads the current access again, for example when the app comes back from Settings.
    public func refreshAccess() async {
        access = await provider.currentAccess()
    }

    /// Turns the Location switch on, after asking for access.
    ///
    /// Side effects: may show the system location prompt. Saves the switch through `settings`.
    ///
    /// - Parameter settings: The settings to change.
    /// - Returns: `true` if Location is now on; `false` if access isn't allowed, in which case
    ///   the switch stays off and an interface explains how to allow it (``access``).
    @discardableResult
    public func turnOn(in settings: NopeSettings) async -> Bool {
        access = await provider.requestAccess()
        guard access.isAllowed else { return false }
        settings.setMetadataItem(.location, isIncluded: true)
        return true
    }

    /// Starts or stops location updates to match the camera and the switch.
    ///
    /// Call it whenever either changes. Updates run only when `isOn`, `cameraIsRunning` and
    /// access is allowed; otherwise they stop and ``latestLocation`` is cleared.
    ///
    /// - Parameters:
    ///   - isOn: Whether the Location switch is on.
    ///   - cameraIsRunning: Whether the camera session is running.
    public func update(isOn: Bool, cameraIsRunning: Bool) async {
        guard isOn && cameraIsRunning else {
            stop()
            return
        }
        access = await provider.currentAccess()
        // A newer call may have replaced this one while it waited (a cancelled SwiftUI task).
        guard !Task.isCancelled, access.isAllowed else {
            stop()
            return
        }
        guard updates == nil else { return }
        let stream = provider.locations()
        updates = Task { [weak self] in
            for await location in stream {
                self?.latestLocation = location
            }
        }
    }

    /// The location to write into a photo taken now.
    ///
    /// - Parameter isOn: Whether the Location switch is on.
    /// - Returns: The latest location when the switch is on and updates run; otherwise `nil`.
    public func location(isOn: Bool) -> PhotoLocation? {
        isOn ? latestLocation : nil
    }

    /// Stops location updates and forgets the last location.
    private func stop() {
        updates?.cancel()
        updates = nil
        latestLocation = nil
    }
}
