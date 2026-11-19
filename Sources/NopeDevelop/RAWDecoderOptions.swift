import CoreImage
import NopeCore

/// The RAW decoder settings that the development of HEIF and JPEG copies depends on.
///
/// `CIRAWFilter` has them all. The protocol exists so a unit test can check, without a camera
/// DNG, every value ``NeutralDevelopment`` sets: the Honesty wording "no noise reduction,
/// sharpening or local tone mapping" (issue #1, "Formats") rests on these values. Each name and
/// its meaning are from `CIRAWFilter.h`.
protocol RAWDecoderOptions: AnyObject {
    /// Whether the decoder can change luminance noise reduction for this file.
    var isLuminanceNoiseReductionSupported: Bool { get }
    /// The luminance noise reduction to apply, from 0 (none) to 1.
    var luminanceNoiseReductionAmount: Float { get set }
    /// Whether the decoder can change color noise reduction for this file.
    var isColorNoiseReductionSupported: Bool { get }
    /// The color noise reduction to apply, from 0 (none) to 1.
    var colorNoiseReductionAmount: Float { get set }
    /// Whether the decoder can change sharpening for this file.
    var isSharpnessSupported: Bool { get }
    /// The sharpening to apply, from 0 (none) to 1.
    var sharpnessAmount: Float { get set }
    /// Whether the decoder can change local contrast for this file.
    var isContrastSupported: Bool { get }
    /// The local contrast to apply to the edges, from 0 (none) to 1.
    var contrastAmount: Float { get set }
    /// Whether the decoder can change detail enhancement for this file.
    var isDetailSupported: Bool { get }
    /// The detail enhancement to apply, from 0 (none).
    var detailAmount: Float { get set }
    /// Whether the decoder can change moiré reduction for this file.
    var isMoireReductionSupported: Bool { get }
    /// The moiré reduction to apply, from 0 (none) to 1.
    var moireReductionAmount: Float { get set }
    /// Whether the decoder can change local tone mapping for this file.
    var isLocalToneMapSupported: Bool { get }
    /// The local tone mapping to apply, from 0 (none) to 1.
    var localToneMapAmount: Float { get set }
    /// Whether the decoder can apply the file's lens correction.
    var isLensCorrectionSupported: Bool { get }
    /// Whether the decoder applies the file's lens correction to the pixels.
    var isLensCorrectionEnabled: Bool { get set }
    /// The global tone curve: 1 is the full curve, 0 is none (a linear response).
    var boostAmount: Float { get set }
}

/// Core Image's RAW filter has every setting the development depends on, with the same names.
extension CIRAWFilter: RAWDecoderOptions {}

/// The neutral development settings for the HEIF and JPEG copies.
enum NeutralDevelopment {
    /// Sets the decoder's neutral options and the look's tone.
    ///
    /// Noise reduction (luminance and color), sharpening, detail, moiré reduction, local contrast
    /// and local tone mapping are set to 0 wherever the decoder supports changing them, and lens
    /// correction is turned off, so the pixels are never corrected (`docs/PRIVACY.md`). The tone
    /// follows the look: `boostAmount` is 1 for `DevelopedLook.standard` and 0 for
    /// `DevelopedLook.flat`. A setting the decoder doesn't offer for a file can't be changed,
    /// so it is left as the decoder has it; the opt-in test with a camera DNG reads every value
    /// back (`docs/TESTING.md`, "Developed looks").
    ///
    /// - Parameters:
    ///   - options: The decoder's settings for one DNG.
    ///   - look: The tone: one global tone curve, or none.
    static func apply(to options: some RAWDecoderOptions, look: DevelopedLook) {
        if options.isLuminanceNoiseReductionSupported { options.luminanceNoiseReductionAmount = 0 }
        if options.isColorNoiseReductionSupported { options.colorNoiseReductionAmount = 0 }
        if options.isSharpnessSupported { options.sharpnessAmount = 0 }
        if options.isContrastSupported { options.contrastAmount = 0 }
        if options.isDetailSupported { options.detailAmount = 0 }
        if options.isMoireReductionSupported { options.moireReductionAmount = 0 }
        if options.isLocalToneMapSupported { options.localToneMapAmount = 0 }
        if options.isLensCorrectionSupported { options.isLensCorrectionEnabled = false }
        options.boostAmount = look == .flat ? 0 : 1
    }
}
