import NopeCore
import SwiftUI

/// The summary at the top of What's in This Photo (`docs/design/BUILD-SPEC.md`, 3.15, group 0;
/// issue #118, `docs/design/finish-1.0.md`, section 3): one group built like the groups under it.
///
/// - The head: the formats as the title, then the lens and time, then the pixel size and total
///   size, all on the leading edge. One VoiceOver element, with the identifier
///   `PhotoDetails.summary`.
/// - One row for each fact, always in this order: what kind of file it is, the signature, the
///   optional details, the location (``rows(of:)``). Each symbol is centered in a column of one
///   width that grows with the text size, so the words of every row start on the same line. Each
///   row is one VoiceOver element, read once and in order; a warning row begins with "Warning".
///
/// Color: amber with the triangle for a warning, teal for the one verified fact (signed), the
/// secondary color for the rest. A warning is always told by its triangle and its words too, so
/// night mode's red loses nothing.
struct PhotoSummaryCard: View {
    /// The photo.
    let photo: SavedPhoto

    /// Its details.
    let details: PhotoDetails

    /// The lens it was taken with, or `nil`.
    let lens: Lens?

    /// When the shutter took it, from the session's photo list (`SessionPhoto.takenAt`), or
    /// `nil` when the session has no record of it.
    let takenAt: Date?

    /// The width of the symbol column: 28 points at the default text size, a little wider than
    /// the widest symbol used (the triangle and the bullet list at body size), growing with the
    /// text.
    @ScaledMetric(relativeTo: .body) private var symbolColumn: CGFloat = 28

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - photo: The photo.
    ///   - details: Its details.
    ///   - lens: The lens, or `nil`.
    ///   - takenAt: When the shutter took it, or `nil`.
    init(photo: SavedPhoto, details: PhotoDetails, lens: Lens?, takenAt: Date? = nil) {
        self.photo = photo
        self.details = details
        self.lens = lens
        self.takenAt = takenAt
    }

    /// The group: the head, then a row for each fact.
    var body: some View {
        Section {
            head
            ForEach(Self.rows(of: details)) { row in
                RowView(row: row, symbolColumn: symbolColumn)
            }
        }
    }

    // MARK: - The head

