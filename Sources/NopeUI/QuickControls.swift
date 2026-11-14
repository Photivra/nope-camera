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
        hideControls,
    ]

    /// The tray's items for the current state, in display order.
    ///
    /// - Parameter context: The model and settings.
    static func current(_ context: CameraControlContext) -> [QuickControlItem] {
        builders.compactMap { $0(context) }
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
/// is open. It closes when an item's action runs, on the shutter, or on a tap outside.
struct QuickControlsTray: View {
    /// The items, in display order.
    let items: [QuickControlItem]

    /// Closes the tray.
    let close: () -> Void

    /// Creates the tray.
    ///
    /// - Parameters:
    ///   - items: The items, in display order.
    ///   - close: Closes the tray.
    init(items: [QuickControlItem], close: @escaping () -> Void) {
        self.items = items
        self.close = close
    }

    /// The row.
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CameraStyle.targetSpacing) {
                ForEach(items) { item in
                    QuickControlButton(item: item, close: close)
                        .uprightUnit()
                }
            }
            .padding(.horizontal, CameraStyle.targetSpacing)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Quick Controls", bundle: .module, comment: "VoiceOver and Voice Control name of the button at the end of the lens row that opens a row of camera toggles, and of that row."))
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
