import CryptoKit
import Foundation

/// A P-256 private key that signs one photo and is then discarded.
///
/// In the app it is a Secure Enclave key (`SecureEnclave.P256.Signing.PrivateKey`, see
/// `SecureEnclaveSigningKey.swift`); tests use CryptoKit's software key. The C2PA signer callback
/// expects a DER-encoded ES256 signature (docs/research/c2pa-signing.md, "Signing with a Secure
/// Enclave key").
public protocol PerPhotoSigningKey {
    /// The public key in DER form, for the photo's self-signed certificate.
    var publicKeyDER: Data { get }

    /// Signs data with ECDSA P-256 and SHA-256 (ES256).
    ///
    /// - Parameter data: The bytes to sign.
    /// - Returns: The signature in DER form.
    /// - Throws: The key's error if signing fails, for example when the Secure Enclave is busy.
    func signatureDER(for data: Data) throws -> Data
}
