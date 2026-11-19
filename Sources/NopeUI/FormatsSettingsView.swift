import NopeCore
import SwiftUI

/// Chooses the formats each photo is saved in: a native checkmark list.
///
/// At least one format stays selected: `NopeSettings/canTurnOff(_:deviceSupportsBayerRAW:)`
/// disables the last one. On a device without Bayer RAW the RAW row stays visible, unavailable,
/// and says why. The camera's format status shows the same list between an explanation of the
/// next photo and its links (``FormatDetailsSheet``) for a lens with RAW; for a lens without RAW
/// that sheet shows its one processed file instead, read-only.
struct FormatsSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Whether any camera on the device gives Bayer RAW.
    let deviceSupportsBayerRAW: Bool

    /// Sections shown above the formats, or `nil`.
    let explanation: AnyView?

    /// Sections shown below the formats, or `nil`.
    let footer: AnyView?

    /// Creates the formats list.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    ///   - explanation: Sections shown above the formats, or `nil`.
    ///   - footer: Sections shown below the formats, or `nil`.
    init(
        settings: NopeSettings, deviceSupportsBayerRAW: Bool,
        explanation: AnyView? = nil, footer: AnyView? = nil
    ) {
        self.settings = settings
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
        self.explanation = explanation
        self.footer = footer
    }

    /// The list of formats.
    var body: some View {
        NopeForm {
            if let explanation {
                explanation
            }
            Section {
                ForEach(PhotoFormat.allCases, id: \.self) { format in
                    row(for: format)
                }
            } header: {
                Text("Save Each Photo As", bundle: .module, comment: "Section header above the list of file formats.")
            } footer: {
                VStack(alignment: .leading, spacing: NopeSpace.xs) {
                    Text("At least one format is required.", bundle: .module, comment: "Explains why the last selected format can't be turned off.")
                    if !deviceSupportsBayerRAW {
                        Text(
                            "This device's cameras don't provide unprocessed RAW.", tableName: "Honesty", bundle: .module,
                            comment: "Explains why the RAW format can't be chosen on this device. RAW is a file format name.")
                    }
                }
            }
            if settings.offersRAWPairingChoice(deviceSupportsBayerRAW: deviceSupportsBayerRAW) {
                Section {
                    pairingPicker
                }
            }
            if let footer {
                footer
            }
        }
        .navigationTitle(Text("Formats", bundle: .module, comment: "Settings row and screen title: the file formats each photo is saved in."))
    }

    /// Which copy Photos keeps with the RAW when RAW, HEIF and JPEG are all saved (issue #50).
    private var pairingPicker: some View {
        Picker(selection: Binding(get: { settings.rawPairing }, set: { settings.setRAWPairing($0) })) {
            ForEach(RAWPairing.allCases, id: \.self) { pairing in
                Text(verbatim: Self.name(of: pairing.format)).tag(pairing)
            }
        } label: {
            SettingLabel(
                title: Text("Paired with RAW", bundle: .module, comment: "Picker: which processed copy (HEIF or JPEG) Photos keeps together with the RAW. RAW is a file format name."),
                explanation: Text(
                    "Photos keeps one copy with the RAW as a single photo. The other copy is saved as a separate photo.",
                    bundle: .module,
                    comment: "Explains why there are two items in Photos when RAW, HEIF and JPEG are all saved. Photos is the system photo library app. RAW is a file format name."))
        }
        // A pushed list: a menu picker failed the night mode color tests (the system draws an
        // open menu outside the app's views). HEIF and JPEG Copies uses menus, as the design asks.
        .pickerStyle(.navigationLink)
    }

    /// One format's row: its name, a checkmark when selected, and why it's unavailable.
    ///
    /// - Parameter format: The format.
    private func row(for format: PhotoFormat) -> some View {
        let isAvailable = NopeSettings.isAvailable(format, deviceSupportsBayerRAW: deviceSupportsBayerRAW)
        let isSelected = settings.selectedFormats(deviceSupportsBayerRAW: deviceSupportsBayerRAW).contains(format)
        return Button {
            settings.setFormat(format, isSelected: !isSelected)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                    Text(verbatim: Self.name(of: format))
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    if let caption = caption(for: format, isAvailable: isAvailable) {
                        caption
                            .font(.footnote)
                            .foregroundStyle(CameraStyle.secondaryText)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable || (isSelected && !settings.canTurnOff(format, deviceSupportsBayerRAW: deviceSupportsBayerRAW)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Why a format's row is unavailable, or `nil`.
    ///
    /// - Parameters:
    ///   - format: The format.
    ///   - isAvailable: Whether the device can save the format.
    /// - Returns: "Not available on this device", or `nil`.
    private func caption(for format: PhotoFormat, isAvailable: Bool) -> Text? {
        guard format == .raw, !isAvailable else { return nil }
        return Text("Not available on this device", bundle: .module, comment: "Shown under the RAW format on a device without RAW.")
    }

    /// The format's name. Format names are the same in every language, so they aren't
    /// translated.
    ///
    /// - Parameter format: A format.
    /// - Returns: "RAW (DNG)", "HEIF" or "JPEG".
    static func name(of format: PhotoFormat) -> String {
        switch format {
        case .raw: "RAW (DNG)"
        case .heif: "HEIF"
        case .jpeg: "JPEG"
        }
    }

    /// The selected formats as a short list for the settings row, such as "RAW (DNG) and HEIF",
    /// using the system list format for the current language.
    ///
    /// - Parameters:
    ///   - settings: The settings.
    ///   - deviceSupportsBayerRAW: Whether RAW can be chosen on this device.
    /// - Returns: The available selected formats, in display order.
    static func summary(of settings: NopeSettings, deviceSupportsBayerRAW: Bool) -> String {
        settings.selectedFormats(deviceSupportsBayerRAW: deviceSupportsBayerRAW)
            .map(name(of:))
            .formatted(.list(type: .and))
    }
}
