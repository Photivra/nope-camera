import AVFoundation
import NopeCore

/// One camera as the hardware reported it, copied into plain values.
///
/// ``SystemCaptureHardware`` fills it from `AVCaptureDevice`, its active photo format and the
/// photo output; ``LensCatalog`` turns a list of them into `NopeCore` lenses. Keeping the
/// values plain lets the catalog be tested without a camera.
struct CameraDeviceDescription: Equatable, Sendable {
    /// The kind of camera, from `AVCaptureDevice.DeviceType`.
    enum DeviceType: Equatable, Sendable {
        /// `builtInWideAngleCamera`.
        case wideAngle
        /// `builtInUltraWideCamera`.
        case ultraWide
        /// `builtInTelephotoCamera`.
        case telephoto
        /// Any other type, including virtual multi-camera, TrueDepth and LiDAR devices.
        case other

        /// Converts an AVFoundation device type.
        ///
        /// - Parameter type: The device's `deviceType`.
        init(_ type: AVCaptureDevice.DeviceType) {
            switch type {
            case .builtInWideAngleCamera: self = .wideAngle
            case .builtInUltraWideCamera: self = .ultraWide
            case .builtInTelephotoCamera: self = .telephoto
            default: self = .other
            }
        }
    }

    /// Which side of the device the camera faces.
    enum Position: Equatable, Sendable {
        /// The rear of the device.
        case back
        /// The screen side.
        case front
        /// Not reported, or a value added in a later iOS.
        case unspecified

        /// Converts an AVFoundation position.
        ///
        /// - Parameter position: The device's `position`.
        init(_ position: AVCaptureDevice.Position) {
            switch position {
            case .back: self = .back
            case .front: self = .front
            default: self = .unspecified
            }
        }
    }

    /// One RAW pixel format the photo output offers with this camera.
    struct RAWPixelFormat: Equatable, Sendable {
        /// The pixel format code, such as `'bgg4'`.
        let code: UInt32
        /// Whether it is Bayer RAW (`AVCapturePhotoOutput.isBayerRAWPixelFormat(_:)`), rather
        /// than Apple ProRAW.
        let isBayer: Bool

        /// Creates a RAW format description.
        ///
        /// - Parameters:
        ///   - code: The pixel format code.
        ///   - isBayer: Whether it is Bayer RAW.
        init(code: UInt32, isBayer: Bool) {
            self.code = code
            self.isBayer = isBayer
        }
    }

    /// The device's `uniqueID`. Used only to reopen the device; never written to a photo.
    let uniqueID: String

    /// The kind of camera.
    let deviceType: DeviceType

    /// Which side the camera faces.
    let position: Position

    /// Whether the device is a virtual device built from several cameras. Never used: it can
    /// fuse frames (AGENTS.md, "Honesty").
    let isVirtual: Bool

    /// The RAW pixel formats the photo output offers with this camera, Apple ProRAW off.
    let rawPixelFormats: [RAWPixelFormat]

    /// Whether the photo output offers HEVC (HEIF) encoding with this camera.
    let supportsHEVC: Bool

    /// The ISO range of the active photo format.
    let isoRange: ClosedRange<Double>

    /// The exposure duration range of the active photo format, in seconds.
    let exposureDurationRange: ClosedRange<Double>

    /// The aperture, as f-numbers.
    let aperture: ApertureRange

    /// The most frames in one bracketed capture (`maxBracketedCapturePhotoCount`).
    let maxBracketedPhotoCount: Int

    /// The active format's `supportedMaxPhotoDimensions`, in the order reported.
    let photoDimensions: [PhotoDimensions]

    /// The active format's horizontal field of view, in degrees (`videoFieldOfView`).
    let fieldOfViewDegrees: Double

    /// Creates a camera description.
    ///
    /// - Parameters:
    ///   - uniqueID: The device's `uniqueID`.
    ///   - deviceType: The kind of camera.
    ///   - position: Which side the camera faces.
    ///   - isVirtual: Whether it is a virtual multi-camera device.
    ///   - rawPixelFormats: The RAW pixel formats offered, Apple ProRAW off.
    ///   - supportsHEVC: Whether HEVC (HEIF) encoding is offered.
    ///   - isoRange: The ISO range of the photo format.
    ///   - exposureDurationRange: The exposure duration range, in seconds.
    ///   - aperture: The aperture, as f-numbers.
    ///   - maxBracketedPhotoCount: The most frames in one bracketed capture.
    ///   - photoDimensions: The supported maximum photo sizes, as reported.
    ///   - fieldOfViewDegrees: The horizontal field of view, in degrees.
    init(
        uniqueID: String, deviceType: DeviceType, position: Position, isVirtual: Bool,
        rawPixelFormats: [RAWPixelFormat], supportsHEVC: Bool, isoRange: ClosedRange<Double>,
        exposureDurationRange: ClosedRange<Double>, aperture: ApertureRange, maxBracketedPhotoCount: Int,
        photoDimensions: [PhotoDimensions], fieldOfViewDegrees: Double
    ) {
        self.uniqueID = uniqueID
        self.deviceType = deviceType
        self.position = position
        self.isVirtual = isVirtual
        self.rawPixelFormats = rawPixelFormats
        self.supportsHEVC = supportsHEVC
        self.isoRange = isoRange
        self.exposureDurationRange = exposureDurationRange
        self.aperture = aperture
        self.maxBracketedPhotoCount = maxBracketedPhotoCount
        self.photoDimensions = photoDimensions
        self.fieldOfViewDegrees = fieldOfViewDegrees
    }
}
