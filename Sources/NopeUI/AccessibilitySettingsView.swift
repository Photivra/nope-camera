import SwiftUI

/// What the app does for taking photos without looking at the screen: the hardware shutter
/// buttons, haptics and spoken feedback (issue #68, "Settings").
///
/// It lists only what is built; none of these have a switch yet, so the screen shows facts and
/// no control that does nothing. Settings for them (issue #37) add rows here. The Night Mode
/// entry says how to dim the screen, which nope. never does itself.
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
                    systemImage: "timer",
                    Text(
                        "Timer, above the shutter, sets a self-timer of 3 or 10 seconds. Burst is beside it: hold the shutter for a burst, or use Start Burst so nothing has to be held. VoiceOver says each second of the countdown.", bundle: .module,
                        comment: "Accessibility screen: the self-timer and burst. Timer and Burst are the words of the drive strip above the shutter; use their translations. A burst is a rapid run of separate photos. VoiceOver is Apple's screen reader; keep the name unchanged."))
            } header: {
                Text("Self-Timer and Burst", bundle: .module, comment: "Accessibility screen section header: the self-timer and burst modes of the shutter.")
            }
            Section {
                row(
                    systemImage: "hand.tap",
                    Text(
                        "On iPhone, a tap you can feel confirms each press of the shutter and each saved photo, and marks the moment the level is level.", bundle: .module,
                        comment: "Accessibility screen: haptic feedback. iPhone is a product name; keep it unchanged."))
                row(
                    systemImage: "speaker.wave.2",
                    Text(
                        "VoiceOver says when each photo is saved and signed, or what went wrong.", bundle: .module,
                        comment: "Accessibility screen: spoken feedback. VoiceOver is Apple's screen reader; keep the name unchanged."))
            } header: {
                Text("Feedback", bundle: .module, comment: "Accessibility screen section header: haptics and spoken feedback.")
            }
            Section {
                row(
                    systemImage: "sun.min",
                    Text(
                        "nope. doesn't change the screen's brightness. Dim it in Control Center, or with Reduce White Point in the Accessibility settings.",
                        bundle: .module,
                        comment: "Accessibility screen, Night Mode: how to dim the screen. Keep \"nope.\" unchanged. Control Center and Reduce White Point are names of iOS features: use their names in the language's iOS."))
            } header: {
                Text(SettingsText.nightMode)
            }
        }
        .navigationTitle(Self.title)
    }

    /// The row and screen title, "Accessibility".
    static var title: Text {
        Text(SettingsText.accessibility)
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
