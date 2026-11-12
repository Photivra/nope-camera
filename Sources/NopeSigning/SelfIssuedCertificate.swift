import Foundation
import SwiftASN1
import X509

/// Builds the anonymous, self-issued X.509 certificate that carries one file's public key.
///
/// The certificate is signed by the file's own one-use key, so it isn't chained to any
/// certificate authority. Validators therefore show the signer as untrusted or unknown
/// (C2PA specification 2.2, §15.7, `signingCredential.untrusted`). That is expected and honest:
/// the signature proves the file hasn't changed since nope. signed it, not who took it
/// (docs/research/c2pa-signing.md, "Certificates and trust").
///
/// Privacy rule: every field except the key and the random serial number is the same for every
/// file and every person, so the certificate identifies no one and links no two files
/// (docs/PRIVACY.md, "Content Credentials"):
/// - the subject and issuer are only the common name ``commonName``;
/// - the validity is a fixed range, ``notValidBefore`` to ``notValidAfter``, so it doesn't
///   reveal when the photo was taken;
/// - there is no email address, location, organization or device detail.
enum SelfIssuedCertificate {
    /// The certificate's subject and issuer common name, the same for every file.
    static let commonName = "Photivra Nope Camera anonymous signer"

    /// The start of the fixed validity range: 2000-01-01 00:00:00 UTC.
    ///
    /// A fixed range keeps the capture time out of the certificate. With no timestamp,
    /// validators check the certificate against the current time (C2PA 2.2, §15.8.2), so the range
    /// covers any plausible checking date.
    static let notValidBefore = Date(timeIntervalSince1970: 946_684_800)

    /// The end of the fixed validity range: 2099-12-31 23:59:59 UTC.
    static let notValidAfter = Date(timeIntervalSince1970: 4_102_444_799)

    /// The C2PA signing extended key usage, `1.3.6.1.4.1.62558.2.1` (C2PA 2.2, §14.5.1).
    static let c2paSigningUsage: ASN1ObjectIdentifier = [1, 3, 6, 1, 4, 1, 62558, 2, 1]

    /// Creates the certificate for one key, in PEM form.
    ///
    /// The certificate profile follows C2PA 2.2, §14.5: X.509 v3, not a certificate authority,
    /// `digitalSignature` key usage, and the C2PA signing extended key usage with
    /// `emailProtection` for compatibility. It also carries subject and authority key
    /// identifiers, which the C2PA library requires (c2pa-rs, `certificate_profile.rs`).
    ///
    /// - Parameter key: The file's one-use key. It signs the certificate and its public key goes
    ///   into it.
    /// - Returns: The certificate as a PEM string.
    /// - Throws: An error from swift-certificates if the key can't sign or the certificate can't
    ///   be encoded.
    static func pem(for key: any PerPhotoSigningKey) throws -> String {
        let privateKey = key.certificateKey
        let name = try DistinguishedName {
            CommonName(commonName)
        }
        // The key identifier is the SHA-1 hash of this file's one-use public key (RFC 5280,
        // §4.2.1.2, method 1), so it identifies nothing beyond that key. The C2PA library requires
        // an authority key identifier on every signing certificate, including a self-issued one.
        let keyIdentifier = SubjectKeyIdentifier(hash: privateKey.publicKey)
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            keyIdentifier
            AuthorityKeyIdentifier(keyIdentifier: keyIdentifier.keyIdentifier)
            Critical(KeyUsage(digitalSignature: true))
            try ExtendedKeyUsage([
                ExtendedKeyUsage.Usage(oid: c2paSigningUsage),
                .emailProtection,
            ])
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: privateKey.publicKey,
            notValidBefore: notValidBefore,
            notValidAfter: notValidAfter,
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: privateKey
        )
        return try certificate.serializeAsPEM().pemString
    }
}
