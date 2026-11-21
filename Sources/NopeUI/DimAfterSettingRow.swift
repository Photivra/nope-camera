import NopeCore
import SwiftUI

/// The words of the Dim After menu (issue #119, `docs/design/finish-1.0.md`, section 4).
enum DimAfterText {
    /// The name of a choice, as the menu and its value show it: "1 Minute", "2 Minutes",
    /// "5 Minutes" or "Never". The minutes are a plural string, so each language counts them
    /// its own way.
    ///
    /// - Parameter choice: The choice.
    /// - Returns: Its name.
    static func name(_ choice: DimAfter) -> Text {
        switch choice {
        case .oneMinute: minutes(1)
        case .twoMinutes: minutes(2)
        case .fiveMinutes: minutes(5)
        case .never:
            Text(
                LocalizedStringResource(
                    "Dim After: Never", defaultValue: "Never", bundle: SettingsText.bundle,
                    comment: "Dim After menu choice: Keep Screen On never dims the screen by itself (it still dims in Low Power Mode and when the phone is hot). Draft wording for the Honesty review (issue #119)."))
        }
    }

    /// A number of minutes as a menu choice.
    ///
    /// - Parameter count: The minutes.
    private static func minutes(_ count: Int) -> Text {
        Text(
            "\(count) Minutes", bundle: .module,
            comment: "Dim After menu choice: the screen dims after this many minutes without a touch or photo. The number is a count of minutes, with plural variants.")
    }

    /// The note under the row, for every choice.
    static let note = Text(
        "With Keep Screen On, the screen dims after this long without a touch or photo.", bundle: .module,
        comment: "Note under the Dim After menu in Settings › Screen. It begins with where the setting is used (Keep Screen On, the switch above it; use its translation). Draft wording for the Honesty review (issue #119).")

    /// The note's addition with Never chosen: what Never costs, and when the screen still dims.
    static let neverNote = Text(
        "Never uses more battery and can warm the phone. The screen still dims in Low Power Mode and when the phone is hot.",
        tableName: "Honesty", bundle: .module,
        comment: "Added to the note under the Dim After menu when Never is chosen. Never is the menu choice; Low Power Mode is Apple's name: use the name iOS shows in this language. The catalog has device variants (phone, iPad, device). \"Hot\" means the device's own heat warning level (serious), not the weather. Must not claim more than the English. Draft wording for the Honesty review (issue #119).")
}

/// The Dim After menu in Settings › Screen, under Keep Screen On (issue #119): 1 Minute,
/// 2 Minutes (the default), 5 Minutes or Never, with its note under it and, with Never, what
/// Never costs. Always shown and usable where Keep Screen On is offered, whether the switch is on
/// or off, so no row appears or disappears when a switch changes. VoiceOver reads the note with
/// the row.
struct DimAfterSettingRow: View {
    /// The settings.
    let settings: NopeSettings

    /// Creates the row.
    ///
    /// - Parameter settings: The settings.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The menu with its label and note.
    var body: some View {
        Picker(selection: Binding(get: { settings.dimAfter }, set: { settings.setDimAfter($0) })) {
            ForEach(DimAfter.allCases, id: \.self) { choice in
                DimAfterText.name(choice).tag(choice)
            }
        } label: {
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                Text(SettingsText.dimAfter)
                Group {
                    DimAfterText.note
                    if settings.dimAfter == .never {
                        DimAfterText.neverNote
                    }
                }
                .font(.footnote)
                .foregroundStyle(CameraStyle.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.menu)
        .settingsContainerRow(.dimAfter)
    }
}
