import NopeCore
import SwiftUI

/// A persistent warning about what the photo is, such as "Not Signed" (issue #68, "Feedback
/// tiers"): an amber chip with a symbol and words that stays until the cause goes away, even in
/// clean view. Tapping it shows the explanation.
///
/// The no-RAW fallback is not in this list: the format chip itself turns into its warning.
struct CameraWarning: Identifiable {
    /// A stable identifier, such as "signing".
    let id: String

    /// The chip's words, such as "Not Signed".
    let title: Text

    /// What it means, in one or two sentences. VoiceOver reads it as the chip's value.
    let explanation: Text

    /// Creates a warning.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - title: The chip's words.
    ///   - explanation: What it means.
    init(id: String, title: Text, explanation: Text) {
        self.id = id
        self.title = title
        self.explanation = explanation
    }
}

/// The registry of warning chips: each cause adds one function here that returns its warning,
/// or `nil` when it doesn't apply.
@MainActor
enum CameraWarnings {
    /// Every warning builder, in display order. Add a cause's builder here.
    static let builders: [@MainActor (CameraControlContext, SignatureStatus?) -> CameraWarning?] = [
        signing,
        storage,
        battery,
        lightUnavailable,
        location,
    ]

    /// The warnings that apply now, in display order.
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - lastSignature: The signature of the last photo saved this session, or `nil`.
    static func current(_ context: CameraControlContext, lastSignature: SignatureStatus?) -> [CameraWarning] {
        builders.compactMap { $0(context, lastSignature) }
    }

    /// "Light Unavailable" while the system refuses the light the person turned on, or turned it
    /// off, for example because the device is too warm (issue #38).
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - lastSignature: Not used.
    static func lightUnavailable(_ context: CameraControlContext, lastSignature: SignatureStatus?) -> CameraWarning? {
        guard context.model.light.torch == .unavailable else { return nil }
        return CameraWarning(
            id: "light",
            title: Text("Light Unavailable", bundle: .module, comment: "Warning chip on the camera: the light (torch) the person turned on is off because the system didn't allow it."),
            explanation: Text(
                "The light is off: the system didn't allow it, for example because the device is too warm. Turn Light off and on again in Quick Controls to try again, or choose a lower brightness.",
                bundle: .module,
                comment: "Explains the Light Unavailable warning. Light and Quick Controls are the names of camera controls."))
    }

    /// "Not Signed" after the last photo couldn't be signed while signing is on. A missing
    /// signature is always stated, never hidden (issue #1).
    ///
    /// Signing is off by default (issue #80), so signing that is off is not a warning: the
    /// message after each save says "Saved. Not signed: signing is off in Settings.", and the
    /// photo's details say it isn't signed.
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - lastSignature: The signature of the last photo saved this session, or `nil`.
    static func signing(_ context: CameraControlContext, lastSignature: SignatureStatus?) -> CameraWarning? {
        guard context.settings.signsPhotos, case .unsigned(let reason) = lastSignature, reason != .turnedOff else {
            return nil
        }
        let explanation = Text(verbatim: CaptureMessages.message(for: .unsigned(reason)))
        return CameraWarning(
            id: "signing",
            title: Text("Not Signed", tableName: "Honesty", bundle: .module, comment: "Warning chip on the camera: photos are saved without a Content Credentials signature. Honesty wording: never imply photos are signed."),
            explanation: explanation)
    }
}

extension CameraWarnings {
    /// "Location On" while the Location switch is on (issue #43), so a photo's location is
    /// never added without the person seeing it on the camera.
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - lastSignature: Unused.
    static func location(_ context: CameraControlContext, lastSignature: SignatureStatus?) -> CameraWarning? {
        guard context.settings.metadata.isOn(.location) else { return nil }
        let explanation: Text
        if context.model.location?.access.isAllowed == true {
            explanation = Text(
                "New photos include where they were taken: latitude, longitude and altitude. You can turn Location off under Choose Details in Settings.",
                tableName: "Honesty", bundle: .module,
                comment: "Explanation of the Location On chip on the camera: new photos include their location. Must not claim more than the English.")
        } else {
            explanation = Text(
                "Location is on, but location access is off, so photos are saved without a location.", tableName: "Honesty",
                bundle: .module,
                comment: "Explanation of the Location On chip when the person turned Location on but location access is off in the system settings. Must not claim more than the English.")
        }
        return CameraWarning(
            id: "location",
            title: Text("Location On", tableName: "Honesty", bundle: .module, comment: "Warning chip on the camera: new photos include where they were taken."),
            explanation: explanation)
    }
}

/// An amber warning chip. Tapping it shows the explanation in a popover; VoiceOver reads the
/// explanation as its value without opening it.
struct WarningChip: View {
    /// The warning.
    let warning: CameraWarning

    /// Whether the explanation is shown.
    @State private var showsExplanation = false

    /// Whether night mode is on, so the explanation is red too.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the chip.
    ///
    /// - Parameter warning: The warning.
    init(warning: CameraWarning) {
        self.warning = warning
    }

    /// The chip.
    var body: some View {
        Button {
            showsExplanation = true
        } label: {
            Label {
                warning.title
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .darkBacking(Capsule())
            .overlay(Capsule().strokeBorder(CameraStyle.warning, lineWidth: 1))
            .frame(minHeight: CameraStyle.minimumTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(warning.explanation)
        .accessibilityShowsLargeContentViewer()
        .popover(isPresented: $showsExplanation) {
            warning.explanation
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(idealWidth: 320)
                .presentationCompactAdaptation(.popover)
                .nightModeStyle(isNightMode)
        }
    }
}
