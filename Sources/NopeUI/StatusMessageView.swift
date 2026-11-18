import SwiftUI

/// A centered message with a symbol, a title, an explanation and optional actions
/// (docs/design/BUILD-SPEC.md, 3.8, figures `camera-denied` and `camera-unavailable`).
///
/// Used for the permission and no-camera states. It is built from plain `Text`, `Image` and
/// `Button` views rather than `ContentUnavailableView`, because that view's symbol keeps a fixed
/// size and fails the accessibility audit's Dynamic Type check. At large text sizes the content
/// scrolls instead of being clipped (AGENTS.md, "Larger Text"). The actions are pinned below it,
/// full width, in the primary style (``NopePrimaryActionStyle``), so the one action is always in
/// reach.
struct StatusMessageView<Actions: View>: View {
    /// The headline.
    let title: Text

    /// The SF Symbol shown above the title. It is decorative, so VoiceOver skips it.
    let systemImage: String

    /// The explanation below the title.
    let message: Text

    /// Buttons pinned below the message, if any.
    let actions: Actions

    /// Creates a message with actions.
    ///
    /// - Parameters:
    ///   - title: The headline.
    ///   - systemImage: The SF Symbol shown above the title.
    ///   - message: The explanation below the title.
    ///   - actions: Buttons pinned below the message, drawn in the primary style.
    init(title: Text, systemImage: String, message: Text, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    /// The message, centered when it fits and scrolling when it doesn't, with the actions below.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                stack.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if Actions.self != EmptyView.self {
                    VStack(spacing: NopeSpace.xs) {
                        actions
                    }
                    .buttonStyle(NopePrimaryActionStyle())
                    .frame(maxWidth: NopeSize.pictureStackMaxWidth)
                    .padding(.horizontal, NopeSpace.l)
                    .padding(.vertical, NopeSpace.s)
                    .frame(maxWidth: .infinity)
                    .background(.background)
                }
            }
        }
    }

    /// The symbol, title and explanation, stacked and centered.
    private var stack: some View {
        VStack(spacing: NopeSpace.m) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(CameraStyle.secondaryText)
                .accessibilityHidden(true)
            title
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            message
                .font(.body)
                .foregroundStyle(CameraStyle.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: NopeSize.pictureStackMaxWidth)
        .padding(NopeSpace.l)
        .frame(maxWidth: .infinity)
    }
}

extension StatusMessageView where Actions == EmptyView {
    /// Creates a message with no actions.
    ///
    /// - Parameters:
    ///   - title: The headline.
    ///   - systemImage: The SF Symbol shown above the title.
    ///   - message: The explanation below the title.
    init(title: Text, systemImage: String, message: Text) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// The one primary action of a screen before the camera is ready, such as Continue or Open
/// Settings (docs/design/tokens.md, "System"; BUILD-SPEC.md, 3.8): the system's
/// `.borderedProminent` button at the large size, full width, filled with the label color (white
/// on the dark appearance, black on the light one) with the background color for its words.
///
/// The system blue fill is not used: white words on it failed the accessibility audit's contrast
/// check in the dark appearance. Night mode's red multiply turns the white fill red and keeps the
/// black words.
struct NopePrimaryActionStyle: PrimitiveButtonStyle {
    /// Creates the style. It holds no state.
    init() {}

    /// The button, in the system's prominent style.
    ///
    /// - Parameter configuration: The button's label, role and action.
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color(uiColor: .label))
    }
}
