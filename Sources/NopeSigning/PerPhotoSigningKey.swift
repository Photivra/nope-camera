import Foundation
import X509

/// A P-256 private key that signs one file and is then discarded.
///
/// On a device it is a Secure Enclave key (`SecureEnclaveSigningKey.swift`); in the Simulator,
/// which has no Secure Enclave, it is a software key (`SimulatorSoftwareSigningKey.swift`, compiled
/// for the Simulator only). The key signs twice: once for the file's self-issued certificate, and
/// once for the C2PA claim.
///
/// Privacy rule: a key is created for one file and never stored, so no two files can be linked
/// through their signatures (AGENTS.md, "Honesty").
public protocol PerPhotoSigningKey: Sendable {
    /// The key in the form swift-certificates uses to sign the self-issued certificate. Its
    /// public key goes into the certificate.
    var certificateKey: Certificate.PrivateKey { get }

    /// Signs data with ECDSA P-256 and SHA-256 (ES256).
    ///
    /// The C2PA library's signer callback takes a DER-encoded ECDSA signature
    /// (docs/research/c2pa-signing.md, "Signing with a Secure Enclave key").
    ///
    /// - Parameter data: The bytes to sign: the C2PA claim's signing input.
    /// - Returns: The signature in DER form.
    /// - Throws: The key's error if signing fails, for example when the Secure Enclave is busy.
    func signatureDER(for data: Data) throws -> Data
}

/// Creates a new ``PerPhotoSigningKey`` for each file.
///
/// The app uses ``SecureEnclaveKeyProvider`` on a device. Use ``platformKeyProvider()`` to get the
/// right provider for the build: the Secure Enclave on a device, and a software key only in the
/// Simulator.
public protocol SigningKeyProvider: Sendable {
    /// Creates a new key, used for one file and then discarded.
    ///
    /// - Returns: A key that no other file uses.
    /// - Throws: An error when no key can be created, for example when the Secure Enclave is
    ///   unavailable.
    func makeKey() throws -> any PerPhotoSigningKey
}
