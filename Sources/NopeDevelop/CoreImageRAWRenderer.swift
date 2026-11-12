import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import NopeCore

/// Renders a Bayer DNG with Core Image's RAW filter, neutrally.
///
/// Needs a real Bayer DNG, which a unit test can't create (ImageIO and Core Image don't decode
/// a hand-built DNG in the Simulator), so this thin adapter is excluded from the coverage gate
/// and verified on a device, and with a real DNG in the Simulator by an opt-in test
/// (docs/TESTING.md, "Developed looks"). Its choices, from the `CIRAWFilter.h` documentation of
/// each property:
///
/// - Noise reduction (luminance and color), sharpening, detail, moiré reduction, local contrast
///   (`contrastAmount`, "local contrast to apply to the edges") and local tone mapping are set
///   to 0 where the filter supports them (issue #1, "Formats").
/// - Lens correction is off: the pixels are never corrected (`docs/PRIVACY.md`).
/// - The tone follows the `DevelopedLook`: `boostAmount` is 1 ("full global tone curve", the
///   filter's default) for `DevelopedLook.standard`, and 0 ("no global tone curve, i.e. linear
///   response") for `DevelopedLook.flat`. `boostShadowAmount` "has no effect if the
///   boostAmount is 0".
/// - Everything else (white balance, color matrices, highlight recovery, baseline exposure)
///   keeps the filter's defaults for the file.
/// - The output is upright (the filter applies the DNG's orientation by default), rendered at
///   16 bits per channel in Display P3, the color space the camera reports; encoding applies
///   Display P3's standard transfer function.
struct CoreImageRAWRenderer: RAWRendering {
    /// Creates the renderer. It holds no state.
    init() {}

    /// Sets the filter's neutral options and the look's tone.
    ///
    /// - Parameters:
    ///   - filter: The RAW filter for the DNG.
    ///   - look: The tone: one global tone curve, or none.
    static func configure(_ filter: CIRAWFilter, look: DevelopedLook) {
        if filter.isLuminanceNoiseReductionSupported { filter.luminanceNoiseReductionAmount = 0 }
        if filter.isColorNoiseReductionSupported { filter.colorNoiseReductionAmount = 0 }
        if filter.isSharpnessSupported { filter.sharpnessAmount = 0 }
        if filter.isContrastSupported { filter.contrastAmount = 0 }
        if filter.isDetailSupported { filter.detailAmount = 0 }
        if filter.isMoireReductionSupported { filter.moireReductionAmount = 0 }
        if filter.isLocalToneMapSupported { filter.localToneMapAmount = 0 }
        if filter.isLensCorrectionSupported { filter.isLensCorrectionEnabled = false }
        filter.boostAmount = look == .flat ? 0 : 1
    }

    /// Renders a DNG.
    ///
    /// - Parameters:
    ///   - dng: The DNG's bytes.
    ///   - look: The tone: one global tone curve, or none.
    /// - Returns: The upright image and the DNG's ImageIO properties.
    /// - Throws: `CaptureError.developmentFailed` if the DNG can't be decoded or rendered.
    func render(_ dng: Data, look: DevelopedLook) throws(CaptureError) -> RenderedRAW {
        guard let filter = CIRAWFilter(imageData: dng, identifierHint: "com.adobe.raw-image"),
            let source = CGImageSourceCreateWithData(dng as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        else { throw .developmentFailed }
        Self.configure(filter, look: look)
        guard let image = filter.outputImage,
            let cgImage = CIContext().createCGImage(image, from: image.extent, format: .RGBA16, colorSpace: colorSpace)
        else { throw .developmentFailed }
        return RenderedRAW(image: cgImage, properties: properties)
    }
}
