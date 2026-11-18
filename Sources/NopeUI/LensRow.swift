import NopeCore
import SwiftUI

/// One button per rear lens, such as 0.5×, 1× and 5×. The selected lens is filled white and
/// bold, and marked selected for VoiceOver; a lens without Bayer RAW says "No RAW", with the
/// reason as its hint (issue #1, "Lenses"). It stays selectable, because its labeled fallback is
/// still a photo. The front camera has its own button (``CameraFlipButton``).
///
/// The buttons sit in one capsule group with ``NopeColor/controlFill``, the selected lens filled
/// white (docs/design/BUILD-SPEC.md, 3.1): side by side in the lens row, one above the other in
/// the column layout. Each lens's 36-point capsule sits in its 44-point target, so neighbors'
/// capsules are at least ``NopeSpace/xxs`` apart inside the group.
struct LensButtons: View {
    /// The lenses, in display order.
    let lenses: [Lens]

    /// The selected lens's identifier.
    let selectedID: Lens.ID?

    /// Whether the buttons are stacked in a column.
    let isVertical: Bool

    /// Called with a lens's identifier when it is pressed.
    let select: (Lens.ID) -> Void

    /// Creates the lens buttons.
    ///
    /// - Parameters:
    ///   - lenses: The lenses, in display order.
    ///   - selectedID: The selected lens's identifier.
    ///   - isVertical: Whether the buttons are stacked in a column.
    ///   - select: Called with a lens's identifier when it is pressed.
    init(lenses: [Lens], selectedID: Lens.ID?, isVertical: Bool = false, select: @escaping (Lens.ID) -> Void) {
        self.lenses = lenses
        self.selectedID = selectedID
        self.isVertical = isVertical
        self.select = select
    }

    /// The buttons.
    var body: some View {
        Group {
            if isVertical {
                VStack(spacing: 0) { buttons }
                    .padding(.horizontal, NopeSpace.xxs)
            } else {
                HStack(spacing: NopeSpace.xxs) { buttons }
                    .padding(.horizontal, NopeSpace.xxs)
            }
        }
        // Each lens is 36 points high in its 44-point target, so the group is 44 points across
        // with the selected lens inset 4 points (docs/design/tokens.md, "lensItem").
        .background(groupFill, in: Capsule())
        .overlay {
            if isNightMode || contrast == .increased {
                Capsule().strokeBorder(isNightMode ? NopeColor.nightOutlineUnderMultiply : NopeColor.labelSecondary, lineWidth: NopeSize.outline)
            }
        }
        .sensoryFeedback(NopeHaptic.lensChanged, trigger: selectedID)
    }

    /// Whether night mode is on: the group is outlined instead of filled.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on: the group gets an outline.
    @Environment(\.colorSchemeContrast) private var contrast

    /// The group's fill: the control fill, or near black in night mode.
    private var groupFill: Color {
        isNightMode ? NopeColor.controlFillNight : NopeColor.controlFill
    }

    /// One button per lens.
    private var buttons: some View {
        ForEach(lenses) { lens in
            LensButton(lens: lens, isSelected: lens.id == selectedID) { select(lens.id) }
                .uprightUnit()
        }
    }

    /// The rear lenses, in display order: every lens except the front camera.
    ///
    /// - Parameter lenses: All lenses.
    static func rear(_ lenses: [Lens]) -> [Lens] {
        lenses.filter { $0.kind != .front }
    }
}

/// One lens button: its magnification (or name), and "No RAW" when it has no Bayer RAW. While the
/// lens can't be changed (``LensBusyState``), it is disabled unless it is the lens in use.
struct LensButton: View {
    /// The lens.
    let lens: Lens

    /// Whether the lens is in use.
    let isSelected: Bool

    /// Called when the button is pressed.
    let action: () -> Void

