import NopeCore
import SwiftUI

/// One tile of the quick menu, Q (docs/design/BUILD-SPEC.md, 3.6), such as Grid or Night Mode.
///
/// An item is a button, a switch, or a native menu of values. Its tile shows the name on top,
/// then the symbol and the current value ("Grid", "Thirds"); a tile that is on is filled white.
/// VoiceOver reads the name, then the value.
struct QuickControlItem: Identifiable {
    /// One value of a menu item, such as "Thirds" for the grid.
    struct Option: Identifiable {
        /// A stable identifier within the item.
        let id: String

        /// The value's name.
        let title: Text

        /// Whether it is the value in use.
        let isSelected: Bool

        /// Chooses it.
        let select: @MainActor () -> Void

        /// Creates an option.
        ///
        /// - Parameters:
        ///   - id: A stable identifier within the item.
        ///   - title: The value's name.
        ///   - isSelected: Whether it is the value in use.
        ///   - select: Chooses it.
        init(id: String, title: Text, isSelected: Bool, select: @escaping @MainActor () -> Void) {
            self.id = id
            self.title = title
            self.isSelected = isSelected
            self.select = select
        }
    }

    /// What the item does when pressed.
    enum Kind {
        /// Does one thing, then the panel closes.
        case button(@MainActor () -> Void)

        /// Turns something on or off: `isOn` is the current state, `set` changes it. The panel
        /// stays open.
        case toggle(isOn: Bool, set: @MainActor (Bool) -> Void)

        /// Chooses one value from a native menu. The panel stays open.
        case menu([Option])
    }

    /// A stable identifier, such as "grid". The UI tests find a tile by it.
    let id: String

    /// The item's name, shown on top of its tile and read by VoiceOver.
    let title: Text

    /// The SF Symbol shown before the value.
    let systemImage: String

    /// What it does.
    let kind: Kind

    /// The value shown on the tile when it isn't the one the kind gives (``value``), such as a
    /// percentage for Light or "2 Saved" for Presets; `nil` for the kind's own value.
    var customValue: Text?

    /// Whether the tile is drawn as on when that isn't what the kind gives (``isOn``), such as
    /// Exposure while its compensation isn't 0; `nil` for the kind's own state.
    var customIsOn: Bool?

    /// Creates an item.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - title: The item's name.
    ///   - systemImage: The SF Symbol.
    ///   - kind: What it does.
    ///   - value: The value to show instead of the kind's own, or `nil`.
    ///   - isOn: Whether the tile is on, instead of what the kind gives, or `nil`.
    init(id: String, title: Text, systemImage: String, kind: Kind, value: Text? = nil, isOn: Bool? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.customValue = value
        self.customIsOn = isOn
    }

    /// Whether the item is on: a switch that is on, or a menu whose value isn't its first
    /// (default) option, unless the item says otherwise.
    var isOn: Bool {
        if let customIsOn { return customIsOn }
        return switch kind {
        case .button: false
        case .toggle(let isOn, _): isOn
        case .menu(let options): options.first.map { !$0.isSelected } ?? false
        }
    }

    /// The value on the tile: the item's own value if it has one; otherwise On or Off for a
    /// switch, the chosen option's name for a menu, and nothing for a button.
    var value: Text? {
        if let customValue { return customValue }
        return switch kind {
        case .button: nil
        case .toggle(let isOn, _): isOn ? QuickControlsText.on : QuickControlsText.off
        case .menu(let options): options.first(where: \.isSelected)?.title
        }
    }

    /// Whether pressing the tile closes the panel: a button does; a switch or a menu doesn't,
    /// so several can be changed in a row.
    var closesPanel: Bool {
        if case .button = kind { true } else { false }
    }
}

/// The registry of quick-menu tiles, in display order. Each feature adds one function here; the
/// panel shows whatever the functions return for the current lens and settings (`nil` hides a
/// tile the device can't do or that doesn't apply, such as Far Focus in full auto).
///
/// The order is Flash, Light, Exposure, Close-Up, Far Focus, Fast Shutter, Magnify, Focus
/// Peaking, Grid, Level, Readout, Night Mode, Compare, Presets (docs/design/BUILD-SPEC.md, 3.6):
/// thirteen tiles in full auto on a device with every feature, in five rows of three. Drive and
/// Astro are on the drive strip, and Hide Controls is a button in the panel's foot.
@MainActor
enum QuickControls {
    /// Every item builder, in display order.
    static let builders: [@MainActor (CameraControlContext) -> QuickControlItem?] = [
        flash,
        light,
        exposure,
        closeUp,
        farFocus,
        fastShutter,
        magnifier,
        focusPeaking,
        grid,
        level,
        withValue(liveReadout, readoutValue),
        night,
        compare,
        withValue(presets, presetsValue),
    ]

