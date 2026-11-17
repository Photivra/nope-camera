import Foundation
import Testing

@testable import NopeCore

struct OverlayOptionsTests {
    @Test @MainActor func everyOverlayIsOffByDefaultAndChangesAreSaved() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.overlays == OverlayOptions())
        #expect(!settings.overlays.isAnyOn)
        #expect(settings.overlays.gridStyle == .thirds)

        settings.setShowsGrid(true)
        settings.setGridStyle(.square)
        settings.setShowsLevel(true)
        settings.setShowsFocusPeaking(true)
        settings.setShowsHistogram(true)
        settings.setShowsLiveReadout(true)
        settings.setPinsLiveReadout(true)
        #expect(settings.overlays.isAnyOn)

        let reloaded = NopeSettings(defaults: scratch.defaults).overlays
        #expect(reloaded == settings.overlays)
        #expect(reloaded.showsGrid && reloaded.showsLevel && reloaded.showsFocusPeaking)
        #expect(reloaded.showsHistogram && reloaded.showsLiveReadout && reloaded.pinsLiveReadout)
        #expect(reloaded.gridStyle == .square)
    }

    @Test func theReadoutHidesInCleanViewUnlessPinned() {
        var options = OverlayOptions()
        #expect(!options.pinsLiveReadout)
        #expect(!options.showsLiveReadout(inCleanView: false))
        // Pinned but off: still hidden.
        options.pinsLiveReadout = true
        #expect(!options.showsLiveReadout(inCleanView: true))
        options.showsLiveReadout = true
        #expect(options.showsLiveReadout(inCleanView: true))
        #expect(options.showsLiveReadout(inCleanView: false))
        options.pinsLiveReadout = false
        #expect(!options.showsLiveReadout(inCleanView: true))
        #expect(options.showsLiveReadout(inCleanView: false))
    }

    @Test func eachOptionAloneTurnsTheSummaryOn() {
        let setters: [(inout OverlayOptions) -> Void] = [
            { $0.showsGrid = true }, { $0.showsLevel = true }, { $0.showsFocusPeaking = true },
            { $0.showsHistogram = true }, { $0.showsLiveReadout = true },
        ]
        for set in setters {
            var options = OverlayOptions()
            set(&options)
            #expect(options.isAnyOn)
        }
    }

    @Test func unreadableValuesFallBackToTheDefaults() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("hexagons", forKey: OverlayOptions.Key.gridStyle)
        let options = OverlayOptions(defaults: scratch.defaults)
        #expect(options.gridStyle == .thirds)
    }

    /// Issue #76: the golden ratio and golden spiral grids are removed. A stored setting that
    /// names one reads as thirds, and the spiral's stored placement is dropped on the next save.
    @Test @MainActor func aRemovedGoldenGridReadsAsThirds() {
        #expect(GridStyle.allCases == [.thirds, .fourByFour, .square])
        for removed in ["goldenRatio", "goldenSpiral"] {
            let scratch = ScratchDefaults()
            scratch.defaults.set(true, forKey: OverlayOptions.Key.showsGrid)
            scratch.defaults.set(removed, forKey: OverlayOptions.Key.gridStyle)
            scratch.defaults.set(5, forKey: OverlayOptions.Key.removedSpiralPlacement)
            let settings = NopeSettings(defaults: scratch.defaults)
            #expect(settings.overlays.showsGrid)
            #expect(settings.overlays.gridStyle == .thirds)
            settings.setShowsLevel(true)
            #expect(scratch.defaults.object(forKey: OverlayOptions.Key.removedSpiralPlacement) == nil)
            #expect(scratch.defaults.string(forKey: OverlayOptions.Key.gridStyle) == "thirds")
        }
    }
}

struct GridGeometryTests {
    @Test func thirdsAndQuartersCrossTheWholePicture() {
        let thirds = GridGeometry.lines(for: .thirds, aspectRatio: 0.75)
        #expect(thirds.count == 4)
        #expect(thirds[0] == GuideLine(start: GuidePoint(x: 1.0 / 3.0, y: 0), end: GuidePoint(x: 1.0 / 3.0, y: 1)))
        #expect(thirds[3] == GuideLine(start: GuidePoint(x: 0, y: 2.0 / 3.0), end: GuidePoint(x: 1, y: 2.0 / 3.0)))
        #expect(GridGeometry.lines(for: .fourByFour, aspectRatio: 0.75).count == 6)
    }

    @Test func squareFrameFollowsTheShape() {
        let upright = GridGeometry.lines(for: .square, aspectRatio: 0.75)
        #expect(upright == [
            GuideLine(start: GuidePoint(x: 0, y: 0.125), end: GuidePoint(x: 1, y: 0.125)),
            GuideLine(start: GuidePoint(x: 0, y: 0.875), end: GuidePoint(x: 1, y: 0.875)),
        ])
        let wide = GridGeometry.lines(for: .square, aspectRatio: 2)
        #expect(wide == [
            GuideLine(start: GuidePoint(x: 0.25, y: 0), end: GuidePoint(x: 0.25, y: 1)),
            GuideLine(start: GuidePoint(x: 0.75, y: 0), end: GuidePoint(x: 0.75, y: 1)),
        ])
        #expect(GridGeometry.lines(for: .square, aspectRatio: 1).isEmpty)
        #expect(GridGeometry.lines(for: .square, aspectRatio: 0).isEmpty)
        #expect(GridGeometry.lines(for: .square, aspectRatio: .infinity).isEmpty)
    }
}

