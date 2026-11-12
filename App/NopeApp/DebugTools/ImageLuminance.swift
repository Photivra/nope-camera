#if DEBUG
// Debug-only tag check diagnostic (docs/TESTING.md, "Black frames"): proves from the decoded
// pixels, not from metadata, whether a captured image is exposed.

import CoreImage
import Foundation

/// Measures a decoded image's brightness for the tag check report.
///
/// The first device runs produced DNGs whose 16 tiles were byte-identical, with entropy-coded
/// data repeating one byte value: a constant fill, not a sensor readout. Metadata can't show
/// that, so each capture is decoded and measured here.
enum ImageLuminance {
    /// The widest luma spread, from 0 to 1, below which an image counts as one flat value. One
    /// 8-bit step. A tool threshold, not a platform value.
    static let flatSpread = 1.0 / 255.0

    /// The mean luma, from 0 to 1, below which an image counts as black. A tool threshold: a
    /// correctly exposed indoor scene is far above it.
    static let blackMean = 0.01

    /// Shared Core Image context; creating one is expensive.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Decodes and measures a DNG, HEIF or JPEG file.
    ///
    /// DNGs are developed with `CIRAWFilter` at its defaults, which is enough to tell an exposed
    /// frame from a black or flat one.
    ///
    /// - Parameters:
    ///   - data: The file bytes.
    ///   - isRAW: `true` for a DNG.
    /// - Returns: `meanLuma`, `minLuma`, `maxLuma` (sRGB-encoded Rec. 709 luma, 0 to 1),
    ///   `width`, `height`, `looksFlat`, `looksBlack`, `maxRed`, `maxBlue` and
    ///   `looksZeroFilled`, or an `error` entry.
    static func measure(data: Data, isRAW: Bool) -> [String: Any] {
        let image: CIImage?
        if isRAW {
            image = CIRAWFilter(imageData: data, identifierHint: "com.adobe.raw-image")?.outputImage
        } else {
            image = CIImage(data: data)
        }
        guard let image else { return ["error": "could not decode"] }
        return measure(image)
    }

    /// Measures a decoded image.
    ///
    /// - Parameter image: The image.
    /// - Returns: The same keys as ``measure(data:isRAW:)``.
    static func measure(_ image: CIImage) -> [String: Any] {
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0,
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return ["error": "empty image"] }
        let region = CIVector(cgRect: extent)
        var mean = [Float](repeating: 0, count: 4)
        var minMax = [Float](repeating: 0, count: 8)
        if let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: region])?
            .outputImage
        {
            context.render(
                average, toBitmap: &mean, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf, colorSpace: sRGB)
        }
        if let range = CIFilter(name: "CIAreaMinMax", parameters: [kCIInputImageKey: image, kCIInputExtentKey: region])?
            .outputImage
        {
            context.render(
                range, toBitmap: &minMax, rowBytes: 32, bounds: CGRect(x: 0, y: 0, width: 2, height: 1),
                format: .RGBAf, colorSpace: sRGB)
        }
        let meanLuma = luma(mean[0], mean[1], mean[2])
        let minLuma = luma(minMax[0], minMax[1], minMax[2])
        let maxLuma = luma(minMax[4], minMax[5], minMax[6])
        return [
            "meanLuma": meanLuma,
            "minLuma": minLuma,
            "maxLuma": maxLuma,
            "width": Int(extent.width),
            "height": Int(extent.height),
            "looksFlat": maxLuma - minLuma < flatSpread,
            "looksBlack": meanLuma < blackMean,
            "maxRed": Double(minMax[4]),
            "maxBlue": Double(minMax[6]),
            // A zero-filled YCbCr buffer decodes as a pure green field (no red or blue anywhere),
            // which can pass the mean test above once the ISP applies gain and lens shading.
            "looksZeroFilled": Double(max(minMax[4], minMax[6])) < flatSpread,
        ]
    }

    /// Rec. 709 luma from sRGB-encoded components.
    private static func luma(_ red: Float, _ green: Float, _ blue: Float) -> Double {
        0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
    }
}
#endif
