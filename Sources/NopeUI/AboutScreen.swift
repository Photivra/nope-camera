import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// The app's numeric App Store ID, from which the About screen builds its Rate or Review
    /// link, or `nil` while there is none, which hides the row and its search entry
    /// (`docs/store/STORE-PAGE-PLAN.md`, section 12). ``AboutScreen/appStoreID`` by default; the
    /// app's UI tests set a test id, or simulate none, in Debug builds
    /// (`-NopeSimulatedAppStoreID <digits>` or `none`).
    @Entry public var appStoreID: String? = AboutScreen.appStoreID
}

/// About and licenses: the version, the How to Use nope. row (issue #117), the GPL-3.0-only license text, the project's notices
/// (including the Adobe DNG notice) and where the source code is.
///
/// The license and notice texts are bundled copies of the repository's `LICENSE` and `NOTICE`
/// (`Resources/GPL-3.0.txt` and `Resources/NOTICE.txt`); a unit test keeps them identical. They
/// are legal texts, shown exactly as written and not translated (AGENTS.md, "Keep every
/// notice"). The privacy policy and the source address are links: tapping one hands its `https`
/// address to the system, which opens it in the browser. The app itself makes no network
/// request and has no web view (AGENTS.md, "Prevention first"). App Review Guideline 5.1.1(i)
/// asks for the privacy policy to be reachable within the app.
///
/// The last section, App Store, has one link, Rate or Review, that hands the App Store's
/// write-review address to the system, which opens the App Store. It is a plain link the person
/// taps: the app never asks for a rating, uses no StoreKit review request, and stores nothing
/// about whether the row was tapped (`docs/store/STORE-PAGE-PLAN.md`, section 12). The section
/// shows only once ``appStoreID`` is set, so no dead link ships.
struct AboutScreen: View {
    /// The app's numeric App Store ID ("Apple ID" in App Store Connect, App Information), or
    /// `nil` until the app's App Store record exists. It is not secret. While it is `nil` the
    /// Rate or Review row is hidden, and `scripts/check-app-store-id.sh`, run before each release,
    /// fails.
    nonisolated static let appStoreID: String? = "6838151647"

    /// The App Store's write-review address for an App Store ID:
    /// `https://apps.apple.com/app/id<ID>?action=write-review`.
    ///
    /// The `action=write-review` form is not verified until it can be opened for a live app; it
    /// is a device check after the first release (`docs/TESTING.md`).
    ///
    /// - Parameter appStoreID: The numeric App Store ID, or `nil`.
    /// - Returns: The address, or `nil` without an id or for one that isn't all ASCII digits.
    static func rateAddress(appStoreID: String?) -> String? {
        guard let appStoreID, !appStoreID.isEmpty, appStoreID.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return "https://apps.apple.com/app/id\(appStoreID)?action=write-review"
    }

    /// The write-review address as a URL, opened by the system when tapped.
    ///
    /// - Parameter appStoreID: The numeric App Store ID, or `nil`.
    /// - Returns: The URL, or `nil` when ``rateAddress(appStoreID:)`` is `nil`.
    static func rateURL(appStoreID: String?) -> URL? {
        rateAddress(appStoreID: appStoreID).flatMap { URL(string: $0) }
    }

    /// The write-review address for ``appStoreID``, or `nil` while it isn't set.
    static var rateAddress: String? { rateAddress(appStoreID: appStoreID) }

    /// The write-review URL for ``appStoreID``, or `nil` while it isn't set.
    static var rateURL: URL? { rateURL(appStoreID: appStoreID) }

    /// The App Store ID in use: ``appStoreID``, or the one the app's UI tests set.
    @Environment(\.appStoreID) private var currentAppStoreID

    /// The Settings navigation, or `nil` outside Settings: a search result for Rate or Review
    /// scrolls to the row, which is below the fold.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    /// The address of the source code.
    static let sourceAddress = "https://github.com/Photivra/nope-camera"

    /// The source code address as a URL, opened by the system browser when tapped.
    static let sourceURL = URL(string: sourceAddress)!

    /// The address of the privacy policy (`docs/store/privacy-policy-draft.md`).
    static let privacyPolicyAddress = "https://nope.photivra.com/privacy/"

    /// The privacy policy address as a URL, opened by the system browser when tapped.
    static let privacyPolicyURL = URL(string: privacyPolicyAddress)!

