import Foundation
import NopeCore

/// Develops HEIF and JPEG files from a RAW photo, with metadata built from the allowlist.
///
/// The RAW is rendered neutrally (``CoreImageRAWRenderer``: no noise reduction, sharpening or
/// local tone mapping; issue #1, "Formats") and encoded with the system encoders
/// (``PhotoEncoder``, ``EncodingSettings``). The new file's metadata is built by
/// `MetadataPlan` from the DNG's own properties, which already passed through the allowlist
/// at capture, and its orientation is 1 (up) because the rendered image is upright.
public struct RAWDeveloper: PhotoDeveloping {
    /// Renders the DNG.
    private let renderer: any RAWRendering

    /// Creates the app's developer, with Core Image.
    public init() {
        self.init(renderer: CoreImageRAWRenderer())
    }

    /// Creates a developer with another renderer. Tests pass a fake.
    ///
    /// - Parameter renderer: Renders the DNG.
    init(renderer: any RAWRendering) {
        self.renderer = renderer
    }

    /// The orientation of a developed file: up, because the renderer applies the DNG's
    /// orientation to the pixels (EXIF `Orientation` value 1).
    static let uprightOrientation = 1

    /// Develops a HEIF or JPEG from a DNG.
    ///
    /// - Parameters:
    ///   - raw: The DNG.
    ///   - format: `PhotoFormat.heif` or `PhotoFormat.jpeg`.
    ///   - look: The tone of the developed file.
    ///   - metadata: The plan the file's metadata is built from.
    /// - Returns: The developed file.
    /// - Throws: `CaptureError.developmentFailed` if `format` is RAW, or rendering or encoding
    ///   fails.
    public func develop(
        _ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, metadata: MetadataPlan
    ) async throws(CaptureError) -> PhotoFile {
        guard let settings = EncodingSettings(format: format) else { throw .developmentFailed }
        let rendered = try renderer.render(raw.data, look: look)
        let properties = metadata.properties(
            for: format, from: rendered.properties, orientation: Self.uprightOrientation)
        let data = try PhotoEncoder.encode(rendered.image, settings: settings, properties: properties)
        return PhotoFile(format: format, data: data)
    }
}
