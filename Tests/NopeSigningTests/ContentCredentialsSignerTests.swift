import C2PA
import Foundation
import NopeCore
import Testing
import X509

import class C2PA.Stream

@testable import NopeSigning

/// Reads and validates a signed file with the C2PA library's reader, offline, checking trust the
/// way a validator with no trust list does.
///
/// - Returns: The reader's report as a JSON object.
func validate(_ data: Data, as file: SignableFile) throws -> [String: Any] {
    let settings = C2PASettingsDefinition(
        version: 1, core: CoreSettings(allowedNetworkHosts: []),
        verify: VerifySettings(
            verifyAfterReading: true, verifyTrust: true, ocspFetch: false, remoteManifestFetch: false))
    let context = try C2PAContext(settings: C2PASettings(definition: settings))
    let reader = try Reader(context: context, format: file.container.mediaType, stream: Stream(data: data))
    let json = try reader.json()
    return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

/// A reader report, with the parts the tests check.
struct Report {
    /// The raw report.
    let json: [String: Any]

    init(_ json: [String: Any]) { self.json = json }

    /// `Valid`, `Invalid` or `Trusted`.
    var state: String? { json["validation_state"] as? String }

    /// The status codes of one kind (`success`, `informational`, `failure`) for the active manifest.
    func codes(_ kind: String) -> [String] {
        let results = json["validation_results"] as? [String: Any]
        let active = results?["activeManifest"] as? [String: Any]
        return (active?[kind] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String }
    }

    /// The active manifest.
    var manifest: [String: Any] {
        let manifests = json["manifests"] as? [String: Any] ?? [:]
        return manifests[json["active_manifest"] as? String ?? ""] as? [String: Any] ?? [:]
    }
}

/// The hash check the C2PA library runs for each container.
func hashCode(for file: SignableFile) -> String {
    file.container == .heif ? "assertion.bmffHash" : "assertion.dataHash"
}

/// A key provider that counts the keys it makes.
final class CountingKeyProvider: SigningKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var made = 0
    var count: Int { lock.withLock { made } }
    func makeKey() throws -> any PerPhotoSigningKey {
        lock.withLock { made += 1 }
        return try SimulatorSoftwareKeyProvider().makeKey()
    }
}

/// A key provider that can't make a key, like a device whose Secure Enclave is unavailable.
struct FailingKeyProvider: SigningKeyProvider {
    struct Unavailable: Error {}
    func makeKey() throws -> any PerPhotoSigningKey { throw Unavailable() }
}

/// A key whose claim signature fails, like a busy Secure Enclave.
struct FailingClaimKey: PerPhotoSigningKey {
    struct Busy: Error {}
    let base = SimulatorSoftwareSigningKey()
    var certificateKey: Certificate.PrivateKey { base.certificateKey }
    func signatureDER(for data: Data) throws -> Data { throw Busy() }
}

/// Provides ``FailingClaimKey``s.
struct FailingClaimKeyProvider: SigningKeyProvider {
    func makeKey() throws -> any PerPhotoSigningKey { FailingClaimKey() }
}

/// Flips one bit of the byte at an index.
func flippingBit(of data: Data, at index: Int) -> Data {
    var copy = data
    copy[copy.startIndex + index] ^= 0x01
    return copy
}

// A hang fails the test with its name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
struct ContentCredentialsSignerTests {
    let signer = ContentCredentialsSigner(
        keyProvider: SimulatorSoftwareKeyProvider(), generator: ClaimGenerator(version: "0.1.0"))

    @Test(arguments: SignableFile.allCases)
    func signedFileIsValidAndUntrusted(file: SignableFile) async throws {
        let signed = try await signer.sign(SyntheticPhotos.data(for: file), as: file)
        let report = Report(try validate(signed, as: file))
        #expect(report.state == "Valid")
        #expect(report.codes("success").contains("claimSignature.validated"))
        #expect(report.codes("success").contains("\(hashCode(for: file)).match"))
        // The anonymous certificate isn't on any trust list, and that is the only failure.
        #expect(report.codes("failure") == ["signingCredential.untrusted"])
    }

