import Foundation

/// A screen-size picture of a saved photo, kept compressed in memory for the Last Photo viewer
/// (docs/design/BUILD-SPEC.md, 3.14 and section 6, item 15).
///
/// It holds only pixels, encoded as a JPEG with the system encoder: nothing from the photo's
/// metadata (no location, date or device) and no Content Credentials; only what the encoder
/// writes to describe the picture itself (its size and color space). A viewer decodes it with
/// ``SessionPhotos/picture(of:maximumPixelSize:)`` only for the page shown and its neighbors.
///
/// Privacy: it lives in memory only, never on disk, in a log or in a copy, and ``SessionPhotos``
/// releases it in the background and under memory pressure (AGENTS.md, "Photos never linger";
/// docs/PRIVACY.md, "Last photo and its details").
public struct PhotoPreview: Equatable, Sendable {
    /// The decoded width, in pixels: the most a viewer can zoom to without enlarging pixels.
    public let width: Int
    /// The decoded height, in pixels.
    public let height: Int
    /// The compressed picture, upright, in the sRGB color space.
    public let data: Data

    /// Creates a preview, or `nil` if a size is not positive or there is no data.
    ///
    /// - Parameters:
    ///   - width: The decoded width, in pixels.
    ///   - height: The decoded height, in pixels.
    ///   - data: The compressed picture.
    public init?(width: Int, height: Int, data: Data) {
        guard width > 0, height > 0, !data.isEmpty else { return nil }
        self.width = width
        self.height = height
        self.data = data
    }

    /// The longest side, in pixels.
    public var longestSide: Int { max(width, height) }
}

/// Makes and decodes ``PhotoPreview`` values, in memory.
///
/// `NopeDevelop` implements it with ImageIO (`ImageIOPreviewer`). ``PhotoSaver`` makes one
/// preview per saved photo, after it is in Photos, from the file that is quickest to read: the
/// HEIF or JPEG when there is one, otherwise the DNG.
public protocol PhotoPreviewing: Sendable {
    /// Makes a compressed preview of a saved file.
    ///
    /// - Parameter file: A file that was just saved.
    /// - Returns: The preview, upright, at most ``SessionPhotos/previewMaximumPixelSize`` on its
    ///   longest side, or `nil` if the file can't be read. A missing preview never fails the save.
    func preview(of file: PhotoFile) -> PhotoPreview?

    /// Decodes a preview into pixels.
    ///
    /// - Parameters:
    ///   - preview: The preview.
    ///   - maximumPixelSize: The longest side to decode to, in pixels, or `nil` for the
    ///     preview's own size. A smaller size, such as the size the screen shows it at, decodes
    ///     faster and uses less memory.
    /// - Returns: The pixels, or `nil` if the data can't be decoded.
    func decode(_ preview: PhotoPreview, maximumPixelSize: Int?) -> PhotoThumbnail?
}