    /// The notice Adobe's DNG specification patent license requires, quoted exactly
    /// (AGENTS.md, "Third-party licenses").
    static let dngNotice = "This product includes DNG technology under license by Adobe."

    /// The device's lenses, for the how-to-use guide its How to Use nope. row opens, or none when
    /// not known.
    let lenses: [Lens]

    /// Creates the About screen.
    ///
    /// - Parameter lenses: The device's lenses, or none when not known.
    init(lenses: [Lens] = []) {
        self.lenses = lenses
    }

    /// The form.
    var body: some View {
        NopeForm {
            Section {
                LabeledContent {
                    Text(verbatim: Self.version(from: Bundle.main.infoDictionary ?? [:]))
                } label: {
                    Text("Version", bundle: .module, comment: "Label for the app's version number.")
                }
                // The guide's own title, as in Settings › More, so the two rows read the same
                // (owner decision 6 for issue #117).
                GuideRow(id: .aboutHowToUse, lenses: lenses)
            } header: {
                Text(verbatim: "Photivra Nope Camera")
            }
            Section {
                NavigationLink {
                    LegalTextView(resource: "GPL-3.0", title: Text(SettingsText.license))
                } label: {
                    Text(
                        "GNU General Public License, version 3 only (GPL-3.0-only)", bundle: .module,
                        comment: "Row that opens the full license text. GNU General Public License is the license's name; keep GPL-3.0-only unchanged.")
                }
                .settingsRow(.license)
                Text(
                    "Photivra Nope Camera is free software: you can redistribute it and modify it under the terms of this license.", bundle: .module,
                    comment: "Plain summary of the GPL on the About screen. Keep \"Photivra Nope Camera\" unchanged.")
                    .foregroundStyle(CameraStyle.secondaryText)
            } header: {
                Text("License", bundle: .module, comment: "Title of the screen showing the full license text.")
            }
            Section {
                Text(verbatim: Self.dngNotice)
                NavigationLink {
                    LegalTextView(resource: "NOTICE", title: Text(SettingsText.noticesAndTrademarks))
                } label: {
                    Text(SettingsText.noticesAndTrademarks)
                }
                .settingsRow(.noticesAndTrademarks)
            } header: {
                Text("Third-Party Notices", bundle: .module, comment: "Section header for notices required by other licenses.")
            } footer: {
                Text(
                    "Photivra, Nope Camera, the app icon and the wordmark are trademarks and aren't covered by the GPL.", bundle: .module,
                    comment: "Trademark statement. Keep Photivra, Nope Camera and GPL unchanged.")
            }
            Section {
                Link(destination: Self.privacyPolicyURL) {
                    Text("Privacy Policy", tableName: "Honesty", bundle: .module, comment: "Row on the About screen that opens the privacy policy in the browser. Draft for the Honesty review.")
                }
                .accessibilityHint(Text("Opens in your browser.", tableName: "Honesty", bundle: .module, comment: "Footer under the Privacy Policy row on the About screen, and the row's VoiceOver hint: the policy opens in the browser, not in the app. Draft for the Honesty review."))
                .accessibilityValue(Text(verbatim: Self.privacyPolicyAddress))
                // A link, not a button, for VoiceOver: the iOS 26.5 Simulator reports a `Link` in
                // a `Form` as a button unless the button trait is removed; the same on the other
                // two links (docs/TESTING.md).
                .accessibilityAddTraits(.isLink)
                .accessibilityRemoveTraits(.isButton)
            } footer: {
                Text("Opens in your browser.", tableName: "Honesty", bundle: .module, comment: "Footer under the Privacy Policy row on the About screen, and the row's VoiceOver hint: the policy opens in the browser, not in the app. Draft for the Honesty review.")
            }
            Section {
                Link(destination: Self.sourceURL) {
                    Text(verbatim: Self.sourceAddress)
                }
                .accessibilityLabel(Text("Source code address", bundle: .module, comment: "VoiceOver name of the web address of the source code."))
                .accessibilityValue(Text(verbatim: Self.sourceAddress))
                .accessibilityAddTraits(.isLink)
                .accessibilityRemoveTraits(.isButton)
            } header: {
                Text("Source Code", bundle: .module, comment: "Section header for where to find the app's source code.")
            } footer: {
                Text(
                    "Opens in your browser. Photivra Nope Camera itself makes no network connections.", bundle: .module,
                    comment: "Footer under the source code link on the About screen. Keep \"Photivra Nope Camera\" unchanged.")
            }
            if let rateURL = Self.rateURL(appStoreID: currentAppStoreID) {
                rateSection(rateURL)
            }
        }
        .navigationTitle(Text(SettingsText.about))
        .modifier(SettingsScrollTarget(navigation: navigation, page: .about))
    }