    @Test(arguments: SignableFile.allCases)
    func manifestSaysOnlyWhatNopeDid(file: SignableFile) async throws {
        let signed = try await signer.sign(SyntheticPhotos.data(for: file), as: file)
        let manifest = Report(try validate(signed, as: file)).manifest
        let generator = try #require((manifest["claim_generator_info"] as? [[String: Any]])?.first)
        #expect(generator["name"] as? String == "nope.")
        #expect(generator["version"] as? String == "0.1.0")
        let assertions = try #require(manifest["assertions"] as? [[String: Any]])
        // Besides the hash binding the library adds (the reader lists the HEIF one), the only
        // assertion is the actions assertion.
        let labels = assertions.compactMap { $0["label"] as? String }.filter { !$0.hasPrefix("c2pa.hash.") }
        #expect(labels == ["c2pa.actions.v2"])
        let actionsAssertion = assertions.first { $0["label"] as? String == "c2pa.actions.v2" }
        let data = try #require(actionsAssertion?["data"] as? [String: Any])
        let actions = try #require(data["actions"] as? [[String: Any]])
        #expect(actions.count == 1)
        let action = try #require(actions.first)
        #expect(Set(action.keys) == ["action", "digitalSourceType", "description"])
        #expect(action["action"] as? String == "c2pa.created")
        #expect(action["digitalSourceType"] as? String == ContentCredentialsManifest.digitalCapture)
        #expect(action["description"] as? String == ContentCredentialsManifest.description(of: file))
        let signature = try #require(manifest["signature_info"] as? [String: Any])
        #expect(signature["common_name"] as? String == SelfIssuedCertificate.commonName)
        // No title, thumbnail, ingredient or time: nothing that could identify the person.
        for key in ["title", "thumbnail", "ingredients", "credentials"] {
            #expect((manifest[key] as? [Any])?.isEmpty ?? (manifest[key] == nil), "unexpected \(key)")
        }
        #expect(signature["time"] == nil)
    }

    @Test(arguments: SignableFile.allCases)
    func oneBitChangeInTheImageFailsValidation(file: SignableFile) async throws {
        let signed = try await signer.sign(SyntheticPhotos.data(for: file), as: file)
        // A byte inside the image data: the DNG's pixel strip keeps its offset (182) after
        // signing; the HEIF's media data and the JPEG's scan data end the file.
        let index =
            switch file.container {
            case .dng: 200
            case .heif: signed.count - 1
            case .jpeg: signed.count - 3
            }
        let report = Report(try validate(flippingBit(of: signed, at: index), as: file))
        #expect(report.state == "Invalid")
        #expect(report.codes("failure").contains("\(hashCode(for: file)).mismatch"))
    }

    @Test(arguments: SignableFile.allCases)
    func oneBitChangeInTheClaimFailsValidation(file: SignableFile) async throws {
        let signed = try await signer.sign(SyntheticPhotos.data(for: file), as: file)
        // The instance ID is written once, inside the signed claim.
        let instanceID = try #require(Report(try validate(signed, as: file)).manifest["instance_id"] as? String)
        let range = try #require(signed.range(of: Data(instanceID.utf8)))
        let tampered = flippingBit(of: signed, at: range.upperBound - 1 - signed.startIndex)
        let report = Report(try validate(tampered, as: file))
        #expect(report.state == "Invalid")
        #expect(report.codes("failure").contains("claimSignature.mismatch"))
    }

