import AppIntents
import NopeCore

/// Opens the app's camera from the Lock Screen, Control Center or the Action button (issue #42).
///
/// It is a `CameraCaptureIntent` (App Intents, iOS 18): the system runs it from the "Open nope."
/// control (`OpenCameraControl` in the NopeControls extension). On a locked device the system
/// opens the Lock Screen capture extension (NopeCaptureExtension, LockedCameraCapture); on an
/// unlocked one, it opens the app. Apple's documentation asks for the intent in the app, the
/// capture extension and the control's widget extension, so this file is in all three targets
/// (App/Shared).
///
/// It holds no rules. Its app context carries a copy of the person's settings
/// (``NopeSettingsSnapshot``), which the app writes whenever they change
/// (``SharedSettings/publishToLockScreenCamera(_:)``) and the Lock Screen camera reads when it
/// opens, because Apple doesn't let a capture extension read the App Group's container.
struct OpenCameraIntent: CameraCaptureIntent {
    /// The settings the Lock Screen camera starts with, at most 4 KB (Apple's limit).
    typealias AppContext = NopeSettingsSnapshot

    /// The name in the Shortcuts app and the controls gallery.
    static let title = LocalizedStringResource(
        "Open the Camera", comment: "The name of the action that opens nope.'s camera, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens the nope. camera.",
            comment: "Describes what nope.'s Open the Camera action and control do, in the Shortcuts app and the controls gallery. Keep \"nope.\" unchanged."))

    /// Nothing to do here: the system opens the app or the capture extension.
    ///
    /// - Returns: An empty result.
    func perform() async throws -> some IntentResult {
        .result()
    }
}
