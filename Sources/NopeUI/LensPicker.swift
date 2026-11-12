import NopeCore
import SwiftUI

/// One button per lens. The selected lens is bold and marked selected for VoiceOver; a lens
/// without Bayer RAW is gray and says "No RAW", with the reason as its hint (issue #1,
/// "Lenses"). It stays selectable, because its labeled fallback is still a photo.
struct LensPicker: View {
    /// The lenses, in display order.
    let lenses: [Lens]

    /// The selected lens's identifier.
    let selectedID: Lens.ID?

    /// Called with a lens's identifier when it is pressed.
    let select: (Lens.ID) -> Void

    /// A fixed number of buttons per row, as in the landscape controls column, or `nil` to
    /// choose by fit.
    let perRow: Int?

    /// Creates the lens buttons.
    ///
    /// - Parameters:
    ///   - lenses: The lenses, in display order.
    ///   - selectedID: The selected lens's identifier.
    ///   - perRow: A fixed number of buttons per row at every text size, or `nil` for one row
    ///     that becomes one column when the text is too large to fit.
    ///   - select: Called with a lens's identifier when it is pressed.
    init(lenses: [Lens], selectedID: Lens.ID?, perRow: Int? = nil, select: @escaping (Lens.ID) -> Void) {
        self.lenses = lenses
        self.selectedID = selectedID
        self.perRow = perRow
        self.select = select
    }

    /// The buttons in rows of ``perRow``, or in a row that becomes a column when the text is
    /// large.
    ///
    /// The landscape column keeps the same rows at every text size: a layout that changes with
    /// the text size replaces the buttons, and the accessibility audit then reports their text
    /// as not following Dynamic Type.
    var body: some View {
        Group {
            if let perRow {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(CameraLayout.rows(of: lenses, perRow: perRow).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row) { lens in button(for: lens) }
                        }
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { buttons }
                    VStack(spacing: 8) { buttons }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    /// One button per lens.
    private var buttons: some View {
        ForEach(lenses) { lens in button(for: lens) }
    }

    /// The button for one lens.
    ///
    /// - Parameter lens: The lens.
    private func button(for lens: Lens) -> some View {
        LensButton(lens: lens, isSelected: lens.id == selectedID) { select(lens.id) }
    }
}

/// One lens button: its magnification (or "Front"), and "No RAW" when it has no Bayer RAW.
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
            VStack(spacing: 2) {
                title
                    .fontWeight(isSelected ? .bold : .regular)
                if !lens.supportsBayerRAW {
                    Text("No RAW", tableName: "Honesty", bundle: .module, comment: "Under a lens button: this lens can't save RAW. RAW is a file format name.")
                        .font(.caption2)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        // Unselected lenses use the secondary color: the gray of a lens without RAW comes from
        // that and its "No RAW" text. No extra dimming, which fails the contrast audit.
        .tint(isSelected ? .primary : .secondary)
        .accessibilityLabel(Text(verbatim: LensName.string(for: lens.kind)))
        .accessibilityValue(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityInputLabels([title, Text(verbatim: LensName.string(for: lens.kind))])
    }

    /// The visible title: "0.5×", "1×", "5×", or "Front".
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

    /// The reason a lens without RAW is dimmed, or nothing.
    private var hint: Text {
        lens.supportsBayerRAW
            ? Text(verbatim: "")
            : Text(
                "This lens can't save unprocessed RAW. Its photos have some device processing.",
                tableName: "Honesty", bundle: .module,
                comment: "Explains the no-RAW fallback. Must not claim more than the English: the photo IS processed by the device.")
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
