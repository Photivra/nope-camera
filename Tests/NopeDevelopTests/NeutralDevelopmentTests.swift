@testable import NopeCore
import Testing

@testable import NopeDevelop

/// The decoder settings behind "no noise reduction, sharpening or local tone mapping" for the
/// HEIF and JPEG copies (issue #1, "Formats"). A fake decoder records what is set; the opt-in
/// test with a camera DNG (`ImageIOTests.DevelopedLookTests`) reads the same values back from
/// Core Image's own filter.
struct NeutralDevelopmentTests {
    /// A decoder whose settings all start away from neutral.
    final class FakeDecoder: RAWDecoderOptions {
        let isLuminanceNoiseReductionSupported: Bool
        var luminanceNoiseReductionAmount: Float = 0.5
        let isColorNoiseReductionSupported: Bool
        var colorNoiseReductionAmount: Float = 0.5
        let isSharpnessSupported: Bool
        var sharpnessAmount: Float = 0.5
        let isContrastSupported: Bool
        var contrastAmount: Float = 0.5
        let isDetailSupported: Bool
        var detailAmount: Float = 0.5
        let isMoireReductionSupported: Bool
        var moireReductionAmount: Float = 0.5
        let isLocalToneMapSupported: Bool
        var localToneMapAmount: Float = 0.5
        let isLensCorrectionSupported: Bool
        var isLensCorrectionEnabled = true
        var boostAmount: Float = 0.5

        init(supportsEverything: Bool) {
            isLuminanceNoiseReductionSupported = supportsEverything
            isColorNoiseReductionSupported = supportsEverything
            isSharpnessSupported = supportsEverything
            isContrastSupported = supportsEverything
            isDetailSupported = supportsEverything
            isMoireReductionSupported = supportsEverything
            isLocalToneMapSupported = supportsEverything
            isLensCorrectionSupported = supportsEverything
        }
    }

    @Test(arguments: [DevelopedLook.standard, .flat])
    func everyProcessingStepIsOffWhereTheDecoderOffersIt(look: DevelopedLook) {
        let decoder = FakeDecoder(supportsEverything: true)
        NeutralDevelopment.apply(to: decoder, look: look)
        #expect(decoder.luminanceNoiseReductionAmount == 0)
        #expect(decoder.colorNoiseReductionAmount == 0)
        #expect(decoder.sharpnessAmount == 0)
        #expect(decoder.contrastAmount == 0)
        #expect(decoder.detailAmount == 0)
        #expect(decoder.moireReductionAmount == 0)
        #expect(decoder.localToneMapAmount == 0)
        #expect(!decoder.isLensCorrectionEnabled)
        #expect(decoder.boostAmount == (look == .flat ? 0 : 1))
    }

    @Test func settingsTheDecoderDoesNotOfferAreLeftAlone() {
        let decoder = FakeDecoder(supportsEverything: false)
        NeutralDevelopment.apply(to: decoder, look: .flat)
        #expect(decoder.luminanceNoiseReductionAmount == 0.5)
        #expect(decoder.colorNoiseReductionAmount == 0.5)
        #expect(decoder.sharpnessAmount == 0.5)
        #expect(decoder.contrastAmount == 0.5)
        #expect(decoder.detailAmount == 0.5)
        #expect(decoder.moireReductionAmount == 0.5)
        #expect(decoder.localToneMapAmount == 0.5)
        #expect(decoder.isLensCorrectionEnabled)
        #expect(decoder.boostAmount == 0)
    }
}
