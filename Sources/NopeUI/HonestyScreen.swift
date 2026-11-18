import SwiftUI

/// The Honesty screen: what the app never does, what iOS may still do outside the app's control,
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
            VStack(alignment: .leading, spacing: NopeSpace.xl) {
                neverSection
                iOSSection
                limitsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NopeSpace.m)
        }
        .navigationTitle(Text(SettingsText.honesty))
    }

    /// What the app never does, and how to check.
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
            HonestyStatement(
                title: Text("Location Only If You Turn It On", tableName: "Honesty", bundle: .module, comment: "Honesty heading: photos include a location only when the person turns Location on."),
                text: Text(
                    "Location is off unless you turn it on under Details in Each Photo in nope.'s settings. Then nope. uses your location only while the camera is open, and each photo gets its latitude, longitude and altitude. No direction, speed or GPS time is written, and the location is never sent anywhere.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Issue #43; docs/PRIVACY.md, \"Location\". Details in Each Photo is the name of nope.'s own settings page; use its translation. Keep \"nope.\" unchanged. Must not claim more than the English."))
            HonestyStatement(
                title: Text("Signing Is Your Choice", tableName: "Honesty", bundle: .module, comment: "Honesty heading: photos are signed with Content Credentials only when the person turns signing on."),
                text: Text(
                    "Photos aren't signed unless you turn on Sign Each Photo in nope.'s settings. A signed photo lets anyone check that it hasn't changed since nope. saved it, and shows that it was taken with nope. and which version. It doesn't identify you or your device.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Issue #80; docs/PRIVACY.md, \"Content Credentials\". Sign Each Photo is the name of nope.'s own switch; use its translation. Keep \"nope.\" unchanged. Must not claim more than the English."))
            HonestyStatement(
                title: Text("The Comparison Photo Is Never Saved", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the phone-processed photo of the comparison shot is never saved."),
                text: Text(
                    "With Compare on, nope. takes a second photo with the phone's processing, only to show it next to yours. That photo is never saved, signed or shared, and it is discarded when you close the comparison. Only your nope. photo goes to Photos.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Issue #55; docs/PRIVACY.md, \"Comparison shot\". Compare is the name of nope.'s own camera switch; use its translation. Photos is the system photo library app. Keep \"nope.\" unchanged. Must not claim more than the English."))
            HonestyStatement(
                title: Text("Apple Watch Sends Only Commands", tableName: "Honesty", bundle: .module, comment: "Honesty heading: the Apple Watch app exchanges only commands and short status with the phone. Apple Watch is Apple's product name."),
                text: Text(
                    "nope. on Apple Watch sends only your commands, such as the shutter and the delay, to nope. on your iPhone, and gets back only short status, such as \"Saved and signed\". No photos or photo details go to the watch. watchOS and iOS carry these messages over their own connection between your paired devices; nope. opens no network connection.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 19 in docs/research/privacy-claims.md; issue #63. Apple Watch, iPhone, watchOS and iOS are Apple's names. \"Saved and signed\" is the watch app's own result text; use its translation. Keep \"nope.\" unchanged. Must not claim more than the English."))
            HonestyStatement(
                title: Text("Siri, Shortcuts and Assistants", tableName: "Honesty", bundle: .module, comment: "Honesty heading: what Siri, Shortcuts and other assistants can do with nope. and learn from it (issue #82). Siri and Shortcuts are Apple's names."),
                text: Text(
                    "Siri, Shortcuts and other assistants can use nope. only if you turn on Assistant Access, and nope. asks before each action unless you choose otherwise. An assistant gets one sentence about what happened. It never gets a photo, a location or a photo’s details from nope. This covers nope.’s own actions; photos you save to Photos, and what you let an assistant see on your screen, are up to iOS.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Issue #82; docs/design/assistant-access.md, text 25. Assistant Access is the name of nope.'s setting. Siri, Shortcuts, Photos and iOS are Apple's names. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English."))
        } header: {
            Text("What nope. Never Does", tableName: "Honesty", bundle: .module, comment: "Honesty section header. Keep \"nope.\" unchanged.")
        }
    }

    /// What iOS and Photos may still do, outside the app's control.
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
            HonestyStatement(
                title: Text("Lenses Without RAW", tableName: "Honesty", bundle: .module, comment: "Honesty heading: on lenses that can't save RAW, the phone processes the photo. RAW is a file format name."),
                text: Text(
                    "On a lens that can't save RAW, the phone processes the photo before nope. receives it, and nope. can't turn that processing off. The camera marks these lenses Processed, unless you turn off Show Processed Marker in nope.'s settings, and the photo's details always say so.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Issue #80; docs/PRIVACY.md, \"Processing\". \"Processed\" is the marker on the camera and Show Processed Marker the name of nope.'s own switch; use their translations. RAW is a file format name. Keep \"nope.\" unchanged. Must not claim more than the English."))
            HonestyStatement(
                title: Text("Faces and Autofocus", tableName: "Honesty", bundle: .module, comment: "Honesty heading: iOS may detect faces to choose where to focus."),
                text: Text(
                    "iOS may detect faces in the viewfinder to decide where to focus. Focus on Faces in nope.'s settings decides only whether nope.'s autofocus and auto exposure follow them. nope. doesn't read or save which faces it found.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Claim 18 in docs/research/privacy-claims.md (AVCaptureDevice face-driven autofocus and auto exposure); issue #80. Focus on Faces is the name of nope.'s own switch; use its translation. Don't describe the switch as turning face detection off. Keep \"nope.\" unchanged. Must not claim more than the English."))
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
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            title
                .font(.headline)
            text
                .foregroundStyle(CameraStyle.secondaryText)
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
        VStack(alignment: .leading, spacing: NopeSpace.m) {
            header
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}
