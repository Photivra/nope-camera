import NopeCore
import SwiftUI

/// The format status at the leading end of the status line (docs/design/BUILD-SPEC.md, 3.2): what
/// the next photo will be. A teal seal and the formats it is saved in ("RAW + HEIF") for a
/// single-frame RAW; for a lens without Bayer RAW, the "Processed" marker, an amber triangle and
/// the word, shown before the photo is taken (issue #80). Tapping it opens the explanation, the
/// lens's processing note and the formats (``FormatDetailsSheet``).
///
/// The person can hide the marker in Settings (`NopeSettings/showsProcessedMarker`). The status
/// then names the file the lens saves ("HEIF") with no symbol, and never the teal seal; VoiceOver
/// still says the photo is processed, and so do the photo's details.
///
/// In the status line it is a symbol and words with no fill. On the picture (the column layout,
/// and an iPhone held sideways, the `isStatusOnPicture` environment value) it keeps a capsule of
/// ``NopeMaterial/backing``, so it stays readable over any scene.
///
/// The wording is an honesty claim, so it lives in `Honesty.xcstrings` (AGENTS.md, "Honesty
/// wording is kept apart"). Teal marks only the fact the camera reported (the lens gives Bayer
/// RAW); the fallback uses a warning symbol and a word, never color alone. Format names are
/// Latin abbreviations, so they stay left to right in right-to-left layouts.
struct FormatChip: View {
    /// What the format status shows.
    enum Presentation: Equatable {
        /// The teal seal and the saved formats: the lens gives Bayer RAW.
        case raw
        /// The amber triangle and "Processed": the lens can't save RAW.
        case processedMarker
        /// The processed file's name with no symbol: the lens can't save RAW, and the person
        /// turned the marker off.
        case processedName

        /// The accessibility identifier of the format status in this presentation, for UI
        /// tests: "FormatStatus.raw", "FormatStatus.processedMarker" or
        /// "FormatStatus.processedName".
        var identifier: String {
            switch self {
            case .raw: "FormatStatus.raw"
            case .processedMarker: "FormatStatus.processedMarker"
            case .processedName: "FormatStatus.processedName"
            }
        }
    }

    /// The format of the next photo.
    let format: CaptureFormat

    /// The formats each photo is saved in, in display order. Used for a single-frame RAW; a lens
    /// without RAW saves only its processed file.
    let savedFormats: [PhotoFormat]

    /// Whether the "Processed" marker shows on a lens without RAW.
    let showsProcessedMarker: Bool

    /// Opens the explanation and the formats.
    let action: () -> Void

    /// Whether the status is drawn over the picture, where it gets a backing.
    @Environment(\.isStatusOnPicture) private var isOnPicture

    /// Creates the format status.
    ///
    /// - Parameters:
    ///   - format: The format of the next photo.
    ///   - savedFormats: The formats each photo is saved in, in display order.
    ///   - showsProcessedMarker: Whether the "Processed" marker shows on a lens without RAW
    ///     (`NopeSettings/showsProcessedMarker`).
    ///   - action: Opens the explanation and the formats.
    init(format: CaptureFormat, savedFormats: [PhotoFormat], showsProcessedMarker: Bool = true, action: @escaping () -> Void) {
        self.format = format
        self.savedFormats = savedFormats
        self.showsProcessedMarker = showsProcessedMarker
        self.action = action
    }

    /// Whether the format status is shown. With the controls shown it always is. In clean view
    /// only the "Processed" marker stays, so a processed photo is never taken unannounced
    /// (BUILD-SPEC.md, 3.1); a RAW lens's status, or a hidden marker's file name, goes with the
    /// controls.
    ///
    /// - Parameters:
    ///   - format: The format of the next photo.
    ///   - showsControls: Whether the camera's controls are shown (not clean view).
    ///   - showsProcessedMarker: Whether the "Processed" marker is on in Settings.
    /// - Returns: Whether to show it.
    static func isShown(for format: CaptureFormat, showsControls: Bool, showsProcessedMarker: Bool) -> Bool {
        showsControls || presentation(for: format, showsProcessedMarker: showsProcessedMarker) == .processedMarker
    }

    /// What the format status shows for a format.
    ///
    /// - Parameters:
    ///   - format: The format of the next photo.
    ///   - showsProcessedMarker: Whether the "Processed" marker is on in Settings.
    /// - Returns: The seal and formats, the marker, or the processed file's name.
    static func presentation(for format: CaptureFormat, showsProcessedMarker: Bool) -> Presentation {
        if format.isBayerRAW { return .raw }
        return showsProcessedMarker ? .processedMarker : .processedName
    }

    /// What the format status shows.
    private var presentation: Presentation {
        Self.presentation(for: format, showsProcessedMarker: showsProcessedMarker)
    }

