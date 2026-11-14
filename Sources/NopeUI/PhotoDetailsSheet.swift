import NopeCore
import SwiftUI

/// "What's in This Photo": the facts read back from a photo nope. just saved (issue #53),
/// opened from the last-photo thumbnail.
///
/// A native list with one section per topic, each with a heading VoiceOver can jump between:
/// the files, the exposure as written, the processing, the signature, the details kept and left
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
        signatureSection
        exposureSection
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                DetailRow(title: Text(verbatim: FormatsSettingsView.name(of: file.format)), value: Self.processing(file.processing))
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

    /// Whether the photo is signed, and each signed file's manifest.
    @ViewBuilder private var signatureSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: details.signature == .signed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(details.signature == .signed ? CameraStyle.fact : CameraStyle.warning)
                    .accessibilityHidden(true)
                Text(verbatim: CaptureMessages.message(for: details.signature))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                if let credentials = file.contentCredentials {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: FormatsSettingsView.name(of: file.format)).font(.headline)
                        Text(
                            "Claim generator: \(credentials.generatorName) \(credentials.generatorVersion)", tableName: "Honesty", bundle: .module,
                            comment: "In the photo details: the software the Content Credentials manifest names as its claim generator. The values are a name and a version, such as Photivra Nope Camera 0.2.0.")
                        // The manifest's own words, which are part of the file and stay in English.
                        Text(verbatim: credentials.actionDescription)
                            .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: FormatsSettingsView.name(of: file.format)).font(.headline)
                Spacer(minLength: 8)
                Text(verbatim: file.byteCount.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
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
                value.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                value.foregroundStyle(.secondary)
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
