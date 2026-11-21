import XCTest

/// UI tests for the room around the camera's controls (docs/design/tokens.md, "Spacing";
/// docs/design/screens camera-auto, camera-small, landscape-*, ipad-*, ax-camera): the gap
/// between the picture and the first control row, between the rows, between the items on the
/// picture and its edges, and no two controls overlapping, in portrait, sideways (both ways), on
/// iPad and at the largest text size, each with an accessibility audit.
///
/// The gaps are the design's, in points: 4 (`NopeSpace.xxs`), 8 (`NopeSpace.xs`), 12
/// (`NopeSpace.s`), 6 between the picture and the lens row, half of what the 56-point row leaves
/// around a 44-point control (`CameraLayout.lensRowInset`), and at least 8 between two rows'
/// targets (`NopeSize.targetGap`; issue #116, docs/design/finish-1.0.md, section 1).
extension NopeAppUITests {
    /// `NopeSpace.xs`: items on the picture are inset this far from its edges.
    private static let pictureInset: CGFloat = 8

    /// `CameraLayout.lensRowInset`: the gap above and below the lens row's controls.
    private static let lensRowGap: CGFloat = 6

    /// The gap between the top of the rows and the lens row's controls where the rows overlay
    /// the picture: the lens row's inset less the 2 points the controls move up to keep 8
    /// points from the drive strip (`CameraLayout.lensRowLift(rowGap:)`).
    private static let overlayLensRowGap: CGFloat = 4

