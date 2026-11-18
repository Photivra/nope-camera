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
///
/// In burst mode it also reports when it goes down and comes up (`onPressChange`), so holding it
/// takes a burst (docs/design/BURST.md, 3.1). The disc shrinks while it is held, without
/// animation. The action still runs for assistive activation and for a touch whose press went
/// unreported, but not for a touch that already reported its press, so a tap takes one photo,
/// not two.
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

    /// Called with `true` when a touch goes down on the shutter and `false` when it comes up,
    /// slides off or is cancelled; `nil` outside burst mode.
    let onPressChange: ((Bool) -> Void)?

    /// Counts presses, to trigger the haptic.
    @State private var presses = 0

    /// Whether the current touch reported its press, so its action is skipped.
    @State private var pressWasReported = false

    /// The shutter's diameter, in points.
    static var diameter: CGFloat { NopeSize.shutter }

    /// The side of the stop square: half the disc, so the ring still reads as the shutter.
    static var stopSide: CGFloat { NopeSize.shutterDisc / 2 }

    /// Creates the shutter.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether a photo can be taken now.
    ///   - face: What the disc shows; the plain disc by default.
    ///   - onPressChange: Reports the touch going down and coming up, in burst mode; `nil`
    ///     otherwise.
    ///   - action: Called when the shutter is pressed.
    init(isEnabled: Bool, face: Face = .photo, onPressChange: ((Bool) -> Void)? = nil, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.face = face
        self.onPressChange = onPressChange
        self.action = action
    }

    /// The button.
    var body: some View {
        Button {
            // The touch already reported its press, which took the photo or the burst.
            guard !pressWasReported else { return }
            presses += 1
            action()
        } label: {
            // The style draws the ring and disc, since only it knows whether the shutter is held.
            Color.clear
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(ShutterStyle(face: face, isEnabled: isEnabled, showsHeld: onPressChange != nil, onPressChange: pressChanged))
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

    /// Passes a press or release on, in burst mode, and plays the shutter haptic on the press.
    ///
    /// - Parameter isPressed: Whether the touch is down.
    private func pressChanged(_ isPressed: Bool) {
        guard let onPressChange else { return }
        if isPressed {
            pressWasReported = true
            presses += 1
        } else {
            // The action of the same touch may run just after this, in the same turn of the run
            // loop; it must still see the press as reported.
            DispatchQueue.main.async { pressWasReported = false }
        }
        onPressChange(isPressed)
    }
}

/// Draws the shutter's ring and disc, and reports whether it is held (docs/design/BURST.md, 5.3).
struct ShutterStyle: ButtonStyle {
    /// What the disc shows.
    let face: ShutterButton.Face

    /// Whether a photo can be taken now.
    let isEnabled: Bool

    /// Whether the disc shrinks while held: in burst mode.
    let showsHeld: Bool

    /// Called when the press state changes.
    let onPressChange: (Bool) -> Void

    /// The dark hairline outside the ring, so the shutter's edge shows over a white scene
    /// (issue #68, "Contrast").
    private static var hairlineOpacity: Double { 0.6 }

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - face: What the disc shows.
    ///   - isEnabled: Whether a photo can be taken now.
    ///   - showsHeld: Whether the disc shrinks while held.
    ///   - onPressChange: Called when the press state changes.
    init(face: ShutterButton.Face, isEnabled: Bool, showsHeld: Bool, onPressChange: @escaping (Bool) -> Void) {
        self.face = face
        self.isEnabled = isEnabled
        self.showsHeld = showsHeld
        self.onPressChange = onPressChange
    }

    /// The ring and disc over the button's label.
    ///
    /// - Parameter configuration: The label and press state.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                ZStack {
                    Circle().strokeBorder(NopeColor.label, lineWidth: NopeSize.shutterRing)
                    Circle().strokeBorder(.black.opacity(Self.hairlineOpacity), lineWidth: NopeSize.outline)
                    disc(isHeld: showsHeld && configuration.isPressed)
                }
                .opacity(isEnabled ? 1 : NopeMotion.disabledOpacity)
            }
            .onChange(of: configuration.isPressed) { _, isPressed in onPressChange(isPressed) }
    }

    /// The disc inside the ring, for the face.
    ///
    /// - Parameter isHeld: Whether the shutter is held in burst mode: the disc is smaller.
    @ViewBuilder private func disc(isHeld: Bool) -> some View {
        switch face {
        case .photo:
            let side = isHeld ? NopeSize.shutterDiscHeld : NopeSize.shutterDisc
            Circle().fill(NopeColor.selectedFill)
                .frame(width: side, height: side)
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
                .frame(width: ShutterButton.stopSide, height: ShutterButton.stopSide)
        }
    }
}
