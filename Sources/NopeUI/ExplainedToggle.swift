import SwiftUI

/// A Settings switch with a long explanation (``SettingLabel``).
///
/// At the standard text sizes the explanation is part of the switch's label, as in every other
/// switch row. At the accessibility sizes the switch takes a large share of the row's width, and
/// a long explanation beside it became a very narrow, very tall column: the Live Activity row was
/// about 1,146 points tall at the largest size, more than the screen, and pushed the rows below
/// it far down. There the explanation goes below the switch, across the row's full width, and
/// the two are combined into one accessibility element, so VoiceOver still reads the name and
/// the explanation as the switch, as at the standard sizes.
struct ExplainedToggle: View {
    /// Whether the setting is on.
    let isOn: Binding<Bool>

    /// The setting's name, also the switch's Voice Control name.
    let title: Text

    /// What the setting does.
    let explanation: Text

    /// The current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - isOn: Whether the setting is on.
    ///   - title: The setting's name.
    ///   - explanation: What the setting does.
    init(isOn: Binding<Bool>, title: Text, explanation: Text) {
        self.isOn = isOn
        self.title = title
        self.explanation = explanation
    }

    /// The switch, with the explanation in its label or below it.
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: isOn) { title }
                explanation
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Toggle(isOn: isOn) {
                SettingLabel(title: title, explanation: explanation)
            }
        }
    }
}
