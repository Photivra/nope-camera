import NopeCore
import SwiftUI

/// "What's in This Photo": what the app can say about a photo it saved in this session, read
/// back from the saved files (issue #53; `docs/design/BUILD-SPEC.md`, 3.15), opened from Photo
/// Details.
///
/// A native list in a fixed order: a summary card, then Exposure, Lens and Camera, RAW Sensor
/// Data, Files, Processing, Details in This Photo, Content Credentials, Every Tag and Timing, each
/// with a heading VoiceOver can jump between. Long lists are behind system disclosure rows; each
/// file's full tag list is a page of its own. Every value comes from `SavedPhoto.details`; a value
/// the app doesn't hold has no row.
///
/// Privacy: on screen only. Nothing is logged, stored or copied, the text can't be selected (no
/// clipboard access) and there is no share action. Identifying values (the location, maker
/// notes, IDs) read "Hidden" until the person asks; what was revealed is forgotten when the sheet
/// closes, and the contents are covered while the scene isn't active, so the app switcher's
/// snapshot holds no value.
struct PhotoDetailsSheet: View {
    /// The photos of the last press of the shutter: one, or a bracket's frames.
    let photos: [SavedPhoto]

    /// Opens Photos, or `nil` when the app can't.
    let openPhoto: (() -> Void)?

    /// The device's lenses, to name the lens a photo was taken with when the files don't.
    let lenses: [Lens]

    /// This session's records of the photos (`CameraModel.sessionPhotos`), for the lens and
    /// the time the summary shows (`docs/design/BUILD-SPEC.md`, section 6, item 15). Empty when
    /// the interface has none.
    let session: [SessionPhoto]

    /// The frame shown, for a bracket.
    @State private var selection: Int

    /// The identifying values the person chose to see. On screen only; forgotten when the sheet
    /// closes or another frame is chosen.
    @State private var revealed: Set<String> = []

    /// Whether the app is the active app; the contents are covered otherwise.
    @Environment(\.scenePhase) private var scenePhase

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - photos: The photos of the last press of the shutter.
    ///   - openPhoto: Opens Photos, or `nil`.
    ///   - lenses: The device's lenses, or none.
    ///   - session: This session's records of the photos, or none.
    ///   - selection: The index in `photos` of the frame shown first, for a bracket.
    init(
        photos: [SavedPhoto], openPhoto: (() -> Void)?, lenses: [Lens] = [], session: [SessionPhoto] = [],
        selection: Int = 0
    ) {
        self.photos = photos
        self.openPhoto = openPhoto
        self.lenses = lenses
        self.session = session
        _selection = State(initialValue: selection)
    }

    /// The photo shown.
    private var photo: SavedPhoto? {
        photos.indices.contains(selection) ? photos[selection] : photos.last
    }

    /// The session's record of the photo shown, or `nil` when the session has none.
    private var record: SessionPhoto? {
        photo.flatMap { shown in session.last { $0.photo == shown } }
    }

    /// The list, with a Done button, covered while the app isn't active.
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
                if let photo, let details = photo.details {
                    PhotoDetailsSections(
                        photo: photo, details: details, lens: record?.lens ?? lens(of: details),
                        takenAt: record?.takenAt, revealed: $revealed)
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
        .overlay {
            if scenePhase != .active {
                PhotoDetailsCover()
            }
        }
        .onChange(of: selection) { revealed = [] }
        .onChange(of: scenePhase) { if scenePhase == .background { revealed = [] } }
        .onDisappear { revealed = [] }
        .accessibilityIdentifier("PhotoDetails")
    }

    /// The lens a photo was taken with, from the device's lenses.
    ///
    /// - Parameter details: The photo's details.
    /// - Returns: The lens, or `nil` when it isn't known.
    private func lens(of details: PhotoDetails) -> Lens? {
        details.capture.flatMap { capture in lenses.first { $0.id == capture.lensID } }
    }
}

/// Covers the sheet while the app isn't the active app, so the app switcher's snapshot holds no
/// value (`docs/design/BUILD-SPEC.md`, 3.15).
struct PhotoDetailsCover: View {
    /// Creates the cover.
    init() {}

    /// An opaque background.
    var body: some View {
        Rectangle()
            .fill(.background)
            .ignoresSafeArea()
            .accessibilityIdentifier("PhotoDetails.cover")
    }
}