    @Test func everyFileGetsANewKeyCertificateAndInstanceID() async throws {
        let keys = CountingKeyProvider()
        let signer = ContentCredentialsSigner(keyProvider: keys, generator: ClaimGenerator(version: "0.1.0"))
        let photo = SyntheticPhotos.data(for: .developedJPEG)
        let first = Report(try validate(try await signer.sign(photo, as: .developedJPEG), as: .developedJPEG))
        let second = Report(try validate(try await signer.sign(photo, as: .developedJPEG), as: .developedJPEG))
        #expect(keys.count == 2)
        #expect(first.manifest["instance_id"] as? String != second.manifest["instance_id"] as? String)
        let firstSerial = (first.manifest["signature_info"] as? [String: Any])?["cert_serial_number"] as? String
        let secondSerial = (second.manifest["signature_info"] as? [String: Any])?["cert_serial_number"] as? String
        #expect(firstSerial != nil)
        #expect(firstSerial != secondSerial)
    }

    @Test func missingKeyIsReported() async {
        let signer = ContentCredentialsSigner(keyProvider: FailingKeyProvider(), generator: ClaimGenerator(version: "0.1.0"))
        await #expect(throws: PhotoSigningError.keyCreationFailed) {
            try await signer.sign(SyntheticPhotos.data(for: .singleFrameRAW), as: .singleFrameRAW)
        }
    }

    @Test func failedClaimSignatureIsReported() async {
        let signer = ContentCredentialsSigner(
            keyProvider: FailingClaimKeyProvider(), generator: ClaimGenerator(version: "0.1.0"))
        await #expect(throws: PhotoSigningError.signingFailed) {
            try await signer.sign(SyntheticPhotos.data(for: .developedJPEG), as: .developedJPEG)
        }
        #expect(throws: FailingClaimKey.Busy.self) { try FailingClaimKey().signatureDER(for: Data()) }
    }

    @Test(arguments: SignableFile.allCases)
    func bytesThatArentThatKindOfFileAreReported(file: SignableFile) async {
        await #expect(throws: PhotoSigningError.signingFailed) {
            try await signer.sign(Data("not a photo".utf8), as: file)
        }
    }

    @Test func signingAddsOnlyTheContentCredentialsStore() async throws {
        // JPEG: exactly one new APP11 segment; every other segment is unchanged and in order.
        let jpeg = SyntheticPhotos.data(for: .developedJPEG)
        let signedJPEG = try await signer.sign(jpeg, as: .developedJPEG)
        let before = JPEGSegments.markers(jpeg)
        let after = JPEGSegments.markers(signedJPEG)
        #expect(after.filter { $0 != ContentCredentialsStore.jpegMarker } == before)
        #expect(after.contains(ContentCredentialsStore.jpegMarker))
        #expect(!before.contains(ContentCredentialsStore.jpegMarker))

        // HEIF: one new top-level uuid box with the C2PA UUID; the other boxes are unchanged.
        let heif = SyntheticPhotos.data(for: .developedHEIF)
        let signedHEIF = try await signer.sign(heif, as: .developedHEIF)
        let heifBefore = HEIFBoxes.topLevel(heif)
        let heifAfter = HEIFBoxes.topLevel(signedHEIF)
        #expect(heifAfter.filter { $0 != "uuid" } == heifBefore)
        #expect(heifAfter.filter { $0 == "uuid" }.count == 1)
        #expect(HEIFBoxes.uuids(signedHEIF) == [ContentCredentialsStore.heifBoxUUID])

        // DNG: IFD0 gains exactly tag 52545, type UNDEFINED; every other tag is unchanged.
        let dng = SyntheticPhotos.data(for: .singleFrameRAW)
        let signedDNG = try await signer.sign(dng, as: .singleFrameRAW)
        let tagsBefore = TIFFTags.firstIFD(dng)
        let tagsAfter = TIFFTags.firstIFD(signedDNG)
        #expect(tagsAfter.filter { $0.tag != ContentCredentialsStore.dngTag } == tagsBefore)
        #expect(tagsAfter.filter { $0.tag == ContentCredentialsStore.dngTag }.map(\.type) == [7])
    }
}
