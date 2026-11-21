import AppIntents
import NopeCore

/// "Set Focus Range" for the Shortcuts app (issue #62): Close-Up, Far Focus or no limit, as the
/// quick-controls tray offers them.
///
/// One action with three choices rather than a Close-Up and a Far Focus action: the camera has
/// one autofocus range restriction, so the two exclude each other, and one action can't leave
/// both on. The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it hands
/// ``ShortcutRequest/setFocusRange(_:)`` to the app's ``ShortcutInbox``. The limit applies to the
/// running camera, so the app opens first.
struct SetFocusRangeIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Set Focus Range", comment: "The name of nope.'s action that limits autofocus to near or far subjects, or lifts the limit, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and limits autofocus to near subjects (Close-Up) or far subjects (Far Focus), or lifts the limit. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Set Focus Range action in the Shortcuts app. Close-Up and Far Focus are the names of the camera's controls. Keep \"nope.\" unchanged."))

    /// Runs in the background first, so a refused or cancelled request never opens the app;
    /// the app opens once the request is allowed (`continueInForeground`; issue #82, device
    /// check 1 in docs/TESTING.md). The camera needs the app in the foreground.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    /// The range.
    @Parameter(
        title: LocalizedStringResource(
            "Focus Range", comment: "A setting of nope.'s Set Focus Range action: which subjects autofocus looks for."),
        default: .unlimited)
    var range: FocusRangeOption

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Set focus range to \(\.$range)")
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choice = range.choice
        let question = AssistantQuestions.focusRange(named: String(localized: range.localizedStringResource))
        let answer = try await gate.answer(.setFocusRange, question: question, intent: self, opensApp: true) {
            AssistantAnswer(await inbox.submit(.setFocusRange(choice)))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}

/// The ranges ``SetFocusRangeIntent`` offers.
enum FocusRangeOption: String, AppEnum {
    /// No limit.
    case unlimited
    /// Close-Up.
    case closeUp
    /// Far Focus.
    case far

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Focus Range", comment: "A setting of nope.'s Set Focus Range action: which subjects autofocus looks for."))

    /// Each range's name, as the camera's controls name them.
    static let caseDisplayRepresentations: [FocusRangeOption: DisplayRepresentation] = [
        .unlimited: DisplayRepresentation(
            title: LocalizedStringResource("No Limit", comment: "A choice of nope.'s Set Focus Range action: autofocus searches near and far.")),
        .closeUp: DisplayRepresentation(
            title: LocalizedStringResource("Close-Up", comment: "Quick control and pill on the camera: limits autofocus to near subjects, for small things close to the lens.")),
        .far: DisplayRepresentation(
            title: LocalizedStringResource("Far Focus", comment: "Quick control and pill on the camera: limits autofocus to far subjects, such as a landscape seen past near branches.")),
    ]

    /// The range in `NopeCore`.
    var choice: FocusRangeChoice {
        switch self {
        case .unlimited: .unlimited
        case .closeUp: .closeUp
        case .far: .far
        }
    }
}

/// "Set Photo Size" for the Shortcuts app (issue #62): the standard or the largest photo size of
/// a lens that offers more than one, as Settings > Photo Size chooses it.
///
/// The lenses and their sizes are known only once the camera has started, so the app opens
/// first; the request goes through the app's ``ShortcutInbox`` and stores the choice in the
/// person's settings, which the camera then uses.
struct SetPhotoSizeIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Set Photo Size", comment: "The name of nope.'s action that chooses the photo size of a lens, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and chooses the standard or the largest photo size of a lens that offers more than one. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Set Photo Size action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// Runs in the background first, so a refused or cancelled request never opens the app;
    /// the app opens once the request is allowed (`continueInForeground`; issue #82, device
    /// check 1 in docs/TESTING.md). The camera needs the app in the foreground.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    /// The size.
    @Parameter(
        title: LocalizedStringResource(
            "Photo Size", comment: "Settings row and screen title: the size of photos from lenses that offer more than one."),
        default: .standard)
    var size: PhotoSizeOption

    /// The lens, or `nil` for the lens in use.
    @Parameter(
        title: LocalizedStringResource(
            "Lens", comment: "A setting of nope.'s Take Photo action: which camera to use."))
    var lens: PhotoLens?

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Set photo size to \(\.$size)") {
            \.$lens
        }
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let request = PhotoSizeShortcut(lensKind: lens?.kind, size: size.size)
        let question = AssistantQuestions.photoSize(named: String(localized: size.localizedStringResource), lens: lens?.kind)
        let answer = try await gate.answer(.setPhotoSize, question: question, intent: self, opensApp: true) {
            AssistantAnswer(await inbox.submit(.setPhotoSize(request)))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}

/// The sizes ``SetPhotoSizeIntent`` offers.
enum PhotoSizeOption: String, AppEnum {
    /// The lens's standard, smallest size.
    case standard
    /// The lens's largest size.
    case largest

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Photo Size", comment: "Settings row and screen title: the size of photos from lenses that offer more than one."))

    /// Each size's name.
    static let caseDisplayRepresentations: [PhotoSizeOption: DisplayRepresentation] = [
        .standard: DisplayRepresentation(
            title: LocalizedStringResource("Standard", comment: "A choice of nope.'s Set Photo Size action: the lens's default, smallest photo size.")),
        .largest: DisplayRepresentation(
            title: LocalizedStringResource("Largest", comment: "A choice of nope.'s Set Photo Size action: the largest photo size the lens offers.")),
    ]

