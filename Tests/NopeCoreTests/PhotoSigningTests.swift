import Foundation
import Testing

@testable import NopeCore

struct PhotoSigningTests {
    @Test func signingIsOnByDefault() {
        #expect(SigningSettings.default.isEnabled)
        #expect(SigningSettings().isEnabled)
        #expect(!SigningSettings(isEnabled: false).isEnabled)
    }

    @Test func signingSettingsRoundTrip() throws {
        let off = SigningSettings(isEnabled: false)
        let decoded = try JSONDecoder().decode(SigningSettings.self, from: JSONEncoder().encode(off))
        #expect(decoded == off)
    }

    @Test func filesFromRAW() {
        #expect(SignableFile(developedFrom: .raw) == .singleFrameRAW)
        #expect(SignableFile(developedFrom: .heif) == .developedHEIF)
        #expect(SignableFile(developedFrom: .jpeg) == .developedJPEG)
    }

    @Test func filesFromTheFallback() {
        #expect(SignableFile(fallback: .heif) == .deviceProcessedHEIF)
        #expect(SignableFile(fallback: .jpeg) == .deviceProcessedJPEG)
    }

    @Test func containers() {
        #expect(SignableFile.singleFrameRAW.container == .dng)
        #expect(SignableFile.developedHEIF.container == .heif)
        #expect(SignableFile.deviceProcessedHEIF.container == .heif)
        #expect(SignableFile.developedJPEG.container == .jpeg)
        #expect(SignableFile.deviceProcessedJPEG.container == .jpeg)
    }

    @Test func storeLocations() {
        #expect(ContentCredentialsStore.dngTag == 0xCD41)
        #expect(ContentCredentialsStore.jpegMarker == 0xFFEB)
        #expect(ContentCredentialsStore.heifBoxUUID.uuidString == "D8FEC3D6-1B0E-483C-9297-5828877EC481")
        #expect(ContentCredentialsStore.dng.mediaType == "image/x-adobe-dng")
        #expect(ContentCredentialsStore.heif.mediaType == "image/heic")
        #expect(ContentCredentialsStore.jpeg.mediaType == "image/jpeg")
    }

    @Test func errorsAreDistinct() {
        #expect(PhotoSigningError.keyCreationFailed != .signingFailed)
    }
}
