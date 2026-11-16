import XCTest

/// UI tests for the appearance (owner decision for 0.3.0, "Follow light/dark"): Settings and the
/// screens that aren't the camera follow the system's light or dark setting, as a sheet on iPhone
/// and a popover on iPad; the camera and its own sheets stay dark in both. Night mode, red on
/// black in either setting, is covered in LightAndNightModeUITests and PresetsUITests, which run
/// in the light setting.
extension NopeAppUITests {
    /// The share of sampled pixels in a frame that are light (luminance above the middle), from 0
    /// to 1, or -1 when the screenshot can't be read. The status bar and the home indicator band
    /// are left out. Samples every fourth point.
    ///
    /// - Parameters:
    ///   - app: The app.
    ///   - frame: The frame to sample, or `nil` for the whole window.
    @MainActor
    func lightShare(_ app: XCUIApplication, in frame: CGRect? = nil) -> Double {
        settle()
        let image = XCUIScreen.main.screenshot().image
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return -1 }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        let window = app.windows.firstMatch.frame
        let area = (frame ?? window).intersection(
            CGRect(x: window.minX, y: window.minY + 60, width: window.width, height: window.height - 80))
        var light = 0
        var total = 0
        for y in stride(from: area.minY, to: area.maxY, by: 4) {
            for x in stride(from: area.minX, to: area.maxX, by: 4) {
                let column = min(max(Int(x * image.scale), 0), width - 1)
                let row = min(max(Int(y * image.scale), 0), height - 1)
                let index = (row * width + column) * 4
                let luminance = (299 * Int(bytes[index]) + 587 * Int(bytes[index + 1]) + 114 * Int(bytes[index + 2])) / 1000
                if luminance > 128 { light += 1 }
                total += 1
            }
        }
        return total > 0 ? Double(light) / Double(total) : -1
    }

    /// The frame of the open sheet or popover's navigation bar and the 240 points below it: a
    /// sample of the screen that isn't the camera behind it, on iPhone and iPad alike.
    @MainActor
    func presentedSample(_ app: XCUIApplication, navigationBar title: String) -> CGRect {
        let bar = app.navigationBars[title].frame
        return CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height + 240)
    }

    /// Asserts that a sampled frame is mostly light or mostly dark.
    @MainActor
    func assertAppearance(
        _ app: XCUIApplication, isLight: Bool, in frame: CGRect? = nil, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let share = lightShare(app, in: frame)
        if isLight {
            XCTAssertGreaterThan(share, 0.6, "\(message) isn't light", file: file, line: line)
        } else {
            XCTAssertGreaterThanOrEqual(share, 0, "the screenshot couldn't be read", file: file, line: line)
            XCTAssertLessThan(share, 0.4, "\(message) isn't dark", file: file, line: line)
        }
    }

    /// In the light setting, first run, Settings, a pushed Settings page and Presets are light,
    /// while the camera behind them stays dark; the Settings sheet turns dark when the setting
    /// changes while it is open, and back (the iPad popover keeps its setting while open).
    @MainActor
    func testSettingsAndPresetsFollowTheLightSetting() throws {
        XCUIDevice.shared.appearance = .light
        let app = launch("allow")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        assertAppearance(app, isLight: true, "first run")
        continuePastFirstRun(app)
        assertAppearance(app, isLight: false, "the camera")

        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: true, in: presentedSample(app, navigationBar: "Settings"), "Settings")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Formats")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Formats"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: true, in: presentedSample(app, navigationBar: "Formats"), "Formats")

        // The system setting changes while Settings is open: the iPhone sheet follows; the iPad
        // popover keeps the setting it opened with until it closes.
        XCUIDevice.shared.appearance = .dark
        assertAppearance(
            app, isLight: isPad, in: presentedSample(app, navigationBar: "Formats"),
            isPad ? "the open Formats popover" : "Formats in dark")
        XCUIDevice.shared.appearance = .light
        assertAppearance(app, isLight: true, in: presentedSample(app, navigationBar: "Formats"), "Formats back in light")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        assertAppearance(app, isLight: false, "the camera after Settings")

        quickControl(app, "Presets")
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: true, in: presentedSample(app, navigationBar: "Presets"), "Presets")
        app.buttons["Done"].tap()
    }

    /// Settings opens in the current setting when it changed while only the camera showed (the
    /// window scene then shows the camera's dark, not the system's setting).
    @MainActor
    func testSettingsOpenInTheSettingChangedUnderTheCamera() throws {
        XCUIDevice.shared.appearance = .light
        let app = launch("allow")
        continuePastFirstRun(app)
        let settingsButton = app.buttons["Settings"]
        XCUIDevice.shared.appearance = .dark
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: false, in: presentedSample(app, navigationBar: "Settings"), "Settings in dark")
        app.buttons["Done"].tap()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCUIDevice.shared.appearance = .light
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: true, in: presentedSample(app, navigationBar: "Settings"), "Settings in light")
    }

    /// In the dark setting, first run and Settings are dark.
    @MainActor
    func testSettingsFollowTheDarkSetting() throws {
        XCUIDevice.shared.appearance = .dark
        let app = launch("allow")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        assertAppearance(app, isLight: false, "first run")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: false, in: presentedSample(app, navigationBar: "Settings"), "Settings")
    }

    /// In the light setting, the camera's own sheets stay dark: What's in This Photo, the format
    /// details, the interval settings and Pro Tools.
    @MainActor
    func testCameraSheetsStayDarkInTheLightSetting() throws {
        XCUIDevice.shared.appearance = .light
        let app = launch("allow")
        continuePastFirstRun(app)

        openPhotoDetails(app)
        XCTAssertTrue(app.staticTexts["Files"].waitForExistence(timeout: 5))
        assertAppearance(app, isLight: false, "What's in This Photo")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Photo Format"].waitForExistence(timeout: 5))

        app.buttons["Photo Format"].tap()
        XCTAssertTrue(element(app, containing: "one frame from the sensor").waitForExistence(timeout: 5))
        assertAppearance(app, isLight: false, "the format details")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Photo Format"].waitForExistence(timeout: 5))

        chooseDrive(app, "Interval Shooting")
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        assertAppearance(app, isLight: false, "the interval settings")
        app.buttons["Done"].tap()

        let manual = launch("manual", extraArguments: ["-NopeSettings.showsManualControls", "YES"])
        manualMenu(manual, "Pro Tools")
        XCTAssertTrue(manual.switches["Bracketing"].waitForExistence(timeout: 20))
        assertAppearance(manual, isLight: false, "Pro Tools")
    }

    /// Every Settings screen passes the accessibility audit, contrast included, in the light
    /// setting at the default text size (the Dynamic Type check is in the largest-size runs, as
    /// for the dark setting in ``testSettingsScreensPassAccessibilityAudits()``).
    @MainActor
    func testSettingsScreensPassAccessibilityAuditsInTheLightSetting() throws {
        XCUIDevice.shared.appearance = .light
        let app = launch("allow")
        continuePastFirstRun(app)
        try auditSettingsScreens(app, checksDynamicType: false, checksContrast: !isPad)
    }

    /// Every Settings screen passes the full accessibility audit at the largest text size in the
    /// light setting.
    @MainActor
    func testSettingsAtTheLargestTextSizeInTheLightSetting() throws {
        XCUIDevice.shared.appearance = .light
        let app = launch("denied", extraArguments: Self.largestTextSize)
        XCTAssertTrue(app.staticTexts["Camera Access Is Off"].waitForExistence(timeout: 10))
        try audit(app)
        try auditSettingsScreens(app, checksContrast: !isPad)
    }
}