    /// The tiles for the current state, in display order.
    ///
    /// - Parameter context: The model and settings.
    static func current(_ context: CameraControlContext) -> [QuickControlItem] {
        builders.compactMap { $0(context) }
    }

    /// A builder whose item shows a value worked out here, for builders that live in other
    /// files and show something other than their menu's option name or a switch's On or Off.
    ///
    /// - Parameters:
    ///   - builder: The item's builder.
    ///   - value: The value to show.
    /// - Returns: The builder with the value added.
    static func withValue(
        _ builder: @escaping @MainActor (CameraControlContext) -> QuickControlItem?,
        _ value: @escaping @MainActor (CameraControlContext) -> Text
    ) -> @MainActor (CameraControlContext) -> QuickControlItem? {
        { context in
            guard var item = builder(context) else { return nil }
            item.customValue = value(context)
            return item
        }
    }

    /// The Readout tile's value: Off, On, or Pinned while the readout stays in clean view.
    ///
    /// - Parameter context: The model and settings.
    static func readoutValue(_ context: CameraControlContext) -> Text {
        let overlays = context.settings.overlays
        guard overlays.showsLiveReadout else { return QuickControlsText.off }
        return overlays.pinsLiveReadout ? QuickControlsText.pinned : QuickControlsText.on
    }

    /// The Presets tile's value: how many presets are saved ("2 Saved"), or None Saved.
    ///
    /// - Parameter context: The model and settings.
    static func presetsValue(_ context: CameraControlContext) -> Text {
        QuickControlsText.saved(context.presets?.saved.count ?? 0)
    }

    /// Exposure: opens the exposure compensation dial in full auto (issue #41) and closes the
    /// panel. Shown when the lens can compensate and manual controls are off; with them on, the
    /// readout row has it. Its value is the compensation, such as "+0.7", and it is on while
    /// that isn't 0.
    ///
    /// - Parameter context: The model and settings.
    static func exposure(_ context: CameraControlContext) -> QuickControlItem? {
        let manual = context.model.manual
        guard !manual.isEnabled, manual.canAdjustExposureCompensation else { return nil }
        let isOpen = context.showsExposureDial
        let compensation = manual.settings.exposureCompensation
        return QuickControlItem(
            id: "exposure",
            title: Text("Exposure", bundle: .module, comment: "Name of the exposure compensation control in full auto, in the quick-controls tray and on its dial."),
            systemImage: "plusminus.circle",
            kind: .button { isOpen.wrappedValue = true },
            value: Text(verbatim: ControlText.value(compensation, of: .exposureCompensation)),
            isOn: compensation != 0)
    }

    /// Fast Shutter: how fast a shutter full auto prefers (issue #56), the same choice as in
    /// Settings. Shown while manual controls are off, where it applies. Its value is short:
    /// Standard, 1/500 or 1/1000.
    ///
    /// - Parameter context: The model and settings.
    static func fastShutter(_ context: CameraControlContext) -> QuickControlItem? {
        guard !context.model.manual.isEnabled else { return nil }
        let settings = context.settings
        return QuickControlItem(
            id: "fastShutter", title: FastShutterText.title, systemImage: "hare",
            kind: .menu(
                FastShutter.allCases.map { choice in
                    QuickControlItem.Option(
                        id: choice.rawValue, title: FastShutterText.name(choice), isSelected: settings.fastShutter == choice
                    ) {
                        settings.setFastShutter(choice)
                    }
                }),
            value: QuickControlsText.shortName(of: settings.fastShutter))
    }

    /// Close-Up: limits autofocus to near subjects, so it doesn't jump to the background
    /// (issue #51). Shown where the lens supports it, or while it is on.
    ///
    /// - Parameter context: The model and settings.
    static func closeUp(_ context: CameraControlContext) -> QuickControlItem? {
        let manual = context.model.manual
        guard manual.capabilities.supportsNearFocusLimit || manual.nearFocusLimit else { return nil }
        return QuickControlItem(
            id: "closeUp", title: CloseUpText.title, systemImage: "camera.macro",
            kind: .toggle(isOn: manual.nearFocusLimit) { context.send(.auto(.setNearFocusLimit($0))) })
    }

