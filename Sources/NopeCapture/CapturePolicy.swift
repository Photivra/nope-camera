import AVFoundation
import NopeCore

/// The processing switches nope. applies to every session and photo, as plain values.
///
/// They follow docs/research/capability-survey.md, item 12 ("Avoiding processing"), and Apple's
/// Bayer RAW rules in `AVCapturePhotoOutput.h` (`capturePhoto(with:delegate:)`): Bayer RAW
/// requires `.speed` prioritization and a zoom factor of 1.0. Keeping them in one value means
/// a test asserts every switch, and the hardware adapter only applies them.
struct ProcessingSwitches: Equatable, Sendable {
    /// `.speed` for the output's maximum and for every photo. Required for Bayer RAW, and the
    /// least processing for the fallback.
    let qualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    /// Apple ProRAW: demosaiced and possibly multi-frame, so always off.
    let appleProRAW: Bool
    /// Zero shutter lag: takes the photo from a buffer of earlier frames. Off, so the photo is
    /// the frame exposed after the shutter, and because it is meant for `.balanced` and
    /// `.quality` (`AVCapturePhotoOutput.isZeroShutterLagEnabled`). It is on by default for
    /// apps built for iOS 17 or later.
    let zeroShutterLag: Bool
    /// Responsive capture (overlapping captures). Off; it requires zero shutter lag.
    let responsiveCapture: Bool
    /// Deferred photo delivery (processing later). Off.
    let deferredDelivery: Bool
    /// Constant color (flash-based color correction). Off; RAW requires it off.
    let constantColor: Bool
    /// Content-aware distortion correction, a processing step. Off.
    let contentAwareDistortionCorrection: Bool
    /// The device's geometric distortion correction. Off where it can be turned off.
    let geometricDistortionCorrection: Bool
    /// The device zoom factor. 1.0: Bayer RAW requires it, and nope. never zooms digitally.
    let videoZoomFactor: Double
    /// The flash. Off in this version.
    let flashMode: AVCaptureDevice.FlashMode

    /// Creates a set of switches. nope. uses only ``leastProcessing``.
    ///
    /// - Parameters:
    ///   - qualityPrioritization: The output's maximum and every photo's prioritization.
    ///   - appleProRAW: Whether Apple ProRAW is enabled.
    ///   - zeroShutterLag: Whether zero shutter lag is enabled.
    ///   - responsiveCapture: Whether responsive capture is enabled.
    ///   - deferredDelivery: Whether deferred photo delivery is enabled.
    ///   - constantColor: Whether constant color is enabled.
    ///   - contentAwareDistortionCorrection: Whether content-aware distortion correction is on.
    ///   - geometricDistortionCorrection: Whether geometric distortion correction is on.
    ///   - videoZoomFactor: The device zoom factor.
    ///   - flashMode: The flash mode.
    init(
        qualityPrioritization: AVCapturePhotoOutput.QualityPrioritization, appleProRAW: Bool, zeroShutterLag: Bool,
        responsiveCapture: Bool, deferredDelivery: Bool, constantColor: Bool, contentAwareDistortionCorrection: Bool,
        geometricDistortionCorrection: Bool, videoZoomFactor: Double, flashMode: AVCaptureDevice.FlashMode
    ) {
        self.qualityPrioritization = qualityPrioritization
        self.appleProRAW = appleProRAW
        self.zeroShutterLag = zeroShutterLag
        self.responsiveCapture = responsiveCapture
        self.deferredDelivery = deferredDelivery
        self.constantColor = constantColor
        self.contentAwareDistortionCorrection = contentAwareDistortionCorrection
        self.geometricDistortionCorrection = geometricDistortionCorrection
        self.videoZoomFactor = videoZoomFactor
        self.flashMode = flashMode
    }

    /// The switches nope. uses.
    static let leastProcessing = ProcessingSwitches(
        qualityPrioritization: .speed,
        appleProRAW: false,
        zeroShutterLag: false,
        responsiveCapture: false,
        deferredDelivery: false,
        constantColor: false,
        contentAwareDistortionCorrection: false,
        geometricDistortionCorrection: false,
        videoZoomFactor: 1.0,
        flashMode: .off
    )
}

