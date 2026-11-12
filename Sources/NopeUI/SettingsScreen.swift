import NopeCore
import SwiftUI

/// The settings: a native `Form` in a navigation stack, shown as a sheet from the camera.
///
/// Each row shows its current value, so the state reads at a glance. The screen renders a
/// `NopeSettings` and changes it only through its methods, which hold the rules (AGENTS.md,
/// "One direction of flow"). It follows the system appearance.
///
/// ```swift
/// .sheet(isPresented: $showsSettings) {
///     SettingsScreen(settings: settings, deviceSupportsBayerRAW: true)
/// }
/// ```
public struct SettingsScreen: View {
    /// The settings to show and change.
    private let settings: NopeSettings

    /// Whether any camera on the device gives Bayer RAW. When `false`, the RAW format is shown
    /// as unavailable, with the reason.
    private let deviceSupportsBayerRAW: Bool

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the settings screen.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW
    ///     (`DeviceCapabilities/supportsBayerRAW`). Pass `true` when it isn't known yet.
    public init(settings: NopeSettings, deviceSupportsBayerRAW: Bool) {
        self.settings = settings
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
    }

    /// The form and its toolbar.
    public var body: some View {
        NavigationStack {
            Form {
                captureSection
                privacySection
                aboutSection
            }
            .navigationTitle(Text("Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it."))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // The system checkmark, as iOS shows for a sheet's confirm button. Its name,
                    // "Done", is what VoiceOver reads and Voice Control users say. The Large
                    // Content Viewer shows it at accessibility text sizes.
                    Button {
                        dismiss()
                    } label: {
                        Label {
                            Text("Done", bundle: .module, comment: "Button that closes the settings.")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityShowsLargeContentViewer()
                }
            }
        }
    }

    /// Formats, then the camera screen options.
    @ViewBuilder private var captureSection: some View {
        Section {
            NavigationLink {
                FormatsSettingsView(settings: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW)
            } label: {
                LabeledContent {
                    Text(verbatim: FormatsSettingsView.summary(of: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW))
                } label: {
                    Text("Formats", bundle: .module, comment: "Settings row and screen title: the file formats each photo is saved in.")
                }
            }
        } header: {
            Text("Capture", bundle: .module, comment: "Settings section header for how photos are taken and saved.")
        }
        Section {
            Toggle(
                isOn: Binding(get: { settings.showsManualControls }, set: { settings.setShowsManualControls($0) })
            ) {
                SettingLabel(
                    title: Text("Manual Controls", bundle: .module, comment: "Switch that shows manual exposure controls on the camera screen."),
                    explanation: Text(
                        "Shows manual controls on the camera screen. Off by default.",
                        bundle: .module, comment: "Explains the Manual Controls switch."))
            }
            Toggle(
                isOn: Binding(get: { settings.startsInCleanView }, set: { settings.setStartsInCleanView($0) })
            ) {
                SettingLabel(
                    title: Text("Start in Clean View", bundle: .module, comment: "Switch: the camera opens with only the viewfinder and the shutter."),
                    explanation: Text(
                        "The camera opens with only the viewfinder and the shutter. Warnings about the photo always show.",
                        bundle: .module, comment: "Explains the clean view switch."))
            }
        }
    }

    /// The privacy and signing row.
    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacySettingsView(settings: settings)
            } label: {
                LabeledContent {
                    PrivacySettingsView.summary(of: settings.metadata)
                } label: {
                    Text("Privacy", bundle: .module, comment: "Settings row and screen title: which details are saved in each photo, and signing.")
                }
            }
        }
    }

    /// Honesty and About.
    private var aboutSection: some View {
        Section {
            NavigationLink {
                HonestyScreen()
            } label: {
                Text("Honesty", tableName: "Honesty", bundle: .module, comment: "Settings row and screen title: what nope. does and doesn't do, and what it can't control.")
            }
            NavigationLink {
                AboutScreen()
            } label: {
                Text("About and Licenses", bundle: .module, comment: "Settings row and screen title: version, license and third-party notices.")
            }
        }
    }
}
