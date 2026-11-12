import C2PA
import CryptoKit
import Foundation
import NopeCore
import Testing
import X509

@testable import NopeSigning

// A hang fails the test with its name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
struct KeyProviderTests {
    @Test func simulatorUsesTheSoftwareKeyOnly() {
        // On a device, platformKeyProvider() returns SecureEnclaveKeyProvider and the software
        // key isn't compiled at all (#if targetEnvironment(simulator)).
        #expect(platformKeyProvider() is SimulatorSoftwareKeyProvider)
    }

    @Test func softwareKeySignsVerifiably() throws {
        let key = try SimulatorSoftwareKeyProvider().makeKey()
        let message = Data("claim".utf8)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: key.signatureDER(for: message))
        let software = try #require(key as? SimulatorSoftwareSigningKey)
        #expect(software.key.publicKey.isValidSignature(signature, for: message))
        #expect(key.certificateKey.publicKey == Certificate.PublicKey(software.key.publicKey))
    }

    @Test func everyKeyIsNew() throws {
        let provider = SimulatorSoftwareKeyProvider()
        let first = try provider.makeKey().certificateKey.publicKey
        let second = try provider.makeKey().certificateKey.publicKey
        #expect(first != second)
    }
}

// A hang fails the test with its name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
struct ManifestTests {
    @Test func jsonIsExactlyTheManifest() {
        let manifest = ContentCredentialsManifest(
            file: .singleFrameRAW, generator: ClaimGenerator(version: "1.2.3"),
            instanceID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
        #expect(
            manifest.json()
                == #"{"assertions":[{"data":{"actions":[{"action":"c2pa.created","description":"Captured by Photivra Nope Camera as a single frame of RAW sensor data, with as little processing as the phone allows.","digitalSourceType":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"}]},"label":"c2pa.actions.v2"}],"claim_generator_info":[{"name":"Photivra Nope Camera","version":"1.2.3"}],"claim_version":2,"format":"image/x-adobe-dng","instance_id":"xmp:iid:00000000-0000-4000-8000-000000000001"}"#
        )
    }

    @Test(arguments: SignableFile.allCases)
    func formatFollowsTheContainer(file: SignableFile) {
        let manifest = ContentCredentialsManifest(file: file, generator: ClaimGenerator(version: "1"), instanceID: UUID())
        #expect(manifest.format == file.mediaType)
    }

    @Test func descriptionsClaimNoMoreThanIsTrue() {
        #expect(
            ContentCredentialsManifest.description(of: .singleFrameRAW)
                == "Captured by Photivra Nope Camera as a single frame of RAW sensor data, with as little processing as the phone allows.")
        for file in [SignableFile.developedHEIF, .developedJPEG] {
            #expect(
                ContentCredentialsManifest.description(of: file)
                    == "Developed by Photivra Nope Camera on the phone from a single frame of RAW sensor data.")
        }
        for file in [SignableFile.deviceProcessedHEIF, .deviceProcessedJPEG] {
            #expect(
                ContentCredentialsManifest.description(of: file)
                    == "Captured by Photivra Nope Camera and processed by the phone's camera, because this lens can't save RAW.")
        }
        for file in SignableFile.allCases {
            #expect(!ContentCredentialsManifest.description(of: file).localizedCaseInsensitiveContains("zero processing"))
        }
    }

    @Test func claimGeneratorIsNope() {
        let generator = ClaimGenerator(version: "0.1.0")
        #expect(generator.name == "Photivra Nope Camera")
        #expect(generator.version == "0.1.0")
    }
}

// A hang fails the test with its name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
struct OfflineContextTests {
    @Test func everyNetworkPathIsOff() {
        let settings = OfflineC2PAContext.settings
        #expect(settings.core?.allowedNetworkHosts == [])
        #expect(settings.verify?.ocspFetch == false)
        #expect(settings.verify?.remoteManifestFetch == false)
        #expect(settings.verify?.verifyTrust == false)
        #expect(settings.verify?.verifyAfterSign == false)
        #expect(settings.builder?.thumbnail?.enabled == false)
        #expect(settings.builder?.autoTimestampAssertion?.enabled == false)
        #expect(settings.builder?.certificateStatusFetch == nil)
    }

    @Test func contextIsCreated() throws {
        _ = try OfflineC2PAContext.make()
    }

    /// Even when settings let the library fetch a remote manifest, it can't: the library nope.
    /// links has no network code, so reading a file whose manifest is remote fails.
    @Test func remoteManifestIsNeverFetched() throws {
        let photo = SyntheticPhotos.data(for: .developedJPEG)
        let builder = try Builder(
            context: OfflineC2PAContext.make(),
            manifestJSON: ContentCredentialsManifest(
                file: .developedJPEG, generator: ClaimGenerator(version: "1"), instanceID: UUID()
            ).json())
        try builder.setRemote(url: URL(string: "https://example.invalid/manifest.c2pa")!)
        builder.setNoEmbed()
        let key = SimulatorSoftwareSigningKey()
        let signer = try Signer(
            algorithm: .es256, certificateChainPEM: SelfIssuedCertificate.pem(for: key), tsa: nil
        ) { try key.signatureDER(for: $0) }
        let destination = InMemoryFile()
        try builder.sign(
            format: "image/jpeg", source: InMemoryStream.make(InMemoryFile(photo)),
            destination: InMemoryStream.make(destination), signer: signer)

        var fetching = OfflineC2PAContext.settings
        fetching.core = CoreSettings()
        fetching.verify = VerifySettings(remoteManifestFetch: true)
        let context = try C2PAContext(settings: C2PASettings(definition: fetching))
        #expect(throws: (any Error).self) {
            try Reader(context: context, format: "image/jpeg", stream: InMemoryStream.make(destination)).json()
        }
    }
}

struct SignableFileTests {
    @Test(arguments: SignableFile.allCases)
    func roundTripsThroughPhotoFile(file: SignableFile) {
        let photoFile = PhotoFile(format: file.format, data: Data(), isProcessedByDevice: file.isProcessedByDevice)
        #expect(SignableFile(photoFile) == file)
    }

    @Test func aDNGIsAlwaysSingleFrameRAW() {
        #expect(SignableFile(PhotoFile(format: .raw, data: Data(), isProcessedByDevice: true)) == .singleFrameRAW)
    }

    @Test func mediaTypes() {
        #expect(SignableFile.singleFrameRAW.mediaType == "image/x-adobe-dng")
        #expect(SignableFile.developedHEIF.mediaType == "image/heic")
        #expect(SignableFile.deviceProcessedJPEG.mediaType == "image/jpeg")
    }
}
