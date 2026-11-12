#if DEBUG
// Debug-only: the simulated camera scenarios the UI tests launch with. Compiled only in the
// Debug configuration; Release builds always use the device's cameras.

import Foundation
import NopeCore

/// Chooses a ``SimulatedCaptureBackend`` scenario from the launch arguments, so the UI tests can
/// drive every camera state on the Simulator, which has no camera.
///
/// Launch with `-NopeSimulatedCamera <scenario>`, where the scenario is a ``Scenario`` raw value.
enum SimulatedCameraLaunch {
    /// The launch argument: `-NopeSimulatedCamera`.
    static let argument = "-NopeSimulatedCamera"

    /// A simulated camera state.
    enum Scenario: String, CaseIterable {
        /// Permission not asked yet; allowing it gives four lenses, the telephoto without RAW.
        case allow
        /// Access already allowed; the camera then reports another app using it.
        case interrupted
        /// Access already allowed; the device then reports critical heat.
        case hot
        /// Access already allowed; every capture fails.
        case captureFails
        /// Access already allowed; every photo is blank, so the first capture leads to the
        /// "isn't sending a picture" state after one restart.
        case blankPicture
        /// Access already allowed; the camera then reports iPad multitasking (Split View, Slide
        /// Over or Stage Manager).
        case multitasking
        /// Access already allowed; no lens has Bayer RAW, like an iPad without RAW, so every
        /// photo is the labeled fallback.
        case noRAW
        /// Access already allowed; every finished file fails the metadata read-back (a simulated
        /// future system tag), so nothing is saved.
        case metadataRejected
        /// Access already allowed; adding to the photo library is not allowed.
        case photosDenied
        /// Access already allowed; signing fails, so photos are saved unsigned and the status
        /// says so.
        case signingFails
        /// Access already allowed; lenses with manual controls: the wide lens has every control,
        /// including a variable aperture and S and I modes; the ultra wide has a fixed aperture
        /// and only P and M; the front camera has no manual focus. Pair it with
        /// `-NopeSettings.showsManualControls YES` to show the controls.
        case manual
        /// Access declined.
        case denied
        /// Access allowed, but no camera.
        case noCamera
    }

    /// Four lenses like an iPhone Pro's: ultra wide, wide and front with Bayer RAW, and a 5×
    /// telephoto without it, to show the labeled fallback.
    static let lenses: [Lens] = [
        Lens(id: "simulated-ultra-wide", kind: .ultraWide, bayerRAWFormat: "rgg4", magnification: 0.5),
        Lens(id: "simulated-wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1),
        Lens(id: "simulated-telephoto", kind: .telephoto, bayerRAWFormat: nil, magnification: 5),
        Lens(id: "simulated-front", kind: .front, bayerRAWFormat: "bgg4"),
    ]

    /// Two lenses like an iPad's without RAW: a wide and a front camera, neither with Bayer RAW.
    static let lensesWithoutRAW: [Lens] = [
        Lens(id: "simulated-wide-no-raw", kind: .wide, bayerRAWFormat: nil, magnification: 1),
        Lens(id: "simulated-front-no-raw", kind: .front, bayerRAWFormat: nil),
    ]
    /// The `UserDefaults` suite that holds settings during UI tests.
    static let settingsSuiteName = "NopeUITestSettings"

    /// An emptied settings store for a UI test launch, or `nil` without a scenario, so UI tests
    /// always start from the default settings and never change the real ones.
    static func settingsStore() -> UserDefaults? {
        guard ProcessInfo.processInfo.arguments.contains(argument),
            let store = UserDefaults(suiteName: settingsSuiteName)
        else { return nil }
        store.removePersistentDomain(forName: settingsSuiteName)
        return store
    }

    /// The scenario in the launch arguments, or `nil` without one.
    static var scenario: Scenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return Scenario(rawValue: arguments[index + 1])
    }

    /// The simulated save pipeline for the scenario in the launch arguments, or `nil` without
    /// one. Nothing touches the Simulator's photo library.
    ///
    /// - Parameter appVersion: The app's version.
    static func saver(appVersion: String) -> PhotoSaver? {
        guard let scenario else { return nil }
        return PhotoSaver(
            developer: SimulatedDeveloper(), signer: SimulatedSigner(fails: scenario == .signingFails),
            reader: SimulatedReadBack(addsUnexpectedTag: scenario == .metadataRejected),
            library: SimulatedPhotoLibrary(allowsAdding: scenario != .photosDenied), appVersion: appVersion)
    }
    /// Every manual control, as on a recent rear wide camera with iOS 27.
    static let fullManual = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: true, supportsISOPriority: true,
        supportsAperturePriority: true, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center, .spot, .wholeFrame])

    /// Manual exposure without priority modes, as before iOS 27.
    static let basicManual = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: false, supportsISOPriority: false,
        supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center])

    /// The lenses of the `manual` scenario.
    static let manualLenses: [Lens] = [
        Lens(
            id: "simulated-ultra-wide", kind: .ultraWide, bayerRAWFormat: "rgg4", magnification: 0.5,
            isoRange: 15...3600, exposureDurationRange: 0.000_014...1, aperture: .fixed(2.2), maxBracketedPhotoCount: 3,
            manualControls: basicManual),
        Lens(
            id: "simulated-wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1, isoRange: 54...12_096,
            exposureDurationRange: 0.000_014...1,
            aperture: ApertureRange(minimumFNumber: 1.48, maximumFNumber: 4, recommendedStops: [1.48, 1.8, 2.8, 4]),
            maxBracketedPhotoCount: 8, manualControls: fullManual),
        Lens(
            id: "simulated-front", kind: .front, bayerRAWFormat: "bgg4", isoRange: 20...1920,
            exposureDurationRange: 0.000_014...0.5, aperture: .fixed(1.9),
            manualControls: ManualCapabilities(
                supportsManualExposure: true, supportsShutterPriority: false, supportsISOPriority: false,
                supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
                supportsAutoFocus: false, supportsFocusLock: false, supportsManualFocus: false,
                supportsManualWhiteBalance: true, meteringModes: [.center])),
    ]

    /// The simulated backend for the scenario in the launch arguments, or `nil` without one.
    static func backend() -> SimulatedCaptureBackend? {
        guard let scenario else { return nil }
        let capabilities = DeviceCapabilities(lenses: lenses)
        switch scenario {
        case .allow:
            return SimulatedCaptureBackend(
                permission: .notDetermined, permissionAfterRequest: .authorized, capabilities: capabilities)
        case .interrupted:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: capabilities, eventsAfterStart: [.interrupted(.inUseElsewhere)])
        case .hot:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: capabilities, eventsAfterStart: [.heat(.critical)])
        case .captureFails:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities, captureError: .captureFailed)
        case .blankPicture:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities, captureError: .blankPicture)
        case .multitasking:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: capabilities, eventsAfterStart: [.interrupted(.multitasking)])
        case .noRAW:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: DeviceCapabilities(lenses: lensesWithoutRAW))
        case .metadataRejected, .photosDenied, .signingFails:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities)
        case .manual:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: DeviceCapabilities(lenses: manualLenses))
        case .denied:
            return SimulatedCaptureBackend(permission: .denied)
        case .noCamera:
            return SimulatedCaptureBackend(permission: .authorized)
        }
    }
}
#endif