    /// Creates a lens button.
    ///
    /// - Parameters:
    ///   - lens: The lens.
    ///   - isSelected: Whether the lens is in use.
    ///   - action: Called when the button is pressed.
    init(lens: Lens, isSelected: Bool, action: @escaping () -> Void) {
        self.lens = lens
        self.isSelected = isSelected
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                title
                    .font(NopeFont.lens)
                if !lens.supportsBayerRAW {
                    Text("No RAW", tableName: "Honesty", bundle: .module, comment: "Under a lens button: this lens can't save RAW. RAW is a file format name.")
                        .font(NopeFont.readoutMode)
                }
            }
            // At least 40 points wide with 4 points each side (docs/design/tokens.md,
            // "lensItem"; the design's lenses). With the compact capsule's 12 points each side
            // "0.5×" was 53 points wide; turned upright while the iPhone is sideways, that width
            // became the lens group's height, past the 44-point row, and the group touched the
            // picture's lower edge.
            .frame(minWidth: NopeSize.lensItemMinWidth - 2 * NopeSpace.xxs)
        }
        .buttonStyle(
            NopeCapsuleStyle(
                isSelected: isSelected, size: NopeSize.lensItem, isCompact: true, idleFill: .none, labelPadding: NopeSpace.xxs))
        .accessibilityLabel(Text(verbatim: LensName.string(for: lens.kind)))
        .accessibilityValue(title)
        // Disabled while the lens can't be changed, unless it is the lens in use (issue #96).
        .lensBusyControl(isSelected: isSelected, hint: lens.supportsBayerRAW ? nil : Self.noRAWHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityInputLabels([title, Text(verbatim: LensName.string(for: lens.kind))])
        .accessibilityShowsLargeContentViewer()
    }

    /// The visible title: "0.5×", "1×", "5×", or the lens's name.
    ///
    /// The number uses the person's locale (`FormatStyle`); the multiplication sign is a symbol
    /// used the same way in every launch language, so it isn't in the string catalog.
    private var title: Text {
        if let magnification = lens.magnification {
            Text(verbatim: magnification.formatted(.number.precision(.fractionLength(0...1))) + "×")
        } else {
            Text(verbatim: LensName.string(for: lens.kind))
        }
    }

    /// Why a lens says "No RAW".
    static var noRAWHint: Text {
        Text(
            "This lens can't save unprocessed RAW. Its photos have some device processing.",
            tableName: "Honesty", bundle: .module,
            comment: "Explains the no-RAW fallback. Must not claim more than the English: the photo IS processed by the device.")
    }
}

/// Switches between the front camera and the rear lens last used, as its own round button at the
/// trailing end of the lens row (the bottom of the column layout), rather than a lens button
/// (issue #68; docs/design/BUILD-SPEC.md, 3.1). Disabled while the lens can't be changed
/// (``LensBusyState``).
struct CameraFlipButton: View {
    /// Switches the camera.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Switches the camera.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                Text("Switch Camera", bundle: .module, comment: "VoiceOver and Voice Control name of the button that switches between the front and rear cameras.")
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
            }
            .labelStyle(.iconOnly)
            .font(.title3)
        }
        .buttonStyle(NopeIconButtonStyle())
        // Disabled while the lens can't be changed (issue #96).
        .lensBusyControl()
    }
}

/// Q, beside the shutter: opens and closes the quick menu (docs/design/BUILD-SPEC.md, 3.6). It is
/// filled white while the menu is open. Its name, "Quick Menu", is what VoiceOver reads and what
/// Voice Control users say; the Large Content Viewer shows it.
struct QuickButton: View {
    /// Whether the quick menu is open.
    let isOpen: Bool

    /// The diameter: ``NopeSize/quick``, or ``NopeSize/scrollingRowButton`` in the scrolling
    /// layout.
    let size: CGFloat

    /// Opens or closes the quick menu.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isOpen: Whether the quick menu is open.
    ///   - size: The diameter, in points.
    ///   - action: Opens or closes the quick menu.
    init(isOpen: Bool, size: CGFloat = NopeSize.quick, action: @escaping () -> Void) {
        self.isOpen = isOpen
        self.size = size
        self.action = action
    }

