import NopeCore
import SwiftUI

/// "What's in This Photo": the facts read back from a photo the app just saved (issue #53),
/// opened from the last-photo thumbnail.
///
/// A native list with one section per topic, each with a heading VoiceOver can jump between:
/// the files, the RAW clipping, the exposure as written, the processing, the signature, the details kept and left
/// out, everything the read-back found, and the timings. Every value comes from
/// `SavedPhoto.details`; a value the file doesn't hold isn't shown.
///
/// Privacy: on screen only. Nothing is logged, stored or copied, and the text can't be selected
/// (no clipboard access).
struct PhotoDetailsSheet: View {
    /// The photos of the last press of the shutter: one, or a bracket's frames.
    let photos: [SavedPhoto]

    /// Opens Photos, or `nil` when the app can't.
    let openPhoto: (() -> Void)?

    /// The frame shown, for a bracket.
    @State private var selection = 0

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - photos: The photos of the last press of the shutter.
    ///   - openPhoto: Opens Photos, or `nil`.
    init(photos: [SavedPhoto], openPhoto: (() -> Void)?) {
        self.photos = photos
        self.openPhoto = openPhoto
    }

    /// The photo shown.
    private var photo: SavedPhoto? {
        photos.indices.contains(selection) ? photos[selection] : photos.last
    }

