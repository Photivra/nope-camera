import SwiftUI

/// The shutter: a large round button, drawn because no system control exists for it.
///
/// It is 76 points across (``NopeSize/shutter``), larger than the 44-point minimum (AGENTS.md,
/// "Touch targets"), and supports VoiceOver, Voice Control ("Take Photo") and the Large Content
/// Viewer. A haptic confirms each press. The volume buttons and Camera Control are wired by the
/// app target, and the Space bar by ``CameraCommands``. On iPad it shows a round pointer
/// highlight. It stays in the middle of the shutter row in portrait and of the controls column
/// in landscape, in reach of the thumb in both orientations.
///
/// The disc says what a press does (docs/design/BUILD-SPEC.md, 3.5): with the self-timer chosen
/// and idle it shows the delay ("3" or "10") in black; while a series or countdown runs, the disc
/// gives way to a stop square, because a press stops it. Its name stays "Take Photo"; the
/// VoiceOver value says the mode (`shutterDriveValue(_:)`).
struct ShutterButton: View {
    /// What the disc shows.
    enum Face: Equatable {
        /// The plain white disc.
        case photo

        /// The self-timer's delay on the disc, in seconds.
        case timer(seconds: Int)

        /// A stop square: a series or countdown runs, and a press stops it.
        case stop
    }

    /// Whether a photo can be taken now.
    let isEnabled: Bool

    /// What the disc shows.
    let face: Face

    /// Called when the shutter is pressed.
    let action: () -> Void

    /// Counts presses, to trigger the haptic.
    @State private var presses = 0

    /// The shutter's diameter, in points.
    static var diameter: CGFloat { NopeSize.shutter }

    /// The side of the stop square: half the disc, so the ring still reads as the shutter.
    static var stopSide: CGFloat { NopeSize.shutterDisc / 2 }

    /// The dark hairline outside the ring, so the shutter's edge shows over a white scene
    /// (issue #68, "Contrast").
    private static var hairlineOpacity: Double { 0.6 }

    /// Creates the shutter.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether a photo can be taken now.
    ///   - face: What the disc shows; the plain disc by default.
    ///   - action: Called when the shutter is pressed.
    init(isEnabled: Bool, face: Face = .photo, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.face = face
        self.action = action
    }

    /// The button.
    var body: some View {
        Button {
            presses += 1
            action()
        } label: {
            ZStack {
                Circle().strokeBorder(NopeColor.label, lineWidth: NopeSize.shutterRing)
                Circle().strokeBorder(.black.opacity(Self.hairlineOpacity), lineWidth: NopeSize.outline)
                disc
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .opacity(isEnabled ? 1 : NopeMotion.disabledOpacity)
        }
        .buttonStyle(.plain)
        // A round highlight under the iPad pointer, matching the drawn shape.
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.highlight)
        .disabled(!isEnabled)
        .sensoryFeedback(NopeHaptic.shutter, trigger: presses)
        .accessibilityLabel(Text("Take Photo", bundle: .module, comment: "VoiceOver and Voice Control name of the shutter button."))
        .accessibilityShowsLargeContentViewer {
            Label {
                Text("Take Photo", bundle: .module, comment: "VoiceOver and Voice Control name of the shutter button.")
            } icon: {
                Image(systemName: "camera.circle")
            }
        }
    }

    /// The disc inside the ring, for the face.
    @ViewBuilder private var disc: some View {
        switch face {
        case .photo:
            Circle().fill(NopeColor.selectedFill)
                .frame(width: NopeSize.shutterDisc, height: NopeSize.shutterDisc)
        case .timer(let seconds):
            Circle().fill(NopeColor.selectedFill)
                .frame(width: NopeSize.shutterDisc, height: NopeSize.shutterDisc)
                .overlay {
                    // The number is the delay in the person's numbering system.
                    Text(seconds, format: .number)
                        .font(NopeFont.q.monospacedDigit())
                        .foregroundStyle(NopeColor.selectedLabel)
                        .minimumScaleFactor(0.5)
                        .accessibilityHidden(true)
                }
        case .stop:
            RoundedRectangle(cornerRadius: NopeRadius.small / 2)
                .fill(NopeColor.selectedFill)
                .frame(width: Self.stopSide, height: Self.stopSide)
        }
    }
}
