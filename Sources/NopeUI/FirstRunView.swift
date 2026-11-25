import SwiftUI

/// The first screen before camera access is asked (issue #68, "First run"; docs/design/BUILD-SPEC.md,
/// 3.8, figures `first-run` and `first-run-light`): the app's name, three statements about what it
/// does, and Continue, which shows the system camera prompt in context. A note says Photos access
/// is asked the first time a photo is saved. It follows the system's light or dark appearance.
///
/// The statements are honesty claims, so they live in `Honesty.xcstrings`; the second says that
/// signing is the person's choice and off until they turn it on (issue #80). At large text sizes
/// the text scrolls and Continue stays pinned below it, full width, so nothing is clipped.
struct FirstRunView: View {
    /// Asks for camera access.
    let requestAccess: () -> Void

    /// Creates the first-run screen.
    ///
    /// - Parameter requestAccess: Asks for camera access; called by Continue.
    init(requestAccess: @escaping () -> Void) {
        self.requestAccess = requestAccess
    }

    /// The name, the statements and Continue.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NopeSpace.xxl) {
                    // The app's name as a heading in the system font: interface text, not the
                    // wordmark (AGENTS.md, "Name and wordmark").
                    Text(verbatim: "nope.")
                        .font(.largeTitle.bold())
                        // Without the period for VoiceOver: the audit flags "nope." as not
                        // human-readable; the name is read the same way.
                        .accessibilityLabel(Text(verbatim: "nope"))
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: NopeSpace.l) {
                        statement(
                            Text(
                                "Photos with as little processing as this phone allows.", tableName: "Honesty", bundle: .module,
                                comment: "First-run statement 1 of 3. Must not claim more than the English: as little processing as the phone allows, never zero."))
                        statement(
                            Text(
                                "You can sign each photo, so changes can be detected. Signing is off until you turn it on.",
                                tableName: "Honesty", bundle: .module,
                                comment: "First-run statement 2 of 3: signing is the person's choice and off by default. Must not claim more than the English. Draft wording for the Honesty review (docs/design/BUILD-SPEC.md, section 5). Honesty wording: a fluent human must review every translation before release."))
                        statement(
                            Text(
                                "nope. never connects to the internet and collects nothing about you.", tableName: "Honesty", bundle: .module,
                                comment: "First-run statement 3 of 3. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English."))
                    }
                    Text(
                        "Next, iOS asks for camera access. Photos access is asked the first time you save.", bundle: .module,
                        comment: "Note under Continue on the first-run screen. iOS is a product name; keep it unchanged.")
                        .font(.footnote)
                        .foregroundStyle(CameraStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(NopeSpace.l)
                .frame(maxWidth: NopeSize.pictureStackMaxWidth + 2 * NopeSpace.l, minHeight: proxy.size.height, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Continue stays pinned below the scrolling text, so it is always in reach.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: requestAccess) {
                    Text("Continue", bundle: .module, comment: "Button on the first-run screen: goes on to the system camera access prompt.")
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

    /// One statement, with no symbol, as in the design.
    ///
    /// - Parameter text: The statement.
    private func statement(_ text: Text) -> some View {
        text
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}
