#if DEBUG
// Debug-only: an App Store ID for the UI tests of the Rate or Review row on the About screen,
// which is hidden while the app has no id (docs/store/STORE-PAGE-PLAN.md, section 12). Release
// builds always use `AboutScreen.appStoreID`.

import Foundation
import NopeUI
import SwiftUI

/// Reads `-NopeSimulatedAppStoreID <digits>` from the launch arguments; `none` simulates an app
/// with no App Store ID, so the Rate or Review row is hidden.
enum SimulatedAppStore {
    /// The launch argument: `-NopeSimulatedAppStoreID`.
    static let argument = "-NopeSimulatedAppStoreID"

    /// The value after the launch argument, or `nil` without one.
    static var value: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Whether the launch arguments simulate an app with no App Store ID (`none`).
    static var simulatesNoID: Bool { value == "none" }

    /// The App Store ID in the launch arguments, or `nil` without one or with `none`.
    static var appStoreID: String? { simulatesNoID ? nil : value }

    /// Sets the environment's App Store ID to the launch argument's, and leaves it alone
    /// without one.
    struct Override: ViewModifier {
        /// The App Store ID the app has.
        @Environment(\.appStoreID) private var appStoreID

        /// The content, with the launch argument's App Store ID.
        ///
        /// - Parameter content: The content.
        func body(content: Content) -> some View {
            content.environment(\.appStoreID, SimulatedAppStore.simulatesNoID ? nil : (SimulatedAppStore.appStoreID ?? appStoreID))
        }
    }
}
#endif
