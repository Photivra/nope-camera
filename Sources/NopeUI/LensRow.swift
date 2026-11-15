import NopeCore
import SwiftUI

/// One button per rear lens, such as 0.5×, 1× and 5×. The selected lens is filled white and
/// bold, and marked selected for VoiceOver; a lens without Bayer RAW says "No RAW", with the
/// reason as its hint (issue #1, "Lenses"). It stays selectable, because its labeled fallback is
/// still a photo. The front camera has its own button (``CameraFlipButton``).
///
/// In a row the buttons sit side by side and wrap into a column when the text is too large; in
/// the iPad's control column they are one column.
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
                VStack(spacing: CameraStyle.targetSpacing) { buttons }
            } else {
                HStack(spacing: CameraStyle.targetSpacing) { buttons }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
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

/// One lens button: its magnification (or name), and "No RAW" when it has no Bayer RAW.
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
                    .font(.subheadline.monospacedDigit())
                if !lens.supportsBayerRAW {
                    Text("No RAW", tableName: "Honesty", bundle: .module, comment: "Under a lens button: this lens can't save RAW. RAW is a file format name.")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(SelectableCapsuleStyle(isSelected: isSelected))
        .accessibilityLabel(Text(verbatim: LensName.string(for: lens.kind)))
        .accessibilityValue(title)
        .accessibilityHint(hint)
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

    /// The reason a lens without RAW says "No RAW", or nothing.
    private var hint: Text {
        lens.supportsBayerRAW
            ? Text(verbatim: "")
            : Text(
                "This lens can't save unprocessed RAW. Its photos have some device processing.",
                tableName: "Honesty", bundle: .module,
                comment: "Explains the no-RAW fallback. Must not claim more than the English: the photo IS processed by the device.")
    }
}

/// Switches between the front camera and the rear lens last used, as its own button beside the
/// shutter rather than a lens button (issue #68).
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
            .foregroundStyle(.white)
            .padding(8)
            .frame(minWidth: ThumbnailSlot.side, minHeight: ThumbnailSlot.side)
            .background(Color(white: 0.2), in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityShowsLargeContentViewer()
    }
}

/// The ⋯ button at the end of the lens row: opens and closes the quick-controls tray.
struct QuickControlsButton: View {
    /// Whether the tray is open.
    let isOpen: Bool

    /// Opens or closes the tray.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isOpen: Whether the tray is open.
    ///   - action: Opens or closes the tray.
    init(isOpen: Bool, action: @escaping () -> Void) {
        self.isOpen = isOpen
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                Text("Quick Controls", bundle: .module, comment: "VoiceOver and Voice Control name of the button at the end of the lens row that opens a row of camera toggles, and of that row.")
            } icon: {
                Image(systemName: isOpen ? "xmark" : "ellipsis")
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(SelectableCapsuleStyle(isSelected: isOpen))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
        .uprightUnit()
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
