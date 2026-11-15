import SwiftUI

/// The first screen before camera access is asked (issue #68, "First run"): the app's name, three
/// statements about what it does, and Continue, which shows the system camera prompt in context.
/// A note says Photos access is asked the first time a photo is saved.
///
/// The statements are honesty claims, so they live in `Honesty.xcstrings`. At large text sizes
/// the screen scrolls, with Continue at the end, so nothing is clipped.
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
                VStack(alignment: .leading, spacing: 24) {
                    // The app's name as a heading in the system font: interface text, not the
                    // wordmark (AGENTS.md, "Name and wordmark").
                    Text(verbatim: "nope.")
                        .font(.largeTitle.bold())
                        // Without the period for VoiceOver: the audit flags "nope." as not
                        // human-readable; the name is read the same way.
                        .accessibilityLabel(Text(verbatim: "nope"))
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 20) {
                        statement(
                            systemImage: "camera.aperture",
                            Text(
                                "Photos with as little processing as this phone allows.", tableName: "Honesty", bundle: .module,
                                comment: "First-run statement 1 of 3. Must not claim more than the English: as little processing as the phone allows, never zero."))
                        statement(
                            systemImage: "checkmark.seal",
                            Text(
                                "Each photo is signed, so changes can be detected.", tableName: "Honesty", bundle: .module,
                                comment: "First-run statement 2 of 3: photos get a Content Credentials signature (on by default). Must not claim more than the English: the signature shows changes, it doesn't prove who took the photo."))
                        statement(
                            systemImage: "wifi.slash",
                            Text(
                                "nope. never connects to the internet and keeps nothing about you.", tableName: "Honesty", bundle: .module,
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
                .padding(24)
                .frame(maxWidth: 560, minHeight: proxy.size.height, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Continue stays pinned below the scrolling text, so it is always in reach.
            .safeAreaInset(edge: .bottom) {
                Button(action: requestAccess) {
                    Text("Continue", bundle: .module, comment: "Button on the first-run screen: goes on to the system camera access prompt.")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                // The bordered style, not the prominent one: white text on the system blue fill
                // fails the accessibility audit's contrast check in dark mode.
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: 512)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.background)
            }
        }
    }

    /// One statement with its symbol.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol, decorative.
    ///   - text: The statement.
    private func statement(systemImage: String, _ text: Text) -> some View {
        Label {
            text
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(.title3)
                .accessibilityHidden(true)
        }
    }
}
