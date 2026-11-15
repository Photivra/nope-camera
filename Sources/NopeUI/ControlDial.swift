import NopeCore
import SwiftUI

/// The dial of one control, over the bottom of the picture on a dark backing: its name and the
/// lens's range, then − and + steppers around a native slider over the lens's real steps, and
/// Auto (issue #68, "Manual"). Nothing needs a gesture: every step has a button.
///
/// In Auto the value is the camera's; a step or the slider switches the control to Manual, and
/// Auto hands it back. The aperture uses a segmented picker of the recommended stops, and white
/// balance adds a tint slider and presets. While the camera reports readings, the meter shows
/// how the exposure compares with its reading.
struct ControlDial: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Creates a dial.
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

    /// Whether the control is set manually.
    private var isManual: Bool { manual.settings.isManual(control) }

    /// The dial.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: ControlText.name(control))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: SlotValue.text(for: control, in: manual))
                    .font(.headline.monospacedDigit())
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                if let reading = manual.reading {
                    Text(ControlText.meter(reading.exposureOffset))
                        .font(.footnote.monospacedDigit())
                        .accessibilityLabel(Text("Meter", bundle: .module, comment: "VoiceOver name of the exposure meter: how the exposure compares with the camera's reading."))
                        .accessibilityValue(Text(ControlText.meter(reading.exposureOffset)))
                }
            }
            content
            if let scale = manual.scale(for: control) {
                Text(
                    "This lens: \(ControlText.range(scale, of: control))", bundle: .module,
                    comment: "The range of a control on the selected lens, for example This lens: 54 – 12,096.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .darkBacking()
        .accessibilityElement(children: .contain)
    }

    /// The steppers and slider, or why the control can't be set.
    @ViewBuilder private var content: some View {
        switch manual.availability(of: control) {
        case .adjustable:
            HStack(spacing: CameraStyle.targetSpacing) {
                stepButton(by: -1)
                if control == .aperture, let scale = manual.scale(for: control) {
                    AperturePicker(model: model, stops: scale.values)
                } else {
                    ScaleSlider(model: model, control: control)
                }
                stepButton(by: 1)
                autoButton
            }
            if control == .whiteBalance {
                TintAndPresets(model: model)
            }
        case .fixed:
            note(Text("This lens has a fixed aperture.", bundle: .module, comment: "Explains why the aperture can't be changed on this lens."))
        case .blockedByManualExposure:
            note(Text("Exposure compensation works only while ISO or the shutter is on Auto.", bundle: .module, comment: "Explains why exposure compensation is disabled when ISO and shutter are both set manually."))
        case .unavailable:
            note(Text("Not available on this lens.", bundle: .module, comment: "Explains that the selected lens can't set this control."))
        }
    }

    /// − or +: one step down or up, which sets the control manually.
    ///
    /// - Parameter steps: −1 or 1.
    private func stepButton(by steps: Int) -> some View {
        Button {
            Task { await model.send(.manual(.step(control, by: steps))) }
        } label: {
            Label {
                steps < 0
                    ? Text("Decrease", bundle: .module, comment: "Button on a manual control's dial: one step lower.")
                    : Text("Increase", bundle: .module, comment: "Button on a manual control's dial: one step higher.")
            } icon: {
                Image(systemName: steps < 0 ? "minus" : "plus")
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(SelectableCapsuleStyle(isSelected: false))
        .accessibilityShowsLargeContentViewer()
    }

    /// Auto: filled white while the camera sets the control. Pressing it in Auto fixes the value
    /// in use; pressing it in Manual hands the control back to the camera.
    private var autoButton: some View {
        Button {
            Task { await model.send(.manual(isManual ? .setAuto(control) : .step(control, by: 0))) }
        } label: {
            Text(verbatim: ControlText.mode(isManual: false))
        }
        .buttonStyle(SelectableCapsuleStyle(isSelected: !isManual))
        .accessibilityAddTraits(isManual ? [] : .isSelected)
        .accessibilityHint(Text(verbatim: isManual ? switchToAuto : switchToManual))
    }

    /// "Switch to Auto".
    private var switchToAuto: String {
        String(localized: "Switch to Auto", bundle: .module, comment: "VoiceOver action that hands a control back to the camera.")
    }

    /// "Switch to Manual".
    private var switchToManual: String {
        String(localized: "Switch to Manual", bundle: .module, comment: "VoiceOver action that fixes a control at its current value.")
    }

    /// A short explanation.
    ///
    /// - Parameter text: The explanation.
    private func note(_ text: Text) -> some View {
        text.font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
}

/// A native slider over a control's steps; moving it sets the control manually.
struct ScaleSlider: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Creates the slider.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - control: The control.
    init(model: CameraModel, control: ManualControl) {
        self.model = model
        self.control = control
    }

    /// The slider, or nothing when the lens has no scale, or only one value, for the control.
    var body: some View {
        if let scale = model.manual.scale(for: control), scale.values.count > 1 {
            let index = Binding<Double>(
                get: { Double(scale.nearestIndex(to: model.manual.value(of: control) ?? scale.values[0])) },
                set: { position in
                    let value = scale.values[Int(position.rounded())]
                    Task { await model.send(.manual(.setValue(control, value))) }
                })
            Slider(value: index, in: 0...Double(scale.values.count - 1), step: 1) {
                Text(verbatim: ControlText.name(control))
            }
            .accessibilityValue(Text(verbatim: SlotValue.text(for: control, in: model.manual)))
        }
    }
}

/// The aperture's recommended stops as a segmented picker.
struct AperturePicker: View {
    /// The camera model.
    let model: CameraModel

    /// The f-numbers, widest first.
    let stops: [Double]

    /// Creates the picker.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - stops: The f-numbers, widest first.
    init(model: CameraModel, stops: [Double]) {
        self.model = model
        self.stops = stops
    }

    /// The picker.
    var body: some View {
        Picker(
            selection: Binding(
                get: { model.manual.value(of: .aperture) ?? stops[0] },
                set: { value in Task { await model.send(.manual(.setValue(.aperture, value))) } })
        ) {
            ForEach(stops, id: \.self) { stop in
                Text(verbatim: ControlText.value(stop, of: .aperture)).tag(stop)
            }
        } label: {
            Text(verbatim: ControlText.name(.aperture))
        }
        .pickerStyle(.segmented)
    }
}

/// The white balance tint slider and the presets menu.
struct TintAndPresets: View {
    /// The camera model.
    let model: CameraModel

    /// Creates the tint slider and presets.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The tint slider and the presets.
    var body: some View {
        let scale = ControlScale.tint
        let index = Binding<Double>(
            get: { Double(scale.nearestIndex(to: model.manual.tint)) },
            set: { position in
                Task { await model.send(.manual(.setTint(scale.values[Int(position.rounded())]))) }
            })
        HStack {
            Text("Tint", bundle: .module, comment: "Label of the white balance tint slider (green to magenta).")
                .font(.footnote)
            Slider(value: index, in: 0...Double(scale.values.count - 1), step: 1) {
                Text("Tint", bundle: .module, comment: "Label of the white balance tint slider (green to magenta).")
            }
            .accessibilityValue(Text(verbatim: model.manual.tint.formatted(.number.precision(.fractionLength(0)))))
        }
        Menu {
            ForEach(WhiteBalancePreset.allCases, id: \.self) { preset in
                Button(ControlText.name(preset)) {
                    Task { await model.send(.manual(.setWhiteBalancePreset(preset))) }
                }
            }
        } label: {
            Text("Presets", bundle: .module, comment: "Menu of white balance presets such as Daylight and Tungsten.")
                .frame(minHeight: 44)
        }
    }
}