    /// The smallest gap between two rows' targets: the lens controls and the drive strip, the
    /// drive strip and the shutter row (`NopeSize.targetGap`, issue #116).
    private static let rowTargetGap: CGFloat = 8

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
    /// below the picture (or, where the rows overlay it, 4 points inside their band); the drive
    /// strip at least 8 points below the lens row; the shutter at least 8 points below the strip;
    /// the manual readouts 8 points inside the picture and above the rows; nothing overlapping.
    @MainActor
    private func assertStackedSpacing(
        _ app: XCUIApplication, _ context: String, isSideways: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) {
        let rows = stackedRows(app)
        let rowsOverlay = rows.lensRow.minY - Self.overlayLensRowGap < rows.picture.maxY - Self.rounding
        if !rowsOverlay {
            assertGap(rows.picture, above: rows.lensRow, atLeast: Self.lensRowGap, "\(context): the lens row touches the picture", file: file, line: line)
        }
        assertGap(rows.lensRow, above: rows.strip, atLeast: Self.rowTargetGap, "\(context): the drive strip touches the lens row", file: file, line: line)
        assertGap(rows.strip, above: rows.shutter, atLeast: Self.rowTargetGap, "\(context): the shutter touches the drive strip", file: file, line: line)
        let format = app.buttons["Photo Format"]
        if format.exists, !isSideways {
            XCTAssertLessThanOrEqual(format.frame.maxY, rows.picture.minY + Self.rounding, "\(context): the status runs onto the picture", file: file, line: line)
        }
        // The visible picture: above the rows where they overlay it.
        var visible = rows.picture
        if rowsOverlay { visible.size.height = rows.lensRow.minY - Self.overlayLensRowGap - visible.minY }
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
            if rows.lensRow.minY - Self.overlayLensRowGap < rows.picture.maxY - Self.rounding { visible.size.height = rows.lensRow.minY - Self.overlayLensRowGap - visible.minY }
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

    // MARK: - The spare height shared between the rows (issue #116)

    /// `NopeSize.minTarget`: the smallest target.
    private static let minTarget: CGFloat = 44

    /// `NopeSize.shutterRowMin`: the shutter row's smallest height.
    private static let shutterRowMin: CGFloat = 88

    /// `CameraLayout.minimumRowGap`, `maximumRowGap`: the row gap's first share and its cap.
    private static let rowGapFirst: CGFloat = 2
    private static let rowGapCap: CGFloat = 24

    /// The status line's height (`NopeSize.statusRow`) at the default text size.
    private static let statusRow: CGFloat = 44

    /// The picture's top edge and the gap between the lens row and the drive strip, by screen
    /// size, from docs/design/finish-1.0.md, 1.3, as measured on the iOS 27.2 Simulators: the
    /// picture is where it was before issue #116, below the safe area's top inset and the status
    /// line. Screens not listed are checked against the rule alone.
    private static let designedRows: [(size: CGSize, pictureTop: CGFloat, rowGap: CGFloat)] = [
        (CGSize(width: 375, height: 667), 64, 0),
        (CGSize(width: 375, height: 812), 94, 0),
        (CGSize(width: 393, height: 852), 103, 2),
        (CGSize(width: 402, height: 874), 106, 4),
        (CGSize(width: 390, height: 844), 91, 5),
        (CGSize(width: 414, height: 896), 92, 11),
        (CGSize(width: 430, height: 932), 103, 12),
        (CGSize(width: 440, height: 956), 106, 15),
        (CGSize(width: 428, height: 926), 91, 15),
    ]

    /// The gap the design gives a spare height (`CameraLayout.rowGap(spareHeight:)`).
    private static func designedRowGap(spareHeight: CGFloat) -> CGFloat {
        guard spareHeight > 0 else { return 0 }
        let rest = max(spareHeight - rowGapFirst, 0) / 3
        return min((min(spareHeight, rowGapFirst) + rest).rounded(.down), rowGapCap)
    }

    /// The frames of every target in the stacked layout's rows, by name.
    @MainActor
    private func stackedTargets(_ app: XCUIApplication) -> (lensRow: [(String, CGRect)], strip: [(String, CGRect)], shutterRow: [(String, CGRect)]) {
        func frames(_ names: [String]) -> [(String, CGRect)] {
            names.map { (name: $0, element: app.buttons[$0].firstMatch) }
                .filter { $0.element.exists && !$0.element.frame.isEmpty }
                .map { ($0.name, $0.element.frame) }
        }
        return (
            frames(["ManualControlsButton", "Ultra Wide", "Wide", "Telephoto", "Switch Camera"]),
            frames(["Single", "Timer", "Burst", "Bracket", "Interval", "Astro"]),
            frames(["openPhotos", "Last Photo", "Take Photo", "quickMenuButton"])
        )
    }

    /// Waits up to ten seconds until the camera has finished appearing: the shutter is drawn at
    /// its full 76 points and its frame stops changing. On a busy Simulator the screen was still
    /// growing into place after the usual pause (a 30 × 15 point Manual Controls button, right
    /// to left on a 402 × 874 point iPhone).
    @MainActor
    private func waitUntilCameraIsInPlace(_ app: XCUIApplication) {
        let shutter = app.buttons["Take Photo"]
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        var last = CGRect.null
        while clock.now < deadline {
            let frame = shutter.exists ? shutter.frame : .null
            if frame.width >= 76 - Self.rounding, frame == last { return }
            last = frame
            _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Camera in place")], timeout: 0.5)
        }
    }

    /// Records the measured rows of the stacked layout with a screenshot, so the run's result
    /// bundle holds the numbers and the picture of each case.
    @MainActor
    private func recordRows(_ app: XCUIApplication, _ context: String, _ summary: String) {
        XCTContext.runActivity(named: "\(context): \(summary)") { activity in
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "spacing \(context)"
            shot.lifetime = .keepAlways
            activity.add(shot)
        }
    }

    /// Checks issue #116's rule in the stacked layout: the picture is the window's width and
    /// 4:3, where it was; every target in the rows is at least 44 points and 8 points from the
    /// targets of the next row; the gap between the lens row and the drive strip is the one
    /// the spare height gives (the design's table where the screen is listed); and the shutter
    /// row takes the rest, with the shutter centered where it has 8 points above it.
    @MainActor
    private func assertRowsShareTheSpareHeight(
        _ app: XCUIApplication, _ context: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let window = app.windows.firstMatch.frame
        let rows = stackedRows(app)
        let targets = stackedTargets(app)
        XCTAssertFalse(targets.lensRow.isEmpty || targets.strip.isEmpty, "\(context): the rows aren't shown", file: file, line: line)
        // The picture keeps its size.
        XCTAssertEqual(rows.picture.minX, window.minX, accuracy: Self.rounding, "\(context): the picture moved sideways", file: file, line: line)
        XCTAssertEqual(rows.picture.width, window.width, accuracy: Self.rounding, "\(context): the picture isn't the window's width", file: file, line: line)
        XCTAssertEqual(rows.picture.height, rows.picture.width * 4 / 3, accuracy: Self.rounding, "\(context): the picture isn't 4:3", file: file, line: line)
        // Every target is at least 44 points, and 8 points from the next row's targets.
        for (name, frame) in targets.lensRow + targets.strip + targets.shutterRow {
            XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), Self.minTarget - Self.rounding, "\(context): \(name) \(frame) is smaller than 44 points", file: file, line: line)
        }
        let lens = targets.lensRow.map(\.1).reduce(CGRect.null) { $0.union($1) }
        let strip = targets.strip.map(\.1).reduce(CGRect.null) { $0.union($1) }
        for (name, frame) in targets.shutterRow {
            assertGap(strip, above: frame, atLeast: Self.rowTargetGap, "\(context): \(name) is closer than 8 points to the drive strip", file: file, line: line)
        }
        assertGap(lens, above: strip, atLeast: Self.rowTargetGap, "\(context): the lens controls are closer than 8 points to the drive strip", file: file, line: line)
        // The shares of the spare height. The shutter row starts at the strip's lower edge. Where
        // the shutter has more than 8 points above it, it is centered in the row, so the row's
        // height, and with it the spare height, follows from where the shutter is; a shorter row
        // moves it down to keep 8 points above it.
        let shutter = rows.shutter
        let aboveShutter = shutter.minY - strip.maxY
        let isCentered = aboveShutter > Self.rowTargetGap + Self.rounding / 2
        // The rows overlay the picture when their top edge, 4 points above the lens controls
        // there, is above the picture's lower edge (on a 5.4-inch iPhone by 4 points).
        let rowsOverlay = lens.minY - Self.overlayLensRowGap < rows.picture.maxY - Self.rounding
        let gap = strip.minY - lens.maxY - Self.lensRowGap
        let shutterRow = 2 * aboveShutter + shutter.height
        let spare = rowsOverlay || !isCentered ? 0 : max(shutterRow - Self.shutterRowMin + gap, 0)
        let summary = String(
            format: "window %.0f × %.0f, picture %.1f to %.1f (%.1f × %.1f), lens controls %.1f to %.1f, drive strip %.1f to %.1f, shutter %.1f to %.1f; lens-to-strip %.1f, strip-to-shutter %.1f, rows %@, spare %@, row gap %.1f",
            window.width, window.height, rows.picture.minY, rows.picture.maxY, rows.picture.width, rows.picture.height, lens.minY,
            lens.maxY, strip.minY, strip.maxY, shutter.minY, shutter.maxY, strip.minY - lens.maxY, shutter.minY - strip.maxY,
            rowsOverlay ? "over the picture" : "below the picture", isCentered ? String(format: "%.1f", spare) : "under 6", max(gap, 0))
        recordRows(app, context, summary)
        if rowsOverlay {
            // No spare height: the lens controls move up 2 points inside the rows instead, and the
            // shutter row is at its smallest with the shutter 8 points below the strip.
            XCTAssertEqual(strip.minY - lens.maxY, Self.rowTargetGap, accuracy: Self.rounding, "\(context): \(summary)", file: file, line: line)
            XCTAssertEqual(shutter.minY - strip.maxY, Self.rowTargetGap, accuracy: Self.rounding, "\(context): \(summary)", file: file, line: line)
        } else {
            assertGap(rows.picture, above: lens, atLeast: Self.lensRowGap, "\(context): the lens row touches the picture", file: file, line: line)
            if isCentered {
                XCTAssertEqual(gap, Self.designedRowGap(spareHeight: spare), accuracy: Self.rounding, "\(context): \(summary)", file: file, line: line)
            }
        }
        let size = CGSize(width: min(window.width, window.height), height: max(window.width, window.height))
        if let designed = Self.designedRows.first(where: { $0.size == size }) {
            XCTAssertEqual(rows.picture.minY, designed.pictureTop, accuracy: Self.rounding, "\(context): the picture moved: \(summary)", file: file, line: line)
            if !rowsOverlay {
                XCTAssertEqual(gap, designed.rowGap, accuracy: Self.rounding, "\(context): not the design's gap: \(summary)", file: file, line: line)
            }
        }
        assertNoOverlap(app, context, file: file, line: line)
    }

    /// Issue #116 on iPhone: the spare height below the picture is shared between the gap under
    /// the lens row and the shutter row; the picture keeps its size and place; every target is 44
    /// points and 8 points from the next row. Checked in full auto, with manual controls on,
    /// sideways both ways, right to left and in night mode, each with an accessibility audit.
    @MainActor
    func testCameraRowsShareTheSpareHeight() throws {
        guard !isPad else { throw XCTSkip("The stacked layout is the iPhone's; testCameraColumnGivesTheShutterRoom checks the column.") }
        let cases: [(name: String, arguments: [String], turns: Bool)] = [
            ("full auto", [], true),
            ("manual", Self.spacingManualOn, false),
            ("right to left", Self.rightToLeft, false),
            ("night mode", ["-NopeSettings.isNightModeOn", "YES"], false),
        ]
        for testCase in cases {
            let app = launch("manual", extraArguments: testCase.arguments)
            XCTAssertTrue(app.buttons["ManualControlsButton"].waitForExistence(timeout: 20))
            settle()
            waitUntilCameraIsInPlace(app)
            assertRowsShareTheSpareHeight(app, testCase.name)
            try audit(app)
            guard testCase.turns else { continue }
            let portraitPicture = app.otherElements["Viewfinder"].frame
            for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
                try turnSideways(app, to: orientation)
                let context = "\(testCase.name), sideways \(orientation.rawValue)"
                XCTAssertEqual(app.otherElements["Viewfinder"].frame, portraitPicture, "\(context): the picture moved when the iPhone turned")
                assertRowsShareTheSpareHeight(app, context)
            }
            XCUIDevice.shared.orientation = .portrait
        }
    }

    /// Issue #116 on iPad (the column layout): in a window at least 600 points tall Q and Last
    /// Photo are 16 points from the shutter, in portrait and landscape, also right to left and in
    /// night mode; the picture is 4:3 and beside the column; nothing overlaps.
    @MainActor
    func testCameraColumnGivesTheShutterRoom() throws {
        guard isPad else { throw XCTSkip("The column layout is checked on iPad.") }
        let cases: [(name: String, arguments: [String])] = [
            ("full auto", []), ("right to left", Self.rightToLeft), ("night mode", ["-NopeSettings.isNightModeOn", "YES"]),
        ]
        for testCase in cases {
            try checkColumnShutterRoom(launch("manual", extraArguments: testCase.arguments), testCase.name)
        }
    }

    /// The column's checks of ``testCameraColumnGivesTheShutterRoom()`` in portrait and landscape.
    @MainActor
    private func checkColumnShutterRoom(_ app: XCUIApplication, _ name: String) throws {
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 30))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.5)
            settle()
            waitUntilCameraIsInPlace(app)
            let context = "iPad \(name) \(orientation.rawValue)"
            let window = app.windows.firstMatch.frame
            let picture = app.otherElements["Viewfinder"].frame
            let quick = app.buttons["quickMenuButton"].frame
            let shutter = app.buttons["Take Photo"].frame
            let photos = app.buttons["openPhotos"].exists ? app.buttons["openPhotos"].frame : app.buttons["Last Photo"].firstMatch.frame
            let gap: CGFloat = window.height >= 600 ? 16 : Self.rowTargetGap
            let summary = String(
                format: "window %.0f × %.0f, picture %.1f × %.1f, Q to shutter %.1f, shutter to Last Photo %.1f", window.width, window.height,
                picture.width, picture.height, shutter.minY - quick.maxY, photos.minY - shutter.maxY)
            recordRows(app, context, summary)
            XCTAssertEqual(shutter.minY - quick.maxY, gap, accuracy: Self.rounding, "\(context): \(summary)")
            XCTAssertEqual(photos.minY - shutter.maxY, gap, accuracy: Self.rounding, "\(context): \(summary)")
            let ratio = max(picture.width, picture.height) / min(picture.width, picture.height)
            XCTAssertEqual(ratio, 4 / 3, accuracy: 0.01, "\(context): the picture isn't 4:3: \(summary)")
            // Beside the column: right to left, the column is on the left.
            let besideColumn = picture.maxX <= quick.minX - Self.pictureInset + Self.rounding || picture.minX >= quick.maxX + Self.pictureInset - Self.rounding
            XCTAssertTrue(besideColumn, "\(context): the picture runs under the column: \(picture), Q \(quick)")
            assertNoOverlap(app, context)
            try audit(app)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Waits until an element is gone.
    @MainActor
    private func waitUntilSpacingGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }
}
