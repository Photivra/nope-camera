import SwiftUI

/// What nope. does for taking photos without looking at the screen: the hardware shutter
/// buttons, haptics and spoken feedback (issue #68, "Settings").
///
/// It lists only what is built; none of these have a switch yet, so the screen shows facts and
/// no control that does nothing. Settings for them (issue #37) add rows here.
struct AccessibilitySettingsView: View {
    /// Creates the screen.
    init() {}

    /// The list.
    var body: some View {
        Form {
            Section {
                row(
                    systemImage: "button.vertical.left.press",
                    Text(
                        "The volume buttons, and the Camera Control on iPhones that have one, take a photo.", bundle: .module,
                        comment: "Accessibility screen: hardware buttons work as the shutter. Camera Control is Apple's name for the camera button on recent iPhones."))
                row(
                    systemImage: "keyboard",
                    Text(
                        "With a hardware keyboard, the Space bar takes a photo.", bundle: .module,
                        comment: "Accessibility screen: a connected keyboard's Space bar works as the shutter."))
            } header: {
                Text("Taking Photos", bundle: .module, comment: "Accessibility screen section header: the ways to take a photo besides the on-screen shutter.")
            }
            Section {
                row(
                    systemImage: "hand.tap",
                    Text(
                        "On iPhone, a tap you can feel confirms each press of the shutter and each saved photo.", bundle: .module,
                        comment: "Accessibility screen: haptic feedback. iPhone is a product name; keep it unchanged."))
                row(
                    systemImage: "speaker.wave.2",
                    Text(
                        "VoiceOver says when each photo is saved and signed, or what went wrong.", bundle: .module,
                        comment: "Accessibility screen: spoken feedback. VoiceOver is Apple's screen reader; keep the name unchanged."))
            } header: {
                Text("Feedback", bundle: .module, comment: "Accessibility screen section header: haptics and spoken feedback.")
            }
        }
        .navigationTitle(Self.title)
    }

    /// The row and screen title, "Accessibility".
    static var title: Text {
        Text("Accessibility", bundle: .module, comment: "Settings row and screen title: taking photos without looking at the screen (hardware buttons, haptics, spoken feedback).")
    }

    /// One fact with its symbol.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol, decorative.
    ///   - text: The fact.
    private func row(systemImage: String, _ text: Text) -> some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
    }
}