    /// The formats, the lens and time, and the sizes, on the leading edge.
    private var head: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            Text(verbatim: photo.formats.map(FormatsSettingsView.name(of:)).formatted(.list(type: .and)))
                .font(.title3.weight(.semibold))
            Group {
                if let caption = Self.caption(lens: lens, takenAt: takenAt) {
                    Text(verbatim: caption)
                }
                sizeLine
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(CameraStyle.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("PhotoDetails.summary")
    }

    /// The caption's words: the lens and the time, such as "1× · 2:41 PM", joined as the
    /// viewer's caption joins them (`docs/design/BUILD-SPEC.md`, 3.15, group 0, and section 6,
    /// item 15; decision P3): from the session's photo list, even when the files hold neither.
    ///
    /// - Parameters:
    ///   - lens: The lens, or `nil`.
    ///   - takenAt: When the shutter took the photo, or `nil`.
    /// - Returns: The caption, or `nil` when neither is known.
    static func caption(lens: Lens?, takenAt: Date?) -> String? {
        let parts = [lens.map(PhotoDetailsText.name(of:)), takenAt.map(PhotoViewerFacts.time)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The pixel size and the total size of the files, such as "4032 × 3024 pixels · 26.9 MB".
    private var sizeLine: Text {
        let total = details.files.reduce(0) { $0 + $1.byteCount }.formatted(.byteCount(style: .file))
        guard let pixels = details.files.lazy.compactMap(PhotoDetailsText.pixels(of:)).first else {
            return Text(verbatim: total)
        }
        return Text(
            "\(pixels) · \(total)", bundle: .module,
            comment: "Summary in the photo details: the photo's size in pixels, then the total size of its files, such as 4032 × 3024 pixels · 26.9 MB. Keep the separator.")
    }

    // MARK: - The rows

    /// One fact of the summary: its symbol and color, its words and, for some, a second line
    /// that says why.
    struct Row: Identifiable, Equatable {
        /// Which fact; also the row's order.
        enum Fact: String, Equatable {
            /// What kind of file it is.
            case kind
            /// The signature.
            case signature
            /// How many optional details the files hold.
            case details
            /// Whether the files hold the location.
            case location
        }

        /// The symbol's color.
        enum Tone: Equatable {
            /// The secondary color: plain information.
            case plain
            /// Teal: the one verified fact, signed.
            case fact
            /// Amber, with the triangle: a warning.
            case warning
        }

        /// Which fact.
        let id: Fact
        /// The SF Symbol name, hidden from VoiceOver.
        let symbol: String
        /// The symbol's color.
        let tone: Tone
        /// The words.
        let title: String
        /// The second line in the secondary style, or `nil`.
        let detail: String?

        /// Creates a row.
        ///
        /// - Parameters:
        ///   - id: Which fact.
        ///   - symbol: The SF Symbol name.
        ///   - tone: The symbol's color.
        ///   - title: The words.
        ///   - detail: The second line, or `nil`.
        init(id: Fact, symbol: String, tone: Tone, title: String, detail: String?) {
            self.id = id
            self.symbol = symbol
            self.tone = tone
            self.title = title
            self.detail = detail
        }

        /// What VoiceOver reads for the row: the words and the second line, with "Warning"
        /// first for a warning.
        var spokenLabel: String {
            let words = detail.map { detail in
                String(
                    format: String(
                        localized: "Summary row: %@, %@", defaultValue: "%1$@, %2$@", bundle: .module,
                        comment: "VoiceOver label of a row in the summary of What's in This Photo that has a second line: the row's words, then the second line, such as Not signed, Signing is off in Settings. Keep both placeholders."),
                    title, detail)
            } ?? title
            guard tone == .warning else { return words }
            return String(
                localized: "Warning, \(words)", bundle: .module,
                comment: "VoiceOver label of a warning row in the summary of What's in This Photo: the word Warning, then the row's words, such as Warning, Location is in the files.")
        }
    }

    /// The summary's rows, always in this order: what kind of file, the signature, the optional
    /// details, the location (`docs/design/finish-1.0.md`, 3.2).
    ///
    /// - Parameter details: The photo's details.
    /// - Returns: The four rows.
    static func rows(of details: PhotoDetails) -> [Row] {
        [kindRow(of: details), signatureRow(details.signature), detailsRow(details.optionalDetailCount), locationRow(details.holdsLocation)]
    }

    /// What kind of file it is: processed by the device (a warning, with the reason), or the
    /// RAW and the copies developed from it.
    ///
    /// - Parameter details: The details.
    /// - Returns: The row.
    static func kindRow(of details: PhotoDetails) -> Row {
        guard details.files.contains(where: { $0.processing == .byDevice }) else {
            return Row(id: .kind, symbol: "camera", tone: .plain, title: kind(of: details), detail: nil)
        }
        return Row(
            id: .kind, symbol: "exclamationmark.triangle.fill", tone: .warning,
            title: String(localized: "Processed by this iPhone", table: "Honesty", bundle: .module, comment: "Summary row in the photo details: the phone's camera processed this photo, because the lens can't save RAW. Shown with a warning symbol. On iPad the English names the iPad, and on other devices it says \"device\"; translate each variant. Draft wording for the Honesty review."),
            detail: String(localized: "This lens can't save RAW", table: "Honesty", bundle: .module, comment: "Second line of the summary row Processed by this iPhone in the photo details: why the photo was processed. RAW is a file format name. Draft wording for the Honesty review."))
    }

    /// The signature: Signed; or Not signed with the reason, a warning unless signing is off by
    /// the person's choice (`docs/design/BUILD-SPEC.md`, 3.9).
    ///
    /// - Parameter signature: The photo's signature status.
    /// - Returns: The row.
    static func signatureRow(_ signature: SignatureStatus) -> Row {
        let symbol = PhotoDetailsSections.signatureSymbol(signature)
        let notSigned = String(
            localized: "Summary row: Not signed", defaultValue: "Not signed", table: "Honesty", bundle: .module,
            comment: "Summary row in the photo details: the photo has no Content Credentials signature. A second line says why. Honesty wording: never imply the photo is signed. Draft wording for the Honesty review.")
        let reason: String
        switch signature {
        case .signed:
            return Row(
                id: .signature, symbol: symbol, tone: .fact,
                title: String(
                    localized: "Summary row: Signed", defaultValue: "Signed", table: "Honesty", bundle: .module,
                    comment: "Summary row in the photo details, with a seal: every file of the photo has a Content Credentials signature. Draft wording for the Honesty review."),
                detail: nil)
        case .unsigned(.turnedOff):
            return Row(
                id: .signature, symbol: symbol, tone: .plain, title: notSigned,
                detail: String(localized: "Signing is off in Settings", table: "Honesty", bundle: .module, comment: "Second line of the summary row Not signed in the photo details: the person turned the Sign Each Photo setting off. Not a warning. Draft wording for the Honesty review."))
        case .unsigned(.failed):
            reason = String(localized: "The signature couldn't be made", table: "Honesty", bundle: .module, comment: "Second line of the summary row Not signed in the photo details: signing was on, but creating the Content Credentials signature failed, so the photo was saved without one. Shown as a warning. Draft wording for the Honesty review.")
        case .unsigned(.unavailable):
            reason = String(localized: "This version of the app can't sign photos", table: "Honesty", bundle: .module, comment: "Second line of the summary row Not signed in the photo details: signing was on, but this build of the app has no signer. Shown as a warning. Draft wording for the Honesty review.")
        case .unsigned(.signedFileFailedCheck):
            reason = String(localized: "The signed file didn't pass the check", table: "Honesty", bundle: .module, comment: "Second line of the summary row Not signed in the photo details: a signed file failed the app's read-back check, so the unsigned file, which passed, was saved instead. Shown as a warning. Draft wording for the Honesty review.")
        }
        return Row(id: .signature, symbol: symbol, tone: .warning, title: notSigned, detail: reason)
    }

    /// How many optional details the files hold, the location not counted.
    ///
    /// - Parameter count: The count.
    /// - Returns: The row.
    static func detailsRow(_ count: Int) -> Row {
        let title =
            count == 0
            ? String(localized: "No optional details in the files", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: the saved files hold none of the optional details (date, camera, lens and so on). Draft wording for the Honesty review.")
            : String(localized: "\(count) optional details in the files", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: how many of the optional details (date, camera, lens and so on) the saved files hold. The location is not counted: it has its own line. Draft wording for the Honesty review.")
        return Row(id: .details, symbol: "list.bullet", tone: .plain, title: title, detail: nil)
    }

    /// Whether the files hold the location: a warning when they do.
    ///
    /// - Parameter holdsLocation: Whether the files hold it.
    /// - Returns: The row.
    static func locationRow(_ holdsLocation: Bool) -> Row {
        holdsLocation
            ? Row(
                id: .location, symbol: "exclamationmark.triangle.fill", tone: .warning,
                title: String(localized: "Location is in the files", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: the saved files hold the location where the photo was taken (GPS). Shown with a warning symbol. Draft wording for the Honesty review."),
                detail: nil)
            : Row(
                id: .location, symbol: "location.slash", tone: .plain,
                title: String(localized: "No location in the files", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: the saved files hold no location. Draft wording for the Honesty review."),
                detail: nil)
    }

    /// The kind of a photo with RAW: one frame of sensor data, and the copies developed from it.
    /// A photo saved without its RAW (copies only) says how the copies were made.
    ///
    /// - Parameter details: The details.
    /// - Returns: The sentence, from `Honesty.xcstrings`.
    static func kind(of details: PhotoDetails) -> String {
        let copies = details.files.filter { if case .developed = $0.processing { true } else { false } }
        guard details.rawFile != nil else {
            return PhotoDetailsSections.processingText(copies.first?.processing ?? .developed(.standard))
        }
        let names = copies.map { FormatsSettingsView.name(of: $0.format) }.formatted(.list(type: .and))
        switch copies.count {
        case 0:
            return String(localized: "RAW: one frame of sensor data", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: the photo is a RAW file, one frame of the sensor's data. It must not be read as 'no processing': it says only what the file is. RAW is a file format name. Draft wording for the Honesty review.")
        case 1:
            return String(localized: "RAW: one frame of sensor data, and a \(names) copy developed by nope.", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: a RAW file, one frame of the sensor's data, and one copy (the placeholder is its format, such as HEIF) that nope. developed from it. RAW is a file format name. Keep nope. unchanged. Draft wording for the Honesty review.")
        default:
            return String(localized: "RAW: one frame of sensor data, and \(names) copies developed by nope.", table: "Honesty", bundle: .module, comment: "Summary line in the photo details: a RAW file, one frame of the sensor's data, and copies (the placeholder lists their formats, such as HEIF and JPEG) that nope. developed from it. RAW is a file format name. Keep nope. unchanged. Draft wording for the Honesty review.")
        }
    }

    /// One row: the symbol centered in the symbol column, then the words and the second line,
    /// read by VoiceOver as one element.
    private struct RowView: View {
        /// The row.
        let row: Row

        /// The symbol column's width.
        let symbolColumn: CGFloat

        /// The row.
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: NopeSpace.s) {
                Image(systemName: row.symbol)
                    .foregroundStyle(style)
                    .frame(width: symbolColumn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                    Text(verbatim: row.title)
                    if let detail = row.detail {
                        Text(verbatim: detail)
                            .font(.subheadline)
                            .foregroundStyle(CameraStyle.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.spokenLabel))
            .accessibilityIdentifier("PhotoDetails.summary.\(row.id.rawValue)")
        }

        /// The symbol's color.
        private var style: AnyShapeStyle {
            switch row.tone {
            case .plain: AnyShapeStyle(CameraStyle.secondaryText)
            case .fact: AnyShapeStyle(CameraStyle.fact)
            case .warning: AnyShapeStyle(CameraStyle.warning)
            }
        }
    }
}

/// A line of words led by a symbol that VoiceOver skips: the words carry the state. An
/// `HStack` on the first baseline rather than a `Label`, whose wrapped text the accessibility
/// audit reported as clipped inside a list row.
struct SymbolLine: View {
    /// The words.
    let text: Text

    /// The SF Symbol name.
    let symbol: String

    /// The symbol's color.
    let style: AnyShapeStyle

    /// Creates the line.
    ///
    /// - Parameters:
    ///   - text: The words.
    ///   - symbol: The SF Symbol name.
    ///   - style: The symbol's color.
    init(text: Text, symbol: String, style: AnyShapeStyle) {
        self.text = text
        self.symbol = symbol
        self.style = style
    }

    /// The line.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NopeSpace.xs) {
            Image(systemName: symbol)
                .foregroundStyle(style)
                .accessibilityHidden(true)
            text.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Words and formats shared by the groups of What's in This Photo.
enum PhotoDetailsText {
    /// A lens's short name: its zoom factor, such as "1×", or its kind ("Front") without one.
    ///
    /// - Parameter lens: The lens.
    /// - Returns: The name.
    static func name(of lens: Lens) -> String {
        lens.magnification.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "×" }
            ?? LensName.string(for: lens.kind)
    }

    /// A file's size in pixels, such as "4032 × 3024 pixels", or `nil` without one.
    ///
    /// - Parameter file: The file.
    /// - Returns: The text.
    static func pixels(of file: PhotoDetails.File) -> String? {
        guard let width = file.pixelWidth, let height = file.pixelHeight else { return nil }
        return String(
            localized: "\(width.formatted(.number.grouping(.never))) × \(height.formatted(.number.grouping(.never))) pixels", bundle: .module,
            comment: "In the photo details: a file's size in pixels, width by height, such as 4032 × 3024 pixels.")
    }

    /// Numbers as a list, such as "528, 528, 528, 528".
    ///
    /// - Parameter values: The values.
    /// - Returns: The list, in the current language.
    static func numbers(_ values: [Double]) -> String {
        values.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) }
            .formatted(.list(type: .and, width: .narrow))
    }

    /// "Not in the files", the note under a value the files don't hold.
    static var notInFiles: Text {
        Text("Not in the files", tableName: "Honesty", bundle: .module, comment: "In the photo details, under a value the saved files don't hold: it is what the camera reported or the lens that was selected, kept by nope. in memory. Must stay true if those values stop being kept. Draft wording for the Honesty review.")
    }

    /// "As written in the files.", the footer of the Exposure and Lens and Camera groups.
    static var asWritten: Text {
        Text("As written in the files.", tableName: "Honesty", bundle: .module, comment: "Footer of the Exposure and the Lens and Camera groups in the photo details: the values are exactly what the saved files hold. Draft wording for the Honesty review.")
    }
}
