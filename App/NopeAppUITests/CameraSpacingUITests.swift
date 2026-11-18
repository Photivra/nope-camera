import XCTest

/// UI tests for the room around the camera's controls (docs/design/tokens.md, "Spacing";
/// docs/design/screens camera-auto, camera-small, landscape-*, ipad-*, ax-camera): the gap
/// between the picture and the first control row, between the rows, between the items on the
/// picture and its edges, and no two controls overlapping, in portrait, sideways (both ways), on
/// iPad and at the largest text size, each with an accessibility audit.
///
/// The gaps are the design's, in points: 4 (`NopeSpace.xxs`), 8 (`NopeSpace.xs`), 12
/// (`NopeSpace.s`), and 6 around the lens row, half of what the 56-point row leaves around a
/// 44-point control (`CameraLayout.lensRowInset`).
extension NopeAppUITests {
    /// `NopeSpace.xs`: items on the picture are inset this far from its edges.
    private static let pictureInset: CGFloat = 8

    /// `CameraLayout.lensRowInset`: the gap above and below the lens row's controls.
    private static let lensRowGap: CGFloat = 6

    /// The smallest gap between the drive strip and the shutter: half of what the 88-point
    /// shutter row (`NopeSize.shutterRowMin`) leaves around the 76-point shutter.
    private static let shutterRowGap: CGFloat = 6

    /// `NopeSpace.s`: the gap between the rows of the scrolling layout.
    private static let scrollingRowGap: CGFloat = 12

    /// Half a point of rounding in the frames the accessibility tree reports.
    private static let rounding: CGFloat = 1

    /// Manual controls on at launch.
    private static let spacingManualOn = ["-NopeSettings.showsManualControls", "YES"]

    /// The camera's controls, by accessibility identifier or label, that must never overlap.
    private static let controlNames = [
        "Photo Format", "ManualControlsButton", "Ultra Wide", "Wide", "Telephoto", "Switch Camera", "Single", "Timer",
        "Burst", "Interval", "Astro", "Take Photo", "Quick Menu", "Settings", "More Manual Controls",
        "Exposure Compensation", "ISO", "Aperture", "Focus", "White Balance",
    ]

    /// The frames of the controls that are on screen, by name.
    @MainActor
    private func controlFrames(_ app: XCUIApplication) -> [(name: String, frame: CGRect)] {
        let window = app.windows.firstMatch.frame
        return Self.controlNames.compactMap { name in
            let button = app.buttons[name].firstMatch
            guard button.exists, !button.frame.isEmpty, window.intersects(button.frame) else { return nil }
            return (name, button.frame)
        }
    }

    /// Fails when any two controls overlap by more than the rounding.
    @MainActor
    private func assertNoOverlap(_ app: XCUIApplication, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = controlFrames(app)
        for (index, first) in frames.enumerated() {
            for second in frames.dropFirst(index + 1) {
                let overlap = first.frame.intersection(second.frame)
                let overlaps = !overlap.isNull && overlap.width > Self.rounding && overlap.height > Self.rounding
                XCTAssertFalse(overlaps, "\(context): \(first.name) \(first.frame) overlaps \(second.name) \(second.frame)", file: file, line: line)
            }
        }
    }

