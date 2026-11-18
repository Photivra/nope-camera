import AppIntents
import NopeCore

/// "Take Bracket" for Siri and the Shortcuts app (issue #62): opens the app to the camera and
/// takes one exposure bracket: 3, 5 or 7 separate photos, a chosen number of stops apart, in a
/// chosen order (darkest, metered or brightest first; docs/design/BRACKETING.md, decision 17).
///
/// A separate action from ``TakePhotoIntent``, not a parameter of it: a bracket and a burst are
/// different captures (exposures set exactly per frame, against frames as fast as the camera
/// allows), with different limits (3, 5 or 7 frames on a lens with manual exposure, against 1 to
/// 50 on any lens), so one action with both would offer combinations that can't be taken.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it hands a ``BracketShortcut``
/// to the app's ``ShortcutInbox`` and says the outcome. The bracket is taken once, through the
/// same bracket path as the shutter's; the bracket chosen on the drive strip doesn't change.
struct TakeBracketIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Take Bracket", comment: "The name of nope.'s action that takes an exposure bracket: several separate photos at different exposures, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and takes separate photos at different exposures, once. Your bracket setting doesn't change.",
            comment: "Describes nope.'s Take Bracket action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// The camera needs the app in the foreground, so the app opens before the intent runs.
    static let openAppWhenRun = true

    /// The number of frames.
    /// Exposure (the default) or Focus.
    @Parameter(
        title: LocalizedStringResource(
            "Type", comment: "A setting of nope.'s Take Bracket action: the kind of bracket, exposure or focus."),
        default: .exposure)
    var type: BracketTypeChoice

    @Parameter(
        title: LocalizedStringResource(
            "Frames", comment: "A setting of nope.'s Take Bracket action: how many photos the bracket takes."),
        default: .three)
    var frames: BracketFrameChoice

    /// A focus bracket's frames, moved to the nearest the app offers (3 to 50).
    @Parameter(
        title: LocalizedStringResource(
            "Focus Frames", comment: "A setting of nope.'s Take Bracket action with the type Focus: how many photos the focus bracket takes."),
        default: 10, inclusiveRange: (3, 50))
    var focusFrames: Int

    /// A focus bracket's range: as set in the app, or the whole range.
    @Parameter(
        title: LocalizedStringResource(
            "Range", comment: "A setting of nope.'s Take Bracket action with the type Focus: which focus positions the bracket covers."),
        default: .asSet)
    var range: FocusRangeChoiceEntity

    /// The exposure difference between neighboring frames.
    @Parameter(
        title: LocalizedStringResource(
            "Step", comment: "A setting of nope.'s Take Bracket action: the exposure difference between neighboring photos, in stops."),
        default: .oneStop)
    var step: BracketStepChoice

    /// The order of the frames; Darkest First, the order of earlier versions, by default.
    @Parameter(
        title: LocalizedStringResource(
            "Order", comment: "A setting of nope.'s Take Bracket action: the order in which the photos are taken."),
        default: .darkestFirst)
    var order: BracketOrderChoice

    /// The preset delay: none, 3 or 10 seconds, as the self-timer offers.
    @Parameter(
        title: LocalizedStringResource(
            "Delay", comment: "A setting of nope.'s Take Photo action: how long to wait before the photo."),
        default: .noDelay)
    var delay: PhotoDelay

    /// The lens, or `nil` for the lens in use.
    @Parameter(
        title: LocalizedStringResource(
            "Lens", comment: "A setting of nope.'s Take Photo action: which camera to use."))
    var lens: PhotoLens?

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Switch(\.$type) {
            Case(.focus) {
                Summary("Take a \(\.$type) bracket of \(\.$focusFrames) photos") {
                    \.$range
                    \.$delay
                    \.$lens
                }
            }
            DefaultCase {
                Summary("Take a bracket of \(\.$frames), \(\.$step) apart") {
                    \.$type
                    \.$order
                    \.$delay
                    \.$lens
                }
            }
        }
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let request = BracketShortcut(
            type: type.type, focusFrameCount: focusFrames, focusRange: range.range, frameCount: frames.count, step: step.stops, order: order.order, delaySeconds: delay.timer?.seconds ?? 0,
            lensKind: lens?.kind)
        let outcome = await inbox.submit(.takeBracket(request))
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
    }
}

/// The frame counts ``TakeBracketIntent`` offers: those of `BracketSettings.frameCounts`.
enum BracketFrameChoice: String, AppEnum {
    /// Three frames.
    case three
    /// Five frames.
    case five
    /// Seven frames.
    case seven

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Frames", comment: "A setting of nope.'s Take Bracket action: how many photos the bracket takes."))

    /// Each count's name.
    static let caseDisplayRepresentations: [BracketFrameChoice: DisplayRepresentation] = [
        .three: DisplayRepresentation(
            title: LocalizedStringResource("3 Photos", comment: "A choice of the Frames setting of nope.'s Take Bracket action.")),
        .five: DisplayRepresentation(
            title: LocalizedStringResource("5 Photos", comment: "A choice of the Frames setting of nope.'s Take Bracket action.")),
        .seven: DisplayRepresentation(
            title: LocalizedStringResource("7 Photos", comment: "A choice of the Frames setting of nope.'s Take Bracket action.")),
    ]

