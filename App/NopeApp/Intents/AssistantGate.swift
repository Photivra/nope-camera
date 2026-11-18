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
/// open the app if the action needs the camera (`continueInForeground`); run the existing code.
/// A refused or cancelled request never opens the app and changes nothing.
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
    /// - Parameters:
    ///   - action: The entry point.
    ///   - question: The question and its button, with the values the action will run with.
    ///   - intent: The intent, which asks the question and moves to the foreground.
    ///   - opensApp: Whether the action needs the camera screen, so the app opens once the
    ///     request is allowed.
    ///   - run: The existing action: its sentence and the photos it saved.
    /// - Returns: The sentence and the "Photos Saved" number (0 for anything not run).
    func answer(
        _ action: AssistantAction, question: AssistantQuestion, intent: some AppIntent, opensApp: Bool,
        run: () async -> AssistantAnswer
    ) async -> AssistantAnswer {
        await answer(
            action, confirm: { await Self.confirm(question, with: intent) },
            openApp: {
                // The camera runs only in the foreground. A failure leaves the request to the
                // inbox, which answers that the camera isn't available.
                if opensApp { try? await intent.continueInForeground(nil, alwaysConfirm: false) }
            }, run: run)
    }

    /// Runs one gated request with a given way to ask and to open the app, and gives its answer.
    /// The intents use ``answer(_:question:intent:opensApp:run:)``; Debug builds' simulated
    /// shortcut passes a fixed answer for the question.
    ///
    /// - Parameters:
    ///   - action: The entry point.
    ///   - confirm: Asks the person; `true` when they confirmed.
    ///   - openApp: Opens the app, when the action needs it, once the request is allowed.
    ///   - run: The existing action.
    /// - Returns: The sentence and the "Photos Saved" number (0 for anything not run).
    func answer(
        _ action: AssistantAction, confirm: () async -> Bool, openApp: () async -> Void,
        run: () async -> AssistantAnswer
    ) async -> AssistantAnswer {
        let outcome = await session.perform(
            action, access: { access }, confirm: confirm,
            run: {
                await openApp()
                return await run()
            })
        switch outcome {
        case .refused: return AssistantAnswer(AssistantText.offAnswer)
        case .requiresUnlock: return AssistantAnswer(AssistantText.unlockAnswer)
        case .cancelled: return AssistantAnswer(AssistantText.cancelledAnswer)
        case .ran(let answer):
            session.announce(String(localized: answer.sentence))
            return answer
        }
    }

    /// Asks the system's question (`requestConfirmation`): the sentence, spoken and shown, the
    /// line under it on screen only, and buttons that name the action and Cancel.
    ///
    /// - Parameters:
    ///   - question: The question.
    ///   - intent: The intent that asks.
    /// - Returns: `true` when the person confirmed; `false` when they cancelled or dismissed it,
    ///   or it timed out (the system throws).
    nonisolated private static func confirm(_ question: AssistantQuestion, with intent: some AppIntent) async -> Bool {
        do {
            try await intent.requestConfirmation(
                actionName: .custom(
                    acceptLabel: question.button, acceptAlternatives: [], denyLabel: AssistantText.cancel,
                    denyAlternatives: []),
                dialog: IntentDialog(question.question)
            ) {
                AssistantQuestionFooter()
            }
            return true
        } catch {
            return false
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

    /// After Cancel (text 18).
    static let cancelledAnswer = LocalizedStringResource(
        "Cancelled. Nothing changed.", table: "Honesty",
        comment: "Siri's answer after the person cancelled nope.'s question before an action. Draft for the Honesty review. Must not claim more than the English.")

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
