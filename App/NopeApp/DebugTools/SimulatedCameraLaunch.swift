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
        /// Access already allowed; lenses with manual controls: the wide lens has every control,
        /// including a variable aperture and S and I modes; the ultra wide has a fixed aperture
        /// and only P and M; the front camera has no manual focus. Pair it with
        /// `-manualControlsEnabled YES` to show the controls.
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
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
            let scenario = Scenario(rawValue: arguments[index + 1])
        else { return nil }
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
