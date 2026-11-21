import NopeCore
import SwiftUI

/// The invitation to the how-to-use guide on the camera (issue #117; `docs/design/finish-1.0.md`,
/// 2.1; figures `guide-invite` and `guide-invite-night`): "How to use nope.", a capsule Open and
/// a round Dismiss with an ✕, both 44-point targets.
///
/// It sits on the picture's lower edge, in the stack of the drive cards and hints, with their
/// backing and radius, so it covers no control and never stands between the person and the
/// shutter. When it shows is `GuideInvitation.showsCard(_:)`. Open and Dismiss are both final.
/// VoiceOver reads it as one group after the picture's own elements, and it doesn't take focus
/// when it appears. When the name and buttons don't fit on one line (the largest text sizes, long
/// languages), the buttons move under the name.
struct GuideCard: View {
    /// Opens the guide.
    let open: () -> Void

    /// Hides the card for good.
    let dismiss: () -> Void

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - open: Opens the guide (and answers the invitation).
    ///   - dismiss: Hides the card for good.
    init(open: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.open = open
        self.dismiss = dismiss
    }

    /// The card.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NopeSpace.s) {
                title
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                openButton
                dismissButton
            }
            VStack(alignment: .leading, spacing: NopeSpace.xs) {
                title
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: NopeSpace.s) {
                    openButton
                    Spacer(minLength: 0)
                    dismissButton
                }
            }
        }
        .padding(.leading, NopeSpace.m)
        .padding(.trailing, NopeSpace.xs)
        .padding(.vertical, NopeSpace.xs)
        .frame(minHeight: NopeSize.capsule + 2 * NopeSpace.xs)
        .modifier(ModeCardBackground())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("GuideCard")
    }

    /// "How to use nope.".
    private var title: some View {
        Text(GuideText.cardTitle)
            .font(NopeFont.status)
            .foregroundStyle(NopeColor.label)
    }

    /// Open, a capsule.
    private var openButton: some View {
        Button(action: open) {
            Text(GuideText.open)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
        .accessibilityHint(Text(GuideText.opensGuide))
        .accessibilityIdentifier("guideCard.open")
    }

    /// Dismiss, a round ✕.
    private var dismissButton: some View {
        Button(action: dismiss) {
            Label {
                Text(GuideText.dismiss)
            } icon: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(NopeIconButtonStyle(idleFill: .tile))
        .accessibilityHint(Text(GuideText.hidesCard))
        .accessibilityIdentifier("guideCard.dismiss")
        .accessibilityShowsLargeContentViewer {
            Label { Text(GuideText.dismiss) } icon: { Image(systemName: "xmark") }
        }
    }
}
