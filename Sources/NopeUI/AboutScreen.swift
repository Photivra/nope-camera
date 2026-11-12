import SwiftUI

/// About and licenses: the version, the GPL-3.0-only license text, the project's notices
/// (including the Adobe DNG notice) and where the source code is.
///
/// The license and notice texts are bundled copies of the repository's `LICENSE` and `NOTICE`
/// (`Resources/GPL-3.0.txt` and `Resources/NOTICE.txt`); a unit test keeps them identical. They
/// are legal texts, shown exactly as written and not translated (AGENTS.md, "Keep every
/// notice"). The source address is a link: tapping it hands the `https` address to the system,
/// which opens it in the browser. nope. itself makes no network request (AGENTS.md,
/// "Prevention first").
struct AboutScreen: View {
    /// The address of the source code.
    static let sourceAddress = "https://github.com/Photivra/nope-camera"

    /// The source code address as a URL, opened by the system browser when tapped.
    static let sourceURL = URL(string: sourceAddress)!

    /// The notice Adobe's DNG specification patent license requires, quoted exactly
    /// (AGENTS.md, "Third-party licenses").
    static let dngNotice = "This product includes DNG technology under license by Adobe."

    /// Creates the About screen.
    init() {}

    /// The form.
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim: Self.version(from: Bundle.main.infoDictionary ?? [:]))
                } label: {
                    Text("Version", bundle: .module, comment: "Label for the app's version number.")
                }
            } header: {
                Text(verbatim: "Photivra Nope Camera")
            }
            Section {
                NavigationLink {
                    LegalTextView(
                        resource: "GPL-3.0",
                        title: Text("License", bundle: .module, comment: "Title of the screen showing the full license text."))
                } label: {
                    Text(
                        "GNU General Public License, version 3 only (GPL-3.0-only)", bundle: .module,
                        comment: "Row that opens the full license text. GNU General Public License is the license's name; keep GPL-3.0-only unchanged.")
                }
                Text(
                    "nope. is free software: you can redistribute it and modify it under the terms of this license.", bundle: .module,
                    comment: "Plain summary of the GPL. Keep \"nope.\" unchanged.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("License", bundle: .module, comment: "Title of the screen showing the full license text.")
            }
            Section {
                Text(verbatim: Self.dngNotice)
                NavigationLink {
                    LegalTextView(
                        resource: "NOTICE",
                        title: Text("Notices and Trademarks", bundle: .module, comment: "Row and screen title for the copyright, trademark and third-party notices."))
                } label: {
                    Text("Notices and Trademarks", bundle: .module, comment: "Row and screen title for the copyright, trademark and third-party notices.")
                }
            } header: {
                Text("Third-Party Notices", bundle: .module, comment: "Section header for notices required by other licenses.")
            } footer: {
                Text(
                    "Photivra, Nope Camera, the app icon and the wordmark are trademarks and aren't covered by the GPL.", bundle: .module,
                    comment: "Trademark statement. Keep Photivra, Nope Camera and GPL unchanged.")
            }
            Section {
                Link(destination: Self.sourceURL) {
                    Text(verbatim: Self.sourceAddress)
                }
                .accessibilityLabel(Text("Source code address", bundle: .module, comment: "VoiceOver name of the web address of the source code."))
                .accessibilityValue(Text(verbatim: Self.sourceAddress))
            } header: {
                Text("Source Code", bundle: .module, comment: "Section header for where to find the app's source code.")
            } footer: {
                Text(
                    "Opens in your browser. nope. itself makes no network connections.", bundle: .module,
                    comment: "Footer under the source code link. Keep \"nope.\" unchanged.")
            }
        }
        .navigationTitle(Text("About and Licenses", bundle: .module, comment: "Settings row and screen title: version, license and third-party notices."))
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Text(verbatim: paragraphs[index])
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .padding()
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
