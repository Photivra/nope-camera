import C2PA
import Foundation
import NopeCore

/// Signs each file with C2PA Content Credentials, using a new key for every file, fully offline.
///
/// For each call to ``sign(_:)``:
/// 1. the key provider creates a new P-256 key (the Secure Enclave on a device);
/// 2. the key signs an anonymous, self-issued certificate for itself (``SelfIssuedCertificate``);
/// 3. the C2PA library embeds a manifest (``ContentCredentialsManifest``) and the key signs the
///    claim (ES256), with no timestamp authority and no network (``OfflineC2PAContext``);
/// 4. the key is released and never used again.
///
/// Privacy rule: nothing in the signature identifies the person or the device, and no two files
/// share a key, certificate or instance ID (docs/PRIVACY.md, "Content Credentials"). The
/// certificate isn't chained to a trusted certificate authority, so validators show the signer
/// as untrusted; the signature proves the file is unchanged, not who took it.
///
/// Threading: the work is synchronous and CPU-bound (it hashes the whole file); call it off the
/// main actor. The type holds no mutable state, so one signer can serve concurrent calls.
public struct ContentCredentialsSigner: PhotoSigning {
    /// Creates each file's key.
    private let keyProvider: any SigningKeyProvider

    /// Photivra Nope Camera and its version, written into every manifest.
    private let generator: ClaimGenerator

    /// Creates a signer.
    ///
    /// - Parameters:
    ///   - keyProvider: Creates one key per file. Pass ``platformKeyProvider()`` in the app.
    ///   - generator: Photivra Nope Camera and its version, written into every manifest.
    public init(keyProvider: any SigningKeyProvider, generator: ClaimGenerator) {
        self.keyProvider = keyProvider
        self.generator = generator
    }

    /// Signs one file.
    ///
    /// - Parameter file: The complete file, with its final metadata.
    /// - Returns: The same file with a Content Credentials manifest embedded in the one place
    ///   its format allows (see `SignableFile.mediaType`); nothing else in the file changes.
    /// - Throws: ``PhotoSigningError/keyCreationFailed`` if no key could be created, or
    ///   ``PhotoSigningError/signingFailed`` if the certificate, the claim signature or the
    ///   C2PA library failed, for example because the bytes aren't a valid file of that kind.
    public func sign(_ file: PhotoFile) async throws(PhotoSigningError) -> PhotoFile {
        let kind = SignableFile(file)
        let key: any PerPhotoSigningKey
        do {
            key = try keyProvider.makeKey()
        } catch {
            throw .keyCreationFailed
        }
        do {
            let manifest = ContentCredentialsManifest(file: kind, generator: generator, instanceID: UUID())
            let signed = try Self.embed(file.data, as: kind, manifest: manifest, key: key)
            return PhotoFile(format: file.format, data: signed, isProcessedByDevice: file.isProcessedByDevice)
        } catch {
            throw .signingFailed
        }
    }

    /// Embeds and signs a manifest with one key.
    ///
    /// - Parameters:
    ///   - data: The file.
    ///   - file: What the file is.
    ///   - manifest: The manifest to embed.
    ///   - key: The file's one-use key.
    /// - Returns: The signed file.
    /// - Throws: Any error from the certificate, the key or the C2PA library.
    static func embed(
        _ data: Data, as file: SignableFile, manifest: ContentCredentialsManifest, key: any PerPhotoSigningKey
    ) throws -> Data {
        let certificatePEM = try SelfIssuedCertificate.pem(for: key)
        let signer = try Signer(algorithm: .es256, certificateChainPEM: certificatePEM, tsa: nil) { claim in
            try key.signatureDER(for: claim)
        }
        let builder = try Builder(context: OfflineC2PAContext.make(), manifestJSON: manifest.json())
        let source = InMemoryFile(data)
        let destination = InMemoryFile()
        try builder.sign(
            format: file.mediaType, source: InMemoryStream.make(source),
            destination: InMemoryStream.make(destination), signer: signer)
        return destination.data
    }
}
