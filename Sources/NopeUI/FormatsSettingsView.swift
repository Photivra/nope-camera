import NopeCore
import SwiftUI

/// Chooses the formats each photo is saved in: a native checkmark list.
///
/// At least one format stays selected: `NopeSettings/canTurnOff(_:deviceSupportsBayerRAW:)`
/// disables the last one. On a device without Bayer RAW the RAW row stays visible, unavailable, and says why.
struct FormatsSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Whether any camera on the device gives Bayer RAW.
    let deviceSupportsBayerRAW: Bool

    /// Creates the formats list.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    init(settings: NopeSettings, deviceSupportsBayerRAW: Bool) {
        self.settings = settings
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
    }

    /// The list of formats.
    var body: some View {
        Form {
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
            if settings.savesDevelopedFormat {
                lookSection
            }
        }
        .navigationTitle(Text("Formats", bundle: .module, comment: "Settings row and screen title: the file formats each photo is saved in."))
    }

    /// How HEIF and JPEG are developed: a native inline picker, each look with a one-line
    /// explanation. Shown only while HEIF or JPEG is selected. The wording is a processing claim,
    /// so the explanations are in `Honesty.xcstrings`.
    private var lookSection: some View {
        Section {
            Picker(
                selection: Binding(get: { settings.developedLook }, set: { settings.setDevelopedLook($0) })
            ) {
                ForEach(DevelopedLook.allCases, id: \.self) { look in
                    SettingLabel(title: Self.title(of: look), explanation: Self.explanation(of: look))
                        .tag(look)
                }
            } label: {
                Text("HEIF and JPEG Look", bundle: .module, comment: "Picker label: how the HEIF and JPEG copies are developed from the RAW. HEIF and JPEG are file format names.")
            }
            .pickerStyle(.inline)
        } footer: {
            Text(
                "This changes only the HEIF and JPEG copies. The RAW is never changed.", tableName: "Honesty", bundle: .module,
                comment: "Footer under the look picker. RAW, HEIF and JPEG are file format names. Must not claim more than the English.")
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