    /// The format status.
    var body: some View {
        Button(action: action) {
            HStack(spacing: NopeSpace.xs) {
                symbol
                title
            }
        }
        .buttonStyle(FormatStatusStyle(isOnPicture: isOnPicture))
        // For tests: what the status shows, which its label and value don't say.
        .accessibilityIdentifier(presentation.identifier)
        .accessibilityLabel(Self.accessibilityName)
        .accessibilityValue(Text(verbatim: Self.spokenValue(for: format, savedFormats: savedFormats)))
        .accessibilityInputLabels([Self.accessibilityName, title])
        .accessibilityShowsLargeContentViewer()
    }

    /// The seal, the triangle, or nothing for a hidden marker.
    @ViewBuilder private var symbol: some View {
        switch presentation {
        case .raw:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(CameraStyle.fact)
                .accessibilityHidden(true)
        case .processedMarker:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CameraStyle.warning)
                .accessibilityHidden(true)
        case .processedName:
            EmptyView()
        }
    }

    /// "RAW + HEIF", "Processed", or the processed file's name ("HEIF").
    private var title: Text {
        switch presentation {
        case .raw:
            // Left-to-right marks keep "RAW + HEIF" in reading order in right-to-left layouts.
            Text(verbatim: "\u{200E}" + Self.names(of: savedFormats) + "\u{200E}")
        case .processedMarker:
            Text(
                "Processed", tableName: "Honesty", bundle: .module,
                comment: "Format status on the camera, with an amber triangle, before a photo on a lens that can't save RAW: the phone processes that lens's photos. The same word starts \"Processed: no RAW on this lens\"; use the same translation. Must not claim more than the English. Honesty wording: a fluent human must review every translation before release.")
        case .processedName:
            Text(verbatim: Self.names(of: Self.files(for: format, savedFormats: savedFormats)))
        }
    }

    /// "Photo Format", the name VoiceOver and Voice Control use.
    static var accessibilityName: Text {
        Text("Photo Format", tableName: "Honesty", bundle: .module, comment: "VoiceOver and Voice Control name of the chip at the top of the camera that says what the next photo will be. Tapping it explains the format and lists the formats.")
    }

    /// The files a photo with this format is saved as: the selected formats for a single-frame
    /// RAW, or the lens's one processed file (`PhotoSaver` saves only that file for a lens
    /// without RAW).
    ///
    /// - Parameters:
    ///   - format: The format of the next photo.
    ///   - savedFormats: The selected formats, in display order.
    /// - Returns: The formats, in display order.
    static func files(for format: CaptureFormat, savedFormats: [PhotoFormat]) -> [PhotoFormat] {
        switch format {
        case .bayerRAW: savedFormats
        case .processedFallback(.heif): [.heif]
        case .processedFallback(.jpeg): [.jpeg]
        }
    }

    /// The format status's VoiceOver value: "single-frame RAW, RAW + HEIF", or "Processed: no RAW
    /// on this lens, HEIF" for a lens without RAW, whether the marker shows or not
    /// (docs/design/ACCESSIBILITY.md, "VoiceOver order").
    ///
    /// - Parameters:
    ///   - format: The format of the next photo.
    ///   - savedFormats: The selected formats, in display order.
    /// - Returns: The value.
    static func spokenValue(for format: CaptureFormat, savedFormats: [PhotoFormat]) -> String {
        let files = names(of: files(for: format, savedFormats: savedFormats))
        guard !format.isBayerRAW else { return "\(spokenName(for: format)), \(files)" }
        let processed = String(
            localized: "Processed marker: spoken value", defaultValue: "Processed: no RAW on this lens", table: "Honesty",
            bundle: .module,
            comment: "VoiceOver value of the Processed marker on the camera, read before the format, for example \"Processed: no RAW on this lens, HEIF\". RAW is a file format name. Not the title-case chip text \"Processed: No RAW on This Lens\", which has its own key. Must not claim more than the English. Honesty wording: a fluent human must review every translation before release.")
        return "\(processed), \(files)"
    }

    /// The formats' short names joined with plus signs, such as "RAW + HEIF". The names are the
    /// same in every language and aren't translated.
    ///
    /// - Parameter formats: The formats, in display order.
    /// - Returns: The joined names.
    static func names(of formats: [PhotoFormat]) -> String {
        formats.map { format in
            switch format {
            case .raw: "RAW"
            case .heif: "HEIF"
            case .jpeg: "JPEG"
            }
        }
        .joined(separator: " + ")
    }

    /// The format's name for VoiceOver, as a sentence fragment.
    ///
    /// - Parameter format: A capture format.
    /// - Returns: For example "single-frame RAW" or "HEIF with some device processing".
    static func spokenName(for format: CaptureFormat) -> String {
        switch format {
        case .bayerRAW:
            String(localized: "single-frame RAW", table: "Honesty", bundle: .module, comment: "Spoken format name in the viewfinder description. RAW is a file format name.")
        case .processedFallback(.heif):
            String(localized: "HEIF with some device processing", table: "Honesty", bundle: .module, comment: "Spoken format name for the no-RAW fallback. HEIF is a file format name.")
        case .processedFallback(.jpeg):
            String(localized: "JPEG with some device processing", table: "Honesty", bundle: .module, comment: "Spoken format name for the no-RAW fallback. JPEG is a file format name.")
        }
    }
}

