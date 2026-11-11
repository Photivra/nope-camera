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

    /// Creates a request for a lens, choosing the format with ``CaptureFormat/init(for:)``.
    ///
    /// - Parameter lens: The lens to use.
    public init(lens: Lens) {
        self.lens = lens
        self.format = CaptureFormat(for: lens)
    }
}
