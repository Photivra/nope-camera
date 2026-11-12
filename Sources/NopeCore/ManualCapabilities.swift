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
    public init(
        supportsManualExposure: Bool, supportsShutterPriority: Bool, supportsISOPriority: Bool,
        supportsAperturePriority: Bool, exposureCompensationRange: ClosedRange<Double>?, supportsExposureLock: Bool,
        supportsAutoFocus: Bool, supportsFocusLock: Bool, supportsManualFocus: Bool, supportsManualWhiteBalance: Bool,
        meteringModes: [MeteringMode]
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