struct LevelTests {
    /// Gravity for a device turned clockwise by an angle, held upright.
    static func upright(turnedBy degrees: Double) -> GravityVector {
        let radians = degrees * .pi / 180
        return GravityVector(x: sin(radians), y: -cos(radians), z: 0)
    }

    @Test func horizonTiltIsMeasuredFromTheNearestOrientation() throws {
        var tracker = LevelTracker()
        #expect(tracker.state == nil)
        guard case .horizon(let rotation, let tilt, let isLevel) = tracker.update(Self.upright(turnedBy: 5)) else {
            Issue.record("expected the horizon level")
            return
        }
        #expect(abs(rotation - 5) < 0.001 && abs(tilt - 5) < 0.001 && !isLevel)
        guard case .horizon(_, let sideways, _) = tracker.update(Self.upright(turnedBy: 87)) else {
            Issue.record("expected the horizon level")
            return
        }
        #expect(abs(sideways + 3) < 0.001)
        do { let state = tracker.update(Self.upright(turnedBy: -90.5)); #expect(state.isLevel) }
        #expect(tracker.state?.isLevel == true)
    }

    @Test func levelHasHysteresis() {
        var tracker = LevelTracker()
        do { let state = tracker.update(Self.upright(turnedBy: 1.2)); #expect(!state.isLevel) }
        do { let state = tracker.update(Self.upright(turnedBy: 0.8)); #expect(state.isLevel) }
        // Once level, it stays level until the wider release tolerance.
        do { let state = tracker.update(Self.upright(turnedBy: 1.2)); #expect(state.isLevel) }
        do { let state = tracker.update(Self.upright(turnedBy: 1.6)); #expect(!state.isLevel) }
        do { let state = tracker.update(Self.upright(turnedBy: 1.2)); #expect(!state.isLevel) }
    }

    @Test func pointingDownShowsTheFlatLevel() {
        var tracker = LevelTracker()
        let down = tracker.update(GravityVector(x: 0, y: 0, z: -1))
        #expect(down == .flat(pitchDegrees: 0, rollDegrees: 0, isLevel: true))
        // Top edge raised 10 degrees: gravity tips toward the bottom edge.
        let raised = 10 * Double.pi / 180
        guard case .flat(let pitch, let roll, let isLevel) = tracker.update(
            GravityVector(x: 0, y: -sin(raised), z: -cos(raised)))
        else {
            Issue.record("expected the flat level")
            return
        }
        #expect(abs(pitch - 10) < 0.001 && abs(roll) < 0.001 && !isLevel)
        // 30 degrees from down keeps the flat level once shown (exit at 35), but doesn't start it.
        let thirty = 30 * Double.pi / 180
        let tipped = GravityVector(x: -sin(thirty), y: 0, z: -cos(thirty))
        guard case .flat(_, let tippedRoll, _) = tracker.update(tipped) else {
            Issue.record("expected the flat level")
            return
        }
        #expect(abs(tippedRoll - 30) < 0.001)
        var fresh = LevelTracker()
        guard case .horizon = fresh.update(tipped) else {
            Issue.record("expected the horizon level")
            return
        }
    }

    @Test func noGravityReadsAsAHorizon() {
        var tracker = LevelTracker()
        guard case .horizon = tracker.update(GravityVector(x: 0, y: 0, z: 0)) else {
            Issue.record("expected the horizon level")
            return
        }
    }

    /// A gravity source that sends its readings, then ends.
    struct FixedSource: GravitySource {
        let readings: [GravityVector]
        func gravityUpdates() -> AsyncStream<GravityVector> {
            AsyncStream { continuation in
                for reading in readings { continuation.yield(reading) }
                continuation.finish()
            }
        }
    }

    @Test @MainActor func modelFollowsTheSourceAndClearsWhenItEnds() async {
        let model = LevelModel()
        #expect(model.state == nil)
        await model.run(FixedSource(readings: [Self.upright(turnedBy: 0)]))
        #expect(model.state == nil)
    }

    @Test @MainActor func modelPublishesReadingsWhileRunning() async {
        let (stream, continuation) = AsyncStream.makeStream(of: GravityVector.self)
        struct StreamSource: GravitySource {
            let stream: AsyncStream<GravityVector>
            func gravityUpdates() -> AsyncStream<GravityVector> { stream }
        }
        let model = LevelModel()
        let task = Task { await model.run(StreamSource(stream: stream)) }
        continuation.yield(Self.upright(turnedBy: 0))
        while model.state == nil { await Task.yield() }
        #expect(model.state?.isLevel == true)
        continuation.finish()
        await task.value
        #expect(model.state == nil)
    }
}
