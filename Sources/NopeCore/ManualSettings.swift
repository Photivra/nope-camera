import Foundation

/// What the camera is using right now, as the hardware reports it.
///
/// A ``ManualCaptureBackend`` sends readings while manual controls are on, at a reduced rate.
/// Interfaces show them in every slot set to Auto, so the person sees what the meter chose.
public struct ExposureReading: Equatable, Sendable {
    /// The ISO in use.
    public let iso: Double

    /// The exposure duration in use, in seconds.
    public let exposureDuration: Double

    /// How far the scene's metered exposure is from the camera's target, in EV
    /// (`AVCaptureDevice.exposureTargetOffset`): 0 when the exposure matches the meter, negative
    /// when the photo will be darker than the meter's reading.
    public let exposureOffset: Double

    /// The relative focus position, from 0 (closest) to 1 (farthest). It is not a distance.
    public let lensPosition: Double

    /// The aperture in use, as an f-number.
    public let aperture: Double

    /// The white balance in use, or `nil` when the camera can't convert its gains.
    public let whiteBalance: WhiteBalance?

    /// Creates a reading.
    ///
    /// - Parameters:
    ///   - iso: The ISO in use.
    ///   - exposureDuration: The exposure duration in use, in seconds.
    ///   - exposureOffset: The metered offset from the target, in EV.
    ///   - lensPosition: The relative focus position, 0 to 1.
    ///   - aperture: The aperture in use, as an f-number.
    ///   - whiteBalance: The white balance in use, or `nil`.
    public init(
        iso: Double, exposureDuration: Double, exposureOffset: Double, lensPosition: Double, aperture: Double,
        whiteBalance: WhiteBalance?
    ) {
        self.iso = iso
        self.exposureDuration = exposureDuration
        self.exposureOffset = exposureOffset
        self.lensPosition = lensPosition
        self.aperture = aperture
        self.whiteBalance = whiteBalance
    }
}

/// The manual settings the person chose. A `nil` value means Auto: the camera sets it.
///
/// ``automatic`` is full auto, the default. ``ManualControlsModel`` changes the settings in
/// response to intents and keeps them consistent with the selected lens; interfaces only read
/// them.
public struct ManualSettings: Equatable, Sendable {
    /// The ISO, or `nil` for Auto.
    public var iso: Double?

    /// The exposure duration in seconds, or `nil` for Auto.
    public var shutter: Double?

    /// The aperture as an f-number, or `nil` for Auto.
    public var aperture: Double?

    /// Exposure compensation in EV; 0 is none. It applies only while at least one of ISO and
    /// shutter is Auto.
    public var exposureCompensation: Double

    /// The relative focus position from 0 (closest) to 1 (farthest), or `nil` for autofocus.
    public var focus: Double?

    /// The white balance, or `nil` for Auto.
    public var whiteBalance: WhiteBalance?

    /// How auto exposure measures the scene.
    public var metering: MeteringMode

    /// Whether auto exposure is locked (AE-L). Meaningful only while ISO, shutter and aperture
    /// are Auto.
    public var exposureLocked: Bool

    /// Whether autofocus is locked (AF-L). Meaningful only while focus is Auto.
    public var focusLocked: Bool

    /// Full auto: every control on Auto, the default metering and no locks.
    public static let automatic = ManualSettings()

    /// Creates settings. With no arguments, full auto.
    ///
    /// - Parameters:
    ///   - iso: The ISO, or `nil` for Auto.
    ///   - shutter: The exposure duration in seconds, or `nil` for Auto.
    ///   - aperture: The f-number, or `nil` for Auto.
    ///   - exposureCompensation: Exposure compensation in EV.
    ///   - focus: The relative focus position, or `nil` for autofocus.
    ///   - whiteBalance: The white balance, or `nil` for Auto.
    ///   - metering: The metering mode.
    ///   - exposureLocked: Whether auto exposure is locked.
    ///   - focusLocked: Whether autofocus is locked.
    public init(
        iso: Double? = nil, shutter: Double? = nil, aperture: Double? = nil, exposureCompensation: Double = 0,
        focus: Double? = nil, whiteBalance: WhiteBalance? = nil, metering: MeteringMode = .center,
        exposureLocked: Bool = false, focusLocked: Bool = false
    ) {
        self.iso = iso
        self.shutter = shutter
        self.aperture = aperture
        self.exposureCompensation = exposureCompensation
        self.focus = focus
        self.whiteBalance = whiteBalance
        self.metering = metering
        self.exposureLocked = exposureLocked
        self.focusLocked = focusLocked
    }

    /// Whether a control is set manually (shown as M), rather than by the camera (A).
    /// Exposure compensation counts as manual when it isn't 0.
    ///
    /// - Parameter control: A control.
    /// - Returns: `true` when the person set it.
    public func isManual(_ control: ManualControl) -> Bool {
        switch control {
        case .exposureCompensation: exposureCompensation != 0
        case .iso: iso != nil
        case .shutter: shutter != nil
        case .aperture: aperture != nil
        case .focus: focus != nil
        case .whiteBalance: whiteBalance != nil
        }
    }

    /// How many controls are set manually.
    public var manualControlCount: Int {
        ManualControl.allCases.filter(isManual).count
    }

    /// Whether everything is automatic: no manual control, the default metering and no lock.
    /// When it's `false`, an interface offers "All Auto".
    public var isAutomatic: Bool {
        self == .automatic
    }

    /// The exposure mode these settings amount to: P, S, I or M, from which of ISO and shutter
    /// are set.
    public var exposureMode: ExposureMode {
        switch (iso != nil, shutter != nil) {
        case (false, false): .program
        case (false, true): .shutterPriority
        case (true, false): .isoPriority
        case (true, true): .manual
        }
    }
}
