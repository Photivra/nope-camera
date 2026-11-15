import NopeCore
import SwiftUI

/// How HEIF and JPEG are developed from the RAW: a native inline picker, each look with a
/// one-line explanation. Settings links to it while HEIF or JPEG is selected. The wording is a
/// processing claim, so the explanations are in `Honesty.xcstrings`.
struct LookSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Creates the look picker.
    ///
    /// - Parameter settings: The settings to show and change.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The look picker.
    var body: some View {
        Form {
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
            }
            // A row rather than a section footer: as a footer right under the inline picker,
            // the accessibility audit reported it as not following Dynamic Type.
            Section {
                Text(
                    "This changes only the HEIF and JPEG copies. The RAW is never changed.", tableName: "Honesty", bundle: .module,
                    comment: "Footer under the look picker. RAW, HEIF and JPEG are file format names. Must not claim more than the English.")
                    .font(.footnote)
            }
        }
        .navigationTitle(Self.rowTitle)
    }

    /// The row and screen title, "Look".
    static var rowTitle: Text {
        Text("Look", bundle: .module, comment: "Settings row and screen title: how the HEIF and JPEG copies are developed from the RAW (Standard or Flat).")
    }

    /// A navigation row to the look, showing the current look.
    ///
    /// - Parameter settings: The settings.
    static func link(settings: NopeSettings) -> some View {
        NavigationLink {
            LookSettingsView(settings: settings)
        } label: {
            LabeledContent {
                title(of: settings.developedLook)
            } label: {
                rowTitle
            }
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
}
