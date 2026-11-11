import CryptoKit
import Foundation

/// Lets a Secure Enclave key sign photos.
///
/// This is a hardware adapter: the Secure Enclave doesn't exist in the iOS Simulator, so this
/// file is listed in `scripts/coverage-exclusions.txt` and verified on a device. The private key
/// never leaves the Secure Enclave.
extension SecureEnclave.P256.Signing.PrivateKey: PerPhotoSigningKey {
    /// The public key in DER form.
    public var publicKeyDER: Data {
        publicKey.derRepresentation
    }

    /// Signs data inside the Secure Enclave.
    ///
    /// - Parameter data: The bytes to sign.
    /// - Returns: The ES256 signature in DER form.
    /// - Throws: A CryptoKit error if the Secure Enclave can't sign.
    public func signatureDER(for data: Data) throws -> Data {
        try signature(for: data).derRepresentation
    }
}
