import Foundation

/// What ``CameraModel`` asks a ``CaptureBackend`` to set up or capture: one lens and one format.
///
/// The model builds it from the selected lens with ``CaptureFormat/init(for:)``, so the format
/// decision stays in `NopeCore`.
public struct CaptureRequest: Equatable, Sendable {
    /// The lens to use.
    public let lens: Lens

    /// The format to capture.
    public let format: CaptureFormat

    /// The plan the photo's metadata is built from. The backend writes the file with
    /// ``MetadataPlan/properties(for:from:orientation:)``, never with the system's full
    /// metadata.
    public let metadata: MetadataPlan

    /// Creates a request for a lens, choosing the format with ``CaptureFormat/init(for:)``.
    ///
    /// - Parameters:
    ///   - lens: The lens to use.
    ///   - metadata: The metadata plan. Defaults to the first-launch settings: every optional
    ///     detail removed.
    public init(lens: Lens, metadata: MetadataPlan = MetadataPlan()) {
        self.lens = lens
        self.format = CaptureFormat(for: lens)
        self.metadata = metadata
    }

    /// Creates a request for a lens with an explicit format.
    ///
    /// ``CameraModel`` never uses it: it always lets ``CaptureFormat/init(for:)`` decide. It
    /// exists for diagnostics that must capture a lens's processed fallback even though the lens
    /// has Bayer RAW, such as the Debug-only tag check (docs/TESTING.md, "Tag check").
    ///
    /// - Parameters:
    ///   - lens: The lens to use.
    ///   - format: The format to capture. A Bayer RAW format must be one the lens supports.
    ///   - metadata: The metadata plan. Defaults to the first-launch settings.
    public init(lens: Lens, format: CaptureFormat, metadata: MetadataPlan = MetadataPlan()) {
        self.lens = lens
        self.format = format
        self.metadata = metadata
    }
}
