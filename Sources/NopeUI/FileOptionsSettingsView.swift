import NopeCore
import SwiftUI

/// How the HEIF and JPEG copies are encoded (issue #57): compression, HEIF bit depth, color
/// space and size, each a native picker with a one-line explanation, and a button that restores the
/// defaults.
///
/// Advanced options: Settings links to this screen only while HEIF or JPEG is selected, and the
/// defaults need no change (owner principle: full auto by default, every file setting the
/// device allows behind the advanced options). The rules and values are in
/// `DevelopedFileOptions`; this view only shows them.
struct FileOptionsSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Creates the file options.
    ///
    /// - Parameter settings: The settings to show and change.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The form.
    var body: some View {
        Form {
            // Each picker has a short name, so its value fits beside it, and its explanation in
            // the row below: with the explanation in the label, a long value such as "System
            // Default" was clipped (accessibility audit).
            if settings.formats.contains(.heif) {
                Section { qualityPicker(for: .heif) }
                Section { bitDepthPicker }
            }
            if settings.formats.contains(.jpeg) {
                Section { qualityPicker(for: .jpeg) }
            }
            Section { colorSpacePicker }
            Section { sizePicker }
            // A row rather than a section footer: the accessibility audit reported footers as
            // not following Dynamic Type (see LookSettingsView).
            Section {
                Text(
                    "This changes only the HEIF and JPEG copies. The RAW is never changed.", tableName: "Honesty", bundle: .module,
                    comment: "Footer under the look picker. RAW, HEIF and JPEG are file format names. Must not claim more than the English.")
                    .font(.footnote)
                if !settings.fileOptions.isDefault {
                    Button {
                        settings.setFileOptions(DevelopedFileOptions())
                    } label: {
                        Text("Restore Defaults", bundle: .module, comment: "Button that sets every file option back to its default.")
                    }
                    // Primary text: the tinted text of a form button failed the contrast audit
                    // on the dark grouped background.
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(Self.rowTitle)
    }

    /// The row and screen title, "File Options".
    static var rowTitle: Text {
        Text("File Options", bundle: .module, comment: "Settings row and screen title: advanced options for how the HEIF and JPEG copies are encoded (compression, bit depth, color space).")
    }

    /// A navigation row to the file options, showing whether they are at their defaults.
    ///
    /// - Parameter settings: The settings.
    static func link(settings: NopeSettings) -> some View {
        NavigationLink {
            FileOptionsSettingsView(settings: settings)
        } label: {
            LabeledContent {
                if settings.fileOptions.isDefault {
                    Text(String(localized: "File options: Default", defaultValue: "Default", bundle: .module, comment: "Settings row value: every file option is at its default."))
                } else {
                    Text(String(localized: "File options: Custom", defaultValue: "Custom", bundle: .module, comment: "Settings row value: at least one file option was changed from its default."))
                }
            } label: {
                rowTitle
            }
        }
    }

    /// The compression picker for HEIF or JPEG.
    ///
    /// - Parameter format: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    @ViewBuilder
    private func qualityPicker(for format: PhotoFormat) -> some View {
        Picker(
            selection: Binding(
                get: { settings.fileOptions.quality(for: format) },
                set: { quality in
                    var options = settings.fileOptions
                    if format == .heif { options.heifQuality = quality } else { options.jpegQuality = quality }
                    settings.setFileOptions(options)
                })
        ) {
            ForEach(CompressionQuality.allCases, id: \.self) { quality in
                Self.title(of: quality).tag(quality)
            }
        } label: {
            format == .heif
                ? Text("HEIF Compression", bundle: .module, comment: "Picker: how much the HEIF copy is compressed. HEIF is a file format name.")
                : Text("JPEG Compression", bundle: .module, comment: "Picker: how much the JPEG copy is compressed. JPEG is a file format name.")
        }
        // A pushed list: a menu's long value, such as "System Default", was reported clipped.
        .pickerStyle(.navigationLink)
        Text(
            "Lower quality makes smaller files, with visible compression in fine detail.", bundle: .module,
            comment: "Explains the compression pickers.")
            .font(.footnote)
            .foregroundStyle(CameraStyle.secondaryText)
    }

    /// The HEIF bit depth picker.
    @ViewBuilder
    private var bitDepthPicker: some View {
        Picker(
            selection: Binding(
                get: { settings.fileOptions.heifBitDepth },
                set: { depth in
                    var options = settings.fileOptions
                    options.heifBitDepth = depth
                    settings.setFileOptions(options)
                })
        ) {
            ForEach(HEIFBitDepth.allCases, id: \.self) { depth in
                Self.title(of: depth).tag(depth)
            }
        } label: {
            Text("HEIF Bit Depth", bundle: .module, comment: "Picker: bits per color channel of the HEIF copy. HEIF is a file format name.")
        }
        // A pushed list: a menu's long value, such as "System Default", was reported clipped.
        .pickerStyle(.navigationLink)
        Text(
            "10-bit keeps smoother gradients. 8-bit files are smaller.", bundle: .module,
            comment: "Explains the HEIF bit depth picker.")
            .font(.footnote)
            .foregroundStyle(CameraStyle.secondaryText)
    }

    /// The color space picker.
    @ViewBuilder
    private var colorSpacePicker: some View {
        Picker(
            selection: Binding(
                get: { settings.fileOptions.colorSpace },
                set: { space in
                    var options = settings.fileOptions
                    options.colorSpace = space
                    settings.setFileOptions(options)
                })
        ) {
            ForEach(OutputColorSpace.allCases, id: \.self) { space in
                Text(verbatim: Self.name(of: space)).tag(space)
            }
        } label: {
            Text("Color Space", bundle: .module, comment: "Picker: the color space of the HEIF and JPEG copies (Display P3 or sRGB).")
        }
        // A pushed list: a menu's long value, such as "System Default", was reported clipped.
        .pickerStyle(.navigationLink)
        Text(
            "Display P3 keeps the camera's colors. sRGB suits sites and screens that show only sRGB; colors outside it are clipped.",
            bundle: .module, comment: "Explains the color space picker. Display P3 and sRGB are color space names; keep them unchanged.")
            .font(.footnote)
            .foregroundStyle(CameraStyle.secondaryText)
    }

    /// The size picker.
    @ViewBuilder
    private var sizePicker: some View {
        Picker(
            selection: Binding(
                get: { settings.fileOptions.size },
                set: { size in
                    var options = settings.fileOptions
                    options.size = size
                    settings.setFileOptions(options)
                })
        ) {
            ForEach(OutputSize.allCases, id: \.self) { size in
                Self.title(of: size).tag(size)
            }
        } label: {
            Text("Copy Size", bundle: .module, comment: "Picker: the width and height of the HEIF and JPEG copies, compared with the RAW.")
        }
        // A pushed list: a menu's long value was reported clipped.
        .pickerStyle(.navigationLink)
        Text(
            "Smaller copies are quicker to share and take less space. The RAW keeps every pixel.", bundle: .module,
            comment: "Explains the copy size picker. RAW is a file format name.")
            .font(.footnote)
            .foregroundStyle(CameraStyle.secondaryText)
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
