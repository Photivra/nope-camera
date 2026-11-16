import Foundation

/// One physical camera on the device, described as plain data.
///
/// Lenses are discovered at run time by a ``CaptureBackend``; an interface renders them without
/// knowing the hardware (AGENTS.md, "Capabilities are data"). Every range is what the camera
/// reported for the format the app uses, so it can differ between devices and iOS versions.
public struct Lens: Identifiable, Equatable, Sendable {
    /// Where a lens sits and how wide it sees.
    public enum Kind: Equatable, Sendable, CaseIterable {
        /// The rear ultra wide camera.
        case ultraWide
        /// The rear wide (main) camera.
        case wide
        /// A rear telephoto camera.
        case telephoto
        /// The front camera.
        case front
    }

    /// A stable identifier for this lens on this device, supplied by the backend.
    ///
    /// It identifies the lens only within the app and is never written to a photo.
    public let id: String

    /// Where the lens sits and how wide it sees.
    public let kind: Kind

    /// The four-character code of the lens's single-frame Bayer RAW pixel format, such as
    /// `bgg4`, or `nil` when the lens has no Bayer RAW format.
    ///
    /// When it's `nil`, the lens can only give ``processedFallback``, which has some device
    /// processing, and the interface must say so (issue #1, "No-RAW fallback").
    public let bayerRAWFormat: String?

    /// The least-processed format the lens can give when it has no Bayer RAW.
    public let processedFallback: ProcessedFallback

    /// How much closer this lens sees than the rear wide camera: 0.5 for a typical ultra wide,
    /// 1 for the wide camera, 5 for a 5× telephoto. `nil` when unknown, and always `nil` for the
    /// front camera, which has no rear wide camera to compare with.
    ///
    /// It is computed from each camera's field of view, so it is approximate. It is for labels
    /// only: the app never zooms digitally.
    public let magnification: Double?

    /// The ISO values the lens supports in its photo format, or `nil` when unknown.
    public let isoRange: ClosedRange<Double>?

    /// The exposure durations the lens supports in its photo format, in seconds, or `nil` when
    /// unknown.
    public let exposureDurationRange: ClosedRange<Double>?

    /// The lens's aperture, as f-numbers. A fixed aperture has one stop.
    public let aperture: ApertureRange?

    /// The most frames one bracketed capture may contain on this lens; 0 when bracketing isn't
    /// supported or the value is unknown.
    public let maxBracketedPhotoCount: Int

    /// The photo sizes the lens's format supports, smallest first.
    public let photoDimensions: [PhotoDimensions]

    /// The manual controls the lens supports. ``ManualCapabilities/none`` when unknown.
    public let manualControls: ManualCapabilities

    /// The lens's focal length as it would be on a 35 mm film camera with the same angle of
    /// view, in millimeters, or `nil` when unknown. Computed from the field of view, so it is
    /// approximate. Full auto uses it for the handheld shutter rule (``AutoShutter``).
    public let equivalentFocalLength: Double?

    /// The flash modes the lens supports, as the photo output reported them for this camera.
    /// Empty, or only ``FlashMode/off``, when the lens has no flash. Always empty for the front
    /// camera: the app uses no screen flash (issue #38).
    public let flashModes: [FlashMode]

    /// Whether the lens has a torch: a light that can stay on while framing and taking photos.
    public let hasTorch: Bool