    /// The number of frames.
    var count: Int {
        switch self {
        case .three: 3
        case .five: 5
        case .seven: 7
        }
    }
}

/// The steps ``TakeBracketIntent`` offers: those of `BracketSettings.steps`.
enum BracketStepChoice: String, AppEnum {
    /// A third of a stop.
    case thirdStop
    /// Two thirds of a stop.
    case twoThirdsStop
    /// One stop.
    case oneStop
    /// Two stops.
    case twoStops

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Step", comment: "A setting of nope.'s Take Bracket action: the exposure difference between neighboring photos, in stops."))

    /// Each step's name.
    static let caseDisplayRepresentations: [BracketStepChoice: DisplayRepresentation] = [
        .thirdStop: DisplayRepresentation(
            title: LocalizedStringResource("1/3 Stop", comment: "A choice of the Step setting of nope.'s Take Bracket action: a third of a stop (EV) between photos.")),
        .twoThirdsStop: DisplayRepresentation(
            title: LocalizedStringResource("2/3 Stop", comment: "A choice of the Step setting of nope.'s Take Bracket action: two thirds of a stop (EV) between photos.")),
        .oneStop: DisplayRepresentation(
            title: LocalizedStringResource("1 Stop", comment: "A choice of the Step setting of nope.'s Take Bracket action: one stop (EV) between photos.")),
        .twoStops: DisplayRepresentation(
            title: LocalizedStringResource("2 Stops", comment: "A choice of the Step setting of nope.'s Take Bracket action: two stops (EV) between photos.")),
    ]

    /// The step in EV (stops).
    var stops: Double {
        switch self {
        case .thirdStop: 1.0 / 3.0
        case .twoThirdsStop: 2.0 / 3.0
        case .oneStop: 1
        case .twoStops: 2
        }
    }
}

/// The orders ``TakeBracketIntent`` offers: those of `BracketOrder`.
enum BracketOrderChoice: String, AppEnum {
    /// The darkest frame first.
    case darkestFirst
    /// The metered frame first, then outward.
    case meteredFirst
    /// The brightest frame first.
    case brightestFirst

    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Order", comment: "A setting of nope.'s Take Bracket action: the order in which the photos are taken."))

    /// Each order's name.
    static let caseDisplayRepresentations: [BracketOrderChoice: DisplayRepresentation] = [
        .darkestFirst: DisplayRepresentation(
            title: LocalizedStringResource("Darkest First", comment: "A choice of the Order setting of nope.'s Take Bracket action: the darkest photo first.")),
        .meteredFirst: DisplayRepresentation(
            title: LocalizedStringResource("Metered First", comment: "A choice of the Order setting of nope.'s Take Bracket action: the photo at the metered exposure first, then darker and brighter ones.")),
        .brightestFirst: DisplayRepresentation(
            title: LocalizedStringResource("Brightest First", comment: "A choice of the Order setting of nope.'s Take Bracket action: the brightest photo first.")),
    ]

    /// The order.
    var order: BracketOrder {
        switch self {
        case .darkestFirst: .darkestFirst
        case .meteredFirst: .meteredFirst
        case .brightestFirst: .brightestFirst
        }
    }
}

/// The Type setting of Take Bracket.
enum BracketTypeChoice: String, AppEnum {
    case exposure
    case focus

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Type", comment: "A setting of nope.'s Take Bracket action: the kind of bracket, exposure or focus."))

    static let caseDisplayRepresentations: [BracketTypeChoice: DisplayRepresentation] = [
        .exposure: DisplayRepresentation(
            title: LocalizedStringResource("Exposure", comment: "A choice of the Type setting of nope.'s Take Bracket action: photos at different exposures.")),
        .focus: DisplayRepresentation(
            title: LocalizedStringResource("Focus", comment: "A choice of the Type setting of nope.'s Take Bracket action: photos at different focus positions, for stacking in other software.")),
    ]

    /// The type in `NopeCore`.
    var type: BracketType {
        switch self {
        case .exposure: .exposure
        case .focus: .focus
        }
    }
}

/// The Range setting of Take Bracket with the type Focus.
enum FocusRangeChoiceEntity: String, AppEnum {
    case asSet
    case wholeRange

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Range", comment: "A setting of nope.'s Take Bracket action with the type Focus: which focus positions the bracket covers."))

    static let caseDisplayRepresentations: [FocusRangeChoiceEntity: DisplayRepresentation] = [
        .asSet: DisplayRepresentation(
            title: LocalizedStringResource("As Set in nope.", comment: "A choice of the Range setting of nope.'s Take Bracket action: the focus range set in the app. Keep \"nope.\" unchanged.")),
        .wholeRange: DisplayRepresentation(
            title: LocalizedStringResource("Whole Range", comment: "A choice of the Range setting of nope.'s Take Bracket action: every focus position from the closest to the farthest.")),
    ]

    /// The range in `NopeCore`.
    var range: FocusBracketRange {
        switch self {
        case .asSet: .asSet
        case .wholeRange: .wholeRange
        }
    }
}