    /// The App Store section: the Rate or Review link, last on the screen, drawn like the
    /// Privacy Policy link, with no symbol, badge or color of its own, so night mode turns it red
    /// like the other links.
    ///
    /// - Parameter url: The write-review URL.
    private func rateSection(_ url: URL) -> some View {
        Section {
            Link(destination: url) {
                Text(SettingsText.rateOrReview)
            }
            .accessibilityHint(Text("Opens the App Store.", bundle: .module, comment: "VoiceOver hint of the Rate or Review row on the About screen: tapping it leaves the app for the App Store. App Store is Apple's name; use its name in the language's iOS."))
            .accessibilityAddTraits(.isLink)
            .accessibilityRemoveTraits(.isButton)
            .settingsRow(.rateOrReview)
        } header: {
            Text("App Store", bundle: .module, comment: "Section header on the About screen above the Rate or Review row. App Store is Apple's name; use its name in the language's iOS.")
        } footer: {
            Text("Opens the App Store. Ratings and reviews there are public.", bundle: .module, comment: "Footer under the Rate or Review row on the About screen: the row leaves the app, and anything written there can be read by anyone. App Store is Apple's name; use its name in the language's iOS.")
        }
    }

    /// The version and build number from an Info.plist dictionary, such as "0.1.0 (1)".
    ///
    /// - Parameter info: The app's Info.plist values.
    /// - Returns: `CFBundleShortVersionString` and `CFBundleVersion`, or the parts present.
    static func version(from info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return "(\(build))"
        case (nil, nil): return ""
        }
    }
}

/// A bundled legal text, shown exactly as written, one paragraph at a time, in the body
/// font so it grows with Dynamic Type.
struct LegalTextView: View {
    /// The paragraphs of the text.
    let paragraphs: [String]

    /// The navigation title.
    let title: Text

    /// Creates the view for a bundled text file.
    ///
    /// - Parameters:
    ///   - resource: The name of a `.txt` file in the module's resources.
    ///   - title: The navigation title.
    init(resource: String, title: Text) {
        paragraphs = Self.paragraphs(of: Self.text(named: resource))
        self.title = title
    }

    /// The text in a scrolling, selectable column.
    ///
    /// The column is lazy: only the paragraphs on screen are laid out and in the accessibility
    /// tree. The license is about 160,000 points tall at the largest text size; laid out whole,
    /// the CI test that audits this screen took 770 seconds and the audit's Dynamic Type check
    /// failed on the first paragraph (build 43786103024). Lazy, the audit at the largest size
    /// takes about 8 seconds on a local Simulator. VoiceOver still reads on through the text,
    /// which scrolls as it goes.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NopeSpace.s) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(verbatim: paragraphs[index])
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .padding(NopeSpace.m)
        }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }

    /// Reads a bundled text file.
    ///
    /// - Parameter name: The file name without `.txt`.
    /// - Returns: The file's text, or an empty string if it is missing.
    static func text(named name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    /// The shortest line, in characters, that counts as hard-wrapped running text. The license
    /// files wrap their prose at about 72 characters; shorter lines are headings, titles or
    /// list entries and keep their line breaks.
    static let wrappedLineLength = 60

    /// Splits a text into paragraphs at blank lines, removes the spaces that indent or center
    /// each line, and rejoins prose that the plain-text file wrapped by hand, so the text wraps
    /// to the screen at every text size. The words are unchanged.
    ///
    /// - Parameter text: The text.
    /// - Returns: The non-empty paragraphs, in order.
    static func paragraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                let lines = paragraph.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let isWrappedProse = lines.dropLast().allSatisfy { $0.count >= wrappedLineLength }
                return lines.joined(separator: isWrappedProse ? " " : "\n")
            }
            .filter { !$0.isEmpty }
    }
}
