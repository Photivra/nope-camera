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

    /// What the simulated phone does.
    enum Scenario: String {
        /// The camera is ready; a photo is saved and signed.
        case ready
        /// The camera is ready; a photo is saved but not signed.
        case notSigned
        /// The camera isn't running on the phone.
        case notRunning
        /// The phone's camera access is declined.
        case permissionDenied
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
        return WatchMessageCoding.encode(reply(to: command))
    }

    /// The reply to a command.
    ///
    /// - Parameter command: The command.
    /// - Returns: The update.
    private func reply(to command: WatchCommand) -> PhoneUpdate {
        switch (scenario, command) {
        case (.notRunning, .takePhoto): PhoneUpdate(status: .unavailable(.notRunning), result: .notTaken(.notRunning))
        case (.notRunning, _): PhoneUpdate(status: .unavailable(.notRunning))
        case (.permissionDenied, _): PhoneUpdate(status: .unavailable(.permissionDenied))
        case (.countdown, .cancelTimer):
            cancel()
        case (.countdown, _):
            PhoneUpdate(status: isCancelled ? .ready : .countingDown(secondsLeft: 10))
        case (_, .takePhoto): PhoneUpdate(status: .ready, result: .saved(isSigned: scenario == .ready))
        default: PhoneUpdate(status: .ready)
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
