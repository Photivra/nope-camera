import CryptoKit
import Foundation
import X509

/// Lets a Secure Enclave key sign photos.
///
/// This is a hardware adapter: the Secure Enclave doesn't exist in the iOS Simulator, so this
/// file is listed in `scripts/coverage-exclusions.txt` and verified on a device. The private key
/// never leaves the Secure Enclave.
extension SecureEnclave.P256.Signing.PrivateKey: PerPhotoSigningKey {
    /// The key in swift-certificates' form, for the self-issued certificate.
    public var certificateKey: Certificate.PrivateKey {
        Certificate.PrivateKey(self)
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

/// Creates a new Secure Enclave key for each file.
///
/// Privacy rule: the key is created without access control or a keychain entry, and its
/// `dataRepresentation` is never read or stored, so it can't be used again once the signer
/// releases it (AGENTS.md, "Honesty"; issue #1, "Signing"). No App Attest and no network: the key
/// is anonymous and proves nothing about the device.
///
/// Requires a device with a Secure Enclave. In the Simulator, ``makeKey()`` throws.
public struct SecureEnclaveKeyProvider: SigningKeyProvider {
    /// Creates the provider.
    public init() {}

    /// Creates a new P-256 key in the Secure Enclave.
    ///
    /// - Returns: The new key.
    /// - Throws: A CryptoKit error when the Secure Enclave is unavailable or refuses.
    public func makeKey() throws -> any PerPhotoSigningKey {
        try SecureEnclave.P256.Signing.PrivateKey()
    }
}