/// The look of the format status: ``NopeFont/status`` in white, a 44-point target, and on the
/// picture a capsule of ``NopeMaterial/backing`` (with an outline under Increase Contrast). In
/// the status line it has no fill, so its symbol lines up with the margin.
struct FormatStatusStyle: ButtonStyle {
    /// Whether the status is drawn over the picture.
    let isOnPicture: Bool

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the style.
    ///
    /// - Parameter isOnPicture: Whether the status is drawn over the picture.
    init(isOnPicture: Bool) {
        self.isOnPicture = isOnPicture
    }

    /// The styled status.
    ///
    /// - Parameter configuration: The label and press state.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NopeFont.status)
            .foregroundStyle(NopeColor.label)
            .padding(.horizontal, isOnPicture ? NopeSpace.s : 0)
            .frame(minHeight: NopeSize.pill)
            .modifier(
                NopeControlBackground(
                    appearance: NopeControlAppearance(
                        fill: isOnPicture ? .material(.backing) : .none, label: NopeColor.label,
                        secondaryLabel: NopeColor.labelSecondary,
                        outline: isOnPicture && contrast == .increased ? NopeColor.labelSecondary : nil),
                    shape: Capsule()))
            .nopeHitTarget()
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
    }
}

/// The format status's sheet: what the next photo is, in plain words; then, for a lens with RAW,
/// the formats to choose from, the Look row while a HEIF or JPEG copy is saved, and All Photo
/// Settings (BUILD-SPEC.md, 3.2). A popover on iPad, a sheet on iPhone.
///
/// For a lens without RAW the formats are read-only (owner decision of 2026-11-18): the sheet
/// shows the processing note (``ProcessingNote``, issue #80), the one processed file that lens
/// saves, that the format choices are for the other lenses, the Show Processed Marker switch, and
/// a row that opens Settings at Formats to change them. Nothing on it changes the formats.
///
/// Look, All Photo Settings and Formats for Other Lenses close the sheet and then open Settings
/// through `openSettingsAt`. Settings opens only once the sheet has gone, since the camera can't
/// show both at once.
struct FormatDetailsSheet: View {
    /// The person's settings.
    let settings: NopeSettings

    /// The format of the next photo.
    let format: CaptureFormat

    /// The selected lens's distortion correction, for the processing note of a lens without RAW.
    let distortionCorrection: DistortionCorrection

    /// Whether any camera on the device gives Bayer RAW.
    let deviceSupportsBayerRAW: Bool

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Opens Settings at a page, or `nil` where Settings can't be opened.
    @Environment(\.openSettingsAt) private var openSettingsAt

    /// The Settings page to open once the sheet has gone, or `nil`.
    @State private var settingsToOpen: SettingsID?

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - format: The format of the next photo.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    ///   - distortionCorrection: The selected lens's distortion correction
    ///     (`Lens/distortionCorrection`). Defaults to the value that claims least.
    init(
        settings: NopeSettings, format: CaptureFormat, deviceSupportsBayerRAW: Bool,
        distortionCorrection: DistortionCorrection = .notSwitchable
    ) {
        self.settings = settings
        self.format = format
        self.distortionCorrection = distortionCorrection
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
    }