    /// "Quick Menu".
    static var name: Text {
        QuickControlsText.title
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            // "Q" is the button's mark, the same in every launch language, as the shutter's ring
            // is; its name is localized.
            Text(verbatim: "Q")
                .font(NopeFont.q)
        }
        .buttonStyle(NopeIconButtonStyle(size: size, isSelected: isOpen))
        .accessibilityLabel(Self.name)
        // Voice Control: the name, then the letter the button shows (docs/design/ACCESSIBILITY.md).
        .accessibilityInputLabels([Self.name, Text(verbatim: "Q")])
        .accessibilityIdentifier("quickMenuButton")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label { Self.name } icon: { Image(systemName: "square.grid.3x3") }
        }
        .uprightUnit()
    }
}

/// One full-width row per lens, the front camera included, for the scrolling layout at
/// accessibility text sizes (docs/design/BUILD-SPEC.md, 3.12): the lens's name over its
/// magnification, the selected lens filled white. A lens without RAW says "No RAW". While the
/// lens can't be changed (``LensBusyState``), every row but the lens in use is disabled.
struct LensRows: View {
    /// The lenses, in display order.
    let lenses: [Lens]

    /// The selected lens's identifier.
    let selectedID: Lens.ID?

    /// Called with a lens's identifier when it is pressed.
    let select: (Lens.ID) -> Void

    /// Creates the rows.
    ///
    /// - Parameters:
    ///   - lenses: The lenses, in display order.
    ///   - selectedID: The selected lens's identifier.
    ///   - select: Called with a lens's identifier when it is pressed.
    init(lenses: [Lens], selectedID: Lens.ID?, select: @escaping (Lens.ID) -> Void) {
        self.lenses = lenses
        self.selectedID = selectedID
        self.select = select
    }

    /// The rows.
    var body: some View {
        // 12 points apart, as every row of the scrolling layout (docs/design/screens/ax-camera).
        VStack(spacing: NopeSpace.s) {
            ForEach(lenses) { lens in
                let isSelected = lens.id == selectedID
                Button {
                    select(lens.id)
                } label: {
                    CameraRowLabel(name: Text(verbatim: LensName.string(for: lens.kind)), value: value(of: lens), detail: detail(of: lens))
                }
                .buttonStyle(NopeTileStyle(isOn: isSelected, minHeight: NopeSize.scrollingRowButton))
                // Named as the lens buttons are: the lens's name, with the magnification as the
                // value and the reason for "No RAW" as the hint. Disabled while the lens can't be
                // changed, unless it is the lens in use; no row is added or removed (issue #96).
                .accessibilityLabel(Text(verbatim: LensName.string(for: lens.kind)))
                .accessibilityValue(value(of: lens) ?? Text(verbatim: ""))
                .lensBusyControl(isSelected: isSelected, hint: detail(of: lens) == nil ? nil : LensButton.noRAWHint)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityInputLabels([Text(verbatim: LensName.string(for: lens.kind))])
            }
        }
        .sensoryFeedback(NopeHaptic.lensChanged, trigger: selectedID)
    }

    /// "1×", or nothing for a lens without a magnification.
    ///
    /// - Parameter lens: The lens.
    private func value(of lens: Lens) -> Text? {
        lens.magnification.map { Text(verbatim: $0.formatted(.number.precision(.fractionLength(0...1))) + "×") }
    }

    /// "No RAW" under a lens that can't save RAW, or nothing.
    ///
    /// - Parameter lens: The lens.
    private func detail(of lens: Lens) -> Text? {
        lens.supportsBayerRAW
            ? nil
            : Text("No RAW", tableName: "Honesty", bundle: .module, comment: "Under a lens button: this lens can't save RAW. RAW is a file format name.")
    }
}

/// The localized names of the kinds of lens.
enum LensName {
    /// The name of a kind of lens, such as "Wide".
    ///
    /// - Parameter kind: The kind of lens.
    /// - Returns: The localized name.
    static func string(for kind: Lens.Kind) -> String {
        switch kind {
        case .ultraWide:
            String(localized: "Ultra Wide", bundle: .module, comment: "Name of the rear ultra wide camera lens.")
        case .wide:
            String(localized: "Wide", bundle: .module, comment: "Name of the rear wide (main) camera lens.")
        case .telephoto:
            String(localized: "Telephoto", bundle: .module, comment: "Name of a rear telephoto camera lens.")
        case .front:
            String(localized: "Front", bundle: .module, comment: "Name of the front (selfie) camera.")
        }
    }
}
