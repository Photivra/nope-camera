import ActivityKit
import NopeCore
import UIKit

/// Shows the Live Activity with ActivityKit (issue #64), for `LiveActivityCoordinator`.
///
/// Updates are local only: the activity is requested with no push type, so no push token exists
/// and nothing is sent anywhere (AGENTS.md, "No network"). The decisions are in
/// `LiveActivityCoordinator`, which is fully tested; this adapter only calls the system.
@MainActor
final class SystemLiveActivities: LiveActivityPresenting {
    /// The type of the app's one Live Activity.
    private typealias SeriesActivity = Activity<SeriesActivityAttributes>

    /// The identifier of the activity shown now, or `nil`. `Activity` isn't `Sendable`, so each
    /// change looks the activity up by its identifier where it runs.
    private var activityID: String?

    /// The last update or end sent, so the next one runs after it.
    private var pending: Task<Void, Never>?

    /// Ends any activity left from an earlier run of the app, which can no longer be updated:
    /// a series doesn't outlive the app's process.
    /// They are read here, at launch, so an activity this run starts before the change runs is
    /// never ended with them (final review of 1.0.0, minor 7).
    init() {
        let leftovers = Set(SeriesActivity.activities.map(\.id))
        guard !leftovers.isEmpty else { return }
        send { await Self.endLeftovers(leftovers) }
    }

    /// Whether the person allows Live Activities for the app.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Starts the activity.
    ///
    /// - Parameter content: What it shows.
    /// - Returns: Whether the system started it.
    func start(_ content: LiveActivityContent) -> Bool {
        do {
            let activity = try SeriesActivity.request(
                attributes: SeriesActivityAttributes(), content: ActivityContent(state: content, staleDate: nil),
                pushType: nil)
            activityID = activity.id
            return true
        } catch {
            return false
        }
    }

    /// Changes what the activity shows.
    ///
    /// - Parameter content: What it shows now.
    func update(_ content: LiveActivityContent) {
        guard let activityID else { return }
        send { await Self.update(activityID, to: content) }
    }

    /// Ends the activity.
    ///
    /// - Parameters:
    ///   - content: What it shows last.
    ///   - dismissal: When it goes away.
    func end(_ content: LiveActivityContent, dismissal: LiveActivityDismissal) {
        guard let activityID else { return }
        self.activityID = nil
        send { await Self.end(activityID, with: content, dismissal: dismissal) }
    }

    /// Sends a change after the ones before it, with a moment of background time so a change made
    /// as the app leaves the foreground still reaches the system.
    ///
    /// - Parameter change: The change.
    private func send(_ change: @escaping @Sendable () async -> Void) {
        let previous = pending
        let application = UIApplication.shared
        let identifier = application.beginBackgroundTask(withName: "Live Activity")
        pending = Task {
            await previous?.value
            await change()
            if identifier != .invalid { application.endBackgroundTask(identifier) }
        }
    }

    /// Changes what an activity shows.
    ///
    /// - Parameters:
    ///   - id: The activity's identifier.
    ///   - content: What it shows now.
    private nonisolated static func update(_ id: String, to content: LiveActivityContent) async {
        guard let activity = SeriesActivity.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: content, staleDate: nil))
    }

    /// Ends an activity.
    ///
    /// - Parameters:
    ///   - id: The activity's identifier.
    ///   - content: What it shows last.
    ///   - dismissal: When it goes away.
    private nonisolated static func end(
        _ id: String, with content: LiveActivityContent, dismissal: LiveActivityDismissal
    ) async {
        guard let activity = SeriesActivity.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy =
            switch dismissal {
            case .immediate: .immediate
            case .after(let date): .after(date)
            }
        await activity.end(ActivityContent(state: content, staleDate: nil), dismissalPolicy: policy)
    }

    /// Ends the activities left from an earlier run of the app.
    ///
    /// - Parameter ids: Their identifiers, read at launch.
    private nonisolated static func endLeftovers(_ ids: Set<String>) async {
        for activity in SeriesActivity.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Asks iOS for time to finish saving photos after the app leaves the foreground, with
/// `UIApplication.beginBackgroundTask(withName:expirationHandler:)`: a limited extension of the
/// app's run time, not a background mode (AGENTS.md, "Battery").
@MainActor
final class SystemBackgroundTime: BackgroundTimeRequesting {
    /// The open request, or `.invalid`.
    private var identifier = UIBackgroundTaskIdentifier.invalid

    /// Asks for time to finish.
    ///
    /// - Parameter onExpiration: Runs when the time is about to run out.
    /// - Returns: Whether the system gave the time.
    func beginBackgroundTime(onExpiration: @escaping @MainActor () -> Void) -> Bool {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish saving photos") { [weak self] in
            // The system calls this on the main thread.
            MainActor.assumeIsolated {
                onExpiration()
                self?.endBackgroundTime()
            }
        }
        return identifier != .invalid
    }

    /// Gives the time back.
    func endBackgroundTime() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
