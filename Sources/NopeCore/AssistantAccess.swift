import Foundation

/// How often the app asks before an assistant action runs, while Assistant Access is on (issue
/// #82, `docs/design/assistant-access.md`, 3.3). ``everyAction`` by default.
public enum AssistantAskLevel: String, CaseIterable, Sendable {
    /// Every action is named and confirmed before it runs ("Every Action").
    case everyAction
    /// Only actions that take photos are confirmed; changes run without asking ("Only Before a
    /// Photo").
    case beforePhoto
    /// Nothing is confirmed ("Never").
    case never
}

/// What an entry point is, for the Assistant Access check (`docs/design/assistant-access.md`,
/// section 4). Every entry point of the app declares one, so the entry-point check
/// (`scripts/check-security.sh`) sees each with a kind.
public enum AssistantActionKind: Sendable {
    /// Takes photos: Take Photo, Take Bracket, Start Interval Shooting.
    case takesPhotos
    /// Changes something: every other gated action.
    case changes
    /// Only opens a screen of the app (Open the Camera, Open Assistant Access). Never refused:
    /// the system can open any app for an assistant without the app's help.
    case opensScreen
    /// A control a person presses (the Control Center Night Mode control, the Live Activity's
    /// Stop button). Never refused, as the shutter and the volume buttons aren't.
    case pressedByPerson
}

/// What the Assistant Access check decided for one request.
public enum AssistantDecision: Equatable, Sendable {
    /// Refused because Assistant Access is off. Nothing changes and no photo is taken; the
    /// answer says that access is off and where to turn it on.
    case refuse
    /// Refused because the device is locked. Nothing changes and no photo is taken; the answer
    /// says to unlock. A fallback: the system asks for an unlock first
    /// (`authenticationPolicy`; `docs/TESTING.md`, Assistant Access device check 5).
    case requiresUnlock
    /// Asked first: the action is named and confirmed before it runs.
    case ask
    /// Run without asking.
    case run
}

/// One of the app's entry points for Siri, Shortcuts, other assistants and the system's
/// controls (`docs/design/assistant-access.md`, section 7). The raw value names it in the
/// session record and in `security/assistant-entry-points.txt`.
public enum AssistantAction: String, CaseIterable, Sendable {
    /// Take Photo.
    case takePhoto
    /// Take Bracket.
    case takeBracket
    /// Start Interval Shooting.
    case startInterval
    /// Stop Interval Shooting.
    case stopInterval
    /// Switch Lens.
    case switchLens
    /// Turn On the Light.
    case turnOnLight
    /// Turn Off the Light.
    case turnOffLight
    /// Set Night Mode.
    case setNightMode
    /// Set Focus Range.
    case setFocusRange
    /// Set Photo Size.
    case setPhotoSize
    /// Set Fast Shutter.
    case setFastShutter
    /// Set Focus on Faces.
    case setFocusOnFaces
    /// Apply Preset.
    case applyPreset
    /// Open the Camera, also the "Open nope." control.
    case openCamera
    /// Open Assistant Access: opens Settings at the page.
    case openAssistantAccess
    /// The Control Center and Lock Screen Night Mode control.
    case nightModeControl
    /// The Live Activity's Stop button.
    case liveActivityStop

    /// The action's kind.
    public var kind: AssistantActionKind {
        switch self {
        case .takePhoto, .takeBracket, .startInterval: .takesPhotos
        case .stopInterval, .switchLens, .turnOnLight, .turnOffLight, .setNightMode, .setFocusRange, .setPhotoSize,
            .setFastShutter, .setFocusOnFaces, .applyPreset:
            .changes
        case .openCamera, .openAssistantAccess: .opensScreen
        case .nightModeControl, .liveActivityStop: .pressedByPerson
        }
    }

    /// Whether the action goes through the check: it takes photos or changes something.
    public var isGated: Bool {
        kind == .takesPhotos || kind == .changes
    }
}

