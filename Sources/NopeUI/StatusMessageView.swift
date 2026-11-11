import SwiftUI

/// A centered message with a symbol, a title, an explanation and optional actions.
///
/// Used for the permission and no-camera states. It is built from plain `Text`, `Image` and
/// `Button` views rather than `ContentUnavailableView`, because that view's symbol keeps a fixed
/// size and fails the accessibility audit's Dynamic Type check. At large text sizes the content
/// scrolls instead of being clipped (AGENTS.md, "Larger Text").
struct StatusMessageView<Actions: View>: View {
    /// The headline.
    let title: Text

    /// The SF Symbol shown above the title. It is decorative, so VoiceOver skips it.
    let systemImage: String

    /// The explanation below the title.
    let message: Text

    /// Buttons below the explanation, if any.
    let actions: Actions

    /// Creates a message with actions.
    ///
    /// - Parameters:
    ///   - title: The headline.
    ///   - systemImage: The SF Symbol shown above the title.
    ///   - message: The explanation below the title.
    ///   - actions: Buttons below the explanation.
    init(title: Text, systemImage: String, message: Text, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    /// The message, centered when it fits and scrolling when it doesn't.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                stack.frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// The symbol, title, explanation and actions, stacked and centered.
    private var stack: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            title
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            message
                .font(.body)
                .foregroundStyle(.secondary)
            actions
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding()
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
