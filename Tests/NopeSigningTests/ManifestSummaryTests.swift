import Foundation
import NopeCore
import Testing

@testable import NopeSigning

/// The manifest summary each signed file carries for the "What's in this photo" details
/// (issue #53).
@Suite(.timeLimit(.minutes(1)))
struct ManifestSummaryTests {
    let signer = ContentCredentialsSigner(
        keyProvider: SimulatorSoftwareKeyProvider(), generator: ClaimGenerator(version: "0.2.0"))

    @Test(arguments: SignableFile.allCases)
    func aSignedFileSummarizesItsManifest(file: SignableFile) async throws {
        let unsigned = PhotoFile(
            format: file.format, data: SyntheticPhotos.data(for: file), isProcessedByDevice: file.isProcessedByDevice)
        let first = try #require(try await signer.sign(unsigned).contentCredentials)
        #expect(first.generatorName == "Photivra Nope Camera")
        #expect(first.generatorVersion == "0.2.0")
        #expect(first.actionDescription == ContentCredentialsManifest.description(of: file))
        #expect(first.manifestSHA256.count == 64)
        #expect(first.manifestSHA256.allSatisfy { "0123456789abcdef".contains($0) })
        // A new key and instance ID for every file, so every manifest store, and its hash, differs.
        let second = try #require(try await signer.sign(unsigned).contentCredentials)
        #expect(second.manifestSHA256 != first.manifestSHA256)
    }

    @Test func theHashIsTheStoresSHA256() {
        // SHA-256 of the three bytes "abc" (FIPS 180-2, appendix B.1).
        let summary = signer.summary(of: .developedJPEG, manifestStore: Data("abc".utf8))
        #expect(summary.manifestSHA256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
