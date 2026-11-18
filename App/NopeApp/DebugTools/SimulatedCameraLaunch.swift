#if DEBUG
// Debug-only: the simulated camera scenarios the UI tests launch with. Compiled only in the
// Debug configuration; Release builds always use the device's cameras.

import Foundation
import NopeCore
import SwiftUI

/// Chooses a ``SimulatedCaptureBackend`` scenario from the launch arguments, so the UI tests can
/// drive every camera state on the Simulator, which has no camera.
///
/// Launch with `-NopeSimulatedCamera <scenario>`, where the scenario is a ``Scenario`` raw value.
enum SimulatedCameraLaunch {
    /// The launch argument: `-NopeSimulatedCamera`.
    static let argument = "-NopeSimulatedCamera"

    /// Interrupts the simulated camera while the app is in the background and ends the
    /// interruption when it returns, as AVFoundation does for a real camera
    /// (`videoDeviceNotAvailableInBackground`), so the UI tests can leave and return during a run.
    ///
    /// Only an interruption this started is ended: every change of the scene's phase used to end
    /// any interruption, so the launch's own move to active ended the `interrupted` and
    /// `multitasking` scenarios' interruption, and their message never showed.
    ///
    /// - Parameters:
    ///   - isInBackground: Whether the app is in the background now.
    ///   - backend: The launch's backend; anything but the simulated one is left alone.
    @MainActor static func followScenePhase(_ isInBackground: Bool, backend: any CaptureBackend) {
        guard let simulated = backend as? SimulatedCaptureBackend,
            let event = backgroundEvent(isInBackground: isInBackground, interruptedForBackground: &interruptedForBackground)
        else { return }
        simulated.emit(event)
    }

    /// Whether ``followScenePhase(_:backend:)`` interrupted the camera for the background and
    /// hasn't ended it yet.
    @MainActor static var interruptedForBackground = false

