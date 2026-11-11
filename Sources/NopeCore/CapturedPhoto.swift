import Foundation

/// One finished capture, held in memory.
///
/// Privacy: in this development stage the photo is never written to a file or saved to Photos.
/// It stays in memory until the next capture replaces it. Saving comes with the metadata
/// allowlist, read-back verification and signing (AGENTS.md, "Metadata is allowlisted and
/// verified" and "Photos never linger").
public struct CapturedPhoto: Equatable, Sendable {
    /// The file bytes exactly as the system produced them: a DNG for Bayer RAW, or a HEIF or
    /// JPEG for the fallback. The metadata hasn't been through the allowlist yet.
    public let data: Data

    /// The format of ``data``.
    public let format: CaptureFormat

    /// The lens that took the photo.
    public let lensID: Lens.ID

    /// The photo's size, in pixels, as the system resolved it.
    public let dimensions: PhotoDimensions

    /// The exposure duration the camera used, in seconds, read just before the capture, or
    /// `nil` when unknown.
    public let exposureDuration: Double?

    /// The ISO the camera used, read just before the capture, or `nil` when unknown.
    public let iso: Double?

    /// Creates a captured photo.
    ///
    /// - Parameters:
    ///   - data: The file bytes.
    ///   - format: The format of the bytes.
    ///   - lensID: The lens that took the photo.
    ///   - dimensions: The photo's size, in pixels.
    ///   - exposureDuration: The exposure duration in seconds, or `nil`.
    ///   - iso: The ISO, or `nil`.
    public init(
        data: Data, format: CaptureFormat, lensID: Lens.ID, dimensions: PhotoDimensions,
        exposureDuration: Double?, iso: Double?
    ) {
        self.data = data
        self.format = format
        self.lensID = lensID
        self.dimensions = dimensions
        self.exposureDuration = exposureDuration
        self.iso = iso
    }
}
