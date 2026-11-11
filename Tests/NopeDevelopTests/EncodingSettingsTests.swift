import ImageIO
import NopeCore
import NopeDevelop
import Testing
import UniformTypeIdentifiers

struct EncodingSettingsTests {
    @Test func rawIsNeverReencoded() {
        #expect(EncodingSettings(format: .raw) == nil)
    }

    @Test func heifIsTenBitWithSystemDefaultQuality() throws {
        let settings = try #require(EncodingSettings(format: .heif))
        #expect(settings.format == .heif)
        #expect(settings.typeIdentifier == UTType.heic.identifier)
        #expect(settings.bitsPerChannel == 10)
        #expect(settings.lossyCompressionQuality == nil)
        #expect(settings.imageDestinationOptions().isEmpty)
    }

    @Test func jpegIsMaximumQuality() throws {
        let settings = try #require(EncodingSettings(format: .jpeg))
        #expect(settings.typeIdentifier == UTType.jpeg.identifier)
        #expect(settings.bitsPerChannel == 8)
        #expect(settings.imageDestinationOptions() == [kCGImageDestinationLossyCompressionQuality as String: 1.0])
    }
}
