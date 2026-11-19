#if DEBUG
// Debug-only: a still photo as the simulated viewfinder's picture, for store screenshots taken
// on the Simulator, which has no camera (docs/store/STORE-PAGE-PLAN.md, section 5.2, option B).
// Compiled only in the Debug configuration; Release builds have no simulated viewfinder and
// show the device's camera. `scripts/check-security.sh` checks that every file here is wrapped
// in `#if DEBUG`, and CI checks the Release binary has no `NopeSimulated` string.

import SwiftUI
import UIKit

/// Reads `-NopeSimulatedViewfinderImage <path>` from the launch arguments: the absolute path of
/// a HEIF, JPEG or PNG file on the Mac running the Simulator.
///
/// The still is shown whole on black, as the camera's preview layer shows the whole frame
/// (`resizeAspect`). It replaces only the picture: the live analysis (histogram, focus peaking,
/// zebras) still measures the simulated frame (`SimulatedCaptureBackend.placeholderFrame`), so
/// screenshots that show those overlays don't describe the still. Use it only for screens whose
/// overlays are off, and only with a photo taken with the app and saved unedited.
enum SimulatedViewfinderImage {
    /// The launch argument: `-NopeSimulatedViewfinderImage`.
    static let argument = "-NopeSimulatedViewfinderImage"

    /// The path in the launch arguments, or `nil` without one.
    ///
    /// - Parameter arguments: The launch arguments.
    /// - Returns: The path that follows ``argument``, or `nil`.
    static func path(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The still from the launch arguments, read once, or `nil` without the argument or when the
    /// file can't be read as an image.
    static let image: UIImage? = path(in: ProcessInfo.processInfo.arguments).flatMap { UIImage(contentsOfFile: $0) }

    /// The still, whole, centered on black.
    ///
    /// - Parameter image: The still.
    static func view(_ image: UIImage) -> some View {
        Color.black.overlay {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
        .accessibilityHidden(true)
    }
}
#endif
