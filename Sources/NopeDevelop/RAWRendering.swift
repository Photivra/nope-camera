import CoreGraphics
import Foundation
import NopeCore

/// A RAW photo rendered to pixels, with the metadata it was read with.
struct RenderedRAW: @unchecked Sendable {
    /// The developed image, upright, 16 bits per channel, in Display P3.
    let image: CGImage
    /// The DNG's ImageIO properties, which `MetadataPlan` copies allowlisted values from.
    /// `@unchecked Sendable`: the dictionary is created once and never mutated.
    let properties: [String: Any]

    /// Pairs an image with its properties.
    ///
    /// - Parameters:
    ///   - image: The developed image.
    ///   - properties: The DNG's ImageIO properties.
    init(image: CGImage, properties: [String: Any]) {
        self.image = image
        self.properties = properties
    }
}

/// Renders a DNG to pixels, behind a protocol so ``RAWDeveloper`` can be tested with a fake.
///
/// `CoreImageRAWRenderer` implements it with Core Image's RAW filter; it needs a real Bayer DNG,
/// which can't be made in a unit test, so it is verified on a device (docs/TESTING.md).
protocol RAWRendering: Sendable {
    /// Renders a DNG.
    ///
    /// - Parameters:
    ///   - dng: The DNG's bytes.
    ///   - look: The tone: one global tone curve, or none.
    /// - Returns: The upright image and the DNG's properties.
    /// - Throws: `CaptureError.developmentFailed` if the DNG can't be decoded or rendered.
    func render(_ dng: Data, look: DevelopedLook) throws(CaptureError) -> RenderedRAW
}
