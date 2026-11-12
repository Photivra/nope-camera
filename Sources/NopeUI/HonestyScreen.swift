import SwiftUI

/// The Honesty screen: what nope. never does, what iOS may still do outside nope.'s control,
/// and what no app can remove.
///
/// Every statement uses the wording of `docs/research/privacy-claims.md` and is backed by the
/// source cited there (the claim number is in each string's translator comment). Apple setting
/// names appear on this screen only, to help people find each setting. The screen states
/// settings by name and doesn't open them. All wording is in `Honesty.xcstrings` and needs a fluent human review in every
/// language before release. VoiceOver reads it top to bottom, one statement at a time.
struct HonestyScreen: View {
    /// Creates the Honesty screen.
    init() {}

    /// The statements, in sections.
    var body: some View {
        // A plain scrolling column rather than a lazy `List`: the screen is static text, and
        // every statement exists from the start for VoiceOver and the accessibility audit.
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                neverSection
                iOSSection
                limitsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(Text("Honesty", tableName: "Honesty", bundle: .module, comment: "Settings row and screen title: what nope. does and doesn't do, and what it can't control."))
    }

    /// What nope. never does, and how to check.
    private var neverSection: some View {
        HonestySection {
            HonestyStatement(
                title: Text("No Network", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the app never goes online."),
                text: Text(
                    "nope. contains no networking code and makes no network connections.", tableName: "Honesty", bundle: .module,
                    comment: "Claim 1 in docs/research/privacy-claims.md. Keep \"nope.\" unchanged. Must not claim more than the English."))
            HonestyStatement(
                title: Text("No Data Collected", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the app collects no data."),
                text: Text(
                    "nope. contains no analytics, crash-reporting or advertising code, and collects no data.", tableName: "Honesty",
                    bundle: .module,
                    comment: "Claims 3 and 5 in docs/research/privacy-claims.md (Data Not Collected; privacy manifest). Keep \"nope.\" unchanged."))
            HonestyStatement(
                title: Text("Check It Yourself", tableName: "Honesty", bundle: .module, comment: "Honesty heading: how to verify that the app makes no connections."),
                text: Text(
                    "Turn on App Privacy Report (Settings › Privacy & Security). It lists every domain an app contacts during the last 7 days, starting from when you turn it on. nope. should list none.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 1 in docs/research/privacy-claims.md. App Privacy Report and the Settings path are Apple's names: use the names iOS shows in this language. Keep \"nope.\" unchanged."))
            HonestyStatement(
                title: Text("The RAW Is Never Changed", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the HEIF and JPEG look setting doesn't alter the RAW. RAW is a file format name."),
                text: Text(
                    "The HEIF and JPEG look in Settings changes only the copies nope. develops from the RAW. The RAW itself is never changed by it.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Keep \"nope.\" unchanged. RAW, HEIF and JPEG are file format names. Must not claim more than the English."))
        } header: {
            Text("What nope. Never Does", tableName: "Honesty", bundle: .module, comment: "Honesty section header. Keep \"nope.\" unchanged.")
        }
    }

    /// What iOS and Photos may still do, outside nope.'s control.
    private var iOSSection: some View {
        HonestySection {
            HonestyStatement(
                title: Text("iOS Connections", tableName: "Honesty", bundle: .module, comment: "Honesty heading: iOS itself goes online. iOS is a product name."),
                text: Text(
                    "iOS itself, for example iCloud Photos, makes its own connections.", tableName: "Honesty", bundle: .module,
                    comment: "Claim 1 in docs/research/privacy-claims.md. iOS and iCloud Photos are Apple's names."))
            HonestyStatement(
                title: Text("iCloud Photos", tableName: "Honesty", bundle: .module, comment: "Honesty heading. Apple's feature name: use the name iOS shows in this language."),
                text: Text(
                    "With standard protection, Apple holds the keys to iCloud Photos. With Advanced Data Protection, only your devices do. Some photo metadata and Shared Albums stay under standard protection.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 11 in docs/research/privacy-claims.md. Advanced Data Protection and Shared Albums are Apple's names: use the names iOS shows in this language."))
            HonestyStatement(
                title: Text("Enhanced Visual Search", tableName: "Honesty", bundle: .module, comment: "Honesty heading. Apple's setting name: use the name iOS shows in this language."),
                text: Text(
                    "Photos may privately compare landmark regions with Apple's servers (Enhanced Visual Search). You can turn it off in Settings › Apps › Photos.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 10 in docs/research/privacy-claims.md. Keep \"may\": it is not verified whether it is on by default. Use the names iOS shows in this language."))
            HonestyStatement(
                title: Text("Analysis in Photos", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the Photos app analyzes photos."),
                text: Text(
                    "Photos uses on-device analysis to recognize people and pets and to classify scenes. Names you give people sync through iCloud.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 13 in docs/research/privacy-claims.md, Apple's own wording. Photos and iCloud are Apple's names."))
            HonestyStatement(
                title: Text("Share with App Developers", tableName: "Honesty", bundle: .module, comment: "Honesty heading. Apple's setting name: use the name iOS shows in this language."),
                text: Text(
                    "If you opt in, Apple may share aggregated, non-identifying crash and usage statistics with developers. They never include your photos. It's in Settings › Privacy & Security › Analytics & Improvements.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 12 and note 12 in docs/research/privacy-claims.md. Use the setting names iOS shows in this language."))
            HonestyStatement(
                title: Text("Sharing from Photos", tableName: "Honesty", bundle: .module, comment: "Honesty heading: what is sent when a photo is shared from the Photos app."),
                text: Text(
                    "When you share from Photos, location is included unless you turn it off under Options. Other details, such as the date and device model, may still be sent.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 14 in docs/research/privacy-claims.md. Options is Apple's button name in the share sheet: use the name iOS shows in this language."))
        } header: {
            Text("What iOS May Still Do", tableName: "Honesty", bundle: .module, comment: "Honesty section header: things iOS does that the app can't change. iOS is a product name.")
        }
    }

    /// The limits no app can get around.
    private var limitsSection: some View {
        HonestySection {
            HonestyStatement(
                title: Text("The Sensor's Noise Pattern", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the camera sensor's unique noise fingerprint."),
                text: Text(
                    "Every camera sensor leaves a faint, unique noise pattern. With enough of your photos, forensic tools can match them to the same camera. No app can fully remove it.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 9 in docs/research/privacy-claims.md (peer-reviewed). Must not claim more than the English."))
            HonestyStatement(
                title: Text("This Build and the Source", tableName: "Honesty", bundle: .module, comment: "Honesty heading: whether the installed app matches the public source code."),
                text: Text(
                    "Apple encrypts and re-signs App Store apps, so there's no standard way to confirm a download was built from our public source.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 15 in docs/research/privacy-claims.md. App Store is Apple's name."))
        } header: {
            Text("What No App Can Remove", tableName: "Honesty", bundle: .module, comment: "Honesty section header: limits no camera app can get around.")
        }
    }
}

/// One Honesty statement: a short heading and the statement, read by VoiceOver as one element.
struct HonestyStatement: View {
    /// The heading.
    let title: Text

    /// The statement.
    let text: Text

    /// Creates a statement.
    ///
    /// - Parameters:
    ///   - title: The heading.
    ///   - text: The statement.
    init(title: Text, text: Text) {
        self.title = title
        self.text = text
    }

    /// The heading above the statement.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.headline)
            text
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A titled group of Honesty statements: a heading, then the statements.
struct HonestySection<Content: View, Header: View>: View {
    /// The statements.
    let content: Content

    /// The section's heading.
    let header: Header

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - content: The statements.
    ///   - header: The section's heading.
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    /// The heading above the statements. VoiceOver users can jump between headings.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}
