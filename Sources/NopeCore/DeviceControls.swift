import Foundation

/// What a ``ManualCaptureBackend`` sets on the camera: exposure, focus, white balance and
/// metering, already checked against the lens.
///
/// ``ManualControlsModel`` builds it with ``init(settings:lens:)``, which holds every rule
/// about which combination a lens supports and keeps each value inside the lens's range. A
/// backend only applies it.
public struct DeviceControls: Equatable, Sendable {
    /// One exposure parameter in a custom exposure.
    public enum Parameter: Equatable, Sendable {
        /// The camera keeps setting it (`AVCaptureDevice.autoISO`, `autoExposureDuration` or
        /// `autoLensAperture`, iOS 27 and later).
        case auto
        /// Keep the value the camera is using now (`AVCaptureDevice.currentLensAperture`).
        case current
        /// A fixed value: an ISO, a duration in seconds or an f-number.
        case value(Double)
    }

    /// How the camera sets exposure.
    public enum Exposure: Equatable, Sendable {
        /// Continuous auto exposure with a compensation in EV.
        case automatic(compensation: Double)
        /// Auto exposure locked at its current values (AE-L).
        case locked
        /// Custom exposure: each parameter fixed, kept, or left to the camera, with a
        /// compensation in EV that the camera applies through the parameters it still sets.
        case custom(iso: Parameter, duration: Parameter, aperture: Parameter, compensation: Double)
    }

    /// How the camera focuses.
    public enum Focus: Equatable, Sendable {
        /// Continuous autofocus.
        case automatic
        /// Autofocus locked where it is (AF-L).
        case locked
        /// Locked at a relative lens position, 0 (closest) to 1 (far).
        case lensPosition(Double)
    }

    /// How the camera sets white balance.
    public enum WhiteBalanceControl: Equatable, Sendable {
        /// Continuous auto white balance.
        case automatic
        /// Locked at a temperature and tint.
        case fixed(WhiteBalance)
    }

    /// The exposure.
    public let exposure: Exposure

    /// The focus.
    public let focus: Focus

    /// The white balance.
    public let whiteBalance: WhiteBalanceControl

    /// The metering mode.
    public let metering: MeteringMode

    /// Everything automatic: how the camera starts.
    public static let automatic = DeviceControls(
        exposure: .automatic(compensation: 0), focus: .automatic, whiteBalance: .automatic, metering: .center)

    /// Creates controls from their parts. ``ManualControlsModel`` uses ``init(settings:lens:)``.
    ///
    /// - Parameters:
    ///   - exposure: The exposure.
    ///   - focus: The focus.
    ///   - whiteBalance: The white balance.
    ///   - metering: The metering mode.
    public init(exposure: Exposure, focus: Focus, whiteBalance: WhiteBalanceControl, metering: MeteringMode) {
        self.exposure = exposure
        self.focus = focus
        self.whiteBalance = whiteBalance
        self.metering = metering
    }

    /// Builds the controls for settings on a lens.
    ///
    /// - Values outside the lens's ranges are moved to the nearest limit.
    /// - A control the lens doesn't support stays automatic.
    /// - An exposure combination the lens doesn't support (for example shutter priority before
    ///   iOS 27) falls back to auto exposure; ``ManualControlsModel`` never asks for one.
    /// - Exposure compensation is dropped when ISO and shutter are both set, because the camera
    ///   has nothing left to adjust (`AVCaptureDevice.exposureTargetBias`).
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - lens: The selected lens.
    public init(settings: ManualSettings, lens: Lens) {
        let capabilities = lens.manualControls
        exposure = Self.exposure(for: settings, lens: lens)
        if let position = settings.focus, capabilities.supportsManualFocus {
            focus = .lensPosition(position.limited(to: 0...1))
        } else if settings.focusLocked, capabilities.supportsFocusLock {
            focus = .locked
        } else {
            focus = .automatic
        }
        if let balance = settings.whiteBalance, capabilities.supportsManualWhiteBalance {
            whiteBalance = .fixed(balance.limited)
        } else {
            whiteBalance = .automatic
        }
        metering = capabilities.meteringModes.contains(settings.metering) ? settings.metering : .center
    }

    /// The exposure for settings on a lens (see ``init(settings:lens:)``).
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - lens: The selected lens.
    /// - Returns: The exposure to apply.
    private static func exposure(for settings: ManualSettings, lens: Lens) -> Exposure {
        let capabilities = lens.manualControls
        let compensation = capabilities.exposureCompensationRange.map {
            settings.exposureCompensation.limited(to: $0)
        } ?? 0
        let iso = lens.isoRange.flatMap { range in settings.iso.map { $0.limited(to: range) } }
        let duration = lens.exposureDurationRange.flatMap { range in settings.shutter.map { $0.limited(to: range) } }
        let aperture: Double? =
            capabilities.supportsAperturePriority
            ? lens.aperture.flatMap { range in
                settings.aperture.map { $0.limited(to: range.minimumFNumber...range.maximumFNumber) }
            } : nil
        let supported: Bool
        switch (iso, duration) {
        case (nil, nil): supported = true
        case (.some, nil): supported = capabilities.supportsISOPriority
        case (nil, .some): supported = capabilities.supportsShutterPriority
        case (.some, .some): supported = capabilities.supportsManualExposure
        }
        guard supported else { return .automatic(compensation: compensation) }
        if iso == nil, duration == nil, aperture == nil {
            return settings.exposureLocked && capabilities.supportsExposureLock
                ? .locked : .automatic(compensation: compensation)
        }
        let anyAuto = iso == nil || duration == nil
        let apertureParameter: Parameter =
            aperture.map(Parameter.value) ?? (anyAuto && capabilities.supportsAperturePriority ? .auto : .current)
        return .custom(
            iso: iso.map(Parameter.value) ?? .auto,
            duration: duration.map(Parameter.value) ?? .auto,
            aperture: apertureParameter,
            compensation: anyAuto ? compensation : 0)
    }
}