/// The Assistant Access check (issue #82): the one rule every assistant entry point asks before
/// it runs, from the person's two settings and whether the device is locked
/// (`docs/design/assistant-access.md`, sections 3.3 and 4).
///
/// The app's intents read it inside `perform()` (``AssistantSession/perform(_:access:confirm:run:)``),
/// and the preset query reads ``offersPresetNames`` before it lists any saved preset. Nothing
/// outside this type decides who may run what.
///
/// ```swift
/// let access = settings.assistantAccess(deviceIsLocked: false)
/// switch access.decision(for: .takePhoto) {
/// case .refuse, .requiresUnlock: break // answer, change nothing
/// case .ask: break // confirm, then run
/// case .run: break
/// }
/// ```
public struct AssistantAccess: Equatable, Sendable {
    /// Whether Assistant Access is on (``NopeSettings/assistantAccess``).
    public var isOn: Bool

    /// When to ask first (``NopeSettings/assistantAsk``). Kept while access is off.
    public var ask: AssistantAskLevel

    /// Whether the device is locked now. Every gated action requires an unlocked device.
    public var deviceIsLocked: Bool

    /// Creates the check.
    ///
    /// - Parameters:
    ///   - isOn: Whether Assistant Access is on.
    ///   - ask: When to ask first.
    ///   - deviceIsLocked: Whether the device is locked now.
    public init(isOn: Bool, ask: AssistantAskLevel, deviceIsLocked: Bool = false) {
        self.isOn = isOn
        self.ask = ask
        self.deviceIsLocked = deviceIsLocked
    }

    /// What to do with a request of a kind.
    ///
    /// `.opensScreen` and `.pressedByPerson` always run. A gated kind is refused while access is
    /// off, needs an unlock while the device is locked, and otherwise asks or runs as
    /// ``ask`` says.
    ///
    /// - Parameter kind: The entry point's kind.
    /// - Returns: The decision.
    public func decision(for kind: AssistantActionKind) -> AssistantDecision {
        switch kind {
        case .opensScreen, .pressedByPerson: return .run
        case .takesPhotos, .changes: break
        }
        guard isOn else { return .refuse }
        guard !deviceIsLocked else { return .requiresUnlock }
        switch ask {
        case .everyAction: return .ask
        case .beforePhoto: return kind == .takesPhotos ? .ask : .run
        case .never: return .run
        }
    }

    /// What to do with a request for an action.
    ///
    /// - Parameter action: The entry point.
    /// - Returns: The decision for its kind.
    public func decision(for action: AssistantAction) -> AssistantDecision {
        decision(for: action.kind)
    }

    /// Whether the names of saved presets may be offered to assistants: only while access is
    /// on (`docs/design/assistant-access.md`, section 8). Factory Defaults, a fixed name, is
    /// always offered.
    public var offersPresetNames: Bool {
        isOn
    }

    /// The saved presets an assistant may see.
    ///
    /// - Parameter saved: The person's saved presets.
    /// - Returns: All of them while access is on; none while it is off.
    public func offeredPresets(_ saved: [SettingsPreset]) -> [SettingsPreset] {
        offersPresetNames ? saved : []
    }
}

/// How a request through ``AssistantSession/perform(_:access:confirm:run:)`` ended.
public enum AssistantGateOutcome<Result> {
    /// Refused: access is off (``AssistantDecision/refuse``). Nothing ran.
    case refused
    /// Refused: the device is locked (``AssistantDecision/requiresUnlock``). Nothing ran.
    case requiresUnlock
    /// Asked, and the person cancelled, dismissed the question or let it time out. Nothing ran.
    case cancelled
    /// The action ran, with its result.
    case ran(Result)
}

/// What happened to one assistant request, for the This Session list.
public enum AssistantRequestResult: Equatable, Sendable {
    /// Asked, and allowed.
    case askedAllowed
    /// Asked, and cancelled.
    case askedCancelled
    /// Ran without asking.
    case ranWithoutAsking
    /// Refused: access was off, or the device was locked.
    case refused
}

/// One line of the This Session list: an action's name and what happened. No values, times or
/// preset names (`docs/design/assistant-access.md`, section 10).
public struct AssistantRequestRecord: Identifiable, Equatable, Sendable {
    /// A number, unique for the process's lifetime.
    public let id: Int
    /// The action.
    public let action: AssistantAction
    /// What happened.
    public let result: AssistantRequestResult

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - id: A unique number.
    ///   - action: The action.
    ///   - result: What happened.
    public init(id: Int, action: AssistantAction, result: AssistantRequestResult) {
        self.id = id
        self.action = action
        self.result = result
    }
}

