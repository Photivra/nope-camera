import Foundation
import NopeCore

/// What the watch says for each status and result: the words, an SF Symbol, and whether it is a
/// verified fact (teal) or a warning (amber). Every status has words and a symbol, never color
/// alone (AGENTS.md, "Vision settings").
struct StatusLine: Equatable {
    /// How the message is marked.
    enum Tone: Equatable {
        /// Plain information.
        case plain
        /// A verified fact, such as "Saved and signed": teal.
        case verified
        /// A warning, such as an unsigned photo or a camera that isn't available: amber.
        case warning
    }

    /// The words, localized.
    let text: String

    /// The SF Symbol shown before the words.
    let symbol: String

    /// How the message is marked.
    let tone: Tone
}

extension StatusLine {
    /// The line for photos that aren't all signed: plain, with the information symbol, when
    /// signing is off by choice; otherwise a warning with the triangle. The words are the same
    /// either way and never say the photo is signed (AGENTS.md, "Honesty").
    ///
    /// - Parameters:
    ///   - text: The words, localized.
    ///   - unsignedReason: Why the photos aren't all signed, or `nil` when the phone didn't say.
    init(text: String, unsignedReason: SignatureStatus.UnsignedReason?) {
        let isByChoice = unsignedReason == .turnedOff
        self.init(
            text: text, symbol: isByChoice ? "info.circle" : WatchText.warningSymbol,
            tone: isByChoice ? .plain : .warning)
    }
}

/// The localized words for the watch's display and results.
enum WatchText {
    /// The status line for what the watch shows.
    ///
    /// - Parameter display: What the watch shows.
    /// - Returns: The message.
    static func message(for display: WatchRemote.Display) -> StatusLine {
        switch display {
        case .connecting:
            StatusLine(
                text: String(localized: "Connecting to your phone…", comment: "Watch status while the watch app first reaches nope. on the phone."),
                symbol: "iphone.radiowaves.left.and.right", tone: .plain)
        case .phoneNotReachable:
            StatusLine(
                text: String(localized: "Can't reach your phone. Keep it nearby with nope. open.", comment: "Watch warning: the paired phone can't be reached. Keep \"nope.\" unchanged."),
                symbol: "iphone.slash", tone: .warning)
        case .ready:
            StatusLine(
                text: String(localized: "Camera ready", comment: "Watch status: the phone's camera can take a photo."),
                symbol: "camera", tone: .plain)
        case .countingDown(let seconds):
            StatusLine(text: countdown(seconds), symbol: "timer", tone: .plain)
        case .waiting:
            StatusLine(
                text: String(localized: "Taking photo…", comment: "Watch status: the phone is taking or saving a photo."),
                symbol: "hourglass", tone: .plain)
        case .unavailable(let problem):
            StatusLine(text: text(for: problem), symbol: warningSymbol, tone: .warning)
        }
    }

