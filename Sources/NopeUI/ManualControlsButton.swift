import NopeCore
import SwiftUI

/// The Manual Controls button on the camera (issue #77; docs/design/BUILD-SPEC.md, 3.4): one tap
/// turns manual controls on, the next turns them off, from full auto and from manual alike.
///
/// It replaces the Manual Controls switch in Settings and the M pill. It calls
/// `CameraModel.setManualControls(_:settings:)`, which stores the choice as the Manual Controls
/// option and sends the intent itself, so turning manual controls off always turns them and the
/// astro helper off, even when the helper had turned them on without changing the option.
///
/// VoiceOver reads "Manual Controls, On" or "Off"; Voice Control answers to "Manual Controls" and
/// to the visible word. It is hidden in clean view by the camera layout, not here.
struct ManualControlsButton: View {
    /// How the button is drawn for its place on the camera.
    enum Presentation: Equatable {
        /// The slider symbol and "Auto" or "Manual" in a capsule: the lens row and the column.
        case capsule

        /// The same, in the small capsule of the narrow column layout.
        case compactCapsule

        /// "A" or "M" in a 44-point circle: the lens row of an iPhone held sideways, where a
        /// word turned upright would not fit the row's height.
        case letter

        /// A full-width row with the name over the state: the scrolling layout at accessibility
        /// text sizes.
        case row
    }

    /// Whether manual controls are on.
    let isOn: Bool

    /// How the button is drawn.
    let presentation: Presentation

    /// Turns manual controls on or off.
    let toggle: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isOn: Whether manual controls are on.
    ///   - presentation: How the button is drawn for its place.
    ///   - toggle: Turns manual controls on or off; the camera layout calls
    ///     `CameraModel.setManualControls(_:settings:)` with the opposite of `isOn`.
    init(isOn: Bool, presentation: Presentation = .capsule, toggle: @escaping () -> Void) {
        self.isOn = isOn
        self.presentation = presentation
        self.toggle = toggle
    }

    /// The button.
    var body: some View {
        styled
            .accessibilityLabel(Self.name)
            .accessibilityValue(isOn ? Self.on : Self.off)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityInputLabels([Self.name, stateWord])
            // Stable for UI tests, whichever presentation is drawn.
            .accessibilityIdentifier(Self.identifier)
            .sensoryFeedback(NopeHaptic.manualControlsChanged, trigger: isOn)
    }

    /// The button in the style of its presentation.
    @ViewBuilder private var styled: some View {
        switch presentation {
        case .capsule, .compactCapsule:
            Button(action: toggle) {
                Label {
                    stateWord
                } icon: {
                    Image(systemName: Self.systemImage)
                }
                .labelStyle(NopePillLabelStyle())
            }
            .buttonStyle(NopeCapsuleStyle(isSelected: isOn, isCompact: presentation == .compactCapsule))
            .accessibilityShowsLargeContentViewer {
                Label { Self.name } icon: { Image(systemName: Self.systemImage) }
            }
        case .letter:
            Button(action: toggle) {
                // "A" and "M" are the mode letters of the manual readouts (ControlText), the same
                // in every launch language.
                Text(verbatim: isOn ? "M" : "A")
                    .font(NopeFont.status)
            }
            .buttonStyle(NopeIconButtonStyle(isSelected: isOn))
            .accessibilityShowsLargeContentViewer {
                Label { Self.name } icon: { Image(systemName: Self.systemImage) }
            }
            .uprightUnit()
        case .row:
            Button(action: toggle) {
                CameraRowLabel(name: Self.name, value: isOn ? Self.on : Self.off, systemImage: Self.systemImage)
            }
            .buttonStyle(NopeTileStyle(isOn: isOn, minHeight: NopeSize.scrollingRowButton))
        }
    }

    /// "Auto" or "Manual", the visible word.
    private var stateWord: Text {
        isOn
            ? Text(String(localized: "Manual Controls button: Manual", defaultValue: "Manual", bundle: .module, comment: "Word on the Manual Controls button on the camera while manual controls are on. One tap turns them off. A short word: it shares a row with the lens buttons."))
            : Text(String(localized: "Manual Controls button: Auto", defaultValue: "Auto", bundle: .module, comment: "Word on the Manual Controls button on the camera while the camera sets everything automatically (manual controls off). One tap turns manual controls on. A short word: it shares a row with the lens buttons."))
    }

    /// The button's accessibility identifier.
    static var identifier: String { "ManualControlsButton" }

    /// The SF Symbol of manual controls.
    static var systemImage: String { "slider.horizontal.3" }

    /// "Manual Controls", the button's name for VoiceOver and Voice Control.
    static var name: Text {
        Text("Manual Controls", bundle: .module, comment: "Switch that shows manual exposure controls on the camera screen.")
    }

    /// "On".
    private static var on: Text {
        Text("On", bundle: .module, comment: "Live readout value: a feature is on.")
    }

    /// "Off".
    private static var off: Text {
        Text("Off", bundle: .module, comment: "Live readout value: a feature is off.")
    }
}

/// The content of a full-width camera row in the scrolling layout (accessibility text sizes):
/// the name on top, then the value, each wrapping rather than truncating.
struct CameraRowLabel: View {
    /// The row's name, such as "Manual Controls" or "Wide".
    let name: Text

    /// The row's value, such as "Off" or "1×", or `nil` for none.
    let value: Text?

    /// A further line under the value, such as "No RAW", or `nil` for none.
    let detail: Text?

    /// The SF Symbol before the name, or `nil` for none.
    let systemImage: String?

    /// The color of the value, set by the button style for its state.
    @Environment(\.nopeSecondaryLabel) private var secondaryLabel

    /// Creates a row's content.
    ///
    /// - Parameters:
    ///   - name: The row's name.
    ///   - value: The row's value, or `nil` for none.
    ///   - detail: A further line under the value, or `nil` for none.
    ///   - systemImage: The SF Symbol before the name, or `nil` for none.
    init(name: Text, value: Text?, detail: Text? = nil, systemImage: String? = nil) {
        self.name = name
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
    }

    /// The name over the value.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            HStack(spacing: NopeSpace.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                name
            }
            .font(NopeFont.status)
            Group {
                if let value { value }
                if let detail { detail }
            }
            .font(NopeFont.pill)
            .foregroundStyle(secondaryLabel)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
