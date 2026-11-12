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
        case .multitasking:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: capabilities, eventsAfterStart: [.interrupted(.multitasking)])
        case .noRAW:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: DeviceCapabilities(lenses: lensesWithoutRAW))
        case .denied:
            return SimulatedCaptureBackend(permission: .denied)
        case .noCamera:
            return SimulatedCaptureBackend(permission: .authorized)
        }
    }
}
#endif
