import AppIntents
import NopeCore
import SwiftUI
import UIKit

/// The one helper every gated App Intent calls inside `perform()` (issue #82,
/// `docs/design/assistant-access.md`, section 4): it runs the request through
/// ``AssistantSession/perform(_:access:confirm:run:)``, the check in `NopeCore`, and turns the
/// outcome into the answer. It holds no rule of its own.
///
/// Order, for every gated action: read the check; refuse with the off answer, or ask with the
/// system's question (`requestConfirmation`), or go on; record the request for the session;
/// bring the app on screen if the action needs the camera (``ForegroundMove``); run the existing
/// code. A refused or cancelled request never opens the app and changes nothing. A cancelled
/// question ends with the system's own error, not an answer (owner decision, 2026-11-21,
/// issue #126).
@MainActor
final class AssistantGate {
    /// What assistants did since the app opened, and the check's runner.
    let session: AssistantSession

    /// The person's settings, which hold Assistant Access and Ask First.
    let settings: NopeSettings

    /// Whether the device is locked now.
    let deviceIsLocked: @MainActor () -> Bool

    /// Creates the gate.
    ///
    /// - Parameters:
    ///   - session: The app's session.
    ///   - settings: The person's settings.
    ///   - deviceIsLocked: Whether the device is locked now. The app passes whether protected
    ///     data is unavailable (`UIApplication.isProtectedDataAvailable`).
    init(session: AssistantSession, settings: NopeSettings, deviceIsLocked: @escaping @MainActor () -> Bool) {
        self.session = session
        self.settings = settings
        self.deviceIsLocked = deviceIsLocked
    }

    /// The check now.
    var access: AssistantAccess {
        settings.assistantAccess(deviceIsLocked: deviceIsLocked())
    }

    /// Runs one gated request and gives its answer.
    ///
    /// Errors from the system pass through, as Apple's guidance asks (issue #126): the
    /// question's (`requestConfirmation` throws when the person cancels or dismisses it, or
    /// when the system ends or restarts the run), and the move to the foreground's. The
    /// system says them in its own words; the app never turns them into an answer of its own.
    ///
    /// - Parameters:
    ///   - action: The entry point.
    ///   - question: The question and its button, with the values the action will run with.
    ///   - intent: The intent, which asks the question and moves to the foreground.
    ///   - opensApp: Whether the action needs the camera screen, so the app comes on screen once
    ///     the request is allowed (``moveToForeground(_:)``).
    ///   - run: The existing action: its sentence and the photos it saved.
    /// - Returns: The sentence and the "Photos Saved" number (0 for anything not run).
    /// - Throws: The question's error when it wasn't confirmed; the foreground move's error, or
    ///   the system's "open the app" error with ``AssistantText/openAppAnswer`` when the app
    ///   isn't on screen and the system can't open it from this request.
    func answer(
        _ action: AssistantAction, question: AssistantQuestion, intent: some AppIntent, opensApp: Bool,
        run: () async -> AssistantAnswer
    ) async throws -> AssistantAnswer {
        try await answer(
            action, confirm: { try await Self.confirm(question, with: intent) },
            openApp: { if opensApp { try await Self.moveToForeground(intent) } }, run: run)
    }

    /// Runs one gated request with a given way to ask and to open the app, and gives its answer.
    /// The intents use ``answer(_:question:intent:opensApp:run:)``; Debug builds' simulated
    /// shortcut passes a fixed answer for the question.
    ///
    /// - Parameters:
    ///   - action: The entry point.
    ///   - confirm: Asks the person; returns when they confirmed, throws otherwise.
    ///   - openApp: Brings the app on screen, when the action needs it, once the request is
    ///     allowed; throws when it can't.
    ///   - run: The existing action.
    /// - Returns: The sentence and the "Photos Saved" number (0 for anything not run).
    /// - Throws: What `confirm` or `openApp` threw. Nothing runs after either throws.
    func answer(
        _ action: AssistantAction, confirm: () async throws -> Void, openApp: () async throws -> Void,
        run: () async -> AssistantAnswer
    ) async throws -> AssistantAnswer {
        // The check in NopeCore records a question that wasn't confirmed as cancelled; the
        // system's error is kept to pass on.
        var questionError: (any Error)?
        let outcome = await session.perform(
            action, access: { access },
            confirm: {
                do {
                    try await confirm()
                    return true
                } catch {
                    questionError = error
                    return false
                }
            },
            run: { () async -> Result<AssistantAnswer, any Error> in
                do {
                    try await openApp()
                } catch {
                    return .failure(error)
                }
                return .success(await run())
            })
        switch outcome {
        case .refused: return AssistantAnswer(AssistantText.offAnswer)
        case .requiresUnlock: return AssistantAnswer(AssistantText.unlockAnswer)
        case .cancelled: throw questionError ?? CancellationError()
        case .ran(.failure(let error)): throw error
        case .ran(.success(let answer)):
            session.announce(String(localized: answer.sentence))
            return answer
        }
    }