    /// The list, with a Done button.
    var body: some View {
        NavigationStack {
            List {
                if photos.count > 1 {
                    Picker(selection: $selection) {
                        ForEach(photos.indices, id: \.self) { index in
                            Text(
                                "Photo \(index + 1) of \(photos.count)", bundle: .module,
                                comment: "Choice in the photo details of an exposure bracket: which of its photos to show. The first number is the photo, the second the count.")
                                .tag(index)
                        }
                    } label: {
                        Text("Photo", bundle: .module, comment: "Label of the picker that chooses which photo of an exposure bracket the details show.")
                    }
                }
                if let details = photo?.details {
                    PhotoDetailsSections(details: details)
                }
                if let openPhoto {
                    Section {
                        Button(action: openPhoto) {
                            Label {
                                Text("Open in Photos", bundle: .module, comment: "Button that opens the Photos app, where the saved photo is. Photos is the system photo library app.")
                            } icon: {
                                Image(systemName: "photo.on.rectangle")
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("What's in This Photo", bundle: .module, comment: "Title of the sheet that lists the facts read back from the photo nope. just saved: files, exposure, signature, details kept and removed."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("PhotoDetails")
    }
}

/// The sections of the photo details.
struct PhotoDetailsSections: View {
    /// The details shown.
    let details: PhotoDetails

    /// Creates the sections.
    ///
    /// - Parameter details: The details shown.
    init(details: PhotoDetails) {
        self.details = details
    }

    /// The sections.
    var body: some View {
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                FileDetailsRows(file: file)
            }
        } header: {
            Text("Files", bundle: .module, comment: "Heading in the photo details: the files saved for this photo.")
        }
        if let clipping = details.rawClipping {
            RAWClippingSection(result: clipping)
        }
        signatureSection
        exposureSection
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                DetailRow(title: Text(verbatim: FormatsSettingsView.name(of: file.format)), value: Self.processing(file.processing))
            }
            // A processed fallback: whether the lens let the app turn off distortion correction
            // (issue #80). RAW never has it, so a RAW photo has no line.
            if let correction = details.distortionCorrection {
                ProcessingNote.distortion(correction)
            }
        } header: {
            Text("Processing", bundle: .module, comment: "Heading in the photo details: what processing each file went through.")
        }
        Section {
            ForEach(details.writtenItems, id: \.self) { item in
                Text(PrivacySettingsView.title(of: item))
            }
            ForEach(details.lockedItems, id: \.self) { item in
                DetailRow(
                    title: Text(PrivacySettingsView.title(of: item)),
                    value: Text("Always kept", tableName: "Honesty", bundle: .module, comment: "In the photo details, next to a metadata item every file keeps because the photo can't be opened without it."))
            }
        } header: {
            Text("Details Kept", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: the metadata items the saved files hold.")
        }
        Section {
            ForEach(details.leftOutItems, id: \.item) { receipt in
                DetailRow(title: Text(PrivacySettingsView.title(of: receipt.item)), value: Self.reason(receipt.state))
            }
        } header: {
            Text("Details Left Out", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: the optional metadata items the saved files don't hold, each with the reason.")
        }
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                DisclosureGroup {
                    ForEach(Array(file.contents.enumerated()), id: \.offset) { _, name in
                        // Specification names (tags, blocks, properties) aren't translated.
                        Text(verbatim: name).font(.footnote.monospaced())
                    }
                } label: {
                    DetailRow(
                        title: Text(verbatim: FormatsSettingsView.name(of: file.format)),
                        value: Text(verbatim: file.contents.count.formatted()))
                }
            }
        } header: {
            Text("Read Back from the Files", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: every metadata tag, block and property nope. read back from each saved file before saving it. Keep nope. unchanged if it appears.")
        } footer: {
            Text("Only for photos taken since nope. opened: nope. can't read your photo library, and these details aren't stored.", tableName: "Honesty", bundle: .module, comment: "Footer in the photo details. nope. has add-only access to the photo library, so it can show details only for photos it saved in this session, from memory. Keep nope. unchanged.")
        }
        Section {
            timing(Text("Taking the Photo", bundle: .module, comment: "Timing in the photo details: from pressing the shutter to the camera returning the photo."), details.timings.capture)
            timing(Text("Developing", bundle: .module, comment: "Timing in the photo details: developing the HEIF and JPEG from the RAW."), details.timings.develop)
            timing(Text("Signing", bundle: .module, comment: "Timing in the photo details: creating the Content Credentials signatures."), details.timings.sign)
            timing(Text("Reading Back", bundle: .module, comment: "Timing in the photo details: reading every file back and checking its metadata."), details.timings.readBack)
            timing(Text("Adding to Photos", bundle: .module, comment: "Timing in the photo details: adding the files to the photo library. Photos is the system photo library app."), details.timings.save)
        } header: {
            Text("Timing", bundle: .module, comment: "Heading in the photo details: how long each step of taking and saving the photo took, in milliseconds.")
        }
    }

    /// The exposure as written, or why there is none.
    @ViewBuilder private var exposureSection: some View {
        Section {
            if let exposure = details.exposure {
                if let time = exposure.exposureTime {
                    DetailRow(title: Text(ControlText.name(.shutter)), value: Text(verbatim: ControlText.value(time, of: .shutter)))
                }
                if let iso = exposure.iso {
                    DetailRow(title: Text(ControlText.name(.iso)), value: Text(verbatim: ControlText.value(iso, of: .iso)))
                }
                if let fNumber = exposure.fNumber {
                    DetailRow(title: Text(ControlText.name(.aperture)), value: Text(verbatim: ControlText.value(fNumber, of: .aperture)))
                }
                if let focalLength = exposure.focalLength {
                    DetailRow(
                        title: Text("Focal Length", bundle: .module, comment: "Row in the photo details: the lens's real focal length, in millimeters, as written in the file."),
                        value: Text(verbatim: Measurement(value: focalLength, unit: UnitLength.millimeters).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2))))))
                }
                if let bias = exposure.exposureBias {
                    DetailRow(title: Text(ControlText.name(.exposureCompensation)), value: Text(verbatim: ControlText.meter(bias)))
                }
                if let fired = exposure.flashFired {
                    DetailRow(
                        title: Text("Flash", bundle: .module, comment: "Camera menu and its Voice Control name: when the flash fires (Off, Auto, On)."),
                        value: fired
                            ? Text("Fired", bundle: .module, comment: "In the photo details, the flash as the file records it: the flash fired for this photo.")
                            : Text("Didn't fire", bundle: .module, comment: "In the photo details, the flash as the file records it: the flash didn't fire for this photo."))
                }
                if let whiteBalance = exposure.whiteBalance {
                    DetailRow(title: Text(ControlText.name(.whiteBalance)), value: Text(verbatim: ControlText.mode(isManual: whiteBalance == .manual)))
                }
            } else if details.items.contains(PhotoDetails.ItemReceipt(item: .exposureSettings, state: .removed)) {
                Text("Not in the files: exposure settings are off in Settings.", tableName: "Honesty", bundle: .module, comment: "Shown in the photo details when the files hold no exposure settings, because the person turned that metadata item off.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The files don't record the exposure.", tableName: "Honesty", bundle: .module, comment: "Shown in the photo details when the saved files hold no exposure values although the exposure settings item is on, because the camera didn't supply them.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Exposure as Written", bundle: .module, comment: "Heading in the photo details: the shutter speed, ISO, aperture and other exposure values exactly as the saved file records them.")
        }
    }

    /// The symbol of the signature row: the seal when signed; the info symbol when signing is
    /// off in Settings, which is the person's choice and not a problem (`docs/design/BUILD-SPEC.md`,
    /// 3.9); the warning triangle when a photo couldn't be signed.
    ///
    /// - Parameter signature: The photo's signature status.
    /// - Returns: An SF Symbol name.
    static func signatureSymbol(_ signature: SignatureStatus) -> String {
        switch signature {
        case .signed: "checkmark.seal.fill"
        case .unsigned(.turnedOff): "info.circle"
        case .unsigned: "exclamationmark.triangle.fill"
        }
    }

    /// The color of the signature row's symbol: teal for a verified fact, the secondary text
    /// color for plain information, amber for a warning.
    ///
    /// - Parameter signature: The photo's signature status.
    /// - Returns: The symbol's style.
    static func signatureStyle(_ signature: SignatureStatus) -> AnyShapeStyle {
        switch signature {
        case .signed: AnyShapeStyle(CameraStyle.fact)
        case .unsigned(.turnedOff): AnyShapeStyle(CameraStyle.secondaryText)
        case .unsigned: AnyShapeStyle(CameraStyle.warning)
        }
    }

    /// Whether the photo is signed, and each signed file's manifest.
    @ViewBuilder private var signatureSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: NopeSpace.xs) {
                Image(systemName: Self.signatureSymbol(details.signature))
                    .foregroundStyle(Self.signatureStyle(details.signature))
                    .accessibilityHidden(true)
                Text(verbatim: CaptureMessages.message(for: details.signature))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                if let credentials = file.contentCredentials {
                    VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                        Text(verbatim: FormatsSettingsView.name(of: file.format)).font(.headline)
                        Text(
                            "Claim generator: \(credentials.generatorName) \(credentials.generatorVersion)", tableName: "Honesty", bundle: .module,
                            comment: "In the photo details: the software the Content Credentials manifest names as its claim generator. The values are a name and a version, such as Photivra Nope Camera 0.2.0.")
                        // The manifest's own words, which are part of the file and stay in English.
                        Text(verbatim: credentials.actionDescription)
                            .foregroundStyle(CameraStyle.secondaryText)
                        Text(
                            "Manifest SHA-256: \(credentials.manifestSHA256)", tableName: "Honesty", bundle: .module,
                            comment: "In the photo details: the SHA-256 hash of the file's Content Credentials manifest, as 64 hexadecimal digits. SHA-256 is a standard name; keep it unchanged.")
                            .font(.footnote.monospaced())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Signature", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: whether the photo carries a Content Credentials signature.")
        }
    }

    /// A timing row, in milliseconds, or nothing when the step didn't run.
    ///
    /// - Parameters:
    ///   - title: The step's name.
    ///   - duration: How long it took, or `nil`.
    @ViewBuilder private func timing(_ title: Text, _ duration: Duration?) -> some View {
        if let duration {
            DetailRow(title: title, value: Text(verbatim: Self.milliseconds(duration)))
        }
    }

    /// A duration as milliseconds, such as "112 ms", in the current language.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: The text.
    static func milliseconds(_ duration: Duration) -> String {
        Measurement(value: Double(SaveTimings.milliseconds(duration)), unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// What processing a file went through, in plain words.
    ///
    /// - Parameter processing: The processing.
    /// - Returns: The text, from `Honesty.xcstrings`.
    static func processing(_ processing: PhotoDetails.Processing) -> Text {
        switch processing {
        case .none:
            Text("The RAW sensor data as the camera delivered it. nope. didn't develop it.", tableName: "Honesty", bundle: .module, comment: "In the photo details, the processing of the RAW (DNG) file: nope. didn't develop or change it. Must not claim more than the English: it doesn't say the phone did nothing. Keep nope. unchanged.")
        case .developed(.standard):
            Text("Developed by nope. from the RAW, Standard look", tableName: "Honesty", bundle: .module, comment: "In the photo details, the processing of a HEIF or JPEG file: nope. developed it from the RAW with the Standard look (one overall tone curve). Keep nope. unchanged.")
        case .developed(.flat):
            Text("Developed by nope. from the RAW, Flat look", tableName: "Honesty", bundle: .module, comment: "In the photo details, the processing of a HEIF or JPEG file: nope. developed it from the RAW with the Flat look (no contrast curve). Keep nope. unchanged.")
        case .byDevice:
            Text("Processed by the phone's camera: this lens can't save RAW", tableName: "Honesty", bundle: .module, comment: "In the photo details, the processing of the fallback file of a lens without RAW: the phone's camera processed it.")
        }
    }

    /// Why an optional item isn't in the files.
    ///
    /// - Parameter state: What happened to the item.
    /// - Returns: The reason, from `Honesty.xcstrings`.
    static func reason(_ state: PhotoDetails.ItemReceipt.State) -> Text {
        switch state {
        case .removed, .written:
            Text("Off in Settings", tableName: "Honesty", bundle: .module, comment: "In the photo details, why a metadata item isn't in the files: the person's switch for it is off.")
        case .nothingToWrite:
            Text("On, but there was nothing to write", tableName: "Honesty", bundle: .module, comment: "In the photo details, why a metadata item isn't in the files although its switch is on: the camera gave no value for it, such as no location or no lens corrections.")
        }
    }
}

/// The clipping counted from the RAW sensor data when the photo was taken (issue #53): the share
/// of photosites that are clipped highlights and clipped shadows, then each color's, with the
/// definition under them; or why it wasn't measured.
struct RAWClippingSection: View {
    /// The clipping, or why it wasn't measured.
    let result: RAWClippingResult

    /// Creates the section.
    ///
    /// - Parameter result: The clipping, or why it wasn't measured.
    init(result: RAWClippingResult) {
        self.result = result
    }

    /// The section.
    var body: some View {
        Section {
            switch result {
            case .measured(let clipping):
                DetailRow(
                    title: Text("Clipped Highlights", bundle: .module, comment: "Row in the photo details: the share of the RAW's photosites recorded at or near the white level (full)."),
                    value: Self.share(clipping.highlightShare))
                DetailRow(
                    title: Text("Clipped Shadows", bundle: .module, comment: "Row in the photo details: the share of the RAW's photosites recorded at or near the black level (no signal)."),
                    value: Self.share(clipping.shadowShare))
                ForEach(clipping.channels, id: \.color) { channel in
                    DetailRow(
                        title: Self.name(of: channel.color),
                        value: Text(
                            "Highlights \(Self.percent(channel.highlightShare)), shadows \(Self.percent(channel.shadowShare))", bundle: .module,
                            comment: "In the photo details, one color of the RAW sensor's color filter: the share of its photosites that are clipped highlights, then clipped shadows, as percentages."))
                }
            case .notMeasured(let failure):
                Self.reason(failure)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Clipping in the RAW", bundle: .module, comment: "Heading in the photo details: how much of the RAW sensor data is clipped (recorded as full white or as black). RAW is a file format name.")
        } footer: {
            if case .measured = result {
                Text(
                    "Counted on the RAW sensor data when the photo was taken, over every photosite of the active area. Clipped highlights are within 0.5% of the white level or above it; clipped shadows are within 0.5% of the black level or below it, where 0.5% is of the range between the two levels.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Footer in the photo details: how the RAW clipping is defined and measured. A photosite is one sensor element. The white and black levels are the RAW file's own values. Must not claim more than the English.")
            }
        }
    }

    /// A share of photosites, such as "0.4% of photosites".
    ///
    /// - Parameter share: The share, 0 to 1.
    /// - Returns: The text.
    static func share(_ share: Double) -> Text {
        Text("\(percent(share)) of photosites", bundle: .module, comment: "In the photo details: a share of the RAW's photosites, such as 0.4% of photosites. A photosite is one sensor element.")
    }

    /// A share as a percentage with up to two significant digits, such as "0.4%" or "0.0012%",
    /// so a small share never reads as 0; exactly 0 is "0%".
    ///
    /// - Parameter share: The share, 0 to 1.
    /// - Returns: The percentage, in the current language.
    static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.significantDigits(1...2)))
    }

    /// The name of a color of the color filter.
    ///
    /// - Parameter color: The color.
    /// - Returns: The name.
    static func name(of color: CFAColor) -> Text {
        switch color {
        case .red: Text("Red", bundle: .module, comment: "In the photo details: the red photosites of the RAW sensor's color filter.")
        case .green: Text("Green", bundle: .module, comment: "In the photo details: the green photosites of the RAW sensor's color filter.")
        case .blue: Text("Blue", bundle: .module, comment: "In the photo details: the blue photosites of the RAW sensor's color filter.")
        }
    }

    /// Why the clipping wasn't measured, in plain words.
    ///
    /// - Parameter failure: The reason.
    /// - Returns: The text, from `Honesty.xcstrings`.
    static func reason(_ failure: RAWClippingFailure) -> Text {
        switch failure {
        case .noSamples:
            Text("Not measured: the camera gave no RAW samples to count.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera returned no RAW sensor samples with the photo.")
        case .unsupportedLayout:
            Text("Not measured: nope. can't read how this camera lays out its RAW samples.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera's RAW sample format isn't one nope. reads. Keep nope. unchanged.")
        case .levelsUnreadable:
            Text("Not measured: the camera's RAW file doesn't give black and white levels that nope. can apply.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the RAW file's black and white levels are missing or in a form nope. doesn't apply. Keep nope. unchanged.")
        case .sizeMismatch:
            Text("Not measured: the RAW samples and the RAW file differ in size.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera's RAW samples and its RAW file don't have the same size, so they can't be compared.")
        case .scaleMismatch:
            Text("Not measured: the RAW samples don't fit the RAW file's white level.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera's RAW sample values are larger than the RAW file's white level allows, so they can't be compared.")
        }
    }
}

