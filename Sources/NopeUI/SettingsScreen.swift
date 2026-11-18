import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// Whether the device shows Live Activities and the person allows them for the app, so
    /// Settings offers the Live Activity switch (issue #64). `false` by default, as in the Lock
    /// Screen capture extension and previews; the app sets it from ActivityKit.
    @Entry public var offersLiveActivity = false
}

/// The settings: a search field, then Presets and five groups in an inset grouped list in a
/// navigation stack, opened from the camera (`docs/design/BUILD-SPEC.md`, 3.10;
/// `docs/design/SETTINGS-PLAN.md`):
///
/// - Presets, always shown where the app has presets, with Factory Defaults inside;
/// - Photos: Formats, HEIF and JPEG Copies, Photo Size, Mirror Front Camera;
/// - Privacy: Details in Each Photo, Sign Each Photo;
/// - Camera: Fast Shutter, Focus on Faces;
/// - Screen: Start in Clean View, Viewfinder Overlays, Show Processed Marker, Night Mode, Keep
///   Night Mode After Astro (where the device offers Astro), Red Viewfinder, Live Activity;
/// - More: Accessibility, Honesty, About and Licenses.
///
/// A row is shown or not by the device only; no row appears or disappears when a setting
/// changes, so focus never moves by itself. Each page row shows its value, and a value that
/// doesn't fit beside its title goes under it (``SettingsValueLabel``). Each switch has a
/// one-sentence explanation (two where honesty needs it). No page is more than two levels
/// below Settings. Search (``SettingsSearch``) finds every row by its name or a keyword, and
/// answers a search for a camera control with where it is.
///
/// The screen renders a `NopeSettings` and changes it only through its methods, which hold the
/// rules (AGENTS.md, "One direction of flow"). It follows the system's light or dark setting,
/// also when it is presented from the dark camera (`ScreenAppearance.system`), and is red on
/// black in night mode.
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

    /// The device's lenses, for the Photo Size row (shown only when a lens offers a choice) and
    /// the Show Processed Marker switch (shown only when a lens has no Bayer RAW).
    private let lenses: [Lens]

    /// The saved settings presets, or `nil` to hide the Presets row (the Lock Screen camera).
    private let presets: SettingsPresets?

    /// The camera, whose lens and exposure a preset saves and sets, or `nil`.
    private let camera: CameraModel?

    /// The navigation the presenter keeps, or `nil` to keep one here.
    private let sharedNavigation: SettingsNavigation?

    /// The navigation kept here when the presenter keeps none.
    @State private var ownNavigation = SettingsNavigation()

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
    ///   - lenses: The device's lenses (`DeviceCapabilities/lenses`), which show the Photo Size
    ///     row when one offers a choice (`Lens/photoSizeChoices`), and the Show Processed Marker
    ///     switch when one has no Bayer RAW. Defaults to none.
    ///   - presets: The saved settings presets (issue #72), or `nil` to hide the Presets row.
    ///   - camera: The camera, whose lens and exposure presets save and set, or `nil`.
    public init(
        settings: NopeSettings, deviceSupportsBayerRAW: Bool, deviceHasFrontCamera: Bool = true,
        location: LocationTagging? = nil, lenses: [Lens] = [], presets: SettingsPresets? = nil,
        camera: CameraModel? = nil
    ) {
        self.init(
            settings: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW, deviceHasFrontCamera: deviceHasFrontCamera,
            location: location, lenses: lenses, presets: presets, camera: camera, navigation: nil)
    }

    /// Creates the settings screen with a navigation the presenter keeps, so the screen stays
    /// on its page when the presentation changes.
    ///
    /// - Parameters:
    ///   - settings: The settings to show and change.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    ///   - deviceHasFrontCamera: Whether the device has a front camera.
    ///   - location: Location tagging, or `nil`.
    ///   - lenses: The device's lenses.
    ///   - presets: The saved settings presets, or `nil`.
    ///   - camera: The camera, or `nil`.
    ///   - navigation: The navigation, or `nil` to keep one in the screen.
    init(
        settings: NopeSettings, deviceSupportsBayerRAW: Bool, deviceHasFrontCamera: Bool, location: LocationTagging?,
        lenses: [Lens], presets: SettingsPresets?, camera: CameraModel?, navigation: SettingsNavigation?
    ) {
        self.presets = presets
        self.camera = camera
        self.settings = settings
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
        self.deviceHasFrontCamera = deviceHasFrontCamera
        self.location = location
        self.lenses = lenses
        sharedNavigation = navigation
    }

    /// The navigation in use.
    private var navigation: SettingsNavigation {
        sharedNavigation ?? ownNavigation
    }

    /// What this device and screen offer, for the rows and for search.
    private var availability: SettingsSearch.Availability {
        SettingsSearch.Availability(
            hasPresets: presets != nil,
            offersPhotoSize: !PhotoSizeSettingsView.lensesWithChoices(lenses).isEmpty,
            hasFrontCamera: deviceHasFrontCamera,
            offersLocation: location != nil,
            offersProcessedMarker: !deviceSupportsBayerRAW || lenses.contains { !$0.supportsBayerRAW },
            offersLiveActivity: offersLiveActivity,
            offersAstro: camera?.deviceOffersAstro ?? false)
    }

    /// The list or the search results, in the navigation stack.
    public var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            Group {
                // No search in Night Mode (see ``SettingsSearchField``), so a search left in the
                // field never replaces the list there.
                if settings.isNightModeOn || SettingsSearch.words(of: navigation.searchText).isEmpty {
                    list
                } else {
                    SettingsSearchResults(query: navigation.searchText, availability: availability) { id in
                        navigation.open(id)
                    }
                }
            }
            .navigationTitle(Text("Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it."))
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SettingsSearchField(text: $navigation.searchText, isHidden: settings.isNightModeOn))
            .onChange(of: settings.isNightModeOn) { _, _ in
                // The list is built again with or without the search field. Any search ends, and
                // on the Settings list the Night Mode row, whose switch was just used, is
                // scrolled back into view.
                navigation.searchText = ""
                if navigation.path.isEmpty { navigation.scrollTarget = .nightMode }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // The system checkmark, as iOS shows for a sheet's confirm button.
                    DoneButton { dismiss() }
                }
            }
            .navigationDestination(for: SettingsPage.self) { page in
                destination(page)
            }
        }
        .environment(navigation)
    }

    /// The Settings list.
    private var list: some View {
        Form {
            if let presets {
                Section {
                    pageRow(.presets, value: PresetText.savedCount(presets.saved.count))
                }
            }
            photosSection
            privacySection
            cameraSection
            screenSection
            moreSection
        }
        .modifier(SettingsScrollTarget(navigation: navigation, page: nil))
    }

    /// A row that opens a page, with its value beside or under its title, and a note under
    /// both where the setting is used only in some state of the camera (3.16).
    ///
    /// - Parameters:
    ///   - page: The page.
    ///   - value: The row's value, or `nil` for a row without one.
    ///   - note: Where the setting is used, or `nil`. Shown only on a row with a value.
    private func pageRow(_ page: SettingsPage, value: Text?, note: Text? = nil) -> some View {
        NavigationLink(value: page) {
            if let value {
                SettingsValueLabel(title: Text(SettingsText.title(of: page.id)), value: value, note: note)
            } else {
                Text(SettingsText.title(of: page.id))
            }
        }
        // On the link too, the element Voice Control acts on: with a note, its name stays the
        // title alone. A row without a note keeps the system's input labels.
        .accessibilityInputLabels([Text(SettingsText.title(of: page.id))], isEnabled: note != nil)
        .settingsRow(page.id)
    }

    /// A page.
    ///
    /// - Parameter page: The page.
    @ViewBuilder
    private func destination(_ page: SettingsPage) -> some View {
        switch page {
        case .presets:
            if let presets {
                PresetsScreen(presets: presets, settings: settings, camera: camera)
            }
        case .formats:
            FormatsSettingsView(settings: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW)
        case .copies:
            CopiesSettingsView(settings: settings)
        case .photoSize:
            PhotoSizeSettingsView(settings: settings, lenses: lenses)
        case .details:
            PrivacySettingsView(settings: settings, location: location)
        case .fastShutter:
            // The camera's own state, which Astro also turns on; the stored option where there
            // is no camera.
            FastShutterSettingsView(
                settings: settings, manualControlsAreOn: camera?.manual.isEnabled ?? settings.showsManualControls)
        case .overlays:
            OverlaySettingsView(settings: settings)
        case .accessibility:
            AccessibilitySettingsView()
        case .honesty:
            HonestyScreen()
        case .about:
            AboutScreen()
        }
    }

    /// Formats, HEIF and JPEG Copies, Photo Size and Mirror Front Camera: what each photo is
    /// saved as.
    private var photosSection: some View {
        Section {
            pageRow(
                .formats,
                value: Text(verbatim: FormatsSettingsView.summary(of: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW)))
            pageRow(.copies, value: CopiesSettingsView.summary(of: settings))
            if availability.offersPhotoSize {
                pageRow(.photoSize, value: PhotoSizeSettingsView.summary(settings: settings, lenses: lenses))
            }
            if deviceHasFrontCamera {
                ExplainedToggle(
                    isOn: Binding(get: { settings.mirrorsFrontCamera }, set: { settings.setMirrorsFrontCamera($0) }),
                    title: Text(SettingsText.mirrorFrontCamera),
                    explanation: Text(
                        "Saves front camera photos mirrored, as the viewfinder shows them.", tableName: "Honesty", bundle: .module,
                        comment: "Explains the Mirror Front Camera switch: when on, front camera photos are saved mirrored, as the viewfinder shows them. Must not claim more than the English."))
                .settingsRow(.mirrorFrontCamera)
            }
        } header: {
            Text(SettingsText.photos)
        }
    }

    /// Details in Each Photo and Sign Each Photo: what each photo says. Release 1.1.0 adds its
    /// rows under Sign Each Photo (Save Photos To, Lock Captures, Assistant Access); each will be
    /// one row here with its own identifier, and the group needs no other change.
    private var privacySection: some View {
        Section {
            pageRow(.details, value: PrivacySettingsView.summary(of: settings.metadata))
            ExplainedToggle(
                isOn: Binding(get: { settings.signsPhotos }, set: { settings.setSignsPhotos($0) }),
                title: Text(SettingsText.signEachPhoto),
                explanation: Text(
                    "Lets anyone check that the photo hasn't changed since nope. saved it. A signed photo shows that it was taken with nope., and which version.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Explains the signing switch. Keep \"nope.\" unchanged. Must not claim more than the English: the signature shows changes, it doesn't prove who took the photo; it names the app and its version."))
            .settingsRow(.signEachPhoto)
        } header: {
            Text(SettingsText.privacy)
        }
    }

    /// Fast Shutter and Focus on Faces: how the camera focuses and exposes.
    private var cameraSection: some View {
        Section {
            pageRow(.fastShutter, value: FastShutterText.name(settings.fastShutter), note: FastShutterText.scopeNote)
            ExplainedToggle(
                isOn: Binding(get: { settings.followsFaces }, set: { settings.setFollowsFaces($0) }),
                title: Text(SettingsText.focusOnFaces),
                explanation: Text(
                    "Autofocus and auto exposure follow faces the camera finds.", bundle: .module,
                    comment: "Explains the Focus on Faces switch. It decides only whether nope.'s autofocus and auto exposure follow faces; don't describe it as turning face detection off."))
            .settingsRow(.focusOnFaces)
        } header: {
            Text(SettingsText.camera)
        }
    }

    /// What the camera screen shows: clean view, overlays, the Processed marker, night mode,
    /// whether night mode stays on after Astro, Red Viewfinder and the Live Activity. Red
    /// Viewfinder is always shown, so it can be set before going out in the dark.
    private var screenSection: some View {
        Section {
            ExplainedToggle(
                isOn: Binding(get: { settings.startsInCleanView }, set: { settings.setStartsInCleanView($0) }),
                title: Text(SettingsText.startInCleanView),
                explanation: Text(
                    "The camera opens with only the viewfinder and the shutter. Warnings about the photo always show.",
                    bundle: .module, comment: "Explains the clean view switch."))
            .settingsRow(.startInCleanView)
            pageRow(.overlays, value: OverlaySettingsView.summary(of: settings.overlays))
            if availability.offersProcessedMarker {
                ExplainedToggle(
                    isOn: Binding(get: { settings.showsProcessedMarker }, set: { settings.setShowsProcessedMarker($0) }),
                    title: Text(SettingsText.showProcessedMarker),
                    explanation: Text(
                        "Shows Processed on the camera when a lens can't save RAW.", tableName: "Honesty", bundle: .module,
                        comment: "Explains the Show Processed Marker switch. \"Processed\" is the marker's text on the camera; use the same word as its translation. RAW is a file format name. Must not claim more than the English."))
                .settingsRow(.showProcessedMarker)
            }
            ExplainedToggle(
                isOn: Binding(get: { settings.isNightModeOn }, set: { settings.setNightMode($0) }),
                title: Text(SettingsText.nightMode),
                explanation: Text(
                    "Red on black, to keep your eyes used to the dark. nope. doesn't change the screen's brightness.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Explains the Night Mode switch. Keep \"nope.\" unchanged. Must not claim more than the English."))
            .settingsRow(.nightMode)
            if availability.offersAstro {
                ExplainedToggle(
                    isOn: Binding(
                        get: { settings.keepsNightModeAfterAstro }, set: { settings.setKeepsNightModeAfterAstro($0) }),
                    title: Text(SettingsText.keepNightModeAfterAstro),
                    explanation: Text(
                        "When Astro turns Night Mode on, it stays on after you leave Astro instead of turning off again.",
                        bundle: .module,
                        comment: "Explains the Keep Night Mode After Astro switch. Astro is the night sky drive mode; Night Mode is the name of nope.'s switch. Use their translations."))
                .settingsRow(.keepNightModeAfterAstro)
            }
            ExplainedToggle(
                isOn: Binding(get: { settings.tintsViewfinderInNightMode }, set: { settings.setTintsViewfinderInNightMode($0) }),
                title: Text(SettingsText.redViewfinder),
                explanation: Text(
                    "In Night Mode, shows the live picture in red too. Only the screen changes; photos keep their colors.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Explains the Red Viewfinder switch, which is always shown and applies while Night Mode is on. Night Mode is the name of nope.'s switch; use its translation. Must not claim more than the English."))
            .settingsRow(.redViewfinder)
            if offersLiveActivity {
                ExplainedToggle(
                    isOn: Binding(get: { settings.showsLiveActivity }, set: { settings.setShowsLiveActivity($0) }),
                    title: Text(SettingsText.liveActivity),
                    explanation: Text(
                        "Shows a series' progress on the Lock Screen and in the Dynamic Island when you leave nope. Counts only; nothing is sent.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the Live Activity switch. Privacy wording: the Live Activity shows only counts and status, and nothing is sent. Keep \"nope.\" unchanged. Lock Screen and Dynamic Island are names of iOS features: use their names in the language's iOS. Must not claim more than the English."))
                .settingsRow(.liveActivity)
            }
        } header: {
            Text(SettingsText.screen)
        }
    }

    /// Accessibility, Honesty and About.
    private var moreSection: some View {
        Section {
            pageRow(.accessibility, value: nil)
            pageRow(.honesty, value: nil)
            pageRow(.about, value: nil)
        } header: {
            Text(SettingsText.more)
        }
    }
}

