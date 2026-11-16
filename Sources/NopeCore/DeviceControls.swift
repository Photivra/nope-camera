import Foundation

/// What a ``ManualCaptureBackend`` sets on the camera: exposure, focus, white balance and
/// metering, already checked against the lens.
///
/// ``ManualControlsModel`` builds it with ``init(settings:lens:assist:)``, which holds every rule
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

    /// Where autofocus and auto exposure aim after a tap (`focusPointOfInterest` and
    /// `exposurePointOfInterest`, in the camera's 0-to-1 coordinates).
    public struct PointOfInterest: Equatable, Sendable {
        /// The point, in the camera's coordinates.
        public let point: FramePoint

        /// Whether autofocus aims there: focus is automatic and the lens supports a focus point.
        public let focuses: Bool

        /// Whether auto exposure meters there: exposure is automatic and the lens supports an
        /// exposure point.
        public let exposes: Bool

        /// Whether focus and exposure adjust once and then lock (`AVCaptureDevice.FocusMode.autoFocus`
        /// and `ExposureMode.autoExpose`), rather than keep following the point until the scene
        /// changes.
        public let locks: Bool

        /// Creates a point of interest.
        ///
        /// - Parameters:
        ///   - point: The point, in the camera's coordinates.
        ///   - focuses: Whether autofocus aims there.
        ///   - exposes: Whether auto exposure meters there.
        ///   - locks: Whether focus and exposure lock after adjusting.
        public init(point: FramePoint, focuses: Bool, exposes: Bool, locks: Bool) {
            self.point = point
            self.focuses = focuses
            self.exposes = exposes
            self.locks = locks
        }
    }

    /// The exposure.
    public let exposure: Exposure

    /// The focus.
    public let focus: Focus

    /// The white balance.
    public let whiteBalance: WhiteBalanceControl

    /// The metering mode.
    public let metering: MeteringMode

    /// The tapped point, or `nil` for the camera's default (the center).
    public let pointOfInterest: PointOfInterest?

    /// Whether autofocus is limited to near subjects (`autoFocusRangeRestriction = .near`).
    public let nearFocusLimit: Bool

    /// Whether autofocus is limited to far subjects (`autoFocusRangeRestriction = .far`). Never
    /// on with ``nearFocusLimit``.
    public let farFocusLimit: Bool

    /// Whether faces the camera detects steer autofocus and auto exposure
    /// (`isFaceDrivenAutoFocusEnabled` and `isFaceDrivenAutoExposureEnabled`). `true` leaves the
    /// system's automatic choice; `false` turns both off. A backend sets each only where the lens
    /// focuses or exposes automatically, because AVFoundation raises an exception otherwise.
    public let followsFaces: Bool

    /// The longest shutter auto exposure may use, in seconds (`activeMaxExposureDuration`), or
    /// `nil` for the camera's default. Set only with ``Exposure/automatic(compensation:)``.
    public let longestAutoExposure: Double?

    /// Everything automatic: how the camera starts.
    public static let automatic = DeviceControls(
        exposure: .automatic(compensation: 0), focus: .automatic, whiteBalance: .automatic, metering: .center)

    /// Creates controls from their parts. ``ManualControlsModel`` uses ``init(settings:lens:assist:)``.
    ///
    /// - Parameters:
    ///   - exposure: The exposure.
    ///   - focus: The focus.
    ///   - whiteBalance: The white balance.
    ///   - metering: The metering mode.
    ///   - pointOfInterest: The tapped point, or `nil`. Defaults to `nil`.
    ///   - nearFocusLimit: Whether autofocus is limited to near subjects. Defaults to `false`.
    ///   - longestAutoExposure: The longest auto exposure in seconds, or `nil`. Defaults to `nil`.
    ///   - farFocusLimit: Whether autofocus is limited to far subjects. Defaults to `false`;
    ///     ignored while `nearFocusLimit` is on.
    ///   - followsFaces: Whether detected faces steer autofocus and auto exposure. Defaults to
    ///     `true`.
    public init(
        exposure: Exposure, focus: Focus, whiteBalance: WhiteBalanceControl, metering: MeteringMode,
        pointOfInterest: PointOfInterest? = nil, nearFocusLimit: Bool = false, longestAutoExposure: Double? = nil,
        farFocusLimit: Bool = false, followsFaces: Bool = true
    ) {
        self.exposure = exposure
        self.focus = focus
        self.whiteBalance = whiteBalance
        self.metering = metering
        self.pointOfInterest = pointOfInterest
        self.nearFocusLimit = nearFocusLimit
        self.longestAutoExposure = longestAutoExposure
        self.farFocusLimit = farFocusLimit && !nearFocusLimit
        self.followsFaces = followsFaces
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
    /// - The automatic aids apply only to what is automatic: the tapped point aims autofocus
    ///   only while focus is automatic, and auto exposure only while exposure is automatic; the
    ///   near and far focus limits need autofocus; the longest shutter needs auto exposure. Each
    ///   needs the lens to support it. Face detection is passed on as it is; the backend applies
    ///   it to whatever is automatic.
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - lens: The selected lens.
    ///   - assist: The automatic aids. Defaults to none.
    public init(settings: ManualSettings, lens: Lens, assist: AssistSettings = .none) {
        let capabilities = lens.manualControls
        let exposure = Self.exposure(for: settings, lens: lens)
        self.exposure = exposure
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
        let autoFocuses = focus == .automatic && capabilities.supportsAutoFocus
        let autoExposes: Bool
        if case .automatic = exposure { autoExposes = true } else { autoExposes = false }
        pointOfInterest = assist.focusTarget.flatMap { target in
            let focuses = autoFocuses && capabilities.supportsFocusPoint
            let exposes = autoExposes && capabilities.supportsExposurePoint
            guard focuses || exposes else { return nil }
            return PointOfInterest(point: target.devicePoint, focuses: focuses, exposes: exposes, locks: target.isLocked)
        }
        nearFocusLimit = assist.nearFocusLimit && autoFocuses && capabilities.supportsNearFocusLimit
        farFocusLimit = assist.farFocusLimit && !nearFocusLimit && autoFocuses && capabilities.supportsFarFocusLimit
        followsFaces = assist.followsFaces
        longestAutoExposure =
            autoExposes
            ? lens.exposureDurationRange.flatMap { range in assist.longestShutter.map { $0.limited(to: range) } } : nil
    }

    /// The exposure for settings on a lens (see ``init(settings:lens:assist:)``).
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