    /// The event for a change of the scene's phase: an interruption on entering the background,
    /// its end on leaving it, and nothing otherwise (another phase change, or a return the
    /// background interruption wasn't sent for).
    ///
    /// - Parameters:
    ///   - isInBackground: Whether the app is in the background now.
    ///   - interruptedForBackground: Whether the camera is interrupted for the background;
    ///     updated.
    /// - Returns: The event to send, or `nil`.
    static func backgroundEvent(isInBackground: Bool, interruptedForBackground: inout Bool) -> CaptureEvent? {
        guard isInBackground != interruptedForBackground else { return nil }
        interruptedForBackground = isInBackground
        return isInBackground ? .interrupted(.backgrounded) : .interruptionEnded
    }

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
        /// Access already allowed; every signed file fails the read-back, so the unsigned files
        /// are saved and the status says they aren't signed.
        case signedFileRejected
        /// Access already allowed; lenses with manual controls: the wide lens has every control,
        /// including a variable aperture and S and I modes; the ultra wide has a fixed aperture
        /// and only P and M; the front camera has no manual focus. Pair it with
        /// `-NopeSettings.showsManualControls YES` to show the controls.
        case manual
        /// Access already allowed; each save takes half a second, so a burst runs long enough
        /// for the UI tests to see and stop it.
        case slowSaving
        /// As `slowSaving`, and each photo takes 0.4 seconds to take, so a tap on the shutter in
        /// burst mode ends before a second photo, and holding it takes a burst at a measurable
        /// rate (docs/design/BURST.md).
        case burst
        /// As `manual`, and each save takes half a second, so the astro helper's frames run long
        /// enough for the UI tests to see and stop them.
        case astro
        /// Access already allowed; lenses with the full-auto aids (tap to focus, exposure
        /// compensation, Close-Up) and focal lengths, in bright light.
        case aids
        /// As `aids`, in light too low for a handheld shutter: "Hold it steady or use a tripod".
        case dimLight
        /// As `aids`, with the wide lens stuck at its nearest focus: the ultra wide suggestion.
        case tooClose
        /// Access already allowed; the four lenses, but the system refuses the light, as on a
        /// device too hot for it.
        case lightUnavailable
        /// Access already allowed; the comparison shot's second photo, with the phone's
        /// processing, always fails (issue #55).
        case comparisonFails
        /// Access declined.
        case denied
        /// Access allowed, but no camera.
        case noCamera
    }

    /// Four lenses like an iPhone Pro's: ultra wide, wide and front with Bayer RAW, and a 5×
    /// telephoto without it, to show the labeled fallback. The wide lens has a flash and a
    /// torch; the others have neither.
    static let lenses: [Lens] = [
        Lens(id: "simulated-ultra-wide", kind: .ultraWide, bayerRAWFormat: "rgg4", magnification: 0.5),
        Lens(
            id: "simulated-wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1, flashModes: FlashMode.allCases,
            hasTorch: true),
        Lens(id: "simulated-telephoto", kind: .telephoto, bayerRAWFormat: nil, magnification: 5),
        Lens(id: "simulated-front", kind: .front, bayerRAWFormat: "bgg4"),
    ]

    /// Two lenses like an iPad's without RAW: a wide and a front camera, neither with Bayer RAW.
    /// The wide lens lets the app turn off distortion correction and the front camera doesn't,
    /// so the UI tests see both processing notes (issue #80).
    static let lensesWithoutRAW: [Lens] = [
        Lens(id: "simulated-wide-no-raw", kind: .wide, bayerRAWFormat: nil, magnification: 1, distortionCorrection: .turnedOff),
        // Two photo sizes, so Settings offers the Photo Size choice (issue #57).
        Lens(
            id: "simulated-front-no-raw", kind: .front, bayerRAWFormat: nil,
            photoDimensions: [PhotoDimensions(width: 4032, height: 3024), PhotoDimensions(width: 8064, height: 6048)]),
    ]
    /// The `UserDefaults` suite that holds settings during UI tests.
    static let settingsSuiteName = "NopeUITestSettings"

    /// The launch argument that turns signing on in the emptied settings store:
    /// `-NopeSimulatedSigning`. Signing is off by default (issue #80); the UI tests of the
    /// signing messages pass it.
    static let signingArgument = "-NopeSimulatedSigning"

    /// An emptied settings store for a UI test launch, or `nil` without a scenario, so UI tests
    /// always start from the default settings and never change the real ones. With
    /// ``signingArgument``, signing is turned on in it.
    @MainActor static func settingsStore() -> UserDefaults? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(argument), let store = UserDefaults(suiteName: settingsSuiteName) else { return nil }
        store.removePersistentDomain(forName: settingsSuiteName)
        if arguments.contains(signingArgument) { NopeSettings(defaults: store).setSignsPhotos(true) }
        return store
    }

    /// The scenario in the launch arguments, or `nil` without one.
    static var scenario: Scenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return Scenario(rawValue: arguments[index + 1])
    }

    /// The launch argument that colors the simulated viewfinder: `-NopeSimulatedViewfinder`.
    static let viewfinderArgument = "-NopeSimulatedViewfinder"

    /// The simulated viewfinder's color from the launch arguments (`white` or `yellow`), or
    /// `nil` for the default dark gray.
    static var viewfinderColor: Color? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: viewfinderArgument), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "white": return .white
        case "yellow": return Color(red: 1, green: 1, blue: 0)
        default: return nil
        }
    }

    /// Whether the launch arguments ask for the target viewfinder: `-NopeSimulatedViewfinder target`.
    static var showsTargetViewfinder: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: viewfinderArgument), index + 1 < arguments.count else { return false }
        return arguments[index + 1] == "target"
    }

    /// The target viewfinder: black, with a white square of a third of each side in the middle.
    /// A point a quarter of the way across is black, and white once the 3× focus magnifier
    /// enlarges the middle.
    static var targetViewfinder: some View {
        GeometryReader { proxy in
            Color.black.overlay {
                Color.white.frame(width: proxy.size.width / 3, height: proxy.size.height / 3)
            }
        }
    }

    /// The simulated save pipeline for the scenario in the launch arguments, or `nil` without
    /// one. Nothing touches the Simulator's photo library.
    ///
    /// - Parameter appVersion: The app's version.
    static func saver(appVersion: String) -> PhotoSaver? {
        guard let scenario else { return nil }
        return PhotoSaver(
            developer: SimulatedDeveloper(),
            signer: SimulatedSigner(fails: scenario == .signingFails, breaksFiles: scenario == .signedFileRejected),
            reader: SimulatedReadBack(addsUnexpectedTag: scenario == .metadataRejected),
            library: SimulatedPhotoLibrary(allowsAdding: scenario != .photosDenied, addSeconds: [.slowSaving, .astro, .burst].contains(scenario) ? 0.5 : 0),
            appVersion: appVersion, thumbnailer: SimulatedThumbnailer())
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

    /// Every control and every full-auto aid, as on a recent rear camera.
    static let aidCapabilities = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: true, supportsISOPriority: true,
        supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center], supportsFocusPoint: true, supportsExposurePoint: true, supportsNearFocusLimit: true)

    /// The lenses of the aid scenarios: ultra wide and wide with every aid, and a fixed-focus
    /// front camera that can only meter a tapped point.
    static let aidLenses: [Lens] = [
        Lens(
            id: "simulated-ultra-wide", kind: .ultraWide, bayerRAWFormat: "rgg4", magnification: 0.5,
            isoRange: 32...3200, exposureDurationRange: 0.000_014...1, aperture: .fixed(2.2),
            manualControls: aidCapabilities, equivalentFocalLength: 13),
        Lens(
            id: "simulated-wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1, isoRange: 50...6400,
            exposureDurationRange: 0.000_014...1, aperture: .fixed(1.8), manualControls: aidCapabilities,
            equivalentFocalLength: 24),
        Lens(
            id: "simulated-front", kind: .front, bayerRAWFormat: "bgg4", isoRange: 20...2000,
            exposureDurationRange: 0.000_014...0.5, aperture: .fixed(1.9),
            manualControls: ManualCapabilities(
                supportsManualExposure: false, supportsShutterPriority: false, supportsISOPriority: false,
                supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
                supportsAutoFocus: false, supportsFocusLock: false, supportsManualFocus: false,
                supportsManualWhiteBalance: false, meteringModes: [.center], supportsExposurePoint: true),
            equivalentFocalLength: 23),
    ]

    /// A scene too dark for a handheld shutter on the wide lens: ISO 6400 at 1/48 s, 2 EV under.
    static let dimReading = ExposureReading(
        iso: 6400, exposureDuration: 1.0 / 48.0, exposureOffset: -2, lensPosition: 0.5, aperture: 1.8,
        whiteBalance: WhiteBalance(temperature: 3200))

    /// Autofocus searching at the lens's nearest position.
    static let tooCloseReading = ExposureReading(
        iso: 100, exposureDuration: 1.0 / 120.0, exposureOffset: 0, lensPosition: 0, aperture: 1.8,
        whiteBalance: WhiteBalance(temperature: 5200), isAdjustingFocus: true)

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
        case .lightUnavailable:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities, torchAvailable: false)
        case .comparisonFails:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities, comparisonError: .captureFailed)
        case .metadataRejected, .photosDenied, .signingFails, .signedFileRejected, .slowSaving:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities)
        case .burst:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: capabilities, captureSeconds: 0.4)
        case .manual, .astro:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: DeviceCapabilities(lenses: manualLenses))
        case .aids:
            return SimulatedCaptureBackend(permission: .authorized, capabilities: DeviceCapabilities(lenses: aidLenses))
        case .dimLight:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: DeviceCapabilities(lenses: aidLenses), reading: dimReading)
        case .tooClose:
            return SimulatedCaptureBackend(
                permission: .authorized, capabilities: DeviceCapabilities(lenses: aidLenses), reading: tooCloseReading,
                // More than the readings in a row the close-up detector needs (eight, two seconds).
                readingCount: 12)
        case .denied:
            return SimulatedCaptureBackend(permission: .denied)
        case .noCamera:
            return SimulatedCaptureBackend(permission: .authorized)
        }
    }
}
#endif
