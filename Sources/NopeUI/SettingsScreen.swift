import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// Whether the device shows Live Activities and the person allows them for the app, so
    /// Settings offers the Live Activity switch (issue #64). `false` by default, as in the Lock
    /// Screen capture extension and previews; the app sets it from ActivityKit.
    @Entry public var offersLiveActivity = false
}

/// The settings: a short inset grouped list in a navigation stack, opened from the camera
/// (issue #68, "Settings"): Photos (formats, look, file options), Privacy (the master switch,
/// signing, the details), Camera (manual controls, clean view, night mode, front camera mirroring)
/// and More (Accessibility, Honesty, About).
///
/// One line per row; each switch's explanation is in a footer or on its detail screen. Each
/// row shows its current value, so the state reads at a glance. The screen renders a
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

    /// Whether the device has a front camera, so the mirroring switch applies.
    private let deviceHasFrontCamera: Bool

    /// Location tagging, or `nil` to hide the Location switch.
    private let location: LocationTagging?

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Whether to offer the Live Activity switch.
    @Environment(\.offersLiveActivity) private var offersLiveActivity

    /// Creates the settings screen.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW
    ///     (`DeviceCapabilities/supportsBayerRAW`). Pass `true` when it isn't known yet.
    ///   - deviceHasFrontCamera: Whether the device has a front camera
    ///     (`DeviceCapabilities/hasFrontCamera`), which shows the "Mirror Front Camera" switch.
    ///     Pass `true` when it isn't known yet.
    ///   - location: Location tagging (`CameraModel/location`), or `nil` when the app has no
    ///     location service, which hides the Location switch.
    public init(
        settings: NopeSettings, deviceSupportsBayerRAW: Bool, deviceHasFrontCamera: Bool = true,
        location: LocationTagging? = nil
    ) {
        self.settings = settings
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
        self.deviceHasFrontCamera = deviceHasFrontCamera
        self.location = location
    }

    /// The form and its toolbar.
    public var body: some View {
        NavigationStack {
            Form {
                photosSection
                privacySection
                cameraSection
                moreSection
            }
            .navigationTitle(Text("Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it."))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // The system checkmark, as iOS shows for a sheet's confirm button.
                    DoneButton { dismiss() }
                }
            }
        }
    }

    /// Formats and, while HEIF or JPEG is selected, the look.
    private var photosSection: some View {
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
            if settings.savesDevelopedFormat {
                LookSettingsView.link(settings: settings)
                FileOptionsSettingsView.link(settings: settings)
            }
        } header: {
            // Its own key: "Photos" alone is the photo count picker in Pro Tools, translated as a count.
            Text(String(localized: "Settings section: Photos", defaultValue: "Photos", bundle: .module, comment: "Settings section header for the formats and look each photo is saved with (a heading, not a count)."))
        }
    }

    /// The master switch, the details screen and signing; each detail's explanation is on its
    /// screen.
    private var privacySection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { settings.metadata.removesAllOptionalDetails },
                    set: { settings.setRemovesAllOptionalDetails($0) })
            ) {
                Text("Remove All Optional Details", tableName: "Honesty", bundle: .module, comment: "Master switch: when on, photos keep only the details they need to open.")
            }
            NavigationLink {
                PrivacySettingsView(settings: settings, location: location)
            } label: {
                LabeledContent {
                    PrivacySettingsView.summary(of: settings.metadata)
                } label: {
                    PrivacySettingsView.title
                }
            }
            // The explanation is under the switch's name, as on the detail screens: as a section
            // footer the accessibility audit reported it as not following Dynamic Type.
            Toggle(isOn: Binding(get: { settings.signsPhotos }, set: { settings.setSignsPhotos($0) })) {
                SettingLabel(
                    title: Text("Sign Each Photo", tableName: "Honesty", bundle: .module, comment: "Switch that adds a Content Credentials signature to each photo."),
                    explanation: Text(
                        "Lets anyone check that the photo hasn't changed since nope. saved it. If off, the photo can't be checked for changes.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the signing switch. Keep \"nope.\" unchanged. Must not claim more than the English: the signature shows changes, it doesn't prove who took the photo."))
            }
        } header: {
            Text("Privacy", bundle: .module, comment: "Settings row and screen title: which details are saved in each photo, and signing.")
        }
    }

    /// Manual controls, clean view and night mode, each with its explanation under its name.
    private var cameraSection: some View {
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
            FastShutterSettingsView.link(settings: settings)
            OverlaySettingsView.link(settings: settings)
            Toggle(isOn: Binding(get: { settings.isNightModeOn }, set: { settings.setNightMode($0) })) {
                SettingLabel(
                    title: Text("Night Mode", bundle: .module, comment: "Switch and its Voice Control name: shows nope.'s screens in red on black for working in the dark. Keep \"nope.\" unchanged."),
                    explanation: Text(
                        "Red on black, to keep your eyes used to the dark. nope. doesn't change the screen's brightness: dim it in Control Center, or with Reduce White Point in the Accessibility settings.",
                        bundle: .module,
                        comment: "Explains the Night Mode switch. Keep \"nope.\" unchanged. Control Center and Reduce White Point are names of iOS features: use their names in the language's iOS."))
            }
            if settings.isNightModeOn {
                Toggle(
                    isOn: Binding(
                        get: { settings.tintsViewfinderInNightMode }, set: { settings.setTintsViewfinderInNightMode($0) })
                ) {
                    SettingLabel(
                        title: Text("Red Viewfinder", bundle: .module, comment: "Switch: in night mode, the live camera picture on screen is shown in red too."),
                        explanation: Text(
                            "Shows the live picture in red too. Only the screen changes; photos keep their colors.",
                            bundle: .module, comment: "Explains the Red Viewfinder switch, shown while night mode is on."))
                }
            }
            if offersLiveActivity {
                Toggle(
                    isOn: Binding(get: { settings.showsLiveActivity }, set: { settings.setShowsLiveActivity($0) })
                ) {
                    SettingLabel(
                        title: Text("Live Activity", bundle: .module, comment: "Switch and its Voice Control name: shows interval shooting, astro frames, a burst or the self-timer on the Lock Screen and in the Dynamic Island. Live Activity is the name of the iOS feature: use its name in the language's iOS."),
                        explanation: Text(
                            "When you leave nope. during a series or while photos are saving, shows how far it got on the Lock Screen and in the Dynamic Island. Counts only, updated on this iPhone and never sent anywhere. Off by default.",
                            tableName: "Honesty", bundle: .module,
                            comment: "Explains the Live Activity switch. Privacy wording: the Live Activity shows only counts and status, is updated on the device and nothing is sent. Keep \"nope.\" unchanged. Lock Screen and Dynamic Island are names of iOS features: use their names in the language's iOS."))
                }
            }
            if deviceHasFrontCamera {
                Toggle(
                    isOn: Binding(get: { settings.mirrorsFrontCamera }, set: { settings.setMirrorsFrontCamera($0) })
                ) {
                    SettingLabel(
                        title: Text("Mirror Front Camera", bundle: .module, comment: "Switch: front camera photos are saved mirrored, as the viewfinder shows them."),
                        explanation: Text(
                            "Saves front camera photos as the viewfinder shows them. Off: photos show you as others see you, and text reads correctly. The viewfinder is mirrored either way.",
                            bundle: .module, comment: "Explains the Mirror Front Camera switch."))
                }
            }
        } header: {
            Text("Camera", bundle: .module, comment: "Settings section header for how the camera screen looks and works. Also the name of the menu with camera commands in the iPad menu bar.")
        }
    }

    /// Accessibility, Honesty and About.
    private var moreSection: some View {
        Section {
            NavigationLink {
                AccessibilitySettingsView()
            } label: {
                AccessibilitySettingsView.title
            }
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
        } header: {
            Text("More", bundle: .module, comment: "Settings section header above Accessibility, Honesty and About.")
        }
    }
}
