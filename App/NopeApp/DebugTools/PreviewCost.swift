#if DEBUG
// Debug-only tools to measure what the Last Photo viewer's previews cost a burst (issue #104;
// docs/TESTING.md, "Burst rate"). Compiled only in the Debug configuration: Release builds
// contain none of this code.
//
// Privacy: a signpost records only when each preview started and ended, under the app's
// subsystem, on the device; no photo data, metadata or value is recorded. Nothing leaves the
// device unless the person records it with Instruments.

import Foundation
import NopeCore
import os

/// Decides whether this launch's saves make previews.
enum PreviewCostLaunch {
    /// The launch argument that turns previews off for the measurement: `-NopeNoSavePreviews`.
    static let noPreviewsArgument = "-NopeNoSavePreviews"

    /// `false` when the current process was launched with ``noPreviewsArgument``.
    static var makesPreviews: Bool {
        !ProcessInfo.processInfo.arguments.contains(noPreviewsArgument)
    }
}

/// A previewer that marks each preview it makes as a "Save preview" interval in Instruments'
/// Points of Interest, and otherwise does what the previewer it wraps does.
struct SignpostedPreviewer: PhotoPreviewing {
    /// The previewer that makes and decodes the previews.
    let wrapped: any PhotoPreviewing

    /// The signposter, in the Points of Interest category so Instruments shows it by default.
    private static let signposter = OSSignposter(subsystem: "com.photivra.nope", category: .pointsOfInterest)

    /// Wraps a previewer.
    ///
    /// - Parameter wrapped: The previewer.
    init(_ wrapped: any PhotoPreviewing) {
        self.wrapped = wrapped
    }

    /// Makes the preview inside a "Save preview" interval.
    ///
    /// - Parameter file: A file that was just saved.
    /// - Returns: The wrapped previewer's preview.
    func preview(of file: PhotoFile) -> PhotoPreview? {
        let state = Self.signposter.beginInterval("Save preview")
        defer { Self.signposter.endInterval("Save preview", state) }
        return wrapped.preview(of: file)
    }

    /// Decodes a preview, as the wrapped previewer does.
    ///
    /// - Parameters:
    ///   - preview: The preview.
    ///   - maximumPixelSize: The longest side to decode to, or `nil`.
    /// - Returns: The pixels, or `nil`.
    func decode(_ preview: PhotoPreview, maximumPixelSize: Int?) -> PhotoThumbnail? {
        wrapped.decode(preview, maximumPixelSize: maximumPixelSize)
    }
}
#endif
