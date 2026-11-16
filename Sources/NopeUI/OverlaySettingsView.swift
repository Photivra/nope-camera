import NopeCore
import SwiftUI

/// The viewfinder overlays: grid and its style, level, focus peaking, histogram and live camera
/// readout, each its own switch, all off by default (issues #40, #47, #51 and #52). Settings
/// links to it from its Camera section.
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

    /// The form.
    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { options.showsGrid }, set: { settings.setShowsGrid($0) })) {
                    SettingLabel(
                        title: Self.gridTitle,
                        explanation: Text("Guide lines over the viewfinder. They aren't saved in the photo.", bundle: .module, comment: "Explains the Grid switch."))
                }
                Toggle(isOn: Binding(get: { options.showsLevel }, set: { settings.setShowsLevel($0) })) {
                    SettingLabel(
                        title: Self.levelTitle,
                        explanation: Text("A horizon bar, or a top-down level when you point straight down. Uses the motion sensors only while it shows.", bundle: .module, comment: "Explains the Level switch."))
                }
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
            // accessibility audit as not following Dynamic Type (see LookSettingsView).
            Section {
                Text("Live aids are measured on the preview, a few times a second, only while they show. Nothing is saved.", tableName: "Honesty", bundle: .module, comment: "Note under the focus peaking, histogram and live readout switches. Must not claim more than the English.")
                    .font(.footnote)
            }
        }
        .navigationTitle(Self.rowTitle)
    }

    /// The grid style, as an inline list that grows with the text size, and Turn Spiral while
    /// the spiral is chosen (a button, so it is also a VoiceOver, Voice Control and Switch
    /// Control action).
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
            if options.gridStyle == .goldenSpiral {
                Button {
                    settings.turnSpiral()
                } label: {
                    LabeledContent {
                        Text("\(options.spiralPlacement.index + 1) of \(SpiralPlacement.count)", bundle: .module, comment: "Which of the golden spiral's eight placements is in use, such as 3 of 8.")
                    } label: {
                        Self.turnSpiralTitle
                    }
                }
                // Primary text, not the tint: the tinted label measured just under 4.5:1 in the
                // accessibility audit.
                .tint(.primary)
            }
        }
    }

    /// The row and screen title, "Viewfinder Overlays".
    static var rowTitle: Text {
        Text("Viewfinder Overlays", bundle: .module, comment: "Settings row and screen title: the grid, level, focus peaking, histogram and live readout drawn over the viewfinder.")
    }

    /// "Grid".
    static var gridTitle: Text {
        Text("Grid", bundle: .module, comment: "Name of the switch and quick control that draws guide lines over the viewfinder.")
    }

    /// "Level".
    static var levelTitle: Text {
        Text("Level", bundle: .module, comment: "Name of the horizon level shown over the viewfinder, and of its switch.")
    }

    /// "Turn Spiral".
    static var turnSpiralTitle: Text {
        Text("Turn Spiral", bundle: .module, comment: "Button that moves the golden spiral grid to its next placement (turned or flipped).")
    }

    /// The name of a grid style.
    ///
    /// - Parameter style: The style.
    static func name(of style: GridStyle) -> Text {
        switch style {
        case .thirds: Text("Thirds", bundle: .module, comment: "Grid style: two lines each way, at thirds (rule of thirds).")
        case .fourByFour: Text("4 × 4", bundle: .module, comment: "Grid style: three lines each way, dividing the picture into 4 by 4.")
        case .square: Text("Square", bundle: .module, comment: "Grid style: a centered square frame, for photos cropped square later.")
        case .goldenRatio: Text("Golden Ratio", bundle: .module, comment: "Grid style: lines at the golden ratio (phi).")
        case .goldenSpiral: Text("Golden Spiral", bundle: .module, comment: "Grid style: a golden (Fibonacci) spiral.")
        }
    }

    /// A navigation row to the overlays, showing "On" when any is on.
    ///
    /// - Parameter settings: The settings.
    static func link(settings: NopeSettings) -> some View {
        NavigationLink {
            OverlaySettingsView(settings: settings)
        } label: {
            LabeledContent {
                settings.overlays.isAnyOn
                    ? Text("On", bundle: .module, comment: "Live readout value: a feature is on.")
                    : Text("Off", bundle: .module, comment: "Live readout value: a feature is off.")
            } label: {
                rowTitle
            }
        }
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
                title: Text("Focus Peaking", bundle: .module, comment: "Name of the switch that highlights in-focus edges over the viewfinder."),
                explanation: Text("Highlights the sharpest edges in magenta.", bundle: .module, comment: "Explains the Focus Peaking switch."))
        }
        Toggle(isOn: Binding(get: { options.showsHistogram }, set: { settings.setShowsHistogram($0) })) {
            SettingLabel(
                title: Text("Histogram", bundle: .module, comment: "Name of the live brightness histogram shown with the manual controls, and of its switch."),
                explanation: Text("Shown with the manual controls. It measures the processed live preview, not the RAW.", tableName: "Honesty", bundle: .module, comment: "Explains the Histogram switch. RAW is a file format name. Must not claim more than the English."))
        }
        Toggle(isOn: Binding(get: { options.showsLiveReadout }, set: { settings.setShowsLiveReadout($0) })) {
            SettingLabel(
                title: LiveReadoutText.title,
                explanation: Text("The camera's live values, such as shutter, ISO, focus and white balance.", bundle: .module, comment: "Explains the Live Camera Readout switch. ISO is the usual camera abbreviation."))
        }
        if options.showsLiveReadout {
            Toggle(isOn: Binding(get: { options.pinsLiveReadout }, set: { settings.setPinsLiveReadout($0) })) {
                SettingLabel(
                    title: LiveReadoutText.pinTitle,
                    explanation: Text("Keeps the readout on screen when the other controls are hidden.", bundle: .module, comment: "Explains the Keep Readout in Clean View switch. Clean view hides every control but the shutter."))
            }
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
