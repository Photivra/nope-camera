import NopeCore
import SwiftUI

/// HEIF and JPEG Copies: the look and the file options of the copies developed from the RAW, on
/// one page (`docs/design/BUILD-SPEC.md`, 3.10; it replaces the Look and File Options pages).
///
/// Sections, in order: a line saying no copy is saved, while none is; Look (Standard, Flat, each
/// with its sentence); Files (HEIF Compression, HEIF Bit Depth, JPEG Compression, Color Space and
/// Copy Size, each a menu on its row with its explanation); Restore Defaults, while a file
/// option is changed, with the footer that the RAW is never changed. Every control stays
/// enabled with RAW only, so the copies can be set up before one is turned on in Formats. The
/// Settings row is always shown. The rules and values are in `NopeSettings` and
/// `DevelopedFileOptions`; this view only shows them.
struct CopiesSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Where Settings is, to scroll to a row search opened, or `nil`.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    /// Creates the page.
    ///
    /// - Parameter settings: The settings to show and change.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The form.
    var body: some View {
        NopeForm {
            if !settings.savesDevelopedFormat {
                Section {
                    // A plain text row, as the notes on the other pages: with the info symbol
                    // of the drawing (a Label), the audit reported the sentence as clipped,
                    // though it showed in full.
                    Text(
                        "No HEIF or JPEG copy is saved now. Turn one on in Formats.", bundle: .module,
                        comment: "First row of the HEIF and JPEG Copies page while only RAW is saved. Formats is the name of the Settings page where the formats are chosen. HEIF, JPEG and RAW are file format names.")
                        .accessibilityIdentifier("settings.copies.notSaved")
                }
            }
            lookSection
            filesSection
            restoreSection
        }
        .navigationTitle(Text(SettingsText.copies))
        .modifier(SettingsScrollTarget(navigation: navigation, page: .copies))
    }

    /// Standard and Flat, each with its sentence.
    private var lookSection: some View {
        Section {
            Picker(selection: Binding(get: { settings.developedLook }, set: { settings.setDevelopedLook($0) })) {
                ForEach(DevelopedLook.allCases, id: \.self) { look in
                    SettingLabel(title: Self.title(of: look), explanation: Self.explanation(of: look))
                        .tag(look)
                }
            } label: {
                Text("HEIF and JPEG Look", bundle: .module, comment: "Picker label: how the HEIF and JPEG copies are developed from the RAW. HEIF and JPEG are file format names.")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(SettingsText.look)
        }
        .settingsRow(.copiesLook)
    }

    /// The five file options.
    private var filesSection: some View {
        Section {
            qualityPicker(for: .heif)
                .settingsContainerRow(.heifCompression)
            filePicker(
                title: SettingsText.heifBitDepth,
                explanation: Text("10-bit keeps smoother gradients. 8-bit files are smaller.", bundle: .module, comment: "Explains the HEIF bit depth picker."),
                selection: Binding(
                    get: { settings.fileOptions.heifBitDepth },
                    set: { depth in update { $0.heifBitDepth = depth } }),
                choices: HEIFBitDepth.allCases, name: Self.title(of:)
            )
            .settingsContainerRow(.heifBitDepth)
            qualityPicker(for: .jpeg)
                .settingsContainerRow(.jpegCompression)
            filePicker(
                title: SettingsText.colorSpace,
                explanation: Text(
                    "Display P3 keeps the camera's colors. sRGB suits sites and screens that show only sRGB; colors outside it are clipped.",
                    bundle: .module, comment: "Explains the color space picker. Display P3 and sRGB are color space names; keep them unchanged."),
                selection: Binding(
                    get: { settings.fileOptions.colorSpace },
                    set: { space in update { $0.colorSpace = space } }),
                choices: OutputColorSpace.allCases, name: { Text(verbatim: Self.name(of: $0)) }
            )
            .settingsContainerRow(.colorSpace)
            filePicker(
                title: SettingsText.copySize,
                explanation: Text(
                    "Smaller copies are quicker to share and take less space. The RAW keeps every pixel.", bundle: .module,
                    comment: "Explains the copy size picker. RAW is a file format name."),
                selection: Binding(
                    get: { settings.fileOptions.size },
                    set: { size in update { $0.size = size } }),
                choices: OutputSize.allCases, name: Self.title(of:)
            )
            .settingsContainerRow(.copySize)
        } header: {
            Text("Files", bundle: .module, comment: "Section header on the HEIF and JPEG Copies page, above the compression, bit depth, color space and size of the copies.")
        }
    }

    /// Restore Defaults, while a file option is changed, and the footer.
    private var restoreSection: some View {
        Section {
            if !settings.fileOptions.isDefault {
                Button {
                    settings.setFileOptions(DevelopedFileOptions())
                } label: {
                    Text(SettingsText.restoreDefaults)
                }
                // Primary text: the tinted text of a form button failed the contrast audit on
                // the dark grouped background.
                .foregroundStyle(.primary)
                .settingsRow(.copiesRestoreDefaults)
            }
            // A row rather than a section footer: the accessibility audit reported footers as
            // not following Dynamic Type.
            Text(
                "This changes only the HEIF and JPEG copies. The RAW is never changed.", tableName: "Honesty", bundle: .module,
                comment: "Footer under the look picker. RAW, HEIF and JPEG are file format names. Must not claim more than the English.")
                .font(.footnote)
                .foregroundStyle(CameraStyle.secondaryText)
        }
    }

    /// Changes the file options.
    ///
    /// - Parameter change: The change to make.
    private func update(_ change: (inout DevelopedFileOptions) -> Void) {
        var options = settings.fileOptions
        change(&options)
        settings.setFileOptions(options)
    }

    /// The compression menu for HEIF or JPEG.
    ///
    /// - Parameter format: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    private func qualityPicker(for format: PhotoFormat) -> some View {
        filePicker(
            title: format == .heif ? SettingsText.heifCompression : SettingsText.jpegCompression,
            explanation: Text(
                "Lower quality makes smaller files, with visible compression in fine detail.", bundle: .module,
                comment: "Explains the compression pickers."),
            selection: Binding(
                get: { settings.fileOptions.quality(for: format) },
                set: { quality in
                    update { options in
                        if format == .heif { options.heifQuality = quality } else { options.jpegQuality = quality }
                    }
                }),
            choices: CompressionQuality.allCases, name: Self.title(of:))
    }

    /// One file option: a menu on its row, with its explanation under its name.
    ///
    /// - Parameters:
    ///   - title: The option's name.
    ///   - explanation: What it does.
    ///   - selection: The chosen value.
    ///   - choices: The values, in order.
    ///   - name: A value's name.
    private func filePicker<Value: Hashable>(
        title: LocalizedStringResource, explanation: Text, selection: Binding<Value>, choices: [Value],
        name: @escaping (Value) -> Text
    ) -> some View {
        Picker(selection: selection) {
            ForEach(choices, id: \.self) { value in
                name(value).tag(value)
            }
        } label: {
            SettingLabel(title: Text(title), explanation: explanation)
        }
        .pickerStyle(.menu)
    }

    /// The Settings row: the look while a copy is saved, "Not Saved" otherwise.
    ///
    /// - Parameter settings: The settings.
    /// - Returns: The value text.
    static func summary(of settings: NopeSettings) -> Text {
        if settings.savesDevelopedFormat {
            title(of: settings.developedLook)
        } else {
            Text("Not Saved", bundle: .module, comment: "Value of the HEIF and JPEG Copies row in Settings: only RAW is saved, so no copy is made.")
        }
    }

    /// A look's name.
    ///
    /// - Parameter look: The look.
    /// - Returns: "Standard" or "Flat".
    static func title(of look: DevelopedLook) -> Text {
        switch look {
        case .standard: Text("Standard", bundle: .module, comment: "Developed look: normal-looking HEIF and JPEG.")
        case .flat: Text("Flat", bundle: .module, comment: "Developed look: no contrast curve, closest to the sensor.")
        }
    }

    /// What a look does, in one line.
    ///
    /// - Parameter look: The look.
    /// - Returns: The explanation, from `Honesty.xcstrings`.
    static func explanation(of look: DevelopedLook) -> Text {
        switch look {
        case .standard:
            Text(
                "One overall tone curve, so the photo looks normal.", tableName: "Honesty", bundle: .module,
                comment: "Explains the Standard look: a single global tone curve, nothing local. Must not claim more than the English.")
        case .flat:
            Text(
                "No contrast curve: closest to the sensor, so it looks flat and low in contrast.", tableName: "Honesty", bundle: .module,
                comment: "Explains the Flat look. Must not claim more than the English.")
        }
    }

    /// A size's name.
    ///
    /// - Parameter size: The size.
    /// - Returns: Its localized name.
    static func title(of size: OutputSize) -> Text {
        switch size {
        case .full: Text("Full Size", bundle: .module, comment: "Copy size choice: the same width and height as the RAW.")
        case .half: Text("Half Size", bundle: .module, comment: "Copy size choice: half the width and height of the RAW (a quarter of the pixels).")
        case .quarter: Text("Quarter Size", bundle: .module, comment: "Copy size choice: a quarter of the width and height of the RAW.")
        }
    }

    /// A compression's name.
    ///
    /// - Parameter quality: The compression.
    /// - Returns: Its localized name.
    static func title(of quality: CompressionQuality) -> Text {
        switch quality {
        case .systemDefault: Text("System Default", bundle: .module, comment: "Compression choice: the system encoder's own quality.")
        case .maximum: Text("Maximum Quality", bundle: .module, comment: "Compression choice: the highest quality and largest files.")
        case .high: Text("High Quality", bundle: .module, comment: "Compression choice: high quality, smaller files than maximum.")
        case .medium: Text("Medium Quality", bundle: .module, comment: "Compression choice: medium quality, smaller files.")
        }
    }

    /// A bit depth's name.
    ///
    /// - Parameter depth: The bit depth.
    /// - Returns: "10-bit" or "8-bit", localized.
    static func title(of depth: HEIFBitDepth) -> Text {
        switch depth {
        case .ten: Text("10-bit", bundle: .module, comment: "HEIF bit depth choice: 10 bits per color channel.")
        case .eight: Text("8-bit", bundle: .module, comment: "HEIF bit depth choice: 8 bits per color channel.")
        }
    }

    /// A color space's name. Color space names are the same in every language, so they aren't
    /// translated.
    ///
    /// - Parameter space: The color space.
    /// - Returns: "Display P3" or "sRGB".
    static func name(of space: OutputColorSpace) -> String {
        switch space {
        case .displayP3: "Display P3"
        case .sRGB: "sRGB"
        }
    }
}
