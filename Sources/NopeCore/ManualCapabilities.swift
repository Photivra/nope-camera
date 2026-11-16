import Foundation

/// Which manual controls one lens supports, as plain values.
///
/// A ``CaptureBackend`` fills it from the camera's own answers (for example
/// `isExposureModeSupported(.custom)` and `isLockingFocusWithCustomLensPositionSupported`), so
/// an interface shows only what the lens can do (AGENTS.md, "Progressive enhancement"). The
/// numeric ranges (ISO, shutter, aperture, bracket count) are on ``Lens``.
public struct ManualCapabilities: Equatable, Sendable {
    /// Whether ISO and shutter can both be set (`AVCaptureDevice.ExposureMode.custom`).
    public let supportsManualExposure: Bool

    /// Whether the shutter can be set while the camera keeps setting ISO (iOS 27 and later,
    /// `AVCaptureDevice.autoISO`, checked per format).
    public let supportsShutterPriority: Bool

    /// Whether ISO can be set while the camera keeps setting the shutter (iOS 27 and later,
    /// `AVCaptureDevice.autoExposureDuration`, checked per format).
    public let supportsISOPriority: Bool

    /// Whether the aperture can be set while the camera keeps setting ISO and shutter (a
    /// variable aperture, iOS 27 and later).
    public let supportsAperturePriority: Bool

    /// The exposure compensation the lens accepts, in EV (`minExposureTargetBias` to
    /// `maxExposureTargetBias`), or `nil` when it has none.
    public let exposureCompensationRange: ClosedRange<Double>?

    /// Whether auto exposure can be locked (`AVCaptureDevice.ExposureMode.locked`).
    public let supportsExposureLock: Bool

    /// Whether the lens can focus by itself (`continuousAutoFocus`).
    public let supportsAutoFocus: Bool

    /// Whether autofocus can be locked (`AVCaptureDevice.FocusMode.locked`).
    public let supportsFocusLock: Bool

    /// Whether the focus can be set to a lens position
    /// (`isLockingFocusWithCustomLensPositionSupported`).
    public let supportsManualFocus: Bool

    /// Whether the white balance can be set (`isLockingWhiteBalanceWithCustomDeviceGainsSupported`).
    public let supportsManualWhiteBalance: Bool

    /// The metering modes the lens offers. ``MeteringMode/center`` is the camera's default and
    /// is always listed when the lens meters at all; the others need an exposure region of
    /// interest (iOS 26 and later).
    public let meteringModes: [MeteringMode]

    /// Whether autofocus can aim at a chosen point (`isFocusPointOfInterestSupported`), for tap
    /// to focus. Some front cameras have a fixed focus and can't.
    public let supportsFocusPoint: Bool

    /// Whether auto exposure can meter a chosen point (`isExposurePointOfInterestSupported`), for
    /// tap to expose.
    public let supportsExposurePoint: Bool

    /// Whether autofocus can be limited to near subjects
    /// (`isAutoFocusRangeRestrictionSupported`), for the Close-Up focus limit.
    public let supportsNearFocusLimit: Bool

    /// A lens with no manual controls, such as one a backend can't describe.
    public static let none = ManualCapabilities(
        supportsManualExposure: false, supportsShutterPriority: false, supportsISOPriority: false,
        supportsAperturePriority: false, exposureCompensationRange: nil, supportsExposureLock: false,
        supportsAutoFocus: false, supportsFocusLock: false, supportsManualFocus: false,
        supportsManualWhiteBalance: false, meteringModes: [])

    /// Creates a capability description.
    ///
    /// - Parameters:
    ///   - supportsManualExposure: Whether ISO and shutter can both be set.
    ///   - supportsShutterPriority: Whether shutter priority is supported.
    ///   - supportsISOPriority: Whether ISO priority is supported.
    ///   - supportsAperturePriority: Whether aperture priority is supported.
    ///   - exposureCompensationRange: The exposure compensation range in EV, or `nil`.
    ///   - supportsExposureLock: Whether auto exposure can be locked.
    ///   - supportsAutoFocus: Whether the lens can autofocus.
    ///   - supportsFocusLock: Whether autofocus can be locked.
    ///   - supportsManualFocus: Whether the focus can be set to a lens position.
    ///   - supportsManualWhiteBalance: Whether the white balance can be set.
    ///   - meteringModes: The metering modes offered.
    ///   - supportsFocusPoint: Whether autofocus can aim at a chosen point. Defaults to `false`.
    ///   - supportsExposurePoint: Whether auto exposure can meter a chosen point. Defaults to
    ///     `false`.
    ///   - supportsNearFocusLimit: Whether autofocus can be limited to near subjects. Defaults
    ///     to `false`.
    public init(
        supportsManualExposure: Bool, supportsShutterPriority: Bool, supportsISOPriority: Bool,
        supportsAperturePriority: Bool, exposureCompensationRange: ClosedRange<Double>?, supportsExposureLock: Bool,
        supportsAutoFocus: Bool, supportsFocusLock: Bool, supportsManualFocus: Bool, supportsManualWhiteBalance: Bool,
        meteringModes: [MeteringMode], supportsFocusPoint: Bool = false, supportsExposurePoint: Bool = false,
        supportsNearFocusLimit: Bool = false
    ) {
        self.supportsManualExposure = supportsManualExposure
        self.supportsShutterPriority = supportsShutterPriority
        self.supportsISOPriority = supportsISOPriority
        self.supportsAperturePriority = supportsAperturePriority
        self.exposureCompensationRange = exposureCompensationRange
        self.supportsExposureLock = supportsExposureLock
        self.supportsAutoFocus = supportsAutoFocus
        self.supportsFocusLock = supportsFocusLock
        self.supportsManualFocus = supportsManualFocus
        self.supportsManualWhiteBalance = supportsManualWhiteBalance
        self.meteringModes = meteringModes
        self.supportsFocusPoint = supportsFocusPoint
        self.supportsExposurePoint = supportsExposurePoint
        self.supportsNearFocusLimit = supportsNearFocusLimit
    }

    /// Whether autofocus can be limited to far subjects, for the Far Focus limit (issue #57).
    /// The same answer as ``supportsNearFocusLimit``: the camera's range restriction offers
    /// near and far together (`AVCaptureDevice.AutoFocusRangeRestriction`).
    public var supportsFarFocusLimit: Bool {
        supportsNearFocusLimit
    }

    /// Whether tapping the viewfinder can do anything on this lens: aim autofocus or auto
    /// exposure at the tapped point.
    public var supportsTapToFocus: Bool {
        supportsFocusPoint || supportsExposurePoint
    }

    /// The exposure modes the lens supports, in the order P, S, I, M. Program is always
    /// offered: it is the camera's own auto exposure.
    public var exposureModes: [ExposureMode] {
        ExposureMode.allCases.filter { mode in
            switch mode {
            case .program: true
            case .shutterPriority: supportsShutterPriority
            case .isoPriority: supportsISOPriority
            case .manual: supportsManualExposure
            }
        }
    }
}
