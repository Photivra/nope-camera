import SwiftUI

/// What the app does for taking photos without looking at the screen: the hardware shutter
/// buttons, haptics and spoken feedback (issue #68, "Settings").
///
/// It lists only what is built; none of these have a switch yet, so the screen shows facts and
/// no control that does nothing. Settings for them (issue #37) add rows here. The Night Mode
/// entries say how to dim the screen, which Night Mode never does itself, and that the system
/// keyboard and menus aren't red.
struct AccessibilitySettingsView: View {
    /// Whether the device has two or more rear lenses, so the screen says that pinching to
    /// switch lenses is optional (docs/design/pinch-lens.md, 7.2).
    let offersPinch: Bool

    /// Creates the screen.
    ///
    /// - Parameter offersPinch: Whether a pinch can switch lenses on this device.
    init(offersPinch: Bool = false) {
        self.offersPinch = offersPinch
    }

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
                if offersPinch {
                    row(
                        systemImage: "hand.pinch",
                        Text(
                            "Pinching to switch lenses is optional. The lens buttons do the same.", bundle: .module,
                            comment: "Accessibility screen: the pinch on the camera picture that switches rear lenses is never the only way; the lens buttons do the same."))
                    // Named for the UI tests' one approved audit exception (docs/TESTING.md).
                    .accessibilityIdentifier("settings.accessibility.pinchOptional")
                }
            } header: {
                Text("Taking Photos", bundle: .module, comment: "Accessibility screen section header: the ways to take a photo besides the on-screen shutter.")
            }
            Section {
                row(
                    systemImage: "mic",
                    Text(
                        "“Take a photo with nope.” works after you turn on Assistant Access in Settings › Privacy. nope. then asks before each action; Only Before a Photo or Never asks less. VoiceOver, Voice Control, Switch Control, the volume buttons and Camera Control always work.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Accessibility screen: Siri and Shortcuts need Assistant Access (issue #82; docs/design/assistant-access.md, text 26). \"Take a photo with nope.\" is the Siri phrase; use its translation. Assistant Access, Settings, Privacy, Only Before a Photo and Never are names in nope.'s Settings. VoiceOver, Voice Control, Switch Control and Camera Control are Apple's names. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English."))
            } header: {
                Text("Siri and Shortcuts", bundle: .module, comment: "Accessibility screen section header: taking photos with Siri and the Shortcuts app. Siri and Shortcuts are Apple's names.")
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
                    systemImage: "viewfinder",
                    Text(
                        "Tap the picture to focus there. Lock appears under the focus square for a few seconds. Touch and hold the picture to lock right away.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Accessibility screen: the focus square and Lock fade a few seconds after a tap (docs/design/device-feedback-1.0.md, section 5). Lock is the button under the focus square; use its translation. \"A few seconds\" stays true from 2 to 5 seconds. Draft for the Honesty review. Must not claim more than the English."))
                row(
                    systemImage: "lock",
                    Text(
                        "With VoiceOver or Switch Control on, the focus square and Lock stay until the scene changes. VoiceOver also has the action Lock Focus and Exposure on the viewfinder.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Accessibility screen: with VoiceOver or Switch Control on, the focus square and Lock don't fade (docs/design/device-feedback-1.0.md, section 5). VoiceOver and Switch Control are Apple's names; Lock and Lock Focus and Exposure are nope.'s names; use their translations. Draft for the Honesty review. Must not claim more than the English."))
            } header: {
                Text("Focus and Exposure Lock", tableName: "Honesty", bundle: .module, comment: "Accessibility screen section header: tapping the picture to focus, and locking focus and exposure. Draft for the Honesty review.")
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
                        "Night Mode doesn't change the screen's brightness. Dim it in Control Center, or with Reduce White Point in the Accessibility settings.",
                        bundle: .module,
                        comment: "Accessibility screen, Night Mode: how to dim the screen. Night Mode is the name of nope.'s switch; use its translation. Control Center and Reduce White Point are names of iOS features: use their names in the language's iOS. Draft wording for the Honesty review."))
                row(
                    systemImage: "keyboard",
                    Text(
                        "The keyboard and menus are drawn by iOS and are not red.", bundle: .module,
                        comment: "Accessibility screen, Night Mode: the system keyboard, which opens for search, and system menus keep the dark appearance; nope. can't draw them in red. Draft wording for the Honesty review."))
                row(
                    systemImage: "mic",
                    Text(
                        "Siri, the Shortcuts app and the question asked before an action are drawn by iOS, so they aren’t red. Only Before a Photo or Never in Assistant Access asks less often, or use the shutter.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Accessibility screen, Night Mode: what nope. can't turn red (issue #82). Siri, Shortcuts and iOS are Apple's names; Only Before a Photo, Never and Assistant Access are names in nope.'s Settings. Draft for the Honesty review. Must not claim more than the English."))
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
