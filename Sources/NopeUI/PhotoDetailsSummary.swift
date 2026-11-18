import NopeCore
import SwiftUI

/// The summary at the top of What's in This Photo (`docs/design/BUILD-SPEC.md`, 3.15, group 0):
/// the formats, the lens, the pixel size and total size, then four lines with symbols: what kind
/// of photo it is, the signature, how many optional details the files hold, and whether they hold
/// a location. One section with one row, read by VoiceOver as one element.
struct PhotoSummaryCard: View {
    /// The photo.
    let photo: SavedPhoto

    /// Its details.
    let details: PhotoDetails

    /// The lens it was taken with, or `nil`.
    let lens: Lens?

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - photo: The photo.
    ///   - details: Its details.
    ///   - lens: The lens, or `nil`.
    init(photo: SavedPhoto, details: PhotoDetails, lens: Lens?) {
        self.photo = photo
        self.details = details
        self.lens = lens
    }

    /// The card.
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: NopeSpace.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        formats
                        Spacer(minLength: NopeSpace.xs)
                        caption
                    }
                    VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                        formats
                        caption
                    }
                }
                if let size = sizeLine {
                    size
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(CameraStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                kindLine
                line(
                    Text(verbatim: CaptureMessages.message(for: details.signature)),
                    symbol: PhotoDetailsSections.signatureSymbol(details.signature),
                    style: PhotoDetailsSections.signatureStyle(details.signature))
                line(Self.detailsCount(details.optionalDetailCount), symbol: "list.bullet", style: AnyShapeStyle(CameraStyle.secondaryText))
                if details.holdsLocation {
                    line(
                        Text("Location is in the files", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: the saved files hold the location where the photo was taken (GPS). Shown with a warning symbol. Draft wording for the Honesty review."),
                        symbol: "exclamationmark.triangle.fill", style: AnyShapeStyle(CameraStyle.warning))
                } else {
                    line(
                        Text("No location in the files", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: the saved files hold no location. Draft wording for the Honesty review."),
                        symbol: "location.slash", style: AnyShapeStyle(CameraStyle.secondaryText))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("PhotoDetails.summary")
        }
    }

    /// The formats, as a list such as "RAW (DNG) and HEIF".
    private var formats: some View {
        Text(verbatim: photo.formats.map(FormatsSettingsView.name(of:)).formatted(.list(type: .and)))
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The lens, such as "1×", or nothing when it isn't known.
    ///
    /// The design's caption is the lens and the time (`docs/design/BUILD-SPEC.md`, 3.15, group 0),
    /// both from the session's photo list of the Last Photo viewer (section 6, item 15). Until
    /// that list reaches the sheet, the lens comes from the capture report and no time is shown.
    @ViewBuilder private var caption: some View {
        if let lens {
            Text(verbatim: PhotoDetailsText.name(of: lens))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(CameraStyle.secondaryText)
        }
    }

    /// The pixel size and the total size of the files, such as "4032 × 3024 pixels · 26.9 MB".
    private var sizeLine: Text? {
        let total = details.files.reduce(0) { $0 + $1.byteCount }.formatted(.byteCount(style: .file))
        guard let pixels = details.files.lazy.compactMap(PhotoDetailsText.pixels(of:)).first else {
            return Text(verbatim: total)
        }
        return Text(
            "\(pixels) · \(total)", bundle: .module,
            comment: "Summary in the photo details: the photo's size in pixels, then the total size of its files, such as 4032 × 3024 pixels · 26.9 MB. Keep the separator.")
    }

    /// What kind of photo it is: a processed fallback (with the warning symbol), or the RAW and
    /// the copies developed from it.
    @ViewBuilder private var kindLine: some View {
        if details.files.contains(where: { $0.processing == .byDevice }) {
            line(PhotoDetailsSections.processing(.byDevice), symbol: "exclamationmark.triangle.fill", style: AnyShapeStyle(CameraStyle.warning))
        } else {
            line(Self.kind(of: details), symbol: "camera", style: AnyShapeStyle(CameraStyle.secondaryText))
        }
    }

    /// A line with its symbol, which is hidden from VoiceOver: the words carry the state.
    ///
    /// - Parameters:
    ///   - text: The words.
    ///   - symbol: The SF Symbol name.
    ///   - style: The symbol's color.
    private func line(_ text: Text, symbol: String, style: AnyShapeStyle) -> some View {
        SymbolLine(text: text, symbol: symbol, style: style)
    }

    /// The kind of a photo with RAW: one frame of sensor data, and the copies developed from it.
    /// A photo saved without its RAW (copies only) says how the copies were made.
    ///
    /// - Parameter details: The details.
    /// - Returns: The sentence, from `Honesty.xcstrings`.
    static func kind(of details: PhotoDetails) -> Text {
        let copies = details.files.filter { if case .developed = $0.processing { true } else { false } }
        guard details.rawFile != nil else {
            return PhotoDetailsSections.processing(copies.first?.processing ?? .developed(.standard))
        }
        let names = copies.map { FormatsSettingsView.name(of: $0.format) }.formatted(.list(type: .and))
        switch copies.count {
        case 0:
            return Text("RAW: one frame of sensor data", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: the photo is a RAW file, one frame of the sensor's data. It must not be read as 'no processing': it says only what the file is. RAW is a file format name. Draft wording for the Honesty review.")
        case 1:
            return Text("RAW: one frame of sensor data, and a \(names) copy developed by nope.", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: a RAW file, one frame of the sensor's data, and one copy (the placeholder is its format, such as HEIF) that nope. developed from it. RAW is a file format name. Keep nope. unchanged. Draft wording for the Honesty review.")
        default:
            return Text("RAW: one frame of sensor data, and \(names) copies developed by nope.", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: a RAW file, one frame of the sensor's data, and copies (the placeholder lists their formats, such as HEIF and JPEG) that nope. developed from it. RAW is a file format name. Keep nope. unchanged. Draft wording for the Honesty review.")
        }
    }

    /// How many optional details the files hold, the location not counted.
    ///
    /// - Parameter count: The count.
    /// - Returns: The sentence, from `Honesty.xcstrings`, with its plural rule.
    static func detailsCount(_ count: Int) -> Text {
        count == 0
            ? Text("No optional details in the files", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: the saved files hold none of the optional details (date, camera, lens and so on). Draft wording for the Honesty review.")
            : Text("\(count) optional details in the files", tableName: "Honesty", bundle: .module, comment: "Summary line in the photo details: how many of the optional details (date, camera, lens and so on) the saved files hold. The location is not counted: it has its own line. Draft wording for the Honesty review.")
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
