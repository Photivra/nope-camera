import Foundation

/// One finished capture, held in memory.
///
/// Privacy: the photo is never written to a file. ``PhotoSaver`` takes it from memory to Photos
/// (AGENTS.md, "Photos never linger").
public struct CapturedPhoto: Equatable, Sendable {
    /// The file bytes: a DNG for Bayer RAW, or a HEIF or JPEG for the fallback. The capture
    /// backend writes them with metadata built from the request's ``CaptureRequest/metadata``
    /// plan; ``PhotoSaver`` reads them back before saving.
    public let data: Data

    /// For Bayer RAW, the RAW image data of the system's own DNG, taken before nope. wrote its
    /// metadata; `nil` for the fallback. The read-back compares the saved DNG's image data with
    /// it, so a changed pixel rejects the photo.
    public let rawImageData: Data?

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
    ///   - rawImageData: The reference RAW image data, or `nil`.
    public init(
        data: Data, format: CaptureFormat, lensID: Lens.ID, dimensions: PhotoDimensions,
        exposureDuration: Double?, iso: Double?, rawImageData: Data? = nil
    ) {
        self.data = data
        self.rawImageData = rawImageData
        self.format = format
        self.lensID = lensID
        self.dimensions = dimensions
        self.exposureDuration = exposureDuration
        self.iso = iso
    }
}
