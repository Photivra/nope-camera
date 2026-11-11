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

    /// Creates the lens buttons.
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

    /// The buttons in a row that wraps onto more rows when the text is large.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
            VStack(spacing: 8) { buttons }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    /// One button per lens.
    private var buttons: some View {
        ForEach(lenses) { lens in
            LensButton(lens: lens, isSelected: lens.id == selectedID) { select(lens.id) }
        }
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
