import NopeCore
import SwiftUI

/// The panel of one control: its name, an Auto/Manual picker, the value in large type, a native
/// slider over the lens's real steps, the lens's range and Reset.
///
/// In Auto the value is the camera's, shown in the secondary color; moving the slider switches
/// the control to Manual. The aperture uses a segmented picker of the recommended stops, and
/// white balance adds a tint slider and presets. The panel has a solid backing over the
/// viewfinder.
struct ControlPanel: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Creates a panel.
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

    /// The panel.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: ControlText.name(control))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if manual.availability(of: control).isAdjustable {
                    AutoManualPicker(model: model, control: control)
                }
            }
            Text(verbatim: SlotValue.text(for: control, in: manual))
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(isManual ? .primary : .secondary)
                .accessibilityHidden(true)
            content
            if let scale = manual.scale(for: control) {
                HStack {
                    Text(
                        "This lens: \(ControlText.range(scale, of: control))", bundle: .module,
                        comment: "The range of a control on the selected lens, for example This lens: 54 – 12,096.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if isManual {
                        Button {
                            Task { await model.send(.manual(.setAuto(control))) }
                        } label: {
                            Text("Reset", bundle: .module, comment: "Button that returns one manual control to automatic.")
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.black, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    /// The slider, or why the control can't be set.
    @ViewBuilder private var content: some View {
        switch manual.availability(of: control) {
        case .adjustable:
            if control == .aperture, let scale = manual.scale(for: control) {
                AperturePicker(model: model, stops: scale.values)
            } else {
                ScaleSlider(model: model, control: control)
                if control == .whiteBalance {
                    TintAndPresets(model: model)
                }
            }
        case .fixed:
            note(Text("This lens has a fixed aperture.", bundle: .module, comment: "Explains why the aperture can't be changed on this lens."))
        case .blockedByManualExposure:
            note(Text("Exposure compensation works only while ISO or the shutter is on Auto.", bundle: .module, comment: "Explains why exposure compensation is disabled when ISO and shutter are both set manually."))
        case .unavailable:
            note(Text("Not available on this lens.", bundle: .module, comment: "Explains that the selected lens can't set this control."))
        }
    }

    /// A short explanation in the secondary style.
    ///
    /// - Parameter text: The explanation.
    private func note(_ text: Text) -> some View {
        text.font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A segmented Auto/Manual picker for one control.
struct AutoManualPicker: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Creates the picker.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - control: The control.
    init(model: CameraModel, control: ManualControl) {
        self.model = model
        self.control = control
    }

    /// The picker. Choosing Manual fixes the value in use; choosing Auto hands it back.
    var body: some View {
        Picker(
            selection: Binding(
                get: { model.manual.settings.isManual(control) },
                set: { manual in
                    Task { await model.send(.manual(manual ? .step(control, by: 0) : .setAuto(control))) }
                })
        ) {
            Text(verbatim: ControlText.mode(isManual: false)).tag(false)
            Text(verbatim: ControlText.mode(isManual: true)).tag(true)
        } label: {
            Text(verbatim: ControlText.name(control))
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("panel-mode")
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