    /// Far Focus: limits autofocus to far subjects, so it doesn't catch a near branch or a window
    /// (issue #57). An advanced option: shown with manual controls on where the lens supports
    /// it, or while it is on.
    ///
    /// - Parameter context: The model and settings.
    static func farFocus(_ context: CameraControlContext) -> QuickControlItem? {
        let manual = context.model.manual
        guard (manual.isEnabled && manual.capabilities.supportsFarFocusLimit) || manual.farFocusLimit else { return nil }
        return QuickControlItem(
            id: "farFocus", title: FarFocusText.title, systemImage: "mountain.2",
            kind: .toggle(isOn: manual.farFocusLimit) { context.send(.auto(.setFarFocusLimit($0))) })
    }

    /// Magnify: shows the viewfinder enlarged around the focus point, for checking focus
    /// (issue #51). Preview only.
    ///
    /// - Parameter context: The model and settings.
    static func magnifier(_ context: CameraControlContext) -> QuickControlItem? {
        QuickControlItem(
            id: "magnifier", title: MagnifierText.title, systemImage: "plus.magnifyingglass",
            kind: .toggle(isOn: context.model.isMagnifying) { context.send(.auto(.setMagnifier($0))) })
    }

    /// Light: the torch, a steady light for close subjects in the dark (issue #38). Shown only
    /// on a lens with a torch. Its value is Off or the brightness, such as "25%"; the Light pill
    /// that appears while it is on changes the brightness.
    ///
    /// - Parameter context: The model and settings.
    static func light(_ context: CameraControlContext) -> QuickControlItem? {
        let light = context.model.light
        // The light stays off while the astro helper is on (issue #60).
        guard light.supportsTorch, !context.model.astro.isOn else { return nil }
        return QuickControlItem(
            id: "light",
            title: Text("Light", bundle: .module, comment: "Camera switch and its Voice Control name: turns on the phone's light (torch) and keeps it on while taking photos."),
            systemImage: light.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
            // On while the light is on, waiting for the camera to start (issue #75), or refused,
            // so a refused light (with its warning) is cleared by turning the switch off, and
            // tried again by turning it on.
            kind: .toggle(isOn: light.torch != .off) { context.send(.light(.setTorch($0))) },
            value: QuickControlsText.lightValue(light.torch, requestedLevel: context.settings.torchLevel))
    }

    /// Flash: Off, Auto or On (issue #38). Shown only on a lens with a flash, with the modes the
    /// lens supports. The menu names each mode in full ("Flash Auto"); the tile's value is the
    /// short word.
    ///
    /// - Parameter context: The model and settings.
    static func flash(_ context: CameraControlContext) -> QuickControlItem? {
        let light = context.model.light
        guard light.supportsFlash else { return nil }
        let settings = context.settings
        return QuickControlItem(
            id: "flash",
            title: Text("Flash", bundle: .module, comment: "Camera menu and its Voice Control name: when the flash fires (Off, Auto, On)."),
            systemImage: FlashText.systemImage(for: settings.flashMode),
            kind: .menu(light.supportedFlashModes.map { mode in
                QuickControlItem.Option(id: mode.rawValue, title: FlashText.name(of: mode), isSelected: settings.flashMode == mode) {
                    settings.setFlashMode(mode)
                }
            }),
            value: QuickControlsText.shortName(of: settings.flashMode))
    }

    /// Night: red and black screens for working in the dark (issue #61). Remembered between
    /// launches; the app never changes the screen's brightness.
    ///
    /// - Parameter context: The model and settings.
    static func night(_ context: CameraControlContext) -> QuickControlItem? {
        let settings = context.settings
        return QuickControlItem(
            id: "night",
            title: Text("Night Mode", bundle: .module, comment: "Switch and its Voice Control name: shows nope.'s screens in red on black for working in the dark. Keep \"nope.\" unchanged."),
            systemImage: "moon.fill",
            kind: .toggle(isOn: settings.isNightModeOn) { settings.setNightMode($0) })
    }

    /// Hide Controls: clean view, which leaves only the shutter, a Show Controls button and any
    /// warnings. It is the first button of the panel's foot, not a tile.
    ///
    /// - Parameter context: The model and settings.
    static func hideControls(_ context: CameraControlContext) -> QuickControlItem {
        QuickControlItem(
            id: "hideControls", title: QuickControlsText.hideControls, systemImage: "eye.slash",
            kind: .button { context.send(.setCleanView(true)) })
    }
}

/// The quick menu's own words: tile values and the foot's buttons.
enum QuickControlsText {
    /// "Quick Menu": the name of the Q button, of the panel for VoiceOver, and the title of the
    /// list at accessibility text sizes.
    static var title: Text {
        Text("Quick Menu", bundle: .module, comment: "VoiceOver and Voice Control name of the Q button beside the shutter, which opens a panel of camera tiles; also the title of that panel when it is a list at the largest text sizes. Replaces Quick Controls.")
    }

