import NopeCore
import SwiftUI

/// One item of the quick-controls tray, such as Hide Controls (issue #68, "Quick-controls
/// tray").
///
/// An item is a button, a switch, or a native menu of values. Switches and menus show their
/// current state in words for VoiceOver; an item that is on is filled white.
struct QuickControlItem: Identifiable {
    /// One value of a menu item, such as "3 s" for a timer.
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
        /// Does one thing, then the tray closes.
        case button(@MainActor () -> Void)

        /// Turns something on or off: `isOn` is the current state, `set` changes it.
        case toggle(isOn: Bool, set: @MainActor (Bool) -> Void)

        /// Chooses one value from a native menu.
        case menu([Option])
    }

    /// A stable identifier, such as "hideControls".
    let id: String

    /// The item's name, shown under its symbol and read by VoiceOver.
    let title: Text

    /// The SF Symbol.
    let systemImage: String

    /// What it does.
    let kind: Kind

    /// Creates an item.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - title: The item's name.
    ///   - systemImage: The SF Symbol.
    ///   - kind: What it does.
    init(id: String, title: Text, systemImage: String, kind: Kind) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
    }

    /// Whether the item is on: a switch that is on, or a menu whose value isn't its first
    /// (default) option.
    var isOn: Bool {
        switch kind {
        case .button: false
        case .toggle(let isOn, _): isOn
        case .menu(let options): options.first.map { !$0.isSelected } ?? false
        }
    }
}

/// The registry of quick-controls tray items, in display order. Each camera toggle adds one
/// function here; the tray shows whatever the functions return for the current lens and
/// settings (`nil` hides an item the device can't do).
///
/// The planned order is Light, Flash, Drive, Exposure, Grid, Level, Fast Shutter, Night, then
/// Hide Controls last (issue #68).
@MainActor
enum QuickControls {
    /// Every item builder, in display order. Add a feature's builder here, before
    /// ``hideControls(_:)``.
    static let builders: [@MainActor (CameraControlContext) -> QuickControlItem?] = [
        light,
        flash,
        drive,
        exposure,
        grid,
        level,
        liveReadout,
        fastShutter,
        closeUp,
        farFocus,
        magnifier,
        astro,
        compare,
        night,
        hideControls,
    ]

    /// The tray's items for the current state, in display order.
    ///
    /// - Parameter context: The model and settings.
    static func current(_ context: CameraControlContext) -> [QuickControlItem] {
        builders.compactMap { $0(context) }
    }

    /// Exposure: opens the exposure compensation dial in full auto (issue #41). Shown when the
    /// lens can compensate and manual controls are off; with them on, the readout row has it.
    ///
    /// - Parameter context: The model and settings.
    static func exposure(_ context: CameraControlContext) -> QuickControlItem? {
        let manual = context.model.manual
        guard !manual.isEnabled, manual.canAdjustExposureCompensation else { return nil }
        let isOpen = context.showsExposureDial
        return QuickControlItem(
            id: "exposure",
            title: Text("Exposure", bundle: .module, comment: "Name of the exposure compensation control in full auto, in the quick-controls tray and on its dial."),
            systemImage: "plusminus.circle",
            kind: .toggle(isOn: isOpen.wrappedValue) { isOpen.wrappedValue = $0 })
    }

    /// Fast Shutter: how fast a shutter full auto prefers (issue #56), the same choice as in
    /// Settings. Shown while manual controls are off, where it applies.
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
                }))
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
    /// on a lens with a torch. Its brightness is on the Light pill that appears while it is on.
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
            // On while the light is on or was refused, so a refused light (with its warning) is
            // cleared by turning the switch off, and tried again by turning it on.
            kind: .toggle(isOn: light.torch != .off) { context.send(.light(.setTorch($0))) })
    }

    /// Flash: Off, Auto or On (issue #38). Shown only on a lens with a flash, with the modes the
    /// lens supports.
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
            }))
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
    /// warnings.
    ///
    /// - Parameter context: The model and settings.
    static func hideControls(_ context: CameraControlContext) -> QuickControlItem? {
        QuickControlItem(
            id: "hideControls",
            title: Text("Hide Controls", bundle: .module, comment: "Button that turns on clean view: hides every control except the shutter."),
            systemImage: "eye.slash",
            kind: .button { context.send(.setCleanView(true)) })
    }
}

