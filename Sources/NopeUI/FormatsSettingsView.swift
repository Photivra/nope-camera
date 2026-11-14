import NopeCore
import SwiftUI

/// Chooses the formats each photo is saved in: a native checkmark list.
///
/// At least one format stays selected: `NopeSettings/canTurnOff(_:deviceSupportsBayerRAW:)`
/// disables the last one. On a device without Bayer RAW the RAW row stays visible, unavailable, and says why.
/// The camera's format chip shows the same list under an explanation of the next photo, with a
/// link to the look (``FormatDetailsSheet``).
struct FormatsSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Whether any camera on the device gives Bayer RAW.
    let deviceSupportsBayerRAW: Bool

    /// An explanation shown above the formats, or `nil`.
    let explanation: AnyView?

    /// Whether a row links to the HEIF and JPEG look while HEIF or JPEG is selected.
    let showsLookLink: Bool

    /// Creates the formats list.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    ///   - explanation: An explanation shown above the formats, or `nil`.
    ///   - showsLookLink: Whether a row links to the look while HEIF or JPEG is selected.
    init(
        settings: NopeSettings, deviceSupportsBayerRAW: Bool, explanation: AnyView? = nil,
        showsLookLink: Bool = false
    ) {
        self.settings = settings
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
        self.explanation = explanation
        self.showsLookLink = showsLookLink
    }

    /// The list of formats.
    var body: some View {
        Form {
            if let explanation {
                Section {
                    explanation
                }
            }
            Section {
                ForEach(PhotoFormat.allCases, id: \.self) { format in
                    row(for: format)
                }
            } header: {
                Text("Save Each Photo As", bundle: .module, comment: "Section header above the list of file formats.")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
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
            if showsLookLink && settings.savesDevelopedFormat {
                Section {
                    LookSettingsView.link(settings: settings)
                }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Self.name(of: format))
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    if !isAvailable {
                        Text("Not available on this device", bundle: .module, comment: "Shown under the RAW format on a device without RAW.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
