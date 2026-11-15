#if DEBUG
// Debug-only: lets the UI tests send a Siri or Shortcuts request, which XCTest can't speak or
// run. Compiled only in the Debug configuration.

import Foundation
import NopeCore
import Observation
import SwiftUI

/// Sends a "Take Photo" request through the app's ``ShortcutInbox`` at launch, exactly as
/// ``TakePhotoIntent`` does, and shows what Siri would say.
///
/// Launch with `-NopeSimulatedShortcut <seconds>`: 0 for no delay, or the delay in seconds.
@MainActor
enum SimulatedShortcut {
    /// The launch argument: `-NopeSimulatedShortcut`.
    static let argument = "-NopeSimulatedShortcut"

    /// The delay from the launch arguments, or `nil` when the argument isn't there.
    static var delaySeconds: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
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
        guard let seconds = delaySeconds, result.message == nil else { return }
        let outcome = await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: seconds)))
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
