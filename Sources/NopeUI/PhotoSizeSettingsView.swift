import NopeCore
import SwiftUI

/// The photo size of each lens that offers more than one (issue #57): a pushed-list picker per
/// lens, with the sizes the lens reports and a plain explanation.
///
/// Advanced option: Settings shows its row only when a lens offers a choice
/// (`Lens.photoSizeChoices`), which is a lens without Bayer RAW; a Bayer RAW lens always takes
/// the sensor's binned RAW. The default is the smallest size, as before this option existed.
/// The rules are in `Lens` and `NopeSettings`; this view only shows them.
struct PhotoSizeSettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// The lenses that offer a choice, in the order the camera lists them.
    let lenses: [Lens]

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - lenses: The device's lenses; only those with a choice are shown.
    init(settings: NopeSettings, lenses: [Lens]) {
        self.settings = settings
        self.lenses = Self.lensesWithChoices(lenses)
    }

    /// The form: one picker per lens, then the explanation.
    var body: some View {
        Form {
            ForEach(lenses) { lens in
                Section {
                    Picker(
                        selection: Binding(
                            get: { settings.photoSize(for: lens) ?? lens.photoSizeChoices[0] },
                            set: { settings.setPhotoSize($0, for: lens) })
                    ) {
                        ForEach(lens.photoSizeChoices, id: \.self) { size in
                            Self.title(of: size).tag(size)
                        }
                    } label: {
                        Text(verbatim: LensName.string(for: lens.kind))
                    }
                    // A pushed list, as Paired with RAW in Formats: a menu's value was reported
                    // clipped at large text sizes.
                    .pickerStyle(.navigationLink)
                }
            }
            // A row rather than a section footer, which the accessibility audit reported as not
            // following Dynamic Type (see CopiesSettingsView).
            Section {
                Text(
                    "These lenses have no RAW, so each photo is the phone's processed file. A larger size has more pixels and bigger files. The smallest size is the default.",
                    bundle: .module,
                    comment: "Explains the Photo Size screen. RAW is a file format name.")
                    .font(.footnote)
            }
        }
        .navigationTitle(Self.rowTitle)
    }

    /// The row and screen title, "Photo Size".
    static var rowTitle: Text {
        Text(SettingsText.photoSize)
    }

    /// The lenses that offer a choice of photo size.
    ///
    /// - Parameter lenses: The device's lenses.
    /// - Returns: Those with `Lens.photoSizeChoices`.
    static func lensesWithChoices(_ lenses: [Lens]) -> [Lens] {
        lenses.filter { !$0.photoSizeChoices.isEmpty }
    }

    /// The Settings row's value: "Default" while every lens takes photos at its default size,
    /// "Custom" otherwise. Settings shows the row only when a lens offers a choice.
    ///
    /// - Parameters:
    ///   - settings: The settings.
    ///   - lenses: The device's lenses.
    /// - Returns: The value text.
    static func summary(settings: NopeSettings, lenses: [Lens]) -> Text {
        if lensesWithChoices(lenses).allSatisfy({ settings.photoSize(for: $0) == $0.defaultPhotoSize }) {
            Text(String(localized: "Photo size: Default", defaultValue: "Default", bundle: .module, comment: "Settings row value: every lens takes photos at its default size."))
        } else {
            Text(String(localized: "Photo size: Custom", defaultValue: "Custom", bundle: .module, comment: "Settings row value: at least one lens takes photos at a size other than its default."))
        }
    }

    /// A size's name: its megapixels and its width and height in pixels.
    ///
    /// - Parameter size: The size.
    /// - Returns: For example "12 MP (4032 × 3024)".
    static func title(of size: PhotoDimensions) -> Text {
        // Rounded down, as cameras name their sensors: 8064 × 6048 is 48.8 million pixels, "48 MP".
        let megapixels = max(1, Int(Double(size.pixelCount) / 1_000_000))
        return Text(
            "\(megapixels) MP (\(size.width) × \(size.height))", bundle: .module,
            comment: "A photo size choice: megapixels (MP), then the width and height in pixels.")
    }
}