/// The quick-controls tray: one scrolling row of items that takes the lens row's place while it
/// is open, or, over the picture in the iPad column layout, rows that wrap so every item shows
/// whole (a row scrolled under the picture's edge cut the last item there). It closes when an
/// item's action runs, on the shutter, or on a tap outside.
struct QuickControlsTray: View {
    /// The items, in display order.
    let items: [QuickControlItem]

    /// Whether the items wrap into rows instead of scrolling.
    let wraps: Bool

    /// Closes the tray.
    let close: () -> Void

    /// Creates the tray.
    ///
    /// - Parameters:
    ///   - items: The items, in display order.
    ///   - wraps: Whether the items wrap into rows instead of scrolling.
    ///   - close: Closes the tray.
    init(items: [QuickControlItem], wraps: Bool = false, close: @escaping () -> Void) {
        self.items = items
        self.wraps = wraps
        self.close = close
    }

    /// The row, or the wrapped rows.
    var body: some View {
        Group {
            if wraps {
                WrappingRows(spacing: CameraStyle.targetSpacing) { buttons }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: CameraStyle.targetSpacing) { buttons }
                        .padding(.horizontal, CameraStyle.targetSpacing)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Quick Controls", bundle: .module, comment: "VoiceOver and Voice Control name of the button at the end of the lens row that opens a row of camera toggles, and of that row."))
    }

    /// One button per item.
    private var buttons: some View {
        ForEach(items) { item in
            QuickControlButton(item: item, close: close)
                .uprightUnit()
        }
    }
}

/// Lays its views out left to right (in reading order) in rows that wrap at the proposed width,
/// each row centered.
struct WrappingRows: Layout {
    /// The space between views and between rows.
    let spacing: CGFloat

    /// Creates the layout.
    ///
    /// - Parameter spacing: The space between views and between rows.
    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    /// The size of the rows at the proposed width.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size.
    ///   - subviews: The views.
    ///   - cache: Unused.
    /// - Returns: The rows' size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    /// Places the views row by row, each row centered in the bounds.
    ///
    /// - Parameters:
    ///   - bounds: Where to place the views.
    ///   - proposal: The proposed size.
    ///   - subviews: The views.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// One row: the indexes of its views, its width and its height.
    private struct Row {
        /// The indexes of the row's views.
        var indices: [Int] = []

        /// The row's width.
        var width: CGFloat = 0

        /// The row's height.
        var height: CGFloat = 0
    }

    /// Splits the views into rows no wider than the width (a view wider than it gets a row of
    /// its own).
    ///
    /// - Parameters:
    ///   - subviews: The views.
    ///   - width: The widest a row may be.
    /// - Returns: The rows.
    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty && needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// One tray item: its symbol above its name, filled white when on.
struct QuickControlButton: View {
    /// The item.
    let item: QuickControlItem

    /// Closes the tray after a button's action.
    let close: () -> Void

    /// Creates the item's control.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - close: Closes the tray after a button's action.
    init(item: QuickControlItem, close: @escaping () -> Void) {
        self.item = item
        self.close = close
    }

    /// The control.
    var body: some View {
        switch item.kind {
        case .button(let action):
            Button {
                action()
                close()
            } label: {
                label
            }
            .buttonStyle(SelectableCapsuleStyle(isSelected: false))
        case .toggle(let isOn, let set):
            Button {
                set(!isOn)
            } label: {
                label
            }
            .buttonStyle(SelectableCapsuleStyle(isSelected: isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
        case .menu(let options):
            Menu {
                Picker(selection: Binding(get: { options.first(where: \.isSelected)?.id ?? "" }, set: { id in
                    options.first(where: { $0.id == id })?.select()
                })) {
                    ForEach(options) { option in option.title.tag(option.id) }
                } label: {
                    item.title
                }
            } label: {
                label
            }
            .buttonStyle(SelectableCapsuleStyle(isSelected: item.isOn))
        }
    }

    /// The symbol and the name.
    private var label: some View {
        Label {
            item.title
        } icon: {
            Image(systemName: item.systemImage)
        }
        .font(.footnote)
        .accessibilityShowsLargeContentViewer()
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
