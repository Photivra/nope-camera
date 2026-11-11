import Foundation

/// One physical camera on the device, described as plain data.
///
/// Lenses are discovered at run time by a ``CaptureBackend``; an interface renders them without
/// knowing the hardware (AGENTS.md, "Capabilities are data"). Every range is what the camera
/// reported for the format nope. uses, so it can differ between devices and iOS versions.
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
    /// only: nope. never zooms digitally.
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
        photoDimensions: [PhotoDimensions] = []
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
    }

    /// Whether this lens delivers single-frame Bayer RAW.
    public var supportsBayerRAW: Bool {
        bayerRAWFormat != nil
    }
}