/// What ``CaptureHardware/configure(_:)`` sets up: one camera, its photo size and the photo
/// settings to prepare.
struct SessionConfiguration: Equatable, Sendable {
    /// The camera's `uniqueID`.
    let deviceID: String
    /// The photo output's `maxPhotoDimensions`, which must be one of the active format's
    /// `supportedMaxPhotoDimensions`; `nil` when the lens reported none.
    let maxPhotoDimensions: PhotoDimensions?
    /// The photo settings to prepare with `setPreparedPhotoSettingsArray(_:completionHandler:)`.
    let photoSettings: PhotoSettingsPlan
    /// The processing switches.
    let switches: ProcessingSwitches

    /// Creates a session configuration.
    ///
    /// - Parameters:
    ///   - deviceID: The camera's `uniqueID`.
    ///   - maxPhotoDimensions: The photo output's maximum photo size, or `nil`.
    ///   - photoSettings: The photo settings to prepare.
    ///   - switches: The processing switches.
    init(
        deviceID: String, maxPhotoDimensions: PhotoDimensions?, photoSettings: PhotoSettingsPlan,
        switches: ProcessingSwitches
    ) {
        self.deviceID = deviceID
        self.maxPhotoDimensions = maxPhotoDimensions
        self.photoSettings = photoSettings
        self.switches = switches
    }
}

/// What one photo asks for: Bayer RAW only, or one processed fallback format.
struct PhotoSettingsPlan: Equatable, Sendable {
    /// The Bayer RAW pixel format code, or `nil` for the processed fallback.
    let rawPixelFormat: UInt32?
    /// The processed format, or `nil` for a RAW-only capture.
    let processedFormat: ProcessedFallback?
    /// The processing switches.
    let switches: ProcessingSwitches

    /// Creates a photo plan.
    ///
    /// - Parameters:
    ///   - rawPixelFormat: The Bayer RAW pixel format code, or `nil`.
    ///   - processedFormat: The processed format, or `nil`.
    ///   - switches: The processing switches.
    init(rawPixelFormat: UInt32?, processedFormat: ProcessedFallback?, switches: ProcessingSwitches) {
        self.rawPixelFormat = rawPixelFormat
        self.processedFormat = processedFormat
        self.switches = switches
    }
}

/// Turns a `NopeCore` capture request into hardware settings.
enum CapturePolicy {
    /// The session configuration for a request.
    ///
    /// The photo size is the lens's smallest supported size: on 48 MP sensors that is the
    /// native 12 MP binned readout, the same size as the Bayer RAW (capability survey, item 1).
    /// Larger processed sizes are made by the camera's pipeline, and 24 MP needs deferred
    /// delivery, which nope. turns off (`AVCapturePhotoOutput.h`).
    ///
    /// - Parameter request: The lens and format.
    /// - Returns: The configuration, or `nil` if the request's RAW format code is invalid.
    static func sessionConfiguration(for request: CaptureRequest) -> SessionConfiguration? {
        guard let plan = photoSettings(for: request.format) else { return nil }
        return SessionConfiguration(
            deviceID: request.lens.id,
            maxPhotoDimensions: request.lens.photoDimensions.min { $0.pixelCount < $1.pixelCount },
            photoSettings: plan,
            switches: .leastProcessing
        )
    }

    /// The photo settings for a format: a RAW-only capture with no processed image for Bayer
    /// RAW (capability survey, item 12), or one processed image for the fallback.
    ///
    /// - Parameter format: The format the model chose.
    /// - Returns: The plan, or `nil` if a Bayer pixel format isn't a valid four-character code.
    static func photoSettings(for format: CaptureFormat) -> PhotoSettingsPlan? {
        switch format {
        case .bayerRAW(let pixelFormat):
            guard let code = FourCharacterCode.code(pixelFormat) else { return nil }
            return PhotoSettingsPlan(rawPixelFormat: code, processedFormat: nil, switches: .leastProcessing)
        case .processedFallback(let fallback):
            return PhotoSettingsPlan(rawPixelFormat: nil, processedFormat: fallback, switches: .leastProcessing)
        }
    }
}
