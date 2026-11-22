import AppIntentsTesting
import XCTest

/// These tests are their own UI test target, `NopeAppIntentsUITests`: `AppIntentsTesting` needs
/// iOS 27 (it links `AppIntentsTypeSupport`, which iOS 26 doesn't have), and a test bundle that
/// links it can't be loaded on an iOS 26 Simulator at all, so in the main UI test bundle it
/// stopped every UI test there ("Failed to load the test bundle").
///
/// Take Photo run the way Siri and Shortcuts run it (issue #126): out of process, through the
/// system's App Intents runner (`AppIntentsTesting`, iOS 27), against the installed app. Unlike
/// `ShortcutUITests`, which send the request through the Debug-only `-NopeSimulatedShortcut`
/// argument inside the app, this goes through `perform()`, the Assistant Access check, the
/// system's question (which the runner confirms) and the move to the foreground.
///
/// The runner refuses an app built without code signing ("Unable to run internal tests on a
/// Customer build"), so run these with signing on (docs/TESTING.md, "Siri and Shortcuts in the
/// UI tests"); in an unsigned build they are skipped. Speech can't be tested here: the phrases
/// are a device check.
@available(iOS 27.0, *)
final class TakePhotoIntentUITests: XCTestCase {
    /// The app's actions, by the bundle identifier of the app under test.
    static let definitions = IntentDefinitions(bundleIdentifier: "com.photivra.nope.dev")

    /// How often a run is tried while the system hasn't indexed the just-installed app yet.
    static let attempts = 5

    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens the app on the camera screen with a simulated camera, signing on, and Assistant
    /// Access set as given.
    ///
    /// - Parameters:
    ///   - access: Whether Assistant Access is on.
    ///   - ask: The Ask First choice (`never`, `beforePhoto` or `everyAction`).
    /// - Returns: The app.
    @MainActor
    func openCamera(access: Bool, ask: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-NopeSimulatedCamera", "noRAW", "-NopeSimulatedSigning",
            "-NopeSettings.assistantAccess", access ? "YES" : "NO", "-NopeSettings.assistantAsk", ask,
        ]
        // As `launchAfterThePreviousRunExits()` in the main UI tests: a launch right after a
        // terminate sometimes waited out XCTest's minute for a process ID.
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 30)
        }
        app.launch()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 30))
        return app
    }

    /// The "Photos Saved" number of a run, skipping the test when the runner refused an
    /// unsigned build (`AppIntentsServicesSecurityErrorDomain` 803).
    ///
    /// - Parameter result: The run's result.
    /// - Returns: The number of photos saved.
    /// - Throws: `XCTSkip` for an unsigned build; the run's error otherwise.
    static func photosSaved(_ result: Result<Int, any Error>) throws -> Int {
        if case .failure(let error as NSError) = result,
            error.domain == "AppIntentsServicesSecurityErrorDomain", error.code == 803
        {
            throw XCTSkip("The App Intents runner needs a signed build: \(error.localizedDescription)")
        }
        return try result.get()
    }

    /// Runs Take Photo and gives its "Photos Saved" number, or the error the run threw.
    ///
    /// Right after an install the system's index may not list the app yet
    /// (`AppIntentsServicesMetadataErrorDomain` 400, "is not present"); that error is retried.
    ///
    /// - Parameter delay: The Custom Delay in seconds, or `nil` for none.
    /// - Returns: The number of photos saved, or the error.
    static func takePhoto(customDelaySeconds delay: Int? = nil) async -> Result<Int, any Error> {
        let intent = definitions.intents["TakePhotoIntent"]
        var last: (any Error)?
        for _ in 0..<attempts {
            do {
                let run =
                    if let delay {
                        try await intent.makeIntent(customDelaySeconds: delay).run()
                    } else {
                        try await intent.makeIntent().run()
                    }
                let saved: Int = try run.value
                return .success(saved)
            } catch let error as NSError where error.domain == "AppIntentsServicesMetadataErrorDomain" && error.code == 400 {
                last = error
                try? await Task.sleep(for: .seconds(2))
            } catch {
                return .failure(error)
            }
        }
        return .failure(last ?? CancellationError())
    }

    @MainActor
    func testWithAccessOffNothingIsTakenAndNoErrorIsThrown() async throws {
        // The off answer is a result, not a failure: Siri says it instead of its generic error.
        _ = openCamera(access: false, ask: "everyAction")
        let result = await Self.takePhoto()
        let saved = try Self.photosSaved(result)
        XCTAssertEqual(saved, 0, "\(result)")
    }

    @MainActor
    func testWithAccessOnAndNoQuestionOnePhotoIsSaved() async throws {
        _ = openCamera(access: true, ask: "never")
        let result = await Self.takePhoto()
        let saved = try Self.photosSaved(result)
        XCTAssertEqual(saved, 1, "\(result)")
    }

    @MainActor
    func testWithEveryActionTheConfirmedQuestionSavesOnePhoto() async throws {
        _ = openCamera(access: true, ask: "everyAction")
        let result = await Self.takePhoto()
        let saved = try Self.photosSaved(result)
        XCTAssertEqual(saved, 1, "\(result)")
    }

    @MainActor
    func testALongDelayIsAnsweredWhenTheTimerStarts() async throws {
        // Before the fix, a 40-second delay ended with the system's timeout after 31 seconds
        // (LNConnectionErrorDomain 1014), which Siri says as its generic error.
        let app = openCamera(access: true, ask: "never")
        let start = ContinuousClock.now
        let result = await Self.takePhoto(customDelaySeconds: 40)
        let saved = try Self.photosSaved(result)
        XCTAssertEqual(saved, 0, "\(result)")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(25))
        // The self-timer runs on the camera, as from the shutter; cancelling it ends the test.
        let cancel = app.buttons["Cancel Timer"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
    }

    @MainActor
    func testWithTheAppClosedTheRequestEndsWithAResult() async throws {
        // The system starts the app for the request. The launch arguments don't reach that
        // launch, so the stored settings apply (Assistant Access off on a fresh install) and the
        // answer is the off answer: a result, not an error. The move to the foreground from a
        // closed app, with access on, is a device check (docs/TESTING.md, "Siri on a device").
        let app = openCamera(access: false, ask: "never")
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 30)
        let result = await Self.takePhoto()
        let saved = try Self.photosSaved(result)
        XCTAssertEqual(saved, 0, "\(result)")
    }
}