/// One file's rows: its format and size, then its pixel size, bit depth and, for a DNG, the
/// color filter pattern, levels and lens corrections.
struct FileDetailsRows: View {
    /// The file.
    let file: PhotoDetails.File

    /// Creates the rows.
    ///
    /// - Parameter file: The file.
    init(file: PhotoDetails.File) {
        self.file = file
    }

    /// The rows, as one element per file for VoiceOver.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            HStack {
                Text(verbatim: FormatsSettingsView.name(of: file.format)).font(.headline)
                Spacer(minLength: 8)
                Text(verbatim: file.byteCount.formatted(.byteCount(style: .file)))
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            if let width = file.pixelWidth, let height = file.pixelHeight {
                Text(
                    "\(width.formatted(.number.grouping(.never))) × \(height.formatted(.number.grouping(.never))) pixels", bundle: .module,
                    comment: "In the photo details: a file's size in pixels, width by height, such as 4032 × 3024 pixels.")
            }
            if let bitDepth = file.bitDepth {
                Text("Bit depth: \(bitDepth)", bundle: .module, comment: "In the photo details: a file's bit depth, the number of bits stored for each sample, such as 16.")
            }
            if let pattern = file.colorFilterPattern {
                Text("Color filter pattern: \(pattern)", bundle: .module, comment: "In the photo details: the RAW sensor's color filter pattern, as letters such as RGGB (R red, G green, B blue). Keep the letters unchanged.")
            }
            if !file.blackLevels.isEmpty {
                Text("Black level: \(Self.levels(file.blackLevels))", bundle: .module, comment: "In the photo details: the RAW file's black level values, as numbers.")
            }
            if !file.whiteLevels.isEmpty {
                Text("White level: \(Self.levels(file.whiteLevels))", bundle: .module, comment: "In the photo details: the RAW file's white level values, as numbers.")
            }
            if file.format == .raw {
                if file.storesLensCorrections {
                    Text("Lens corrections: stored, not applied", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW file holds lens correction instructions that editors can use, but nope. didn't apply them to the pixels.")
                } else {
                    Text("Lens corrections: not stored", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW file holds no lens correction instructions.")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Level values as a list, such as "528, 528, 528, 528".
    ///
    /// - Parameter values: The values.
    /// - Returns: The list, in the current language.
    static func levels(_ values: [Double]) -> String {
        values.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) }
            .formatted(.list(type: .and, width: .narrow))
    }
}

/// A row with a title on the leading side and a value on the trailing side that wraps under it
/// at large text sizes.
struct DetailRow: View {
    /// The title.
    let title: Text

    /// The value.
    let value: Text

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - value: The value.
    init(title: Text, value: Text) {
        self.title = title
        self.value = value
    }

    /// The row.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: 8)
                value.foregroundStyle(CameraStyle.secondaryText).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                title
                value.foregroundStyle(CameraStyle.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension Image {
    /// An image of a photo's thumbnail, made from its RGBA pixels with Core Graphics.
    ///
    /// - Parameter thumbnail: The thumbnail.
    /// - Returns: The image, or `nil` if Core Graphics can't make one.
    static func photo(_ thumbnail: PhotoThumbnail) -> Image? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: thumbnail.rgba as CFData),
            let image = CGImage(
                width: thumbnail.width, height: thumbnail.height, bitsPerComponent: 8,
                bitsPerPixel: 8 * PhotoThumbnail.bytesPerPixel, bytesPerRow: thumbnail.bytesPerRow, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return Image(decorative: image, scale: 1)
    }
}
