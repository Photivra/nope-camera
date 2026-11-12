// Compiled for the iOS Simulator only. The Simulator has no Secure Enclave, so tests and Simulator
// builds sign with CryptoKit's software P-256 key. This guard keeps the software key out of every
// device build, Debug and Release, so a device can only sign with the Secure Enclave
// (docs/PRIVACY.md, "Content Credentials").
#if targetEnvironment(simulator)
import CryptoKit
import Foundation
import X509

/// Creates a software P-256 key for each file, in the Simulator only.
///
/// The type doesn't exist in device builds: its file is compiled only when
/// `targetEnvironment(simulator)` is true.
public struct SimulatorSoftwareKeyProvider: SigningKeyProvider {
    /// Creates the provider.
    public init() {}

    /// Creates a new software P-256 key.
    ///
    /// - Returns: The new key. It never fails.
    public func makeKey() throws -> any PerPhotoSigningKey {
        SimulatorSoftwareSigningKey()
    }
}

/// A software P-256 key that stands in for the Secure Enclave in the Simulator.
struct SimulatorSoftwareSigningKey: PerPhotoSigningKey {
    /// The CryptoKit key, created at random.
    let key: P256.Signing.PrivateKey

    /// Creates a new random software key.
    init() {
        key = P256.Signing.PrivateKey()
    }

    /// The key in swift-certificates' form, for the self-issued certificate.
    var certificateKey: Certificate.PrivateKey {
        Certificate.PrivateKey(key)
    }

    /// Signs data in software.
    ///
    /// - Parameter data: The bytes to sign.
    /// - Returns: The ES256 signature in DER form.
    func signatureDER(for data: Data) throws -> Data {
        try key.signature(for: data).derRepresentation
    }
}
#endif