    /// The explanation, the formats and the links, with a Done button.
    var body: some View {
        NavigationStack {
            content
                // A short title, so the picture behind the sheet stays in view.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        DoneButton { dismiss() }
                    }
                }
        }
        .onDisappear {
            guard let settingsToOpen else { return }
            self.settingsToOpen = nil
            openSettingsAt?(settingsToOpen)
        }
    }

    /// The formats to choose from for a lens with RAW; the read-only list for a lens without it.
    @ViewBuilder private var content: some View {
        if format.isBayerRAW {
            FormatsSettingsView(
                settings: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW,
                explanation: AnyView(Section { summary }), footer: AnyView(rawLensLinks))
        } else {
            processedLensForm
        }
    }

    /// Look while a HEIF or JPEG copy is saved, and All Photo Settings, for a lens with RAW.
    @ViewBuilder private var rawLensLinks: some View {
        if openSettingsAt != nil {
            Section {
                if settings.savesDevelopedFormat {
                    settingsLink(.copies) {
                        SettingsValueLabel(title: Text(SettingsText.look), value: CopiesSettingsView.title(of: settings.developedLook))
                    }
                }
                settingsLink(.photos) {
                    Text("All Photo Settings", bundle: .module, comment: "Button on the Photo Format sheet: closes the sheet and opens Settings at the Photos group (formats, HEIF and JPEG copies, photo size).")
                }
            }
        }
    }

    /// The sheet for a lens without RAW: the summary and the processing note, the one file the
    /// lens saves (read-only), the Show Processed Marker switch, and the row that opens Formats.
    private var processedLensForm: some View {
        NopeForm {
            Section {
                summary
            }
            ProcessingNote(distortionCorrection: distortionCorrection, look: settings.developedLook)
            Section {
                Text(verbatim: FormatChip.names(of: FormatChip.files(for: format, savedFormats: [])))
                    .accessibilityIdentifier("formatSheet.lensFile")
            } header: {
                Text(String(
                    localized: "Photo Format sheet: This Lens Saves", defaultValue: "This Lens Saves", bundle: .module,
                    comment: "Section header on the Photo Format sheet of a lens that can't save RAW, above the one file format that lens saves (for example HEIF). The list can't be changed there."))
            } footer: {
                Text(String(
                    localized: "Photo Format sheet: choices are for the other lenses",
                    defaultValue: "This lens saves one processed file. The formats you choose in Settings are for the other lenses.",
                    table: "Honesty", bundle: .module,
                    comment: "Footer on the Photo Format sheet of a lens that can't save RAW: that lens always saves its one processed file, and the format choices apply to the lenses that save RAW. Must not claim more than the English. Honesty wording: a fluent human must review every translation before release."))
            }
            Section {
                ExplainedToggle(
                    isOn: Binding(get: { settings.showsProcessedMarker }, set: { settings.setShowsProcessedMarker($0) }),
                    title: Text(SettingsText.showProcessedMarker),
                    explanation: Text(
                        "Shows Processed on the camera when a lens can't save RAW.", tableName: "Honesty", bundle: .module,
                        comment: "Explains the Show Processed Marker switch. \"Processed\" is the marker's text on the camera; use the same word as its translation. RAW is a file format name. Must not claim more than the English."))
            }
            if openSettingsAt != nil {
                Section {
                    settingsLink(.formats) {
                        Text(String(
                            localized: "Photo Format sheet: Formats for Other Lenses", defaultValue: "Formats for Other Lenses",
                            bundle: .module,
                            comment: "Button on the Photo Format sheet of a lens that can't save RAW: closes the sheet and opens Settings at Formats, where the formats of the other lenses are chosen."))
                    }
                }
            }
        }
        .navigationTitle(Text("Formats", bundle: .module, comment: "Settings row and screen title: the file formats each photo is saved in."))
    }

    /// A row that closes the sheet and then opens Settings at a page, drawn like a navigation
    /// row.
    ///
    /// - Parameters:
    ///   - id: The Settings page or group to open.
    ///   - label: The row's title, and its value if it has one.
    private func settingsLink(_ id: SettingsID, @ViewBuilder label: () -> some View) -> some View {
        Button {
            settingsToOpen = id
            dismiss()
        } label: {
            HStack(spacing: NopeSpace.xs) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CameraStyle.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    /// What the next photo is, in plain words, after a teal seal or an amber warning symbol.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: NopeSpace.s) {
            Image(systemName: format.isBayerRAW ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(format.isBayerRAW ? CameraStyle.fact : CameraStyle.warning)
                .accessibilityHidden(true)
            Group {
                if format.isBayerRAW {
                    Text(
                        "Each photo is one frame from the sensor, saved as RAW with as little processing as this phone allows. HEIF and JPEG copies are developed from it.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the format chip on the camera. RAW, HEIF and JPEG are file format names. Must not claim more than the English: as little processing as the phone allows, not zero.")
                } else {
                    Text(
                        "This lens can't save unprocessed RAW. Its photos have some device processing.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the no-RAW fallback. Must not claim more than the English: the photo IS processed by the device.")
                }
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The confirm button of a sheet: the system checkmark, named "Done" for VoiceOver and Voice
/// Control, with the Large Content Viewer at accessibility text sizes.
struct DoneButton: View {
    /// Closes the sheet.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Closes the sheet.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                Text("Done", bundle: .module, comment: "Button that closes a sheet, such as Settings or Pro Tools.")
            } icon: {
                Image(systemName: "checkmark")
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityShowsLargeContentViewer()
    }
}
