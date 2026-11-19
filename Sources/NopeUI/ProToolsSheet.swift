import NopeCore
import SwiftUI

/// The exposure mode, metering, AE and AF locks and the live aids, in a standard form, opened
/// from More at the end of the manual readout row (docs/design/BUILD-SPEC.md, 3.4).
///
/// Interval shooting and exposure bracketing are not here: the drive strip and its cards are
/// their one home, so no second control behaves differently (docs/design/SETTINGS-PLAN.md,
/// decision 8; docs/design/BRACKETING.md, decision 1). Each section
/// appears only when the selected lens supports it. Like the camera it covers, the sheet is dark
/// in either system setting (``ScreenAppearance/camera``), and it covers the whole window on
/// every device.
struct ProToolsSheet: View {
    /// The camera model.
    let model: CameraModel

    /// The person's settings, for the live aid switches, or `nil` to leave them out.
    let settings: NopeSettings?

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings, for the focus peaking, histogram and live readout
    ///     switches, or `nil` to leave them out.
    init(model: CameraModel, settings: NopeSettings? = nil) {
        self.model = model
        self.settings = settings
    }

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// The form.
    var body: some View {
        NavigationStack {
            NopeForm {
                if manual.exposureModes.count > 1 || manual.capabilities.meteringModes.count > 1 {
                    // One group, as drawn (docs/design/screens/manual-pro-tools).
                    Section {
                        if manual.exposureModes.count > 1 {
                            exposureModePicker
                        }
                        if manual.capabilities.meteringModes.count > 1 {
                            meteringPicker
                        }
                    }
                }
                if manual.capabilities.supportsExposureLock || manual.capabilities.supportsFocusLock {
                    locksSection
                }
                if let settings {
                    Section {
                        LiveAidToggles(settings: settings)
                    } header: {
                        Text("Live Aids", bundle: .module, comment: "Settings section header above focus peaking, the histogram and the live camera readout.")
                    }
                }
                // Done is a row of the form, not a bar button: the accessibility audit can't
                // measure the contrast of the glass bar button.
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module, comment: "Closes the Pro Tools sheet.")
                    }
                }
            }
            .navigationTitle(Text("Pro Tools", bundle: .module, comment: "Button that opens metering, locks, bracketing and interval shooting."))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Sends a manual intent.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: ManualControlIntent) {
        Task { await model.send(.manual(intent)) }
    }

    /// The exposure mode picker: P, S, I or M, as the lens supports.
    private var exposureModePicker: some View {
        Picker(
            selection: Binding(get: { manual.settings.exposureMode }, set: { send(.setExposureMode($0)) })
        ) {
            ForEach(manual.exposureModes, id: \.self) { mode in
                Text(verbatim: ControlText.name(mode)).tag(mode)
            }
        } label: {
            Text("Exposure Mode", bundle: .module, comment: "Name of the picker for the exposure mode: P, S, I or M.")
        }
        .accessibilityIdentifier("exposure-mode")
    }

    /// The metering mode picker.
    private var meteringPicker: some View {
        Picker(
            selection: Binding(get: { manual.settings.metering }, set: { send(.setMetering($0)) })
        ) {
            ForEach(manual.capabilities.meteringModes, id: \.self) { mode in
                Text(verbatim: ControlText.name(mode)).tag(mode)
            }
        } label: {
            Text("Metering", bundle: .module, comment: "Picker for how auto exposure measures the scene.")
        }
    }

    /// The AE-L and AF-L switches.
    private var locksSection: some View {
        Section {
            if manual.capabilities.supportsExposureLock {
                Toggle(isOn: Binding(get: { manual.settings.exposureLocked }, set: { send(.setExposureLock($0)) })) {
                    Text("Exposure Lock (AE-L)", bundle: .module, comment: "Switch that locks auto exposure. AE-L is the usual camera abbreviation.")
                }
                .disabled(!manual.canLockExposure && !manual.settings.exposureLocked)
            }
            if manual.capabilities.supportsFocusLock {
                Toggle(isOn: Binding(get: { manual.settings.focusLocked }, set: { send(.setFocusLock($0)) })) {
                    Text("Focus Lock (AF-L)", bundle: .module, comment: "Switch that locks autofocus. AF-L is the usual camera abbreviation.")
                }
                .disabled(!manual.canLockFocus && !manual.settings.focusLocked)
            }
        }
    }
}
