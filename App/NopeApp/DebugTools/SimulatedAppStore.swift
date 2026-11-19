#if DEBUG
// Debug-only: an App Store ID for the UI tests of the Rate or Review row on the About screen,
// which is hidden while the app has no id (docs/store/STORE-PAGE-PLAN.md, section 12). Release
// builds always use `AboutScreen.appStoreID`.

import Foundation
import NopeUI
import SwiftUI

/// Reads `-NopeSimulatedAppStoreID <digits>` from the launch arguments.
enum SimulatedAppStore {
    /// The launch argument: `-NopeSimulatedAppStoreID`.
    static let argument = "-NopeSimulatedAppStoreID"

    /// The App Store ID in the launch arguments, or `nil` without one.
    static var appStoreID: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Sets the environment's App Store ID to the launch argument's, and leaves it alone
    /// without one.
    struct Override: ViewModifier {
        /// The App Store ID the app has.
        @Environment(\.appStoreID) private var appStoreID

        /// The content, with the launch argument's App Store ID.
        ///
        /// - Parameter content: The content.
        func body(content: Content) -> some View {
            content.environment(\.appStoreID, SimulatedAppStore.appStoreID ?? appStoreID)
        }
    }
}
#endif
