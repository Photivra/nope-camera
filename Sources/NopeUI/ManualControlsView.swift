import NopeCore
import SwiftUI

/// The manual controls' readout row, shown only when the "Manual controls" option is on: one
/// button per control in a fixed order (`ManualControl`), each with its short name, A or M, and
/// the value in use, then a last button with "All Auto" and Pro Tools (issue #68, "Manual").
///
/// Pressing a readout opens its dial (``ControlDial``) and fills the readout white; pressing it
/// again closes the dial. A control the lens can't set stays in its place. At accessibility text
/// sizes ``ManualControlsList`` replaces the row. Every value and rule comes from
/// `ManualControlsModel`.
struct ManualReadoutRow: View {
    /// The camera model.
    let model: CameraModel

    /// The control whose dial is open, or `nil`.
    @Binding var openControl: ManualControl?

    /// Whether Pro Tools is shown; the camera screen presents it.
    @Binding var showsProTools: Bool

    /// Creates the readout row.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - openControl: The control whose dial is open.
    ///   - showsProTools: Whether Pro Tools is shown.
    init(model: CameraModel, openControl: Binding<ManualControl?>, showsProTools: Binding<Bool>) {
        self.model = model
        _openControl = openControl
        _showsProTools = showsProTools
    }

    /// The row.
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ManualControl.allCases, id: \.self) { control in
                ControlReadout(model: model, control: control, isOpen: openControl == control) {
                    openControl = openControl == control ? nil : control
                }
                .uprightUnit()
            }
            ManualOptionsMenu(model: model, openControl: $openControl, showsProTools: $showsProTools)
                .uprightUnit()
        }
    }
}

/// The last readout button: "All Auto" and Pro Tools (metering, modes, locks, bracketing,
/// interval shooting).
struct ManualOptionsMenu: View {
    /// The camera model.
    let model: CameraModel

    /// The control whose dial is open, or `nil`; "All Auto" closes it.
    @Binding var openControl: ManualControl?

    /// Whether Pro Tools is shown.
    @Binding var showsProTools: Bool

    /// Counts "All Auto" presses, to trigger the haptic.
    @State private var allAutoPresses = 0

    /// Creates the menu.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - openControl: The control whose dial is open.
    ///   - showsProTools: Whether Pro Tools is shown.
    init(model: CameraModel, openControl: Binding<ManualControl?>, showsProTools: Binding<Bool>) {
        self.model = model
        _openControl = openControl
        _showsProTools = showsProTools
    }

