import NopeCore
import SwiftUI

/// The Photivra Nope Camera app for Apple Watch (issue #63): a remote shutter and delay for the
/// iPhone app.
///
/// The watch takes no photos and runs no timer: it sends commands to the iPhone app over
/// WatchConnectivity (``WatchSessionLink``), and the phone's camera and self-timer do the work.
/// Debug builds launched by the UI tests with `-NopeSimulatedPhone <scenario>` use a simulated
/// phone instead (``SimulatedPhone``).
@main
struct NopeWatchApp: App {
    /// The link to the iPhone app for this launch, created once.
    private static let link = makeLink()

    /// The watch app's model.
    @State private var remote = WatchRemote(link: Self.link)

    /// Whether the app is in the foreground, to ask for the phone's status when it returns.
    @Environment(\.scenePhase) private var scenePhase

    /// The app's single window.
    var body: some Scene {
        WindowGroup {
            RemoteShutterView(remote: remote)
                .task { await connect() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await remote.refresh() } }
                }
        }
    }

    /// Connects the model to the phone: activates WatchConnectivity, or in Debug builds for the
    /// UI tests, asks the simulated phone for its status.
    private func connect() async {
        if let session = Self.link as? WatchSessionLink {
            session.connect(to: remote)
        } else {
            await remote.refresh()
        }
    }

    /// The link for this launch: the simulated phone for a UI test scenario in Debug builds,
    /// otherwise WatchConnectivity.
    @MainActor private static func makeLink() -> any PhoneLink {
        #if DEBUG
        if let simulated = SimulatedPhone.fromLaunchArguments() { return simulated }
        #endif
        return WatchSessionLink()
    }
}
