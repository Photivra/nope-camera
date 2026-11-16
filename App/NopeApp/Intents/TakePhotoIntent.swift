import AppIntents
import NopeCore

/// "Take Photo" for Siri and the Shortcuts app (issue #62): opens the app to the camera and takes
/// a photo with the current settings, after an optional delay, with an optional lens; with a
/// count above one, a burst of that many separate photos.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it turns its parameters into a
/// ``PhotoShortcut``, hands it to the app's ``ShortcutInbox``, and says the outcome. The camera
/// screen performs it through `CameraModel`, with the self-timer for a delay. Taking a photo
/// needs the app in the foreground, so the intent opens the app first. Siri hears only whether
/// the photo was saved and signed, never image data or metadata.
struct TakePhotoIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Take Photo", comment: "The name of nope.'s action that takes a photo, in the Shortcuts app and Siri.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and takes a photo with the current settings, after an optional delay.",
            comment: "Describes nope.'s Take Photo action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// The camera needs the app in the foreground (AVFoundation stops capture in the background),
    /// so the app opens before the intent runs.
    static let openAppWhenRun = true

    /// The preset delay: none, 3 or 10 seconds, as the self-timer offers.
    @Parameter(
        title: LocalizedStringResource(
            "Delay", comment: "A setting of nope.'s Take Photo action: how long to wait before the photo."),
        default: .noDelay)
    var delay: PhotoDelay

    /// A custom delay in seconds, which replaces ``delay`` when set.
    @Parameter(
        title: LocalizedStringResource(
            "Custom Delay", comment: "A setting of nope.'s Take Photo action: a delay in seconds that you type."),
        description: LocalizedStringResource(
            "A delay in seconds, up to a minute. It replaces the Delay choice.",
            comment: "Explains the Custom Delay setting of nope.'s Take Photo action. \"Delay\" is the name of the other setting."),
        // A compile-time constant: PhotoShortcut.maximumDelaySeconds, which also checks the value.
        inclusiveRange: (1, 60))
    var customDelaySeconds: Int?

    /// The lens, or `nil` for the lens in use.
    @Parameter(
        title: LocalizedStringResource(
            "Lens", comment: "A setting of nope.'s Take Photo action: which camera to use."))
    var lens: PhotoLens?

    /// How many photos: one, or a burst of up to 50 frames, each its own photo. `nil` for one.
    @Parameter(
        title: LocalizedStringResource(
            "Number of Photos", comment: "A setting of nope.'s actions: how many photos to take."),
        description: LocalizedStringResource(
            "More than one takes a burst: separate photos, as fast as the camera allows, up to 50.",
            comment: "Explains the Number of Photos setting of nope.'s Take Photo action."),
        // A compile-time constant: DriveModel.maximumBurstFrames, which also checks the value.
        inclusiveRange: (1, 50))
    var count: Int?

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Take a photo (delay: \(\.$delay))") {
            \.$customDelaySeconds
            \.$lens
            \.$count
        }
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let photo = PhotoShortcut(
            timer: delay.timer, customDelaySeconds: customDelaySeconds, lensKind: lens?.kind, count: count)
        let outcome = await inbox.submit(.takePhoto(photo))
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
    }
}

/// The preset delays of ``TakePhotoIntent``: the self-timer's 3 and 10 seconds, or none.
enum PhotoDelay: String, AppEnum {
    /// No delay.
    case noDelay
    /// Three seconds.
    case threeSeconds
    /// Ten seconds.
    case tenSeconds

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Delay", comment: "A setting of nope.'s Take Photo action: how long to wait before the photo."))

    /// Each delay's name, also used in Siri phrases such as "Take a photo in 10 seconds".
    static let caseDisplayRepresentations: [PhotoDelay: DisplayRepresentation] = [
        .noDelay: DisplayRepresentation(
            title: LocalizedStringResource(
                "No Delay", comment: "A choice of the Delay setting of nope.'s Take Photo action: take the photo at once.")),
        .threeSeconds: DisplayRepresentation(
            title: LocalizedStringResource(
                "3 Seconds", comment: "A choice of the Delay setting of nope.'s Take Photo action, also said to Siri.")),
        .tenSeconds: DisplayRepresentation(
            title: LocalizedStringResource(
                "10 Seconds", comment: "A choice of the Delay setting of nope.'s Take Photo action, also said to Siri.")),
    ]

    /// The self-timer delay, or `nil` for none.
    var timer: SelfTimerDelay? {
        switch self {
        case .noDelay: nil
        case .threeSeconds: .threeSeconds
        case .tenSeconds: .tenSeconds
        }
    }
}

/// The lenses ``TakePhotoIntent`` and ``SwitchLensIntent`` can ask for. A device without the lens says so and takes no
/// photo.
enum PhotoLens: String, AppEnum {
    /// The rear ultra wide camera.
    case ultraWide
    /// The rear wide (main) camera.
    case wide
    /// A rear telephoto camera.
    case telephoto
    /// The front camera.
    case front

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Lens", comment: "A setting of nope.'s Take Photo action: which camera to use."))

    /// Each lens's name, as the camera's lens buttons name them.
    static let caseDisplayRepresentations: [PhotoLens: DisplayRepresentation] = [
        .ultraWide: DisplayRepresentation(
            title: LocalizedStringResource("Ultra Wide", comment: "The ultra wide rear camera, as a lens choice.")),
        .wide: DisplayRepresentation(
            title: LocalizedStringResource("Wide", comment: "The wide (main) rear camera, as a lens choice.")),
        .telephoto: DisplayRepresentation(
            title: LocalizedStringResource("Telephoto", comment: "The telephoto rear camera, as a lens choice.")),
        .front: DisplayRepresentation(
            title: LocalizedStringResource("Front", comment: "The front (selfie) camera, as a lens choice.")),
    ]

    /// The lens kind in `NopeCore`.
    var kind: Lens.Kind {
        switch self {
        case .ultraWide: .ultraWide
        case .wide: .wide
        case .telephoto: .telephoto
        case .front: .front
        }
    }
}
