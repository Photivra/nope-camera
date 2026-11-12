import NopeCore
import SwiftUI

/// The manual controls at accessibility text sizes: one row per control, in the grid's order,
/// with an Auto/Manual switch and a stepper, so nothing is clipped (AGENTS.md, "Larger Text").
///
/// It shows the same values as the grid and sends the same intents.
struct ManualControlsList: View {
    /// The camera model.
    let model: CameraModel

    /// Creates the list.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// One row per control.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ManualControl.allCases, id: \.self) { control in
                ControlRow(model: model, control: control)
            }
        }
        .padding(12)
        .background(.black, in: .rect(cornerRadius: 12))
    }
}

/// One control in the list: its name, the Auto/Manual switch and a stepper with the value.
struct ControlRow: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - control: The control.
    init(model: CameraModel, control: ManualControl) {
        self.model = model
        self.control = control
    }

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// The row.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: ControlText.name(control))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if manual.availability(of: control).isAdjustable {
                Toggle(
                    isOn: Binding(
                        get: { manual.settings.isManual(control) },
                        set: { isManual in
                            Task { await model.send(.manual(isManual ? .step(control, by: 0) : .setAuto(control))) }
                        })
                ) {
                    Text(verbatim: ControlText.mode(isManual: true))
                }
                Stepper {
                    Text(verbatim: SlotValue.text(for: control, in: manual))
                        .monospacedDigit()
                } onIncrement: {
                    Task { await model.send(.manual(.step(control, by: 1))) }
                } onDecrement: {
                    Task { await model.send(.manual(.step(control, by: -1))) }
                }
                .accessibilityLabel(Text(verbatim: ControlText.name(control)))
                .accessibilityValue(Text(verbatim: SlotValue.spoken(for: control, in: manual)))
            } else {
                Text(verbatim: SlotValue.spoken(for: control, in: manual))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
