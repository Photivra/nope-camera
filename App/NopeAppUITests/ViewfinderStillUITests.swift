import XCTest

/// UI test for the Debug-only still viewfinder (`SimulatedViewfinderImage`), used for store
/// screenshots on the Simulator (`docs/store/STORE-PAGE-PLAN.md`, section 5.2, option B). That it
/// isn't in Release builds is checked by `scripts/check-security.sh` (every Debug tool is wrapped
/// in `#if DEBUG`) and by CI's search of the Release binary for `NopeSimulated` strings.
extension NopeAppUITests {
    @MainActor
    func testViewfinderStillReplacesTheSimulatedPicture() throws {
        // A white still, written where the app on the Simulator can read it.
        let still = FileManager.default.temporaryDirectory.appending(path: "viewfinder-still.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
        }
        try XCTUnwrap(image.pngData()).write(to: still)
        defer { try? FileManager.default.removeItem(at: still) }

        let app = launch("photosDenied", extraArguments: ["-NopeSimulatedViewfinderImage", still.path(percentEncoded: false)])
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        settle()
        XCTAssertEqual(centerColor(app, of: app.otherElements["Viewfinder"].frame), .white)

        // Without the argument the picture is the simulated dark gray.
        app.terminate()
        let plain = launch("photosDenied")
        XCTAssertTrue(plain.buttons["Take Photo"].waitForExistence(timeout: 10))
        settle()
        XCTAssertNotEqual(centerColor(plain, of: plain.otherElements["Viewfinder"].frame), .white)
    }
}
