import NopeCore
import SwiftUI

/// The viewfinder overlays: grid and its style, level, focus peaking, histogram and live camera
/// readout, each its own switch, all off by default (issues #40, #47, #51 and #52). Settings
/// links to it from its Screen section, with a value that names what is on. Grid, Level, Focus
/// Peaking and the readout are also Q tiles; each changes the same value.
///
/// The screen renders `NopeSettings` and changes it only through its methods.
struct OverlaySettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Creates the screen.
    ///
    /// - Parameter settings: The settings to show and change.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The options.
    private var options: OverlayOptions { settings.overlays }

    /// Where Settings is, to scroll to a row search opened, or `nil`.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    /// The form.
    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { options.showsGrid }, set: { settings.setShowsGrid($0) })) {
                    SettingLabel(
                        title: Self.gridTitle,
                        explanation: Text("Guide lines over the viewfinder. They aren't saved in the photo.", bundle: .module, comment: "Explains the Grid switch."))
                }
                .settingsRow(.overlaysGrid)
                Toggle(isOn: Binding(get: { options.showsLevel }, set: { settings.setShowsLevel($0) })) {
                    SettingLabel(
                        title: Self.levelTitle,
                        explanation: Text("A horizon bar, or a top-down level when you point straight down. Uses the motion sensors only while it shows.", bundle: .module, comment: "Explains the Level switch."))
                }
                .settingsRow(.overlaysLevel)
            } header: {
                Text("Guides", bundle: .module, comment: "Settings section header above the grid and level switches.")
            }
            if options.showsGrid {
                gridStyleSection
            }
            Section {
                LiveAidToggles(settings: settings)
            } header: {
                Text("Live Aids", bundle: .module, comment: "Settings section header above focus peaking, the histogram and the live camera readout.")
            }
            // A row rather than a section footer: footers under switches were reported by the
            // accessibility audit as not following Dynamic Type (see CopiesSettingsView).
            Section {
                Text("Live aids are measured on the preview, a few times a second, only while they show. Nothing is saved.", tableName: "Honesty", bundle: .module, comment: "Note under the focus peaking, histogram and live readout switches. Must not claim more than the English.")
                    .font(.footnote)
            }
        }
        .navigationTitle(Self.rowTitle)
        .modifier(SettingsScrollTarget(navigation: navigation, page: .overlays))
    }

    /// The grid style, as an inline list that grows with the text size.
    private var gridStyleSection: some View {
        Section {
            Picker(selection: Binding(get: { options.gridStyle }, set: { settings.setGridStyle($0) })) {
                ForEach(GridStyle.allCases, id: \.self) { style in
                    Self.name(of: style).tag(style)
                }
            } label: {
                Text("Grid Style", bundle: .module, comment: "Picker for which guide lines the grid draws.")
            }
            .pickerStyle(.inline)
        }
        .settingsRow(.overlaysGridStyle)
    }

    /// The row and screen title, "Viewfinder Overlays".
    static var rowTitle: Text {
        Text("Viewfinder Overlays", bundle: .module, comment: "Settings row and screen title: the grid, level, focus peaking, histogram and live readout drawn over the viewfinder.")
    }

    /// "Grid".
    static var gridTitle: Text {
        Text(SettingsText.grid)
    }

    /// "Level".
    static var levelTitle: Text {
        Text(SettingsText.level)
    }

    /// "Focus Peaking".
    static var focusPeakingTitle: Text {
        Text(SettingsText.focusPeaking)
    }

    /// The name of a grid style.
    ///
    /// - Parameter style: The style.
    static func name(of style: GridStyle) -> Text {
        switch style {
        case .thirds: Text("Thirds", bundle: .module, comment: "Grid style: two lines each way, at thirds (rule of thirds).")
        case .fourByFour: Text("4 × 4", bundle: .module, comment: "Grid style: three lines each way, dividing the picture into 4 by 4.")
        case .square: Text("Square", bundle: .module, comment: "Grid style: a centered square frame, for photos cropped square later.")
        }
    }

    /// The Settings row's value: "Off"; the names when one or two overlays are on ("Grid,
    /// Level"); a count from three ("3 On"). Keep Readout in Clean View is part of the readout,
    /// not an overlay of its own.
    ///
    /// - Parameter options: The overlay options.
    /// - Returns: The value text.
    static func summary(of options: OverlayOptions) -> Text {
        let names = onNames(of: options).map { String(localized: $0) }
        switch names.count {
        case 0:
            return Text("Off", bundle: .module, comment: "Live readout value: a feature is off.")
        case 1:
            return Text(verbatim: names[0])
        case 2:
            return Text("\(names[0]), \(names[1])", bundle: .module, comment: "Value of the Viewfinder Overlays row in Settings: the names of the two overlays that are on, such as Grid, Level.")
        default:
            return Text("\(names.count) On", bundle: .module, comment: "Value of the Viewfinder Overlays row in Settings: how many overlays are on, three or more.")
        }
    }

    /// The names of the overlays that are on, in the order of the page.
    ///
    /// - Parameter options: The overlay options.
    /// - Returns: The names.
    static func onNames(of options: OverlayOptions) -> [LocalizedStringResource] {
        [
            (options.showsGrid, SettingsText.grid),
            (options.showsLevel, SettingsText.level),
            (options.showsFocusPeaking, SettingsText.focusPeaking),
            (options.showsHistogram, SettingsText.histogram),
            (options.showsLiveReadout, SettingsText.liveReadout),
        ].filter(\.0).map(\.1)
    }
}