    /// Fails when `upper` doesn't end at least `gap` points above `lower`.
    private func assertGap(
        _ upper: CGRect, above lower: CGRect, atLeast gap: CGFloat, _ message: String, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            lower.minY - upper.maxY, gap - Self.rounding, "\(message): \(upper) and \(lower)", file: file, line: line)
    }

    /// Fails when the element isn't inside the area inset by `inset` on every side.
    private func assertInside(
        _ frame: CGRect, _ area: CGRect, inset: CGFloat, _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let inner = area.insetBy(dx: inset - Self.rounding, dy: inset - Self.rounding)
        XCTAssertTrue(inner.contains(frame), "\(message): \(frame) isn't \(inset) points inside \(area)", file: file, line: line)
    }

    /// The frames of the stacked layout's rows, top to bottom.
    @MainActor
    private func stackedRows(_ app: XCUIApplication) -> (picture: CGRect, lensRow: CGRect, strip: CGRect, shutter: CGRect) {
        let lensRow = ["ManualControlsButton", "Ultra Wide", "Wide", "Telephoto", "Switch Camera"]
            .map { app.buttons[$0].firstMatch }
            .filter(\.exists)
            .map(\.frame)
            .reduce(CGRect.null) { $0.union($1) }
        let strip = ["Single", "Timer", "Burst", "Interval", "Astro"]
            .map { app.buttons[$0].firstMatch }
            .filter(\.exists)
            .map(\.frame)
            .reduce(CGRect.null) { $0.union($1) }
        return (app.otherElements["Viewfinder"].frame, lensRow, strip, app.buttons["Take Photo"].frame)
    }

    /// Checks the stacked layout's gaps: the status above the picture; the lens row 6 points
    /// below the picture (or, where the rows overlay it, 6 points inside their band); the drive
    /// strip 6 points below the lens row; the shutter at least 6 points below the strip; the
    /// manual readouts 8 points inside the picture and above the rows; nothing overlapping.
    @MainActor
    private func assertStackedSpacing(
        _ app: XCUIApplication, _ context: String, isSideways: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) {
        let rows = stackedRows(app)
        let rowsOverlay = rows.lensRow.minY < rows.picture.maxY
        if !rowsOverlay {
            assertGap(rows.picture, above: rows.lensRow, atLeast: Self.lensRowGap, "\(context): the lens row touches the picture", file: file, line: line)
        }
        assertGap(rows.lensRow, above: rows.strip, atLeast: Self.lensRowGap, "\(context): the drive strip touches the lens row", file: file, line: line)
        assertGap(rows.strip, above: rows.shutter, atLeast: Self.shutterRowGap, "\(context): the shutter touches the drive strip", file: file, line: line)
        let format = app.buttons["Photo Format"]
        if format.exists, !isSideways {
            XCTAssertLessThanOrEqual(format.frame.maxY, rows.picture.minY + Self.rounding, "\(context): the status runs onto the picture", file: file, line: line)
        }
        // The visible picture: above the rows where they overlay it.
        var visible = rows.picture
        if rowsOverlay { visible.size.height = rows.lensRow.minY - Self.lensRowGap - visible.minY }
        let readouts = ["Exposure Compensation", "ISO", "More Manual Controls"].map { app.buttons[$0].firstMatch }.filter(\.exists)
        for readout in readouts {
            assertInside(readout.frame, visible, inset: Self.pictureInset, "\(context): \(readout.label) is too close to the picture's edge", file: file, line: line)
        }
        assertNoOverlap(app, context, file: file, line: line)
    }

    /// Portrait iPhone, in full auto and with manual controls on, and with Q open: every gap is
    /// at least the design's, and nothing overlaps. On a 4.7-inch iPhone the rows overlay the
    /// picture and the readouts stay above them.
    @MainActor
    func testCameraSpacingPortrait() throws {
        guard !isPad else { throw XCTSkip("The stacked layout is the iPhone's; testCameraSpacingOnIPad checks the column.") }
        let app = launch("manual")
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 20))
        settle()
        assertStackedSpacing(app, "full auto")
        try audit(app)
        manual.tap()
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 5))
        settle()
        assertStackedSpacing(app, "manual")
        // Q's panel: 8 points inside the screen's sides and 8 points above the shutter row.
        app.buttons["Quick Menu"].tap()
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        settle()
        let window = app.windows.firstMatch.frame
        let shutter = app.buttons["Take Photo"].frame
        for tile in [hide, app.buttons["Settings"]] {
            // The tiles sit 16 points inside the panel, which is 8 inside the screen.
            XCTAssertGreaterThanOrEqual(tile.frame.minX - window.minX, 3 * Self.pictureInset - Self.rounding, tile.label)
            XCTAssertGreaterThanOrEqual(window.maxX - tile.frame.maxX, 3 * Self.pictureInset - Self.rounding, tile.label)
            assertGap(tile.frame, above: shutter, atLeast: 3 * Self.pictureInset, "Q's panel runs into the shutter row")
        }
        try audit(app)
    }

    /// Sideways, both ways: the picture stays where it is in portrait; the lens row keeps its gap
    /// from the picture (it touched it, with the lenses turned upright, at 0.5× wider than the
    /// row); the shutter keeps its gap from the strip; the turned status, mode name and readouts
    /// stay 8 points inside the picture, above any rows over it; nothing overlaps.
    @MainActor
    func testCameraSpacingSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; testCameraSpacingOnIPad covers it.") }
        let app = launch("manual", extraArguments: Self.spacingManualOn)
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 20))
        settle()
        let portraitPicture = app.otherElements["Viewfinder"].frame
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            try turnSideways(app, to: orientation)
            let context = "sideways \(orientation.rawValue)"
            let rows = stackedRows(app)
            XCTAssertEqual(rows.picture, portraitPicture, "\(context): the picture moved when the iPhone turned")
            assertStackedSpacing(app, context, isSideways: true)
            var visible = rows.picture
            if rows.lensRow.minY < rows.picture.maxY { visible.size.height = rows.lensRow.minY - Self.lensRowGap - visible.minY }
            for element in [app.buttons["Photo Format"].firstMatch, app.staticTexts["Single"].firstMatch] where element.exists {
                assertInside(element.frame, visible, inset: Self.pictureInset, "\(context): \(element.label) is too close to the picture's edge")
            }
            // Text drawn a quarter turn is measured unturned by the audit (see
            // testCameraShellSideways); those findings are skipped here.
            try app.performCompleteAccessibilityAudit { issue in
                guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
                return issue.auditType == .contrast && element.exists && element.frame.height > element.frame.width
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// iPad, portrait and landscape: the column's controls keep 8 points from the picture; the
    /// format status, pills, readouts and drive strip stay 8 points inside it; nothing overlaps;
    /// Q's panel stays inside the picture beside the column.
    @MainActor
    func testCameraSpacingOnIPad() throws {
        guard isPad else { throw XCTSkip("The column layout is checked on iPad.") }
        let app = launch("manual", extraArguments: Self.spacingManualOn)
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 20))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.5)
            settle()
            let context = "iPad \(orientation.rawValue)"
            let picture = app.otherElements["Viewfinder"].frame
            for name in ["Settings", "ManualControlsButton", "Quick Menu", "Take Photo", "Switch Camera", "Wide"] {
                let control = app.buttons[name].firstMatch
                guard control.exists else { continue }
                XCTAssertGreaterThanOrEqual(control.frame.minX - picture.maxX, Self.pictureInset - Self.rounding, "\(context): \(name) is too close to the picture")
            }
            for name in ["Photo Format", "Single", "Astro", "Exposure Compensation", "More Manual Controls"] {
                let item = app.buttons[name].firstMatch
                guard item.exists else { continue }
                assertInside(item.frame, picture, inset: Self.pictureInset, "\(context): \(name) is too close to the picture's edge")
            }
            assertNoOverlap(app, context)
            try audit(app)
            app.buttons["Quick Menu"].tap()
            let hide = app.buttons["Hide Controls"]
            XCTAssertTrue(hide.waitForExistence(timeout: 5))
            settle()
            // The tiles are 16 points inside the panel, which is 8 points from the column and
            // inside the window.
            let column = ["ManualControlsButton", "quickMenuButton"].map { app.buttons[$0].firstMatch.frame.minX }.min() ?? 0
            let panelTiles = hide.frame.union(app.buttons["quick.settings"].frame)
            XCTAssertGreaterThanOrEqual(column - panelTiles.maxX, 3 * Self.pictureInset - Self.rounding, "\(context): Q's panel runs into the column")
            assertInside(panelTiles, app.windows.firstMatch.frame, inset: 3 * Self.pictureInset, "\(context): Q's panel is too close to the window's edge")
            try audit(app)
            app.buttons["Quick Menu"].tap()
            XCTAssertTrue(waitUntilSpacingGone(hide))
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// The largest text size (the scrolling layout, in every window): the rows are 12 points
    /// apart and don't overlap, the picture's neighbors keep 12 points from it, and the pinned
    /// shutter row's Q and shutter don't overlap.
    @MainActor
    func testCameraSpacingAtTheLargestTextSize() throws {
        let app = launch("manual", extraArguments: Self.largestTextSize + Self.spacingManualOn)
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 20))
        settle()
        let picture = app.otherElements["Viewfinder"].frame
        let format = app.buttons["Photo Format"]
        if format.exists {
            assertGap(format.frame, above: picture, atLeast: Self.scrollingRowGap, "the format status touches the picture")
        }
        let quick = app.buttons["Quick Menu"].frame
        let shutter = app.buttons["Take Photo"].frame
        XCTAssertGreaterThanOrEqual(quick.minX - shutter.maxX, Self.pictureInset - Self.rounding, "Q touches the shutter")
        // The rows below the picture, in order, each fully on screen.
        let window = app.windows.firstMatch.frame
        let rows = ["ManualControlsButton", "Ultra Wide", "Wide", "Single", "Timer"]
            .map { app.buttons[$0].firstMatch }
            .filter { $0.exists && window.contains($0.frame) && $0.frame.maxY < quick.minY }
            .map(\.frame)
            .sorted { $0.minY < $1.minY }
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            assertGap(upper, above: lower, atLeast: Self.scrollingRowGap, "two rows are closer than the design's 12 points")
        }
        if let first = rows.first, first.minY > picture.maxY {
            assertGap(picture, above: first, atLeast: Self.scrollingRowGap, "the first row touches the picture")
        }
        try auditScrollingScreen(app, checksContrast: false)
    }

    /// Waits until an element is gone.
    @MainActor
    private func waitUntilSpacingGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }
}