/// The groups of the photo details, in the fixed order of `docs/design/BUILD-SPEC.md`, 3.15.
struct PhotoDetailsSections: View {
    /// The photo.
    let photo: SavedPhoto

    /// The details shown.
    let details: PhotoDetails

    /// The lens the photo was taken with, or `nil`.
    let lens: Lens?

    /// When the shutter took the photo, from the session, or `nil`.
    let takenAt: Date?

    /// The identifying values the person chose to see.
    @Binding var revealed: Set<String>

    /// Creates the sections.
    ///
    /// - Parameters:
    ///   - photo: The photo.
    ///   - details: The details shown.
    ///   - lens: The lens, or `nil`.
    ///   - takenAt: When the shutter took the photo, or `nil`.
    ///   - revealed: The values the person chose to see.
    init(photo: SavedPhoto, details: PhotoDetails, lens: Lens?, takenAt: Date? = nil, revealed: Binding<Set<String>>) {
        self.photo = photo
        self.details = details
        self.lens = lens
        self.takenAt = takenAt
        self._revealed = revealed
    }

    /// The groups.
    var body: some View {
        PhotoSummaryCard(photo: photo, details: details, lens: lens, takenAt: takenAt)
        // A bracket's frame: its place in the bracket, from the session's values, right after
        // the summary (BUILD-SPEC.md, 3.15; docs/design/BRACKETING.md, section 4).
        if let place = photo.bracket {
            BracketDetailsSection(place: place)
        }
        ExposureSection(details: details)
        LensSection(details: details, lens: lens)
        if let raw = details.rawFile {
            SensorSection(file: raw, clipping: details.rawClipping)
        }
        FilesSection(details: details)
        ProcessingSection(details: details)
        MetadataItemsSection(details: details, revealed: $revealed)
        ContentCredentialsSection(details: details)
        EveryTagSection(details: details, revealed: $revealed)
        Section {
            DisclosureGroup {
                timing(Text("Taking the Photo", bundle: .module, comment: "Timing in the photo details: from pressing the shutter to the camera returning the photo."), details.timings.capture)
                timing(Text("Developing", bundle: .module, comment: "Timing in the photo details: developing the HEIF and JPEG from the RAW."), details.timings.develop)
                timing(Text("Signing", bundle: .module, comment: "Timing in the photo details: creating the Content Credentials signatures."), details.timings.sign)
                timing(Text("Reading Back", bundle: .module, comment: "Timing in the photo details: reading every file back and checking its metadata."), details.timings.readBack)
                timing(Text("Adding to Photos", bundle: .module, comment: "Timing in the photo details: adding the files to the photo library. Photos is the system photo library app."), details.timings.save)
            } label: {
                Text("Timing", bundle: .module, comment: "Heading in the photo details: how long each step of taking and saving the photo took, in milliseconds.")
            }
        } footer: {
            Text("Only for photos taken since nope. opened: nope. can't read your photo library, and these details aren't stored.", tableName: "Honesty", bundle: .module, comment: "Footer in the photo details. nope. has add-only access to the photo library, so it can show details only for photos it saved in this session, from memory. Keep nope. unchanged.")
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

    /// The symbol of the signature line: the seal when signed; the info symbol when signing is
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

    /// The color of the signature line's symbol: teal for a verified fact, the secondary text
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

/// A row with a title on the leading side and a value on the trailing side, with an optional
/// note under the value ("Not in the files", megapixels); the value and note go under the title
/// when they don't fit beside it.
struct DetailRow: View {
    /// The title.
    let title: Text

    /// The value.
    let value: Text

    /// A note under the value, or `nil`.
    let note: Text?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - value: The value.
    ///   - note: A note under the value, or `nil`.
    init(title: Text, value: Text, note: Text? = nil) {
        self.title = title
        self.value = value
        self.note = note
    }

    /// The row, read as one element: title, value, note.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: NopeSpace.xs)
                VStack(alignment: .trailing, spacing: NopeSpace.xxs) {
                    value.multilineTextAlignment(.trailing)
                    note.map { $0.font(.footnote).multilineTextAlignment(.trailing) }
                }
                .foregroundStyle(CameraStyle.secondaryText)
            }
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                title
                Group {
                    value
                    note.map { $0.font(.footnote) }
                }
                .foregroundStyle(CameraStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
