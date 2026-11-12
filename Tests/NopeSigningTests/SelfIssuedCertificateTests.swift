import CryptoKit
import Foundation
import SwiftASN1
import Testing
import X509

@testable import NopeSigning

// A hang fails the test with its name instead of stalling the whole run.
@Suite(.timeLimit(.minutes(1)))
struct SelfIssuedCertificateTests {
    let key = SimulatorSoftwareSigningKey()

    func certificate() throws -> Certificate {
        try Certificate(pemEncoded: SelfIssuedCertificate.pem(for: key))
    }

    @Test func subjectAndIssuerAreOnlyTheGenericName() throws {
        let certificate = try certificate()
        let expected = try DistinguishedName { CommonName("Photivra Nope Camera anonymous signer") }
        #expect(certificate.subject == expected)
        #expect(certificate.issuer == expected)
        #expect(certificate.version == .v3)
    }

    @Test func validityIsTheSameFixedRangeForEveryFile() throws {
        let certificate = try certificate()
        #expect(certificate.notValidBefore == Date(timeIntervalSince1970: 946_684_800))  // 2000-01-01
        #expect(certificate.notValidAfter == Date(timeIntervalSince1970: 4_102_444_799))  // 2099-12-31
    }

    @Test func profileFollowsC2PA() throws {
        let certificate = try certificate()
        let extensions = certificate.extensions
        #expect(try extensions.basicConstraints == .notCertificateAuthority)
        #expect(extensions[oid: .X509ExtensionID.basicConstraints]?.critical == true)
        #expect(try extensions.keyUsage == KeyUsage(digitalSignature: true))
        #expect(extensions[oid: .X509ExtensionID.keyUsage]?.critical == true)
        let usages = try #require(try extensions.extendedKeyUsage)
        #expect(Array(usages) == [ExtendedKeyUsage.Usage(oid: [1, 3, 6, 1, 4, 1, 62558, 2, 1]), .emailProtection])
        let subjectKeyID = try #require(try extensions.subjectKeyIdentifier)
        #expect(try extensions.authorityKeyIdentifier?.keyIdentifier == subjectKeyID.keyIdentifier)
        #expect(certificate.signatureAlgorithm == .ecdsaWithSHA256)
        #expect(extensions.count == 5)
    }

    @Test func carriesTheKeyAndIsSignedByIt() throws {
        let certificate = try certificate()
        #expect(certificate.publicKey == key.certificateKey.publicKey)
        #expect(certificate.publicKey.isValidSignature(certificate.signature, for: certificate))
    }

    @Test func serialNumbersDiffer() throws {
        #expect(try certificate().serialNumber != certificate().serialNumber)
    }
}
