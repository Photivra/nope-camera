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
    /// HEIF and JPEG go through the C2PA library's own writer. A DNG goes through
    /// ``embedInDNG(_:manifest:signer:)`` instead, because the library's DNG writer moves IFD0
    /// and ImageIO can't open the result (issue #66).
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
        if file.format == .raw { return try embedInDNG(data, manifest: manifest, signer: signer) }
        let builder = try Builder(context: OfflineC2PAContext.make(), manifestJSON: manifest.json())
        let source = InMemoryFile(data)
        let destination = InMemoryFile()
        try builder.sign(
            format: file.mediaType, source: InMemoryStream.make(source),
            destination: InMemoryStream.make(destination), signer: signer)
        return destination.data
    }

    /// Signs a DNG with the C2PA data-hash workflow, keeping IFD0 in place.
    ///
    /// 1. The library makes a placeholder store of the final size.
    /// 2. ``DNGManifestSlot`` inserts tag 52545 into IFD0 and puts the placeholder at the end.
    /// 3. The library hashes the file with the store excluded (`c2pa.hash.data`, C2PA 2.2,
    ///    section 9.2) and signs the claim.
    /// 4. The signed store, the same size as the placeholder, replaces it, so the hash still holds.
    ///
    /// - Parameters:
    ///   - data: The DNG.
    ///   - manifest: The manifest to embed.
    ///   - signer: The file's one-use signer; the context takes it.
    /// - Returns: The signed DNG.
    /// - Throws: Any error from the library, or a ``DNGManifestSlot/Failure``, for example if
    ///   the signed store isn't the placeholder's size.
    static func embedInDNG(_ data: Data, manifest: ContentCredentialsManifest, signer: sending Signer) throws -> Data {
        let format = SignableFile.singleFrameRAW.mediaType
        let builder = try Builder(context: OfflineC2PAContext.make(signer: signer), manifestJSON: manifest.json())
        let placeholder = try builder.placeholder(format: format)
        let bound = try DNGManifestSlot.insert(storeLength: placeholder.count, into: data)
        let withPlaceholder = try bound.replacingStore(with: placeholder)
        try builder.setDataHashExclusions([
            (start: UInt64(bound.storeRange.lowerBound), length: UInt64(bound.storeRange.count))
        ])
        try builder.updateHashFromStream(format: format, stream: InMemoryStream.make(InMemoryFile(withPlaceholder)))
        return try bound.replacingStore(with: builder.signEmbeddable(format: format))
    }
}