/// The sentence an assistant got for an action that ran, which the camera shows as a hint
/// ("Siri or Shortcuts", then the sentence).
public struct AssistantNotice: Identifiable, Equatable, Sendable {
    /// A number, unique for the process's lifetime, so a new notice replaces an older one.
    public let id: Int
    /// The sentence, already localized by the app.
    public let sentence: String

    /// Creates a notice.
    ///
    /// - Parameters:
    ///   - id: A unique number.
    ///   - sentence: The sentence.
    public init(id: Int, sentence: String) {
        self.id = id
        self.sentence = sentence
    }
}

/// What assistants did since the app opened, and the one rule-runner every gated entry point
/// uses (issue #82; `docs/design/assistant-access.md`, sections 4, 10 and 11).
///
/// The app owns one session for its lifetime. Each gated App Intent calls
/// ``perform(_:access:confirm:run:)`` inside `perform()`: it reads the check, refuses, asks or
/// goes on, records the request, and runs the existing code. The camera and the Settings page
/// read the record: the hint after an action that ran (``notice``), the card after a refusal
/// (``showsRefusalCard``), the tip after five confirmations (``showsTip``) and the This Session
/// list (``records``).
///
/// Privacy rule (`docs/design/assistant-access.md`, section 10): the record is kept in memory
/// only and cleared when the process ends. It holds an action's name and what happened, never
/// a value, a time or a preset name. The one stored value is the tip's counter, a number that
/// stops at ``tipThreshold``; it is stored outside ``SharedSettingsStore/keyPrefix``, so presets
/// and the Lock Screen camera's snapshot don't carry it.
@MainActor
@Observable
public final class AssistantSession {
    /// The most lines the This Session list keeps.
    nonisolated public static let maximumRecords = 20

    /// The number of confirmed requests after which the tip shows once.
    nonisolated public static let tipThreshold = 5

    /// The store key of the tip's counter.
    nonisolated static let tipCounterKey = "NopeAssistant.confirmedCount"

    /// The requests since the app opened, newest first, at most ``maximumRecords``.
    public private(set) var records: [AssistantRequestRecord] = []

    /// How many requests were refused because access was off since the app opened.
    public private(set) var refusedCount = 0

    /// The refusal count when the person last closed the refusal card.
    private var acknowledgedRefusals = 0

    /// The sentence of the last action that ran, for the camera's hint, or `nil`.
    public private(set) var notice: AssistantNotice?

    /// Whether Open Assistant Access asked for Settings to open at the page, until the camera
    /// screen opens it (``settingsPageOpened()``).
    public private(set) var opensSettingsPage = false

    /// The tip's counter: confirmed requests, up to ``tipThreshold``; one more once the tip was
    /// closed.
    public private(set) var tipCounter: Int

    /// The next unique number for a record or notice.
    private var nextID = 0

    /// Where the tip's counter is stored.
    private let defaults: UserDefaults

