import Foundation

/// What an assistant action that needs the camera does to bring the app on screen, once the
/// Assistant Access check allowed it (issue #126).
///
/// Siri and Shortcuts start a gated action in the background mode, so a refused or cancelled
/// request never opens the app (issue #82). The camera runs only while the app is on screen, so
/// an allowed request that needs it either finds the app already there, moves it to the
/// foreground (App Intents' `continueInForeground`), or, where the system can't do that (a
/// voice-only request, for example), ends with a sentence that says to open the app. Apple's
/// guidance is to check `systemContext.currentMode.canContinueInForeground` first, because
/// `continueInForeground` throws where it can't
/// ([Apple: continueInForeground](https://developer.apple.com/documentation/appintents/appintent/continueinforeground(_:alwaysconfirm:))).
///
/// The intent reads the system's values and does what this says; the decision holds no
/// App Intents types, so it is unit tested here.
public enum ForegroundMove: Equatable, Sendable {
    /// The app is already on screen, or the intent already runs in the foreground: the camera
    /// screen takes the request as it is.
    case none

    /// Move the app to the foreground, then hand the request to the camera screen.
    case continueInForeground

    /// The app isn't on screen and the system can't open it from this request. End with the
    /// sentence that says to open the app; nothing is taken.
    case cannotOpen

    /// Decides the move.
    ///
    /// - Parameters:
    ///   - runsInForeground: Whether the intent already runs in the foreground mode
    ///     (`systemContext.currentMode == .foreground`).
    ///   - appIsOnScreen: Whether the app's window is on screen, active or covered by Siri
    ///     (`UIApplication.applicationState` isn't `.background`). The camera keeps running
    ///     then, so moving isn't needed, and a voice request that can't move still works.
    ///   - canContinueInForeground: Whether the system can move this request to the
    ///     foreground (`systemContext.currentMode.canContinueInForeground`).
    public init(runsInForeground: Bool, appIsOnScreen: Bool, canContinueInForeground: Bool) {
        if runsInForeground || appIsOnScreen {
            self = .none
        } else if canContinueInForeground {
            self = .continueInForeground
        } else {
            self = .cannotOpen
        }
    }
}
