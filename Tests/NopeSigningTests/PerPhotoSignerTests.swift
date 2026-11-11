import CryptoKit
import Foundation
import NopeSigning
import Testing

/// CryptoKit's software key stands in for the Secure Enclave, which the Simulator doesn't have.
extension P256.Signing.PrivateKey: PerPhotoSigningKey {
    public var publicKeyDER: Data { publicKey.derRepresentation }
    public func signatureDER(for data: Data) throws -> Data { try signature(for: data).derRepresentation }
}

struct FailingKey: PerPhotoSigningKey {
    struct Failure: Error {}
    var publicKeyDER: Data { Data() }
    func signatureDER(for data: Data) throws -> Data { throw Failure() }
}

struct PerPhotoSignerTests {
    let photo = Data("photo bytes".utf8)

    @Test func signatureVerifiesWithReturnedKey() throws {
        let signer = PerPhotoSigner { P256.Signing.PrivateKey() }
        let signed = try signer.sign(photo)
        let publicKey = try P256.Signing.PublicKey(derRepresentation: signed.publicKeyDER)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signed.signatureDER)
        #expect(publicKey.isValidSignature(signature, for: photo))
    }

    @Test func everyPhotoGetsAFreshKey() throws {
        let signer = PerPhotoSigner { P256.Signing.PrivateKey() }
        let first = try signer.sign(photo)
        let second = try signer.sign(photo)
        #expect(first.publicKeyDER != second.publicKeyDER)
    }

    @Test func keyCreationFailureIsReported() {
        let signer = PerPhotoSigner { throw FailingKey.Failure() }
        #expect(throws: SigningError.keyCreationFailed) { try signer.sign(photo) }
    }

    @Test func signingFailureIsReported() {
        let signer = PerPhotoSigner { FailingKey() }
        #expect(throws: SigningError.signingFailed) { try signer.sign(photo) }
        #expect(FailingKey().publicKeyDER.isEmpty)
    }
}
