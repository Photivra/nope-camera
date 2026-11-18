import NopeCore
import SwiftUI

/// Content Credentials (`docs/design/BUILD-SPEC.md`, 3.15, group 7): the signature sentence with
/// its symbol; for a signed photo, what the signature shows, each file's manifest (claim
/// generator, the manifest's own words, its SHA-256 behind a disclosure row) and how to check a
/// file; for an unsigned photo, the reason.
struct ContentCredentialsSection: View {
    /// The details.
    let details: PhotoDetails

    /// Creates the group.
    ///
    /// - Parameter details: The details.
    init(details: PhotoDetails) {
        self.details = details
    }

    /// The group.
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: NopeSpace.s) {
                SymbolLine(
                    text: Text(verbatim: CaptureMessages.message(for: details.signature)),
                    symbol: PhotoDetailsSections.signatureSymbol(details.signature),
                    style: PhotoDetailsSections.signatureStyle(details.signature))
                Self.explanation(of: details.signature)
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                if let credentials = file.contentCredentials {
                    VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                        Text(verbatim: FormatsSettingsView.name(of: file.format))
                        Text(
                            "Claim generator: \(credentials.generatorName) \(credentials.generatorVersion)", tableName: "Honesty", bundle: .module,
                            comment: "In the photo details: the software the Content Credentials manifest names as its claim generator. The values are a name and a version, such as Photivra Nope Camera 0.2.0.")
                            .foregroundStyle(CameraStyle.secondaryText)
                        // The manifest's own words, which are part of the file and stay in English.
                        Text(Self.manifestWords(credentials.actionDescription))
                            .font(.footnote)
                            .foregroundStyle(CameraStyle.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    DisclosureGroup {
                        Text(verbatim: credentials.manifestSHA256)
                            .font(.footnote.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text("Manifest SHA-256", tableName: "Honesty", bundle: .module, comment: "Disclosure row in the photo details: opens the SHA-256 hash of the file's Content Credentials manifest, as 64 hexadecimal digits. SHA-256 is a standard name; keep it unchanged.")
                    }
                    .accessibilityInputLabels([
                        Text("Manifest SHA-256", tableName: "Honesty", bundle: .module, comment: "Disclosure row in the photo details: opens the SHA-256 hash of the file's Content Credentials manifest, as 64 hexadecimal digits. SHA-256 is a standard name; keep it unchanged."),
                        Text("Manifest SHA-256, \(FormatsSettingsView.name(of: file.format))", tableName: "Honesty", bundle: .module, comment: "Voice Control name of the Manifest SHA-256 row of one file in the photo details. The placeholder is the file's format, such as RAW (DNG). SHA-256 is a standard name; keep it unchanged."),
                    ])
                }
            }
            if details.signature == .signed {
                Text("To check a file, open it in a Content Credentials checker. Each photo is signed with its own one-time key, so a checker reports the file as valid and the signer as untrusted.", tableName: "Honesty", bundle: .module, comment: "In the photo details, under a signed photo's manifests: how to check a file. Names no product. Must be checked against the checker people are most likely to use before it ships. Draft wording for the Honesty review.")
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Content Credentials", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: the photo's Content Credentials signature. Content Credentials is the name of the C2PA standard's signatures. Draft wording for the Honesty review.")
        }
    }

    /// The manifest's own words in quotation marks, marked as English for the speech voice: they
    /// are part of the file and aren't translated.
    ///
    /// - Parameter words: The manifest's action description.
    /// - Returns: The text.
    static func manifestWords(_ words: String) -> AttributedString {
        var text = AttributedString("“\(words)”")
        text.languageIdentifier = "en"
        return text
    }

    /// What the signature shows, or why there is none.
    ///
    /// - Parameter signature: The photo's signature status.
    /// - Returns: The sentence, from `Honesty.xcstrings`.
    static func explanation(of signature: SignatureStatus) -> Text {
        switch signature {
        case .signed:
            Text("The signature lets anyone check that a file hasn't changed since nope. saved it. It doesn't show who took the photo or on which device.", tableName: "Honesty", bundle: .module, comment: "In the photo details, under a signed photo: what the Content Credentials signature shows and doesn't show. Keep nope. unchanged. Draft wording for the Honesty review.")
        case .unsigned(.turnedOff):
            Text("Sign Each Photo is off in Settings, so these files have no signature.", tableName: "Honesty", bundle: .module, comment: "In the photo details: the photo isn't signed because the person turned the Sign Each Photo setting off. Not a warning. Draft wording for the Honesty review.")
        case .unsigned(.failed):
            Text("Signing was on, but nope. couldn't create the signature for this photo. The files were saved without one. The camera shows Not Signed until a photo is signed again.", tableName: "Honesty", bundle: .module, comment: "In the photo details: signing was on but failed for this photo, so it was saved unsigned. Not Signed is the warning chip on the camera. Keep nope. unchanged. Draft wording for the Honesty review.")
        case .unsigned(.unavailable):
            Text("Signing was on, but this version of the app can't sign photos. The files were saved without a signature.", tableName: "Honesty", bundle: .module, comment: "In the photo details: signing was on, but this build of the app has no signer, so the photo was saved unsigned. Draft wording for the Honesty review.")
        case .unsigned(.signedFileFailedCheck):
            Text("Signing was on, but the signed file didn't pass nope.'s check, so the file that passed was saved without a signature. The camera shows Not Signed until a photo is signed again.", tableName: "Honesty", bundle: .module, comment: "In the photo details: a signed file failed the read-back check, so the unsigned file, which passed, was saved instead. Not Signed is the warning chip on the camera. Keep nope. unchanged. Draft wording for the Honesty review.")
        }
    }
}