    /// Creates an empty session.
    ///
    /// - Parameter defaults: The store for the tip's counter, normally the settings' store.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        tipCounter = min(max(defaults.integer(forKey: Self.tipCounterKey), 0), Self.tipThreshold + 1)
    }

    /// Creates an empty session that stores the tip's counter with the settings.
    ///
    /// - Parameter settings: The person's settings, whose store keeps the counter.
    public convenience init(settings: NopeSettings) {
        self.init(defaults: settings.defaults)
    }

    /// Whether the refusal card shows: a request was refused since the card was last closed.
    public var showsRefusalCard: Bool {
        refusedCount > acknowledgedRefusals
    }

    /// Closes the refusal card until the next refusal.
    public func dismissRefusalCard() {
        acknowledgedRefusals = refusedCount
    }

    /// Whether the tip shows: five requests were confirmed, and the tip wasn't closed yet.
    public var showsTip: Bool {
        tipCounter == Self.tipThreshold
    }

    /// Closes the tip for good.
    public func dismissTip() {
        guard showsTip else { return }
        storeTipCounter(Self.tipThreshold + 1)
    }

    /// Asks the camera screen to open Settings at the Assistant Access page.
    public func requestSettingsPage() {
        opensSettingsPage = true
    }

    /// Records that the camera screen opened the page.
    public func settingsPageOpened() {
        opensSettingsPage = false
    }

    /// Shows a sentence an assistant got, as the camera's hint.
    ///
    /// - Parameter sentence: The sentence, localized.
    public func announce(_ sentence: String) {
        notice = AssistantNotice(id: takeID(), sentence: sentence)
    }

    /// Clears the camera's hint, if it is still this one.
    ///
    /// - Parameter id: The notice shown.
    public func clearNotice(_ id: Int) {
        if notice?.id == id { notice = nil }
    }

    /// Runs one assistant request through the check: refuses, asks or goes on, records it, and
    /// runs the action.
    ///
    /// The check is read when the request starts, and again after a confirmation: access turned
    /// off while the question showed refuses the request. A kind that isn't gated runs without
    /// a record.
    ///
    /// - Parameters:
    ///   - action: The entry point.
    ///   - access: Reads the check now (``NopeSettings/assistantAccess(deviceIsLocked:)``).
    ///   - confirm: Asks the person; `true` when they confirmed. Called only for
    ///     ``AssistantDecision/ask``.
    ///   - run: The existing action.
    /// - Returns: How it ended.
    public func perform<Result>(
        _ action: AssistantAction, access: () -> AssistantAccess, confirm: () async -> Bool,
        run: () async -> Result
    ) async -> AssistantGateOutcome<Result> {
        guard action.isGated else { return .ran(await run()) }
        switch access().decision(for: action) {
        case .refuse:
            return refuse(action)
        case .requiresUnlock:
            record(action, .refused)
            return .requiresUnlock
        case .run:
            record(action, .ranWithoutAsking)
            return .ran(await run())
        case .ask:
            break
        }
        guard await confirm() else {
            record(action, .askedCancelled)
            return .cancelled
        }
        switch access().decision(for: action) {
        case .refuse: return refuse(action)
        case .requiresUnlock:
            record(action, .refused)
            return .requiresUnlock
        case .ask, .run: break
        }
        record(action, .askedAllowed)
        if tipCounter < Self.tipThreshold { storeTipCounter(tipCounter + 1) }
        return .ran(await run())
    }

    /// Records a refusal because access is off, and counts it for the card.
    ///
    /// - Parameter action: The entry point.
    /// - Returns: ``AssistantGateOutcome/refused``.
    private func refuse<Result>(_ action: AssistantAction) -> AssistantGateOutcome<Result> {
        record(action, .refused)
        refusedCount += 1
        return .refused
    }

    /// Adds a line to the This Session list, newest first, keeping at most
    /// ``maximumRecords``.
    ///
    /// - Parameters:
    ///   - action: The entry point.
    ///   - result: What happened.
    private func record(_ action: AssistantAction, _ result: AssistantRequestResult) {
        records.insert(AssistantRequestRecord(id: takeID(), action: action, result: result), at: 0)
        if records.count > Self.maximumRecords { records.removeLast(records.count - Self.maximumRecords) }
    }

    /// Stores the tip's counter.
    ///
    /// - Parameter value: The new value.
    private func storeTipCounter(_ value: Int) {
        tipCounter = value
        defaults.set(value, forKey: Self.tipCounterKey)
    }

    /// The next unique number.
    ///
    /// - Returns: The number.
    private func takeID() -> Int {
        nextID += 1
        return nextID
    }
}

extension ShortcutOutcome {
    /// The "Photos Saved" number a photo action returns beside its sentence, so a shortcut can
    /// branch on it (`docs/design/assistant-access.md`, section 8, decision 9): the photos this
    /// request saved, or 0. Never a file, a format, a lens or a setting.
    public var photosSaved: Int {
        switch self {
        case .saved: 1
        case .savedSeveral(let count, _): count
        case .focusBracketStopped(let saved, _): saved
        default: 0
        }
    }
}