    /// The result line for the last photo the watch asked for.
    ///
    /// An unsigned result is plain status, with the information symbol, when the phone says
    /// signing is off by choice (``SignatureStatus/UnsignedReason/turnedOff``); it is a warning
    /// when a photo couldn't be signed, or when the phone didn't say why (an older version), as
    /// before (docs/design/BUILD-SPEC.md, 3.13 and section 6, item 6).
    ///
    /// - Parameters:
    ///   - result: How it ended.
    ///   - unsignedReason: Why its photos aren't all signed (``WatchRemote/lastUnsignedReason``),
    ///     or `nil`.
    /// - Returns: The message.
    static func message(for result: WatchResult, unsignedReason: SignatureStatus.UnsignedReason? = nil) -> StatusLine {
        switch result {
        case .saved(isSigned: true):
            StatusLine(
                text: String(localized: "Saved and signed", comment: "Watch result: the photo was saved to Photos on the phone and signed with Content Credentials."),
                symbol: "checkmark.seal", tone: .verified)
        case .saved(isSigned: false):
            StatusLine(
                text: String(localized: "Saved, not signed", comment: "Watch warning: the photo was saved on the phone but isn't signed with Content Credentials."),
                unsignedReason: unsignedReason)
        case .savedSeveral(allSigned: true):
            StatusLine(
                text: String(localized: "Photos saved and signed", comment: "Watch result: a bracket of photos was saved on the phone and every one is signed."),
                symbol: "checkmark.seal", tone: .verified)
        case .savedSeveral(allSigned: false):
            StatusLine(
                text: String(localized: "Photos saved, not all signed", comment: "Watch warning: a bracket of photos was saved on the phone, but some aren't signed."),
                unsignedReason: unsignedReason)
        case .notSaved:
            StatusLine(
                text: String(localized: "Not saved. Your phone shows why.", comment: "Watch warning: the photo wasn't saved; the reason is on the phone's screen."),
                symbol: warningSymbol, tone: .warning)
        case .cancelled:
            StatusLine(
                text: String(localized: "Timer canceled. No photo taken.", comment: "Watch result: the self-timer was cancelled, so no photo was taken."),
                symbol: "timer", tone: .plain)
        case .busy:
            StatusLine(
                text: String(localized: "The camera was busy. No photo taken.", comment: "Watch result: the phone was already taking a photo, counting down or in a burst, so nothing was taken."),
                symbol: "hourglass", tone: .warning)
        case .notTaken:
            StatusLine(
                text: String(localized: "No photo taken.", comment: "Watch result: nothing was taken because the phone's camera wasn't available; the status line says why."),
                symbol: "xmark.circle", tone: .warning)
        case .notUnderstood:
            StatusLine(
                text: String(localized: "Update nope. on your phone and watch.", comment: "Watch warning: the phone and watch apps are different versions. Keep \"nope.\" unchanged."),
                symbol: warningSymbol, tone: .warning)
        }
    }

    /// The warning symbol: a triangle, as on every warning in the app (docs/design/tokens.md,
    /// "Color": warnings only, with a triangle and words).
    static let warningSymbol = "exclamationmark.triangle"

    /// Why the phone's camera can't take a photo.
    ///
    /// - Parameter problem: The reason.
    /// - Returns: The words.
    static func text(for problem: WatchCameraProblem) -> String {
        switch problem {
        case .needsPermission:
            String(localized: "Open nope. on your phone to allow camera access.", comment: "Watch warning: nope. on the phone hasn't asked for camera access yet. Keep \"nope.\" unchanged.")
        case .permissionDenied:
            String(localized: "Camera access is off. Turn it on in your phone's Settings app.", comment: "Watch warning: camera access for nope. is declined on the phone. Settings is the system app.")
        case .noCamera:
            String(localized: "Your phone has no camera nope. can use.", comment: "Watch warning: the phone has no usable camera. Keep \"nope.\" unchanged.")
        case .notRunning:
            String(localized: "Camera not available. Open nope. on your phone.", comment: "Watch warning: the camera isn't running on the phone, for example because nope. isn't open there. Keep \"nope.\" unchanged.")
        }
    }

    /// The countdown, for example "Photo in 3 seconds", with the seconds in the system's unit
    /// format.
    ///
    /// - Parameter seconds: The seconds left.
    /// - Returns: The words.
    static func countdown(_ seconds: Int) -> String {
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))
        return String(localized: "Photo in \(duration)", comment: "Watch status while the phone's self-timer counts down. The placeholder is a duration such as \"3 seconds\".")
    }

    /// The name of a delay in the delay picker: "Off", or a duration such as "3 seconds".
    ///
    /// - Parameter delay: The delay.
    /// - Returns: The words.
    static func name(of delay: WatchDelay) -> String {
        guard delay != .none else {
            return String(localized: "Off", comment: "Watch delay picker: no delay before the photo.")
        }
        return Duration.seconds(delay.seconds).formatted(.units(allowed: [.seconds], width: .wide))
    }
}
