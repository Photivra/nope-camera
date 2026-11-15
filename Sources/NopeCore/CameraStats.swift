import Foundation

/// A processing feature of the camera or the photo output that the app keeps off when the device
/// allows (`docs/PRIVACY.md`, "Processing"). The live camera readout lists the ones that are
/// off, as the hardware reports them.
public enum ProcessingFeature: String, CaseIterable, Sendable {
    /// Quality prioritization above speed (`AVCapturePhotoOutput.maxPhotoQualityPrioritization`),
    /// which can mean multi-frame fusion.
    case qualityPrioritization

    /// Apple ProRAW, which is demosaiced and may be multi-frame.
    case appleProRAW

    /// Zero shutter lag, which takes the photo from frames buffered before the press.
    case zeroShutterLag

    /// Responsive capture.
    case responsiveCapture

    /// Deferred photo delivery, which finishes processing later.
    case deferredDelivery

    /// Constant color.
    case constantColor

    /// Content-aware distortion correction.
    case contentAwareDistortionCorrection

    /// Geometric distortion correction.
    case geometricDistortionCorrection
}

/// How the camera's exposure is being controlled, as `AVCaptureDevice.exposureMode` reports it.
public enum ExposureModeReading: Sendable, Equatable {
    /// Continuous auto exposure.
    case auto
    /// Locked at the current values.
    case locked
    /// A custom ISO and exposure duration (manual).
    case custom
}

/// How the camera's focus is being controlled, as `AVCaptureDevice.focusMode` reports it.
public enum FocusModeReading: Sendable, Equatable {
    /// Continuous autofocus.
    case continuousAuto
    /// One autofocus, then locked.
    case auto
    /// Locked at a lens position (also manual focus).
    case locked
}

/// The autofocus range restriction, as `AVCaptureDevice.autoFocusRangeRestriction` reports it.
public enum FocusRangeReading: Sendable, Equatable {
    /// The whole range.
    case none
    /// Near subjects only (the near focus limit).
    case near
    /// Far subjects only.
    case far
}

/// How the camera's white balance is being controlled, as `AVCaptureDevice.whiteBalanceMode`
/// reports it.
public enum WhiteBalanceModeReading: Sendable, Equatable {
    /// Continuous auto white balance.
    case auto
    /// Locked, at the current or custom gains.
    case locked
}

/// The capture system's pressure level, as `AVCaptureDevice.SystemPressureState.Level` reports
/// it: how close the camera is to having to slow down or stop because of heat or power.
public enum SystemPressureReading: Sendable, Equatable {
    /// Normal.
    case nominal
    /// Slightly raised.
    case fair
    /// High: the system may lower the frame rate.
    case serious
    /// Critical: the system will soon lower quality or the frame rate.
    case critical
    /// The system is stopping the camera.
    case shutdown
}

/// The camera's white balance gains, as `AVCaptureDevice.deviceWhiteBalanceGains` reports them.
public struct WhiteBalanceGainsReading: Equatable, Sendable {
    /// The red gain, 1 or more.
    public let red: Double
    /// The green gain, 1 or more.
    public let green: Double
    /// The blue gain, 1 or more.
    public let blue: Double