    /// "On", the value of a switch tile that is on.
    static var on: Text {
        Text("On", bundle: .module, comment: "Live readout value: a feature is on.")
    }

    /// "Off", the value of a switch tile that is off.
    static var off: Text {
        Text("Off", bundle: .module, comment: "Live readout value: a feature is off.")
    }

    /// "Pinned", the Readout tile's value while the readout stays in clean view.
    static var pinned: Text {
        Text("Pinned", bundle: .module, comment: "Value of the Readout tile in the Quick Menu: the live camera readout is on and stays on screen in clean view. Short: it sits in a small tile.")
    }

    /// "Hide Controls", the first button of the panel's foot.
    static var hideControls: Text {
        Text("Hide Controls", bundle: .module, comment: "Button that turns on clean view: hides every control except the shutter.")
    }

    /// "Settings", the second button of the panel's foot.
    static var settings: Text {
        Text("Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it.")
    }

    /// "Done", which closes the list at accessibility text sizes.
    static var done: Text {
        Text("Done", bundle: .module, comment: "Button that closes a sheet, such as Settings or Pro Tools.")
    }

    /// How many presets are saved: "2 Saved", or "None Saved" for none.
    ///
    /// - Parameter count: The number of saved presets.
    static func saved(_ count: Int) -> Text {
        guard count > 0 else {
            return Text("None Saved", bundle: .module, comment: "Value of the Presets tile in the Quick Menu and of the Presets row in Settings: the person has saved no presets (Factory Defaults is still there). Keep it short: it sits in a small tile under the name Presets, so \"None\" alone is enough where that reads naturally.")
        }
        return Text("\(count) Saved", bundle: .module, comment: "Value of the Presets tile in the Quick Menu and of the Presets row in Settings: how many presets the person has saved, at least 1. Keep it short: it sits in a small tile under the name Presets, so a counter word alone is enough where that reads naturally.")
    }

    /// A flash mode's short name on its tile: Off, Auto or On.
    ///
    /// - Parameter mode: The flash mode.
    static func shortName(of mode: FlashMode) -> Text {
        switch mode {
        case .off: off
        case .auto: Text("Auto", bundle: .module, comment: "A control set automatically by the camera.")
        case .on: on
        }
    }

    /// A fast shutter choice's short name on its tile: Standard, 1/500 or 1/1000. The fractions
    /// are shutter speeds, written the same in every language, as on the manual readouts.
    ///
    /// - Parameter choice: The choice.
    static func shortName(of choice: FastShutter) -> Text {
        switch choice {
        case .handheld: FastShutterText.name(.handheld)
        case .freezeMotion: Text(verbatim: "1/500")
        case .freezeFastMotion: Text(verbatim: "1/1000")
        }
    }

    /// The Light tile's value: the brightness while the light is on or waiting for the camera,
    /// Light Unavailable when the system refused it, and Off otherwise.
    ///
    /// - Parameters:
    ///   - torch: The light's state.
    ///   - requestedLevel: The brightness the person chose, from 0 to 1, shown while waiting.
    static func lightValue(_ torch: TorchStatus, requestedLevel: Double) -> Text {
        switch torch {
        case .off: off
        case .on(let level): Text(level, format: .percent.precision(.fractionLength(0)))
        case .pending: Text(requestedLevel, format: .percent.precision(.fractionLength(0)))
        case .unavailable:
            Text("Light Unavailable", bundle: .module, comment: "Warning chip on the camera: the light (torch) the person turned on is off because the system didn't allow it.")
        }
    }
}

/// The words and symbols for flash modes.
enum FlashText {
    /// A flash mode's name, as in the Flash menu.
    ///
    /// - Parameter mode: The flash mode.
    static func name(of mode: FlashMode) -> Text {
        switch mode {
        case .off: Text("Flash Off", bundle: .module, comment: "Flash menu item and pill: the flash never fires.")
        case .auto: Text("Flash Auto", bundle: .module, comment: "Flash menu item and pill: the camera decides whether the flash fires.")
        case .on: Text("Flash On", bundle: .module, comment: "Flash menu item and pill: the flash fires for every photo.")
        }
    }

    /// The SF Symbol for a flash mode.
    ///
    /// - Parameter mode: The flash mode.
    static func systemImage(for mode: FlashMode) -> String {
        switch mode {
        case .off: "bolt.slash.fill"
        case .auto: "bolt.badge.automatic.fill"
        case .on: "bolt.fill"
        }
    }
}
