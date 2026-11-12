import NopeCore
import SwiftUI

/// The manual controls, shown only when the "Manual controls" option is on: the EV meter, the
/// exposure mode picker, Pro Tools, "All Auto", the six-slot grid and the panel of the open slot.
///
/// The grid always has six slots in the same order (`ManualControl`); a control the lens
/// can't set stays in its slot. At accessibility text sizes ``ManualControlsList`` replaces the
/// grid. Every value and rule comes from `ManualControlsModel`.
struct ManualControlsView: View {
    /// The camera model.
    let model: CameraModel

    /// The control whose panel is open, or `nil`.
    @Binding var openControl: ManualControl?

    /// Whether the Pro Tools sheet is shown.
    @State private var showsProTools = false

    /// Counts "All Auto" presses, to trigger the haptic.
    @State private var allAutoPresses = 0

    /// The current text size; accessibility sizes switch to the list.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the manual controls.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - openControl: The control whose panel is open.
    init(model: CameraModel, openControl: Binding<ManualControl?>) {
        self.model = model
        _openControl = openControl
    }

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// The header, the panel and the grid, or the list at accessibility sizes.
    var body: some View {
        VStack(spacing: 8) {
            header
            if dynamicTypeSize.isAccessibilitySize {
                ManualControlsList(model: model)
            } else {
                if let openControl {
                    ControlPanel(model: model, control: openControl)
                }
                grid
            }
            if !manual.settings.isAutomatic {
                allAutoButton
            }
        }
        .sensoryFeedback(.success, trigger: allAutoPresses)
        .sheet(isPresented: $showsProTools) {
            ProToolsSheet(model: model)
        }
    }

    /// The EV meter, the exposure mode picker and the Pro Tools button.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { headerItems }
            VStack(spacing: 8) { headerItems }
        }
    }

    /// The header's parts.
    @ViewBuilder private var headerItems: some View {
        if let reading = manual.reading {
            Text(ControlText.meter(reading.exposureOffset))
                .font(.callout.monospacedDigit())
                .accessibilityLabel(Text("Meter", bundle: .module, comment: "VoiceOver name of the exposure meter: how the exposure compares with the camera's reading."))
                .accessibilityValue(Text(ControlText.meter(reading.exposureOffset)))
        }
        if manual.exposureModes.count > 1 {
            Picker(
                selection: Binding(
                    get: { manual.settings.exposureMode },
                    set: { mode in Task { await model.send(.manual(.setExposureMode(mode))) } })
            ) {
                ForEach(manual.exposureModes, id: \.self) { mode in
                    Text(verbatim: ControlText.mark(mode))
                        .accessibilityLabel(Text(verbatim: ControlText.name(mode)))
                        .tag(mode)
                }
            } label: {
                Text("Exposure Mode", bundle: .module, comment: "Name of the picker for the exposure mode: P, S, I or M.")
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("exposure-mode")
        }
        Button {
            showsProTools = true
        } label: {
            Label {
                Text("Pro Tools", bundle: .module, comment: "Button that opens metering, locks, bracketing and interval shooting.")
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .frame(minHeight: 44)
    }

    /// The six slots, three to a row.
    private var grid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach([Array(ManualControl.allCases.prefix(3)), Array(ManualControl.allCases.suffix(3))], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { control in
                        ControlSlot(model: model, control: control, isOpen: openControl == control) {
                            openControl = openControl == control ? nil : control
                        }
                    }
                }
            }
        }
    }

    /// "All Auto", with how many controls are set manually.
    private var allAutoButton: some View {
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
            Text("All Auto", bundle: .module, comment: "Button that returns every manual control to automatic in one tap.")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(
            Text("\(manual.settings.manualControlCount) set manually", bundle: .module, comment: "How many manual controls the person has set. The number is a count of controls."))
    }
}

/// One slot of the control grid: the short name, an A or M mark, and the value in use.
///
/// For VoiceOver it is one adjustable element: swipe up or down steps the value, double-tap
/// opens its panel, and actions switch it between Auto and Manual or return everything to
/// Auto (AGENTS.md, "Manual controls are adjustable elements").
struct ControlSlot: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Whether the slot's panel is open.
    let isOpen: Bool

    /// Opens or closes the panel.
    let toggle: () -> Void

    /// Creates a slot.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - control: The control.
    ///   - isOpen: Whether its panel is open.
    ///   - toggle: Opens or closes the panel.
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
            VStack(spacing: 2) {
                Text(verbatim: ControlText.shortName(control))
                    .font(.caption2.weight(.semibold))
                // One text, so the mark and the value are checked and drawn together. The letter
                // says A or M; green only adds to it.
                (Text(verbatim: isManual ? "M " : "A ")
                    .fontWeight(.bold)
                    .foregroundStyle(isManual ? Color.green : Color.primary)
                    + Text(verbatim: SlotValue.text(for: control, in: manual)))
                    .font(.footnote.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(isOpen ? .primary : .secondary)
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

    /// "Switch to Auto" or "Switch to Manual".
    private var switchActionName: String {
        isManual
            ? String(localized: "Switch to Auto", bundle: .module, comment: "VoiceOver action that hands a control back to the camera.")
            : String(localized: "Switch to Manual", bundle: .module, comment: "VoiceOver action that fixes a control at its current value.")
    }
}

/// The text a slot shows for a control, from the model.
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
