import AppIntents

/// Opens the app's camera from the Lock Screen, Control Center or the Action button (issue #42).
///
/// It is a `CameraCaptureIntent` (App Intents, iOS 18): the system runs it from the "Open nope."
/// control (`OpenCameraControl` in the NopeControls extension). On a locked device the system
/// opens the Lock Screen capture extension (NopeCaptureExtension, LockedCameraCapture); on an
/// unlocked one, it opens the app. Apple's documentation asks for the intent in the app, the
/// capture extension and the control's widget extension, so this file is in all three targets
/// (App/Shared).
///
/// It holds no rules and passes no app context: the camera starts as it does when opened from
/// the Home Screen.
struct OpenCameraIntent: CameraCaptureIntent {
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
