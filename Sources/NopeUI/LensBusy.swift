import NopeCore
import SwiftUI

/// What the lens controls show while the lens can't be changed (issue #96;
/// docs/design/lens-while-busy.md): the lens buttons, the lens rows, Switch Camera and the
/// close-up hint's switch button.
///
/// While ``blocker`` is not `nil`, every lens control except the lens in use is disabled at once
/// and stays where it is; nothing is hidden or moved. ``isDrawnDimmed`` says whether the disabled
/// controls are drawn at ``NopeMotion/disabledOpacity`` yet: at once for a countdown, burst,
/// interval series or astro run, and for a single photo or bracket only after
/// ``NopeMotion/busyDimDelay``, so a normal photo doesn't make the lens row blink.
struct LensBusyState: Equatable {
    /// Why the lens can't be changed (`CameraModel.lensChangeBlocker`), or `nil` when it can.
    var blocker: LensChangeBlocker?

    /// Whether the disabled controls are drawn dimmed.
    var isDrawnDimmed: Bool

    /// Creates a busy state.
    ///
    /// - Parameters:
    ///   - blocker: Why the lens can't be changed, or `nil` when it can.
    ///   - isDrawnDimmed: Whether the disabled controls are drawn dimmed.
    init(blocker: LensChangeBlocker?, isDrawnDimmed: Bool) {
        self.blocker = blocker
        self.isDrawnDimmed = isDrawnDimmed
    }

    /// The lens can be changed: nothing is disabled.
    static let free = LensBusyState(blocker: nil, isDrawnDimmed: false)

    /// Whether a lens control other than the lens in use is disabled.
    var isDisabled: Bool {
        blocker != nil
    }

    /// The VoiceOver hint of a disabled lens control: the reason during a countdown, burst,
    /// interval series or astro run, the sentence presets use; `nil` otherwise (a single photo
    /// is read as "dimmed" only).
    var hint: Text? {
        blocker == .runningSeries ? Self.takingPhotosHint : nil
    }

    /// "The camera is taking photos. Try again when it's done."
    static var takingPhotosHint: Text {
        Text(
            "The camera is taking photos. Try again when it's done.", bundle: .module,
            comment: "Shown when a settings preset can't be applied, and VoiceOver hint of a dimmed lens button, during a countdown, burst, series or astro run.")
    }

    /// Whether the disabled controls are drawn dimmed for a blocker.
    ///
    /// - Parameters:
    ///   - blocker: Why the lens can't be changed, or `nil`.
    ///   - photoDelayPassed: Whether a photo has lasted ``NopeMotion/busyDimDelay``, or the
    ///     controls were already dimmed when the photo began.
    /// - Returns: `false` when nothing is blocked; for a photo, `photoDelayPassed`; otherwise
    ///   `true`.
    static func isDrawnDimmed(for blocker: LensChangeBlocker?, photoDelayPassed: Bool) -> Bool {
        switch blocker {
        case nil: false
        case .takingPhoto: photoDelayPassed
        case .runningSeries, .comparing: true
        }
    }
}

extension EnvironmentValues {
    /// The lens controls' busy state, set once for the camera screen by
    /// ``SwiftUICore/View/tracksLensBusy(_:)`` and read by each lens control.
    @Entry var lensBusy = LensBusyState.free

    /// Whether a disabled custom button is drawn at ``NopeMotion/disabledOpacity``. `true` by
    /// default; the lens controls set it `false` while a photo is still too short to dim them
    /// (``LensBusyState/isDrawnDimmed``), so they are disabled but drawn as before.
    @Entry var drawsDisabledDimmed = true
}

/// Follows `CameraModel.lensChangeBlocker` for the lens controls under it, and times the
/// dimming of a single photo.
private struct LensBusyTracking: ViewModifier {
    /// Why the lens can't be changed, or `nil`.
    let blocker: LensChangeBlocker?

    /// Whether the current photo has lasted ``NopeMotion/busyDimDelay``, or the controls were
    /// already dimmed when it began.
    @State private var photoDelayPassed = false

    /// The content with ``SwiftUICore/EnvironmentValues/lensBusy`` set.
    ///
    /// - Parameter content: The camera screen.
    func body(content: Content) -> some View {
        content
            .environment(
                \.lensBusy,
                LensBusyState(
                    blocker: blocker,
                    isDrawnDimmed: LensBusyState.isDrawnDimmed(for: blocker, photoDelayPassed: photoDelayPassed)))
            .onChange(of: blocker) { old, new in
                // A photo that follows a dimmed state (a countdown's photo) stays dimmed, and
                // the photo delay starts again after the controls are free.
                if new == .takingPhoto, LensBusyState.isDrawnDimmed(for: old, photoDelayPassed: photoDelayPassed) {
                    photoDelayPassed = true
                } else if new != .takingPhoto {
                    photoDelayPassed = false
                }
            }
            .task(id: blocker) {
                guard blocker == .takingPhoto, !photoDelayPassed else { return }
                try? await Task.sleep(for: NopeMotion.busyDimDelay)
                // Cancelled when the photo ends first: a change back before the delay draws
                // nothing.
                if !Task.isCancelled { photoDelayPassed = true }
            }
    }
}

/// Disables one lens control while the lens can't be changed, as the drive strip does with its
/// words (docs/design/lens-while-busy.md, section 2).
private struct LensBusyControl: ViewModifier {
    /// Whether the control is the lens in use, which stays enabled and full strength.
    let isSelected: Bool

    /// The control's own VoiceOver hint while it isn't disabled.
    let hint: Text?

    /// The lens controls' busy state.
    @Environment(\.lensBusy) private var busy

    /// The control, disabled while busy unless it is the lens in use.
    ///
    /// - Parameter content: The control.
    func body(content: Content) -> some View {
        let isDisabled = busy.isDisabled && !isSelected
        content
            .disabled(isDisabled)
            .environment(\.drawsDisabledDimmed, busy.isDrawnDimmed)
            .accessibilityHint((isDisabled ? busy.hint : nil) ?? hint ?? Text(verbatim: ""))
            // Opacity only, both ways, with or without Reduce Motion.
            .animation(NopeMotion.fade, value: busy)
    }
}

extension View {
    /// Gives the lens controls under this view the busy state of a camera model: put it once on
    /// the camera screen.
    ///
    /// - Parameter blocker: `CameraModel.lensChangeBlocker`.
    /// - Returns: The view.
    func tracksLensBusy(_ blocker: LensChangeBlocker?) -> some View {
        modifier(LensBusyTracking(blocker: blocker))
    }

    /// Disables this lens control while the lens can't be changed, unless it is the lens in use,
    /// and gives it the busy hint during a series.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the control is the lens in use.
    ///   - hint: The control's own VoiceOver hint, such as the reason for "No RAW", or `nil`.
    /// - Returns: The view.
    func lensBusyControl(isSelected: Bool = false, hint: Text? = nil) -> some View {
        modifier(LensBusyControl(isSelected: isSelected, hint: hint))
    }
}
