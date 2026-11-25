#if DEBUG
// Debug-only: lets the watch UI tests run without a paired iPhone, which the watch Simulator
// can't provide to a test. Compiled only in the Debug configuration.

import Foundation
import NopeCore

/// A phone that answers the watch's commands with fixed replies, for the UI tests.
///
/// Launch with `-NopeSimulatedPhone <scenario>`; the scenarios are the cases of ``Scenario``. The
/// replies are encoded with ``WatchMessageCoding``, so the watch decodes them as it does the
/// real phone's.
@MainActor
final class SimulatedPhone: PhoneLink {
    /// The launch argument: `-NopeSimulatedPhone`.
    static let argument = "-NopeSimulatedPhone"

    /// What the simulated phone does. Each case is one state of the watch screen in
    /// docs/design/watch.html.
    enum Scenario: String {
        /// The camera is ready; a photo is saved and signed.
        case ready
        /// The camera is ready; a photo is saved but couldn't be signed, with signing on.
        case notSigned
        /// The camera is ready; a photo is saved and isn't signed, because signing is off in
        /// the phone's settings.
        case notSignedByChoice
        /// The camera is ready; a photo is saved and isn't signed, and the phone doesn't say why
        /// (a phone app from before the reason was sent).
        case notSignedNoReason
        /// The camera is ready; a bracket is saved and every photo is signed.
        case severalSigned
        /// The camera is ready; a bracket is saved and some photos couldn't be signed.
        case severalNotSigned
        /// The camera is ready; a bracket is saved and isn't signed, because signing is off.
        case severalNotSignedByChoice
        /// The camera is ready; the photo isn't saved.
        case notSaved
        /// The camera is ready; the phone is already busy, so nothing is taken.
        case busy
        /// The camera is ready; the phone then takes the photo and doesn't answer with a
        /// result, so the watch keeps waiting.
        case taking
        /// The camera is ready; the phone's reply is in a format this watch can't read.
        case otherVersion
        /// The camera is ready, then stops before the photo, so nothing is taken.
        case becomesUnavailable
        /// The phone never answers, so the watch stays on "Connecting".
        case connecting
        /// The camera isn't running on the phone.
        case notRunning
        /// The phone's app hasn't asked for camera access yet.
        case needsPermission
        /// The phone's camera access is declined.
        case permissionDenied
        /// The phone has no camera the app can use.
        case noCamera
        /// The phone can't be reached.
        case unreachable
        /// The phone's self-timer runs with 10 seconds left; Cancel Timer stops it.
        case countdown
    }

    /// The scenario of this launch.
    let scenario: Scenario

    /// Whether the countdown was cancelled, in the countdown scenario.
    private var isCancelled = false

    /// Creates a simulated phone.
    ///
    /// - Parameter scenario: What it does.
    init(scenario: Scenario) {
        self.scenario = scenario
    }

    /// The simulated phone for the launch arguments, or `nil` when the argument isn't there.
    static func fromLaunchArguments() -> SimulatedPhone? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
            let scenario = Scenario(rawValue: arguments[index + 1])
        else { return nil }
        return SimulatedPhone(scenario: scenario)
    }

    /// Reachable unless the scenario is ``Scenario/unreachable``.
    var isPhoneReachable: Bool {
        scenario != .unreachable
    }

    /// Answers a command as the scenario says.
    ///
    /// - Parameter message: The encoded command.
    /// - Returns: The encoded reply.
    /// - Throws: When the command doesn't decode.
    func send(_ message: Data) async throws -> Data {
        let command = try WatchMessageCoding.decodeCommand(message)
        if scenario == .connecting {
            // The phone never answers: the watch stays on its first status until the test ends.
            try await Task.sleep(for: .seconds(Self.neverAnswers))
        }
        if scenario == .otherVersion, command != .requestStatus {
            return Data(Self.unreadableReply.utf8)
        }
        return WatchMessageCoding.encode(reply(to: command))
    }

    /// Longer than any UI test, in seconds: the time the ``Scenario/connecting`` phone takes to
    /// answer.
    private static let neverAnswers: Double = 3600

    /// A reply no version of the watch app reads, for ``Scenario/otherVersion``.
    private static let unreadableReply = "not a watch message"

    /// The reply to a command.
    ///
    /// - Parameter command: The command.
    /// - Returns: The update.
    private func reply(to command: WatchCommand) -> PhoneUpdate {
        switch (scenario, command) {
        case (.notRunning, .takePhoto): PhoneUpdate(status: .unavailable(.notRunning), result: .notTaken(.notRunning))
        case (.notRunning, _): PhoneUpdate(status: .unavailable(.notRunning))
        case (.needsPermission, _): PhoneUpdate(status: .unavailable(.needsPermission))
        case (.permissionDenied, _): PhoneUpdate(status: .unavailable(.permissionDenied))
        case (.noCamera, _): PhoneUpdate(status: .unavailable(.noCamera))
        case (.countdown, .cancelTimer):
            cancel()
        case (.countdown, _):
            PhoneUpdate(status: isCancelled ? .ready : .countingDown(secondsLeft: 10))
        case (_, .takePhoto): photoResult()
        default: PhoneUpdate(status: .ready)
        }
    }

    /// The reply to Take Photo while the camera is ready.
    ///
    /// - Returns: The update with the scenario's result.
    private func photoResult() -> PhoneUpdate {
        switch scenario {
        case .notSigned: PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .failed)
        case .notSignedByChoice: PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .turnedOff)
        case .notSignedNoReason: PhoneUpdate(status: .ready, result: .saved(isSigned: false))
        case .severalSigned: PhoneUpdate(status: .ready, result: .savedSeveral(allSigned: true))
        case .severalNotSigned: PhoneUpdate(status: .ready, result: .savedSeveral(allSigned: false), unsignedReason: .failed)
        case .severalNotSignedByChoice:
            PhoneUpdate(status: .ready, result: .savedSeveral(allSigned: false), unsignedReason: .turnedOff)
        case .notSaved: PhoneUpdate(status: .ready, result: .notSaved)
        case .busy: PhoneUpdate(status: .ready, result: .busy)
        case .taking: PhoneUpdate(status: .busy)
        case .becomesUnavailable: PhoneUpdate(status: .unavailable(.notRunning), result: .notTaken(.notRunning))
        default: PhoneUpdate(status: .ready, result: .saved(isSigned: true))
        }
    }
    /// Cancels the simulated countdown.
    ///
    /// - Returns: The update after cancelling.
    private func cancel() -> PhoneUpdate {
        isCancelled = true
        return PhoneUpdate(status: .ready, result: .cancelled)
    }
}
#endif