    /// Creates a gains reading.
    ///
    /// - Parameters:
    ///   - red: The red gain.
    ///   - green: The green gain.
    ///   - blue: The blue gain.
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Everything the live camera readout ("stats for nerds", issue #52) shows that the hardware
/// reports: only values AVFoundation already gives, read by key-value observation at a reduced
/// rate while the readout is shown. No video is analyzed for it.
///
/// Privacy rule: shown on screen only; never logged, stored or copied.
public struct CameraStatsReading: Equatable, Sendable {
    /// The ISO in use.
    public var iso: Double
    /// The exposure duration in use, in seconds.
    public var exposureDuration: Double
    /// The exposure bias (compensation) set, in EV.
    public var exposureBias: Double
    /// The metered offset from the exposure target, in EV.
    public var exposureOffset: Double
    /// The aperture in use, as an f-number.
    public var aperture: Double
    /// How exposure is controlled.
    public var exposureMode: ExposureModeReading
    /// The relative focus position, 0 (closest) to 1 (far). Not a distance.
    public var lensPosition: Double
    /// How focus is controlled.
    public var focusMode: FocusModeReading
    /// Whether the lens is moving to focus.
    public var isAdjustingFocus: Bool
    /// The autofocus range restriction, or `nil` when the camera doesn't support one.
    public var focusRange: FocusRangeReading?
    /// The white balance in use, or `nil` when the camera can't convert its gains.
    public var whiteBalance: WhiteBalance?
    /// The white balance gains in use.
    public var gains: WhiteBalanceGainsReading
    /// How white balance is controlled.
    public var whiteBalanceMode: WhiteBalanceModeReading
    /// The zoom factor in use; the app keeps it at 1.0, which Bayer RAW requires.
    public var zoomFactor: Double
    /// The processing features that are on, as the hardware reports them.
    public var processingOn: Set<ProcessingFeature>
    /// Whether the photo output is ready to take a photo now.
    public var isReadyToCapture: Bool
    /// The capture system's pressure level.
    public var systemPressure: SystemPressureReading
    /// Whether Low Power Mode is on.
    public var isLowPowerMode: Bool
    /// The torch level, 0 to 1, or `nil` when the camera has no torch.
    public var torchLevel: Double?

    /// Creates a reading.
    ///
    /// - Parameters:
    ///   - iso: The ISO in use.
    ///   - exposureDuration: The exposure duration, in seconds.
    ///   - exposureBias: The exposure bias, in EV.
    ///   - exposureOffset: The metered offset, in EV.
    ///   - aperture: The aperture, as an f-number.
    ///   - exposureMode: How exposure is controlled.
    ///   - lensPosition: The relative focus position, 0 to 1.
    ///   - focusMode: How focus is controlled.
    ///   - isAdjustingFocus: Whether the lens is moving to focus.
    ///   - focusRange: The autofocus range restriction, or `nil` when unsupported.
    ///   - whiteBalance: The white balance, or `nil`.
    ///   - gains: The white balance gains.
    ///   - whiteBalanceMode: How white balance is controlled.
    ///   - zoomFactor: The zoom factor.
    ///   - processingOn: The processing features that are on.
    ///   - isReadyToCapture: Whether a photo can be taken now.
    ///   - systemPressure: The pressure level.
    ///   - isLowPowerMode: Whether Low Power Mode is on.
    ///   - torchLevel: The torch level, or `nil` without a torch.
    public init(
        iso: Double, exposureDuration: Double, exposureBias: Double, exposureOffset: Double, aperture: Double,
        exposureMode: ExposureModeReading, lensPosition: Double, focusMode: FocusModeReading, isAdjustingFocus: Bool,
        focusRange: FocusRangeReading?, whiteBalance: WhiteBalance?, gains: WhiteBalanceGainsReading,
        whiteBalanceMode: WhiteBalanceModeReading, zoomFactor: Double, processingOn: Set<ProcessingFeature>,
        isReadyToCapture: Bool, systemPressure: SystemPressureReading, isLowPowerMode: Bool, torchLevel: Double?
    ) {
        self.iso = iso
        self.exposureDuration = exposureDuration
        self.exposureBias = exposureBias
        self.exposureOffset = exposureOffset
        self.aperture = aperture
        self.exposureMode = exposureMode
        self.lensPosition = lensPosition
        self.focusMode = focusMode
        self.isAdjustingFocus = isAdjustingFocus
        self.focusRange = focusRange
        self.whiteBalance = whiteBalance
        self.gains = gains
        self.whiteBalanceMode = whiteBalanceMode
        self.zoomFactor = zoomFactor
        self.processingOn = processingOn
        self.isReadyToCapture = isReadyToCapture
        self.systemPressure = systemPressure
        self.isLowPowerMode = isLowPowerMode
        self.torchLevel = torchLevel
    }

    /// The processing features that are off, in a fixed order, for the readout.
    public var processingOff: [ProcessingFeature] {
        ProcessingFeature.allCases.filter { !processingOn.contains($0) }
    }
}