    /// Creates a lens description.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for the lens within the app.
    ///   - kind: Where the lens sits and how wide it sees.
    ///   - bayerRAWFormat: The four-character code of the Bayer RAW pixel format, or `nil` when
    ///     the lens has none.
    ///   - processedFallback: The least-processed format without RAW. Defaults to HEIF.
    ///   - magnification: How much closer the lens sees than the rear wide camera, or `nil`.
    ///   - isoRange: The supported ISO values, or `nil` when unknown.
    ///   - exposureDurationRange: The supported exposure durations in seconds, or `nil`.
    ///   - aperture: The aperture range, or `nil` when unknown.
    ///   - maxBracketedPhotoCount: The most frames in one bracketed capture, or 0.
    ///   - photoDimensions: The supported photo sizes, smallest first.
    ///   - manualControls: The manual controls the lens supports. Defaults to none.
    ///   - equivalentFocalLength: The 35 mm-equivalent focal length in millimeters, or `nil`.
    ///   - flashModes: The flash modes the lens supports. Defaults to none.
    ///   - hasTorch: Whether the lens has a torch. Defaults to `false`.
    public init(
        id: String,
        kind: Kind,
        bayerRAWFormat: String?,
        processedFallback: ProcessedFallback = .heif,
        magnification: Double? = nil,
        isoRange: ClosedRange<Double>? = nil,
        exposureDurationRange: ClosedRange<Double>? = nil,
        aperture: ApertureRange? = nil,
        maxBracketedPhotoCount: Int = 0,
        photoDimensions: [PhotoDimensions] = [],
        manualControls: ManualCapabilities = .none,
        equivalentFocalLength: Double? = nil,
        flashModes: [FlashMode] = [],
        hasTorch: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.bayerRAWFormat = bayerRAWFormat
        self.processedFallback = processedFallback
        self.magnification = magnification
        self.isoRange = isoRange
        self.exposureDurationRange = exposureDurationRange
        self.aperture = aperture
        self.maxBracketedPhotoCount = maxBracketedPhotoCount
        self.photoDimensions = photoDimensions
        self.manualControls = manualControls
        self.equivalentFocalLength = equivalentFocalLength
        self.flashModes = flashModes
        self.hasTorch = hasTorch
    }

    /// Whether this lens delivers single-frame Bayer RAW.
    public var supportsBayerRAW: Bool {
        bayerRAWFormat != nil
    }

    /// The 24 MP size AVFoundation delivers only through deferred photo delivery, which the app
    /// turns off: "The maxPhotoDimensions setting for 24MP (5712, 4284), when supported, is only
    /// serviced as 24MP via deferred photo delivery" (`AVCapturePhotoOutput.h`).
    static let deferredOnlySize = PhotoDimensions(width: 5712, height: 4284)

    /// The photo sizes a person can choose between on this lens, smallest first (issue #57), or
    /// an empty list when there is no choice.
    ///
    /// - A lens with Bayer RAW has no choice: its RAW is always the sensor's binned 12 MP readout,
    ///   whatever the photo size (capability survey, item 1), and its HEIF and JPEG are developed
    ///   from that RAW (their size is ``OutputSize``).
    /// - A lens without Bayer RAW offers the sizes its format reports
    ///   (`supportedMaxPhotoDimensions`) for its processed fallback, without the deferred-only
    ///   24 MP size.
    /// - Fewer than two sizes is no choice.
    public var photoSizeChoices: [PhotoDimensions] {
        guard !supportsBayerRAW else { return [] }
        let choices = photoDimensions.filter { $0 != Self.deferredOnlySize }.sorted { $0.pixelCount < $1.pixelCount }
        return choices.count > 1 ? choices : []
    }

    /// The default photo size: the smallest the lens reports, the camera's own default
    /// (`AVCapturePhotoSettings.maxPhotoDimensions`) and the size the app has always used.
    public var defaultPhotoSize: PhotoDimensions? {
        photoDimensions.min { $0.pixelCount < $1.pixelCount }
    }

    /// The photo size to configure for a person's choice: the choice when the lens offers it
    /// (``photoSizeChoices``), otherwise ``defaultPhotoSize``.
    ///
    /// - Parameter choice: The size the person chose for this lens, or `nil`.
    /// - Returns: The size, or `nil` when the lens reported none.
    public func photoSize(for choice: PhotoDimensions?) -> PhotoDimensions? {
        guard let choice, photoSizeChoices.contains(choice) else { return defaultPhotoSize }
        return choice
    }
}