/// The focus peaking, histogram and live camera readout switches, in Settings and in Pro Tools.
struct LiveAidToggles: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Creates the switches.
    ///
    /// - Parameter settings: The settings to show and change.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The switches.
    var body: some View {
        let options = settings.overlays
        Toggle(isOn: Binding(get: { options.showsFocusPeaking }, set: { settings.setShowsFocusPeaking($0) })) {
            SettingLabel(
                title: OverlaySettingsView.focusPeakingTitle,
                explanation: Text("Highlights the sharpest edges in magenta.", bundle: .module, comment: "Explains the Focus Peaking switch."))
        }
        .settingsRow(.overlaysFocusPeaking)
        Toggle(isOn: Binding(get: { options.showsHistogram }, set: { settings.setShowsHistogram($0) })) {
            SettingLabel(
                title: Text("Histogram", bundle: .module, comment: "Name of the live brightness histogram shown with the manual controls, and of its switch."),
                explanation: Text("Shown with the manual controls. It measures the processed live preview, not the RAW.", tableName: "Honesty", bundle: .module, comment: "Explains the Histogram switch. RAW is a file format name. Must not claim more than the English."))
        }
        .settingsRow(.overlaysHistogram)
        Toggle(isOn: Binding(get: { options.showsLiveReadout }, set: { settings.setShowsLiveReadout($0) })) {
            SettingLabel(
                title: LiveReadoutText.title,
                explanation: Text("The camera's live values, such as shutter, ISO, focus and white balance.", bundle: .module, comment: "Explains the Live Camera Readout switch. ISO is the usual camera abbreviation."))
        }
        .settingsRow(.overlaysLiveReadout)
        if options.showsLiveReadout {
            Toggle(isOn: Binding(get: { options.pinsLiveReadout }, set: { settings.setPinsLiveReadout($0) })) {
                SettingLabel(
                    title: LiveReadoutText.pinTitle,
                    explanation: Text("Keeps the readout on screen when the other controls are hidden.", bundle: .module, comment: "Explains the Keep Readout in Clean View switch. Clean view hides every control but the shutter."))
            }
            .settingsRow(.overlaysKeepReadout)
        }
    }
}

extension QuickControls {
    /// Grid: a menu of Off and each grid style.
    ///
    /// - Parameter context: The model and settings.
    static func grid(_ context: CameraControlContext) -> QuickControlItem? {
        let settings = context.settings
        let options = settings.overlays
        let off = QuickControlItem.Option(
            id: "off", title: Text("Off", bundle: .module, comment: "Live readout value: a feature is off."),
            isSelected: !options.showsGrid
        ) {
            settings.setShowsGrid(false)
        }
        let styles = GridStyle.allCases.map { style in
            QuickControlItem.Option(
                id: style.rawValue, title: OverlaySettingsView.name(of: style),
                isSelected: options.showsGrid && options.gridStyle == style
            ) {
                settings.setGridStyle(style)
                settings.setShowsGrid(true)
            }
        }
        return QuickControlItem(
            id: "grid", title: OverlaySettingsView.gridTitle, systemImage: "grid", kind: .menu([off] + styles))
    }

    /// Live camera readout: a menu of Off, On, and On that stays in clean view (issue #52), the
    /// same choices as the switches in Settings and Pro Tools.
    ///
    /// - Parameter context: The model and settings.
    static func liveReadout(_ context: CameraControlContext) -> QuickControlItem? {
        guard context.model.live.isSupported else { return nil }
        let settings = context.settings
        let options = settings.overlays
        let choices: [(id: String, title: Text, isOn: Bool, isPinned: Bool)] = [
            ("off", Text("Off", bundle: .module, comment: "Live readout value: a feature is off."), false, false),
            ("on", Text("On", bundle: .module, comment: "Live readout value: a feature is on."), true, false),
            ("pinned", LiveReadoutText.pinTitle, true, true),
        ]
        return QuickControlItem(
            id: "liveReadout", title: LiveReadoutText.shortTitle, systemImage: "list.bullet.rectangle",
            kind: .menu(
                choices.map { choice in
                    QuickControlItem.Option(
                        id: choice.id, title: choice.title,
                        isSelected: options.showsLiveReadout == choice.isOn && (!choice.isOn || options.pinsLiveReadout == choice.isPinned)
                    ) {
                        settings.setShowsLiveReadout(choice.isOn)
                        settings.setPinsLiveReadout(choice.isPinned)
                    }
                }))
    }

    /// Focus Peaking: a switch for the same value as Settings › Viewfinder Overlays and Pro Tools
    /// (`docs/design/BUILD-SPEC.md`, 3.6; decision 7.7), so it is two taps away in full auto
    /// too. Shown in full auto and with manual controls on, wherever the live aids can run.
    ///
    /// - Parameter context: The model and settings.
    static func focusPeaking(_ context: CameraControlContext) -> QuickControlItem? {
        guard context.model.live.isSupported else { return nil }
        let settings = context.settings
        return QuickControlItem(
            id: "focusPeaking", title: OverlaySettingsView.focusPeakingTitle, systemImage: "scope",
            kind: .toggle(isOn: settings.overlays.showsFocusPeaking) { settings.setShowsFocusPeaking($0) })
    }

    /// Level: a switch.
    ///
    /// - Parameter context: The model and settings.
    static func level(_ context: CameraControlContext) -> QuickControlItem? {
        let settings = context.settings
        return QuickControlItem(
            id: "level", title: OverlaySettingsView.levelTitle, systemImage: "level",
            kind: .toggle(isOn: settings.overlays.showsLevel) { settings.setShowsLevel($0) })
    }
}
