import SwiftUI

/// The shutter: a large round button, drawn because no system control exists for it.
///
/// It is 76 points across, larger than the 44-point minimum (AGENTS.md, "Touch targets"), and
/// supports VoiceOver, Voice Control ("Take Photo") and the Large Content Viewer. A haptic
/// confirms each press. The volume buttons and Camera Control are wired by the app target.
struct ShutterButton: View {
    /// Whether a photo can be taken now.
    let isEnabled: Bool

    /// Called when the shutter is pressed.
    let action: () -> Void

    /// Counts presses, to trigger the haptic.
    @State private var presses = 0

    /// The shutter's diameter, in points.
    private static var diameter: CGFloat { 76 }

    /// Creates the shutter.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether a photo can be taken now.
    ///   - action: Called when the shutter is pressed.
    init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    /// The button.
    var body: some View {
        Button {
            presses += 1
            action()
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4)
                Circle().fill(.white).padding(9)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .sensoryFeedback(.impact, trigger: presses)
        .accessibilityLabel(Text("Take Photo", bundle: .module, comment: "VoiceOver and Voice Control name of the shutter button."))
        .accessibilityShowsLargeContentViewer {
            Label {
                Text("Take Photo", bundle: .module, comment: "VoiceOver and Voice Control name of the shutter button.")
            } icon: {
                Image(systemName: "camera.circle")
            }
        }
    }
}
