#if DEBUG
// Debug-only: lets the UI tests send a Siri or Shortcuts request, which XCTest can't speak or
// run. Compiled only in the Debug configuration.

import Foundation
import NopeCore
import Observation
import SwiftUI

/// Sends a Siri or Shortcuts request through the app's ``ShortcutInbox`` at launch, exactly as
/// the App Intents do, and shows what Siri would say.
///
/// Launch with `-NopeSimulatedShortcut <request>`: a number for Take Photo with that delay in
/// seconds (0 for none), `burst<count>` for Take Photo with a count, `bracket<count>` for Take
/// Bracket with that many frames one stop apart, darkest first (`bracket<count>-metered` or
/// `bracket<count>-brightest` for another order), `lens-ultraWide` for Switch Lens,
/// `preset-factory` for Apply Preset with Factory Defaults, or `interval` for Start Interval
/// Shooting with the interval and count already chosen. Several requests separated by commas
/// are sent one after another, each once the one before has ended; the last one's answer is
/// shown. For example `interval,lens-ultraWide` asks for a lens while a series runs.
///
/// Each request goes through the Assistant Access check (issue #82), as from an App Intent:
/// launch with `-NopeSettings.assistantAccess YES` (and `-NopeSettings.assistantAsk never` to
/// skip the question) for it to run. The question is confirmed unless
/// `-NopeSimulatedAssistantAnswer cancel` is given.
@MainActor
enum SimulatedShortcut {
    /// The launch argument: `-NopeSimulatedShortcut`.
    static let argument = "-NopeSimulatedShortcut"

    /// The requests from the launch arguments, in order; empty when the argument isn't there or
    /// any part of it isn't understood.
    static var requests: [ShortcutRequest] {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return [] }
        let requests = arguments[index + 1].split(separator: ",").map { request(for: String($0)) }
        return requests.contains(nil) ? [] : requests.compactMap { $0 }
    }

    /// The request one part of the argument names.
    ///
    /// - Parameter value: The part, such as `lens-ultraWide`.
    /// - Returns: The request, or `nil` when it isn't understood.
    private static func request(for value: String) -> ShortcutRequest? {
        if let seconds = Int(value) { return .takePhoto(PhotoShortcut(delaySeconds: seconds)) }
        if value.hasPrefix("burst"), let count = Int(value.dropFirst("burst".count)) {
            return .takePhoto(PhotoShortcut(count: count))
        }
        if value.hasPrefix("bracket") {
            let parts = value.dropFirst("bracket".count).split(separator: "-")
            let orders: [String: BracketOrder] = ["metered": .meteredFirst, "brightest": .brightestFirst]
            guard let count = parts.first.flatMap({ Int($0) }) else { return nil }
            let order = parts.dropFirst().first.flatMap { orders[String($0)] } ?? .darkestFirst
            return .takeBracket(BracketShortcut(frameCount: count, step: 1, order: order))
        }
        if value == "preset-factory" { return .applyPreset(.factoryDefaults) }
        if value == "interval" { return .startInterval(IntervalShortcut()) }
        return value == "lens-ultraWide" ? .selectLens(.ultraWide) : nil
    }

    /// What Siri would say, once the request ends.
    @Observable
    final class Result {
        /// The sentence, or `nil` before the request ends.
        var message: String?
    }

    /// The result of this launch's request.
    static let result = Result()

    /// The launch argument that answers the Assistant Access question: `-NopeSimulatedAssistantAnswer
    /// cancel` cancels it; without it, every question is confirmed.
    static let answerArgument = "-NopeSimulatedAssistantAnswer"

    /// Whether the simulated person confirms the question.
    private static var confirms: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: answerArgument), index + 1 < arguments.count else { return true }
        return arguments[index + 1] != "cancel"
    }

    /// The Assistant Access action a request comes from.
    ///
    /// - Parameter request: The request.
    /// - Returns: Its action.
    static func action(for request: ShortcutRequest) -> AssistantAction {
        switch request {
        case .takePhoto: .takePhoto
        case .takeBracket: .takeBracket
        case .selectLens: .switchLens
        case .setLight(let isOn): isOn ? .turnOnLight : .turnOffLight
        case .startInterval: .startInterval
        case .stopInterval: .stopInterval
        case .setFocusRange: .setFocusRange
        case .setPhotoSize: .setPhotoSize
        case .applyPreset: .applyPreset
        }
    }

    /// Sends the requests, if the launch asks for any, each through the Assistant Access check
    /// as the App Intents send them (``AssistantGate``), and records what Siri would say to the
    /// last one. The question is answered by ``answerArgument``.
    ///
    /// - Parameters:
    ///   - inbox: The app's inbox.
    ///   - gate: The Assistant Access check.
    static func run(with inbox: ShortcutInbox, gate: AssistantGate) async {
        let requests = requests
        guard !requests.isEmpty, result.message == nil else { return }
        var answer: AssistantAnswer?
        for request in requests {
            answer = await gate.answer(action(for: request), confirm: { confirms }, openApp: {}) {
                AssistantAnswer(await inbox.submit(request))
            }
        }
        if let answer { result.message = String(localized: answer.sentence) }
    }

    /// Shows what Siri would say, for the UI tests to read.
    struct ResultView: View {
        /// The sentence on a solid background, once the request ends.
        var body: some View {
            if let message = SimulatedShortcut.result.message {
                Text(verbatim: message)
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("SimulatedShortcutResult")
            }
        }
    }
}
#endif
