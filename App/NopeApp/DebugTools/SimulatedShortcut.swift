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
/// Bracket with that many frames one stop apart, `lens-ultraWide` for Switch Lens, or
/// `preset-factory` for Apply Preset with Factory Defaults.
@MainActor
enum SimulatedShortcut {
    /// The launch argument: `-NopeSimulatedShortcut`.
    static let argument = "-NopeSimulatedShortcut"

    /// The request from the launch arguments, or `nil` when the argument isn't there or isn't
    /// understood.
    static var request: ShortcutRequest? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        if let seconds = Int(value) { return .takePhoto(PhotoShortcut(delaySeconds: seconds)) }
        if value.hasPrefix("burst"), let count = Int(value.dropFirst("burst".count)) {
            return .takePhoto(PhotoShortcut(count: count))
        }
        if value.hasPrefix("bracket"), let count = Int(value.dropFirst("bracket".count)) {
            return .takeBracket(BracketShortcut(frameCount: count, step: 1))
        }
        if value == "preset-factory" { return .applyPreset(.factoryDefaults) }
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

    /// Sends the request, if the launch asks for one, and records what Siri would say.
    ///
    /// - Parameter inbox: The app's inbox.
    static func run(with inbox: ShortcutInbox) async {
        guard let request, result.message == nil else { return }
        let outcome = await inbox.submit(request)
        result.message = String(localized: ShortcutDialog.message(for: outcome))
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