    /// Brings the app on screen for an action that needs the camera, as ``ForegroundMove``
    /// decides: nothing when the app is already on screen or the intent runs in the foreground;
    /// `continueInForeground` where the system can move the request; otherwise the system's
    /// "open the app" error, with ``AssistantText/openAppAnswer``. Apple's guidance is to check
    /// `canContinueInForeground` first, since `continueInForeground` throws where it can't
    /// (issue #126).
    ///
    /// - Parameter intent: The intent being performed.
    /// - Throws: `continueInForeground`'s error, or `needsToContinueInForegroundError`.
    private static func moveToForeground(_ intent: some AppIntent) async throws {
        let mode = intent.systemContext.currentMode
        let move = ForegroundMove(
            runsInForeground: mode == .foreground,
            // Active, or inactive under Siri: the camera screen is shown and its camera runs.
            appIsOnScreen: UIApplication.shared.applicationState != .background,
            canContinueInForeground: mode.canContinueInForeground)
        switch move {
        case .none:
            return
        case .continueInForeground:
            try await intent.continueInForeground(nil, alwaysConfirm: false)
        case .cannotOpen:
            throw intent.needsToContinueInForegroundError(IntentDialog(AssistantText.openAppAnswer), alwaysConfirm: false)
        }
    }

    /// Asks the system's question (`requestConfirmation`): the sentence, spoken and shown, the
    /// line under it on screen only, and buttons that name the action and Cancel.
    ///
    /// - Parameters:
    ///   - question: The question.
    ///   - intent: The intent that asks.
    /// - Throws: The system's error when the person cancelled or dismissed it, it timed out, or
    ///   the system ended the run. It is passed on, never caught (issue #126).
    nonisolated private static func confirm(_ question: AssistantQuestion, with intent: some AppIntent) async throws {
        try await intent.requestConfirmation(
            actionName: .custom(
                acceptLabel: question.button, acceptAlternatives: [], denyLabel: AssistantText.cancel,
                denyAlternatives: []),
            dialog: IntentDialog(question.question)
        ) {
            AssistantQuestionFooter()
        }
    }
}

/// An answer to an assistant: one sentence, and the number of photos the request saved.
struct AssistantAnswer {
    /// The sentence, said by Siri or shown by Shortcuts.
    let sentence: LocalizedStringResource

    /// The photos this request saved; 0 for anything else.
    let photosSaved: Int

    /// Creates an answer.
    ///
    /// - Parameters:
    ///   - sentence: The sentence.
    ///   - photosSaved: The photos saved.
    init(_ sentence: LocalizedStringResource, photosSaved: Int = 0) {
        self.sentence = sentence
        self.photosSaved = photosSaved
    }

    /// The answer for an inbox outcome.
    ///
    /// - Parameter outcome: How the request ended.
    init(_ outcome: ShortcutOutcome) {
        self.init(ShortcutDialog.message(for: outcome), photosSaved: outcome.photosSaved)
    }
}

/// The question asked before an action: a whole sentence with the action's values, and the
/// button that names the action.
struct AssistantQuestion: Sendable {
    /// The question, spoken and shown.
    let question: LocalizedStringResource

    /// The confirm button.
    let button: LocalizedStringResource
}

/// The fixed sentences of Assistant Access in Siri and Shortcuts (`docs/design/assistant-access.md`,
/// section 15). Drafts for the Honesty review.
enum AssistantText {
    /// The off answer (text 15).
    static let offAnswer = LocalizedStringResource(
        "Assistant Access is off. You can turn it on in nope. › Settings › Privacy.", table: "Honesty",
        comment: "Siri's answer when Assistant Access is off: the action was refused and nothing changed. Assistant Access, Settings and Privacy are names in nope.'s Settings. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")

    /// The answer while the device is locked: the fallback of device check 5.
    static let unlockAnswer = LocalizedStringResource(
        "Unlock this device to use nope.'s actions. Nothing changed.", table: "Honesty",
        comment: "Siri's answer when an action was asked for while the iPhone or iPad is locked; nothing was taken or changed. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")

    /// When an action needs the camera, the app isn't on screen, and the system can't open it
    /// from this request (a voice-only request, for example; issue #126). Nothing was taken or
    /// changed.
    static let openAppAnswer = LocalizedStringResource(
        "Open nope. to do this. Nothing changed.", table: "Honesty",
        comment: "Siri's answer when an action of nope. needs its camera, nope. isn't on screen, and Siri can't open it from this request; nothing was taken or changed. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")

    /// The line under each question (text 17).
    static let whereToChange = LocalizedStringResource(
        "You can change this in nope. › Settings › Privacy.", table: "Honesty",
        comment: "Shown under the question Siri or Shortcuts asks before one of nope.'s actions. Settings and Privacy are names in nope.'s Settings. Keep \"nope.\" unchanged. Draft for the Honesty review.")

    /// The question's cancel button.
    static let cancel = LocalizedStringResource(
        "Cancel", comment: "Button of the question Siri or Shortcuts asks before one of nope.'s actions: nothing runs.")
}

/// The line under each question, on screen only: where the setting is.
nonisolated struct AssistantQuestionFooter: View {
    /// The line.
    var body: some View {
        Text(AssistantText.whereToChange)
            .font(.footnote)
            .padding()
    }
}
