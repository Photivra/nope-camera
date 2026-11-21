import NopeCore
import SwiftUI

/// The words of the Burst Limit menu (issue #121, `docs/design/finish-1.0.md`, section 5.1).
enum BurstLimitText {
    /// The name of a choice, as the menu and its value show it: "Off", or the number of photos
    /// formatted for the person's locale.
    ///
    /// - Parameter limit: The choice.
    /// - Returns: Its name.
    static func name(_ limit: BurstLimit) -> Text {
        guard let count = limit.frameCount else {
            return Text(
                LocalizedStringResource(
                    "Burst Limit: Off", defaultValue: "Off", bundle: SettingsText.bundle,
                    comment: "Burst Limit menu choice: no limit, so a tap takes one photo and holding takes photos until you let go."))
        }
        return Text(count, format: .number)
    }

    /// The explanation under the row. It begins with where the setting is used, as the scope
    /// rule asks (`docs/design/SETTINGS-PLAN.md`).
    static let explanation = Text(
        "In Burst, one press takes this many photos; press again to stop early. Off: a tap takes one photo, and holding takes photos until you let go.",
        bundle: .module,
        comment: "Explains the Burst Limit menu in Settings › Camera. Burst is the drive mode's name; Off is the menu choice; use their translations. Draft wording for the Honesty review (issue #121).")
}

/// The Burst Limit menu in Settings › Camera, the last row (issue #121): Off (the default), 3, 5,
/// 10, 20 or 50, with its explanation. Shown on every device and in the Lock Screen camera too,
/// since the settings are shared.
struct BurstLimitSettingRow: View {
    /// The settings.
    let settings: NopeSettings

    /// Creates the row.
    ///
    /// - Parameter settings: The settings.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The menu with its label and explanation.
    var body: some View {
        Picker(selection: Binding(get: { settings.burstLimit }, set: { settings.setBurstLimit($0) })) {
            ForEach(BurstLimit.allCases, id: \.self) { limit in
                BurstLimitText.name(limit).tag(limit)
            }
        } label: {
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                Text(SettingsText.burstLimit)
                BurstLimitText.explanation
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.menu)
        .settingsContainerRow(.burstLimit)
    }
}