/// The Settings search field, left out in Night Mode.
///
/// iOS draws the search field as gray glass outside the app's views, where night mode's red
/// filter (``NightModeStyle``) can't reach it, so Settings has no search field while Night Mode
/// is on (owner decision of 2026-11-18). Every row stays reachable from the list, and the field
/// returns when Night Mode is turned off.
struct SettingsSearchField: ViewModifier {
    /// The search text.
    @Binding var text: String

    /// Whether the field is left out: Night Mode is on.
    let isHidden: Bool

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - text: The search text.
    ///   - isHidden: Whether the field is left out, as in Night Mode.
    init(text: Binding<String>, isHidden: Bool) {
        _text = text
        self.isHidden = isHidden
    }

    /// The content, with the search field in the navigation bar's drawer unless it is left out.
    ///
    /// - Parameter content: The Settings list or the search results.
    func body(content: Content) -> some View {
        if isHidden {
            content
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
        }
    }
}

/// A Settings row's title with its value: beside the title when both fit on one line, under it
/// otherwise, at every text size (`docs/design/BUILD-SPEC.md`, 3.10, "Values wrap"). Neither is
/// ever truncated. VoiceOver reads the title, then the value.
///
/// A row whose setting is used only in some state of the camera has a note too, such as Fast
/// Shutter's "Used only while Manual Controls are off." (`docs/design/BUILD-SPEC.md`, 3.16;
/// `docs/design/SETTING-SCOPE.md`). The note is a line of its own under the title and the
/// value, as wide as the row, in the explanations' footnote size and secondary color. VoiceOver
/// reads it after the value, as part of the label, and Voice Control keeps the title as the
/// row's name.
struct SettingsValueLabel: View {
    /// The row's title.
    let title: Text

    /// The row's value.
    let value: Text

    /// Where the setting is used, or `nil` for a row without a note.
    let note: Text?

    /// Creates the label.
    ///
    /// - Parameters:
    ///   - title: The row's title.
    ///   - value: The row's value.
    ///   - note: Where the setting is used, shown under the title and the value, or `nil`.
    init(title: Text, value: Text, note: Text? = nil) {
        self.title = title
        self.value = value
        self.note = note
    }

    /// The title and value, then the note, if any.
    var body: some View {
        if let note {
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                titleAndValue
                note
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // Voice Control answers to the title alone, not to the longer label with the note.
            .accessibilityInputLabels([title])
        } else {
            titleAndValue
                .accessibilityElement(children: .combine)
        }
    }

    /// The title and value, side by side or stacked.
    private var titleAndValue: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: NopeSpace.xs) {
                title
                    .fixedSize()
                Spacer(minLength: NopeSpace.m)
                value
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize()
            }
            VStack(alignment: .leading) {
                title
                value
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