    /// The menu.
    var body: some View {
        Menu {
            Button {
                allAutoPresses += 1
                openControl = nil
                Task {
                    await model.send(.manual(.allAuto))
                    AccessibilityNotification.Announcement(
                        String(localized: "Full auto", bundle: .module, comment: "Announced after All Auto returned every control to automatic.")
                    ).post()
                }
            } label: {
                Label {
                    Text("All Auto", bundle: .module, comment: "Button that returns every manual control to automatic in one tap.")
                } icon: {
                    Image(systemName: "a.circle")
                }
            }
            .disabled(model.manual.settings.isAutomatic)
            Button {
                showsProTools = true
            } label: {
                Label {
                    Text("Pro Tools", bundle: .module, comment: "Button that opens metering, locks, bracketing and interval shooting.")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        } label: {
            Label {
                Text("More Manual Controls", bundle: .module, comment: "VoiceOver and Voice Control name of the last button of the manual controls row: opens All Auto and Pro Tools.")
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(SelectableCapsuleStyle(isSelected: false))
        .sensoryFeedback(.success, trigger: allAutoPresses)
        .accessibilityShowsLargeContentViewer()
    }
}

/// One readout of the manual controls row: the short name with A or M, and the value in use.
///
/// For VoiceOver it is one adjustable element: swipe up or down steps the value, double-tap
/// opens its dial, and actions switch it between Auto and Manual or return everything to Auto
/// (AGENTS.md, "Manual controls are adjustable elements").
struct ControlReadout: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Whether the control's dial is open.
    let isOpen: Bool

    /// Opens or closes the dial.
    let toggle: () -> Void

    /// Creates a readout.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - control: The control.
    ///   - isOpen: Whether its dial is open.
    ///   - toggle: Opens or closes the dial.
    init(model: CameraModel, control: ManualControl, isOpen: Bool, toggle: @escaping () -> Void) {
        self.model = model
        self.control = control
        self.isOpen = isOpen
        self.toggle = toggle
    }

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// Whether the control is set manually.
    private var isManual: Bool { manual.settings.isManual(control) }

    /// The button.
    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 0) {
                // The letter says A or M, so the mode never depends on color. The control's full
                // name is the VoiceOver label; the value shows which control it is, as on a
                // camera's readout ("ISO 200", "1/125", "f/1.8").
                Text(verbatim: isManual ? "M" : "A")
                    .font(.caption2.weight(.semibold))
                Text(verbatim: visibleValue)
                    .font(.footnote.monospacedDigit())
            }
            // Wraps instead of truncating, so no value is clipped at larger text sizes.
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(SelectableCapsuleStyle(isSelected: isOpen))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ControlText.name(control)))
        .accessibilityValue(Text(verbatim: SlotValue.spoken(for: control, in: manual)))
        .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAdjustableAction { direction in
            let steps = direction == .increment ? 1 : -1
            Task { await model.send(.manual(.step(control, by: steps))) }
        }
        .accessibilityAction(named: Text(verbatim: switchActionName)) {
            Task { await model.send(.manual(isManual ? .setAuto(control) : .step(control, by: 0))) }
        }
        .accessibilityActions {
            if !manual.settings.isAutomatic {
                Button {
                    Task { await model.send(.manual(.allAuto)) }
                } label: {
                    Text("All Auto", bundle: .module, comment: "Button that returns every manual control to automatic in one tap.")
                }
            }
        }
        .accessibilityInputLabels([Text(verbatim: ControlText.shortName(control)), Text(verbatim: ControlText.name(control))])
    }

    /// The readout's text: the value, with "ISO" before an ISO value, which is a bare number.
    private var visibleValue: String {
        let value = SlotValue.text(for: control, in: manual)
        return control == .iso ? "ISO " + value : value
    }

    /// "Switch to Auto" or "Switch to Manual".
    private var switchActionName: String {
        isManual
            ? String(localized: "Switch to Auto", bundle: .module, comment: "VoiceOver action that hands a control back to the camera.")
            : String(localized: "Switch to Manual", bundle: .module, comment: "VoiceOver action that fixes a control at its current value.")
    }
}

/// The text a readout shows for a control, from the model.
@MainActor
enum SlotValue {
    /// The visible value: the value in use, "Fixed" values, or "n/a".
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - manual: The manual controls model.
    static func text(for control: ManualControl, in manual: ManualControlsModel) -> String {
        switch manual.availability(of: control) {
        case .unavailable:
            return String(localized: "n/a", bundle: .module, comment: "Short for not available: this lens can't set this control. Shown in a small grid slot.")
        case .fixed(let value):
            return ControlText.value(value, of: control)
        case .adjustable, .blockedByManualExposure:
            return manual.value(of: control).map { ControlText.value($0, of: control) } ?? "–"
        }
    }

    /// The VoiceOver value: "Manual, 200", "Auto, 1/500", "Fixed, f/1.78" or "Not available".
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - manual: The manual controls model.
    static func spoken(for control: ManualControl, in manual: ManualControlsModel) -> String {
        switch manual.availability(of: control) {
        case .unavailable:
            return String(localized: "Not available", bundle: .module, comment: "VoiceOver value of a control this lens can't set.")
        case .fixed(let value):
            let text = ControlText.value(value, of: control)
            return String(localized: "Fixed, \(text)", bundle: .module, comment: "VoiceOver value of a control the lens can't change, such as a fixed aperture. The value is for example f/1.78.")
        case .adjustable, .blockedByManualExposure:
            let mode = ControlText.mode(isManual: manual.settings.isManual(control))
            let text = text(for: control, in: manual)
            return String(
                localized: "Spoken control value", defaultValue: "\(mode), \(text)", bundle: .module,
                comment: "VoiceOver value of a manual control: Auto or Manual, then the value, for example Manual, 200.")
        }
    }
}
