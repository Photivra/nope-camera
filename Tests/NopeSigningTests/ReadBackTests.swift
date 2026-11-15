import Foundation
import NopeCore
import NopeDevelop
import Testing

@testable import NopeSigning

/// Signed files pass the save pipeline's read-back exactly as their unsigned originals do: the
/// only thing signing adds is the Content Credentials item the signed allowlist names
/// (`MetadataPlan.allowlist(for:signed:)`), and a DNG's RAW image data doesn't change.
@Suite(.timeLimit(.minutes(1)))
struct ReadBackTests {
    let signer = ContentCredentialsSigner(
        keyProvider: SimulatorSoftwareKeyProvider(), generator: ClaimGenerator(version: "0.1.0"))

    /// The app's read-back: the project's own reader plus ImageIO, which must open the file as
    /// exactly one image of its format (issue #66: a DNG signed by the C2PA library's own writer
    /// opened as `public.tiff` with no image).
    func readBack(_ file: PhotoFile) throws -> MetadataReadBack {
        try ImageIOReadBack().readBack(file)
    }

    @Test(arguments: SignableFile.allCases)
    func signingAddsNoViolation(kind: SignableFile) async throws {
        let plan = MetadataPlan()
        let original = PhotoFile(
            format: kind.format, data: SyntheticPhotos.data(for: kind), isProcessedByDevice: kind.isProcessedByDevice)
        let signed = try await signer.sign(original)
        let before = try readBack(original)
        let after = try readBack(signed)

        let unsignedViolations = MetadataVerifier.violations(
            in: before, allowlist: plan.allowlist(for: kind.format, signed: false),
            expectedRawImageData: before.file.rawImageData)
        let signedViolations = MetadataVerifier.violations(
            in: after, allowlist: plan.allowlist(for: kind.format, signed: true),
            expectedRawImageData: before.file.rawImageData)
        #expect(signedViolations == unsignedViolations)

        // The manifest is found, and only the signed allowlist permits it.
        let asIfUnsigned = MetadataVerifier.violations(
            in: after, allowlist: plan.allowlist(for: kind.format, signed: false),
            expectedRawImageData: before.file.rawImageData)
        #expect(asIfUnsigned.count == unsignedViolations.count + 1)
        if kind.format == .raw {
            #expect(after.file.rawImageData == before.file.rawImageData)
            #expect(after.file.rawImageData != nil)
        }
    }
}
