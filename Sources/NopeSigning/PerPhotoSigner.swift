import Foundation

/// Signs each photo with a fresh key that is never reused.
///
/// Privacy rule: a new key for every photo means no two photos can be linked through their
/// signatures (AGENTS.md, "Honesty"; issue #1, "Signing"). The signer keeps no reference to any
/// key after ``sign(_:)`` returns.
public struct PerPhotoSigner: Sendable {
    /// Creates a new private key. Called once per photo.
    public typealias KeyFactory = @Sendable () throws -> any PerPhotoSigningKey

    /// The factory that creates one key per call to ``sign(_:)``.
    private let makeKey: KeyFactory

    /// Creates a signer.
    ///
    /// - Parameter makeKey: Creates a new private key. In the app it creates a Secure Enclave key.
    public init(makeKey: @escaping KeyFactory) {
        self.makeKey = makeKey
    }

    /// Signs one photo's data with a newly created key.
    ///
    /// - Parameter data: The bytes to sign, for example a C2PA claim.
    /// - Returns: The signature and the public key that verifies it.
    /// - Throws: ``SigningError/keyCreationFailed`` if no key could be created, or
    ///   ``SigningError/signingFailed`` if the key couldn't sign. Interfaces present both as
    ///   "not signed", which is a warning that is never hidden.
    public func sign(_ data: Data) throws(SigningError) -> SignedData {
        let key: any PerPhotoSigningKey
        do {
            key = try makeKey()
        } catch {
            throw .keyCreationFailed
        }
        do {
            return SignedData(signatureDER: try key.signatureDER(for: data), publicKeyDER: key.publicKeyDER)
        } catch {
            throw .signingFailed
        }
    }
}

/// A signature and the public key that verifies it.
public struct SignedData: Equatable, Sendable {
    /// The ES256 signature in DER form.
    public let signatureDER: Data

    /// The one-use public key in DER form.
    public let publicKeyDER: Data

    /// Pairs a signature with its public key. Only ``PerPhotoSigner`` creates signed data.
    ///
    /// - Parameters:
    ///   - signatureDER: The ES256 signature in DER form.
    ///   - publicKeyDER: The public key that verifies it, in DER form.
    init(signatureDER: Data, publicKeyDER: Data) {
        self.signatureDER = signatureDER
        self.publicKeyDER = publicKeyDER
    }
}

/// Why a photo couldn't be signed.
///
/// An unsigned photo is never saved silently: the interface shows a "not signed" warning.
public enum SigningError: Error, Equatable, Sendable {
    /// A new key couldn't be created, for example because the Secure Enclave is unavailable.
    case keyCreationFailed

    /// The key couldn't produce a signature.
    case signingFailed
}