    /// The size in `NopeCore`.
    var size: PhotoSizeShortcut.Size {
        switch self {
        case .standard: .standard
        case .largest: .largest
        }
    }
}

/// "Set Fast Shutter" for the Shortcuts app (issue #62): how fast a shutter full auto prefers,
/// with ``NopeSettings/setFastShutter(_:)``, as the Fast Shutter setting does.
///
/// It changes only the stored setting, as ``SetNightModeIntent`` does, so it runs without
/// opening the app; the camera screen follows the change when it is open.
struct SetFastShutterIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Set Fast Shutter", comment: "The name of nope.'s action that chooses how fast a shutter full auto prefers, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Chooses how fast a shutter nope. prefers while Manual Controls are off, to avoid blur. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Set Fast Shutter action in the Shortcuts app. Keep \"nope.\" unchanged. Manual Controls is the name of nope.'s button; use its translation. Must not claim more than the English."))

    /// The choice.
    @Parameter(
        title: LocalizedStringResource(
            "Fast Shutter", comment: "Setting and quick control: how fast a shutter full auto prefers, to avoid blur."),
        default: .standard)
    var choice: FastShutterOption

    /// The person's settings, the same object the camera screen shows.
    @Dependency private var settings: NopeSettings

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Set fast shutter to \(\.$choice)")
    }

    /// Changes the setting and says so.
    ///
    /// - Returns: The answer, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let fastShutter = choice.fastShutter
        let question = AssistantQuestions.fastShutter(named: String(localized: choice.localizedStringResource))
        let answer = try await gate.answer(.setFastShutter, question: question, intent: self, opensApp: false) {
            settings.setFastShutter(fastShutter)
            return AssistantAnswer(
                LocalizedStringResource("Fast Shutter is set.", comment: "Siri's answer after nope.'s Fast Shutter setting was changed."))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}

/// The choices ``SetFastShutterIntent`` offers, as the Fast Shutter setting names them.
enum FastShutterOption: String, AppEnum {
    /// Standard: fast enough to hold by hand.
    case standard
    /// 1/500 s or faster.
    case freezeMotion
    /// 1/1000 s or faster.
    case freezeFastMotion

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Fast Shutter", comment: "Setting and quick control: how fast a shutter full auto prefers, to avoid blur."))

    /// Each choice's name.
    static let caseDisplayRepresentations: [FastShutterOption: DisplayRepresentation] = [
        .standard: DisplayRepresentation(
            title: LocalizedStringResource(
                "Fast shutter: Standard", defaultValue: "Standard",
                comment: "Fast shutter choice: full auto aims for a shutter fast enough to hold by hand. The default.")),
        .freezeMotion: DisplayRepresentation(
            title: LocalizedStringResource(
                "Freeze Motion (1/500 s)", comment: "Fast shutter choice: full auto keeps the shutter at 1/500 second or faster. Keep the fraction.")),
        .freezeFastMotion: DisplayRepresentation(
            title: LocalizedStringResource(
                "Freeze Fast Motion (1/1000 s)", comment: "Fast shutter choice: full auto keeps the shutter at 1/1000 second or faster. Keep the fraction.")),
    ]

    /// The choice in `NopeCore`.
    var fastShutter: FastShutter {
        switch self {
        case .standard: .handheld
        case .freezeMotion: .freezeMotion
        case .freezeFastMotion: .freezeFastMotion
        }
    }
}

/// "Set Focus on Faces" for the Shortcuts app (issue #62; named Set Face Detection before
/// 1.0.0): whether faces the camera detects steer autofocus and auto exposure, with
/// ``NopeSettings/setFollowsFaces(_:)``, as the Focus on Faces switch does. It changes only the
/// stored setting, so it runs without opening the app.
///
/// The type keeps its earlier name, so shortcuts people saved with Set Face Detection keep
/// working: App Intents identifies an action by its `persistentIdentifier`
/// (`PersistentlyIdentifiable`), which by default is derived from the type name. That a saved
/// shortcut survives the new title is an assumption to verify on a device.
struct SetFaceDetectionIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Set Focus on Faces", comment: "The name of nope.'s action that turns Focus on Faces on or off, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Turns on or off whether faces the camera detects steer nope.'s autofocus and auto exposure. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Set Focus on Faces action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// Whether faces steer autofocus and auto exposure. Off by default, as the setting is
    /// (issue #80).
    @Parameter(
        title: LocalizedStringResource(
            "Focus on Faces", comment: "Switch: faces the camera detects steer autofocus and auto exposure."),
        default: false,
        displayName: Bool.IntentDisplayName(
            true: LocalizedStringResource("On", comment: "Night mode turned on, in nope.'s Set Night Mode action."),
            false: LocalizedStringResource("Off", comment: "Night mode turned off, in nope.'s Set Night Mode action.")))
    var isOn: Bool

    /// The person's settings, the same object the camera screen shows.
    @Dependency private var settings: NopeSettings

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Set focus on faces to \(\.$isOn)")
    }

    /// Changes the setting and says the new state.
    ///
    /// - Returns: The new state, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isOn = isOn
        let answer = try await gate.answer(.setFocusOnFaces, question: AssistantQuestions.focusOnFaces(isOn: isOn), intent: self, opensApp: false) {
            settings.setFollowsFaces(isOn)
            return AssistantAnswer(
                isOn
                    ? LocalizedStringResource("Focus on Faces is on.", comment: "Siri's answer after nope.'s Focus on Faces was turned on.")
                    : LocalizedStringResource("Focus on Faces is off.", comment: "Siri's answer after nope.'s Focus on Faces was turned off."))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}
