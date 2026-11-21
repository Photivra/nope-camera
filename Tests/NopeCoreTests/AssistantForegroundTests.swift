import Testing

@testable import NopeCore

/// How an allowed Siri or Shortcuts request that needs the camera reaches the screen (issue #126).
struct AssistantForegroundTests {
    @Test(arguments: [true, false])
    func anAppAlreadyOnScreenIsNotMoved(canContinueInForeground: Bool) {
        // With the app open, as in issue #126, the camera screen takes the request as it is,
        // even where the system couldn't move a request to the foreground (a voice request).
        #expect(
            ForegroundMove(runsInForeground: false, appIsOnScreen: true, canContinueInForeground: canContinueInForeground)
                == .none)
    }

    @Test(arguments: [true, false])
    func anIntentInTheForegroundIsNotMoved(appIsOnScreen: Bool) {
        #expect(ForegroundMove(runsInForeground: true, appIsOnScreen: appIsOnScreen, canContinueInForeground: false) == .none)
    }

    @Test func aClosedAppMovesToTheForegroundWhereTheSystemCan() {
        #expect(
            ForegroundMove(runsInForeground: false, appIsOnScreen: false, canContinueInForeground: true)
                == .continueInForeground)
    }

    @Test func aClosedAppThatCanNotBeOpenedSaysSo() {
        #expect(ForegroundMove(runsInForeground: false, appIsOnScreen: false, canContinueInForeground: false) == .cannotOpen)
    }
}
