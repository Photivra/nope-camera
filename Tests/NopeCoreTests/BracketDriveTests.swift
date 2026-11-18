import Foundation
import Testing

@testable import NopeCore

/// The order of a bracket's frames (docs/design/BRACKETING.md, section 4).
struct BracketOrderTests {
    @Test func offsetsInEachOrder() {
        let expected: [BracketOrder: [Int: [Double]]] = [
            .darkestFirst: [3: [-1, 0, 1], 5: [-2, -1, 0, 1, 2], 7: [-3, -2, -1, 0, 1, 2, 3]],
            .meteredFirst: [3: [0, -1, 1], 5: [0, -1, 1, -2, 2], 7: [0, -1, 1, -2, 2, -3, 3]],
            .brightestFirst: [3: [1, 0, -1], 5: [2, 1, 0, -1, -2], 7: [3, 2, 1, 0, -1, -2, -3]],
        ]
        for order in BracketOrder.allCases {
            for count in BracketSettings.frameCounts {
                let settings = BracketSettings(frameCount: count, step: 1, order: order)
                #expect(settings.offsets == expected[order]?[count], "\(order) \(count)")
            }
        }
        #expect(BracketSettings(frameCount: 3, step: 2, order: .meteredFirst).offsets == [0, -2, 2])
    }

    @Test func darkestFirstIsTheDefaultAndTheStandardBracket() {
        #expect(BracketSettings(frameCount: 3, step: 1).order == .darkestFirst)
        #expect(BracketSettings.standard == BracketSettings(frameCount: 3, step: 1, order: .darkestFirst))
    }

    @Test func aCopyChangesOneValue() {
        let settings = BracketSettings(frameCount: 5, step: 2, order: .brightestFirst)
        #expect(settings.with() == settings)
        #expect(settings.with(frameCount: 3) == BracketSettings(frameCount: 3, step: 2, order: .brightestFirst))
        #expect(settings.with(step: 1) == BracketSettings(frameCount: 5, step: 1, order: .brightestFirst))
        #expect(settings.with(order: .meteredFirst) == BracketSettings(frameCount: 5, step: 2, order: .meteredFirst))
    }

    @Test func theOrderIsStoredByName() throws {
        let data = try JSONEncoder().encode(BracketOrder.meteredFirst)
        #expect(String(decoding: data, as: UTF8.self) == "\"meteredFirst\"")
        #expect(BracketType.exposure.rawValue == "exposure")
    }
}

/// The frames a bracket plans, as Bracket Settings lists them, with the limited ones marked.
struct BracketFramePlanTests {
    @Test func framesWithinTheRangesReachTheirOffsets() {
        let plans = BracketFramePlan.plan(
            offsets: [0, -1, 1], base: BracketFrame(iso: 100, exposureDuration: 0.01), shutterFirst: true,
            isoRange: 50...800, durationRange: 0.001...1)
        #expect(plans.map(\.number) == [1, 2, 3])
        #expect(plans.map(\.frame.exposureDuration) == [0.01, 0.005, 0.02])
        #expect(plans.allSatisfy { !$0.isLimited && $0.limit == nil && $0.limitingFrameNumber == nil })
        #expect(plans.map(\.offset) == [0, -1, 1])
    }

    @Test func aFrameTheLensCantMakeBrighterIsMarked() {
        // Shutter first: the shutter stops at 1 s, ISO stops at 800: +2 EV is as bright as it gets.
        let plans = BracketFramePlan.plan(
            offsets: [0, -2, 2, -4, 4], base: BracketFrame(iso: 200, exposureDuration: 1), shutterFirst: true,
            isoRange: 50...800, durationRange: 0.001...1)
        #expect(plans[2].offset == 2)
        #expect(!plans[2].isLimited)
        #expect(plans[4].isLimited)
        #expect(plans[4].requestedOffset == 4)
        #expect(plans[4].offset == 2)
        #expect(plans[4].limit == .brightest)
        #expect(plans[4].limitingFrameNumber == 3)
        #expect(plans[4].frame == BracketFrame(iso: 800, exposureDuration: 1))
    }

    @Test func aFrameTheLensCantMakeDarkerIsMarked() {
        // ISO first: ISO stops at 50, the shutter at 1/1000 s.
        let plans = BracketFramePlan.plan(
            offsets: [-3, 0], base: BracketFrame(iso: 100, exposureDuration: 0.002), shutterFirst: false,
            isoRange: 50...800, durationRange: 0.001...1)
        #expect(plans[0].isLimited)
        #expect(plans[0].limit == .darkest)
        // The first frame with that exposure is the frame itself.
        #expect(plans[0].limitingFrameNumber == 1)
        #expect(abs(plans[0].offset - -2) < 0.0001)
        #expect(!plans[1].isLimited)
    }

    @Test func progressSaysWhetherFramesAreBeingTaken() {
        #expect(BracketProgress(taken: 0, saved: 0, total: 3).isTaking)
        #expect(!BracketProgress(taken: 3, saved: 1, total: 3).isTaking)
    }
}

/// A library that records the camera's bracket progress each time a photo is added.
actor ProgressRecordingLibrary: PhotoLibrary {
    private let read: @MainActor @Sendable () -> BracketProgress?
    private(set) var seen: [BracketProgress?] = []

    init(read: @escaping @MainActor @Sendable () -> BracketProgress?) {
        self.read = read
    }

    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        let progress = await read()
        seen.append(progress)
    }
}

/// Holds a model for a library created before it.
@MainActor
final class BracketModelBox {
    var model: CameraModel?
}

/// Bracket as a drive choice: full auto, the drive modes, the lens, the progress and each
/// photo's place (docs/design/BRACKETING.md, sections 3 and 7).
@MainActor
struct CameraModelBracketTests {
    typealias Fixtures = ManualFixtures

    /// A started camera that has reported an exposure, with manual controls off.
    func makeModel(
        lenses: [Lens] = [Fixtures.wide, Fixtures.basicLens, Fixtures.bare], saver: PhotoSaver? = CameraModelTests.saver()
    ) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: lenses)
        let model = CameraModel(backend: backend, saver: saver, sleep: { _ in })
        await model.send(.start)
        await model.manual.record(Fixtures.reading)
        return (model, backend)
    }

    @Test func aBracketIsTakenInFullAutoAroundTheReading() async throws {
        let (model, backend) = await makeModel()
        #expect(!model.manual.isEnabled)
        #expect(model.manual.bracketPlan == nil)
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1, order: .meteredFirst))))
        #expect(model.isBracketOn)
        let plan = try #require(model.manual.bracketPlan)
        #expect(plan.map(\.frame.exposureDuration) == [0.01, 0.005, 0.02])
        await model.send(.capture)
        let frames = try #require(await backend.brackets.first)
        // The Frames list equals what is taken.
        #expect(frames == plan.map(\.frame))
        guard case .savedBracket(let photos) = model.captureStatus else {
            Issue.record("expected a saved bracket")
            return
        }
        #expect(photos.count == 3)
        #expect(photos.compactMap(\.bracket?.frame.number) == [1, 2, 3])
        #expect(photos.compactMap(\.bracket?.frame.offset) == [0, -1, 1])
        #expect(photos.allSatisfy { $0.bracket?.count == 3 && $0.bracket?.offsets == [0, -1, 1] })
        #expect(photos.allSatisfy { $0.bracket?.order == .meteredFirst && $0.bracket?.type == .exposure })
        #expect(model.bracketProgress == nil)
        #expect(model.failedBracket == nil)
    }

    @Test func eachOrderTakesTheFramesInThatOrder() async throws {
        let (model, backend) = await makeModel()
        for order in BracketOrder.allCases {
            await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1, order: order))))
            await model.send(.capture)
        }
        let durations = await backend.brackets.map { $0.map(\.exposureDuration) }
        #expect(durations == [[0.005, 0.01, 0.02], [0.01, 0.005, 0.02], [0.02, 0.01, 0.005]])
    }

    @Test func manualISOChangesTheShutterAndAManualShutterChangesISO() async throws {
        let (model, _) = await makeModel()
        await model.send(.manual(.setEnabled(true)))
        // Turning Manual Controls on forgets the last reading (`resetReadingAids()`); the
        // camera reports the next one.
        await model.manual.record(Fixtures.reading)
        await model.send(.manual(.setBracket(.standard)))
        #expect(!model.manual.bracketChangesISOFirst)
        await model.send(.manual(.setValue(.shutter, 0.01)))
        #expect(model.manual.bracketChangesISOFirst)
        #expect(try #require(model.manual.bracketPlan).map(\.frame.iso) == [100, 200, 400])
    }

    @Test func progressIsPublishedWhileSaving() async throws {
        let box = BracketModelBox()
        let library = ProgressRecordingLibrary { box.model?.bracketProgress }
        let backend = ScriptedManualBackend(lenses: [Fixtures.wide])
        let recorded = CameraModel(
            backend: backend,
            saver: PhotoSaver(
                developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: library, appVersion: "0.2.0"))
        box.model = recorded
        await recorded.send(.start)
        await recorded.manual.record(Fixtures.reading)
        await recorded.send(.manual(.setBracket(.standard)))
        await recorded.send(.capture)
        #expect(
            await library.seen == [
                BracketProgress(taken: 3, saved: 0, total: 3), BracketProgress(taken: 3, saved: 1, total: 3),
                BracketProgress(taken: 3, saved: 2, total: 3),
            ])
        #expect(recorded.bracketProgress == nil)
    }

    @Test func aFrameNotSavedSaysHowManyWere() async {
        let (model, _) = await makeModel(saver: CameraModelTests.saver(library: FakeLibrary(error: .saveFailed, failsAfter: 2)))
        await model.send(.manual(.setBracket(.standard)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.saveFailed))
        #expect(model.failedBracket == BracketProgress(taken: 3, saved: 2, total: 3))
        // The next capture starts afresh.
        await model.send(.manual(.setBracket(nil)))
        await model.send(.capture)
        #expect(model.failedBracket == nil)
    }

    @Test func aFailedRequestSavesNothingAndIsNotAShortfall() async {
        let backend = ScriptedManualBackend(lenses: [Fixtures.wide], bracketError: .captureFailed)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        await model.manual.record(Fixtures.reading)
        await model.send(.manual(.setBracket(.standard)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.captureFailed))
        #expect(model.failedBracket == nil)
        #expect(model.bracketProgress == nil)
    }

    @Test func burstAndIntervalTurnTheBracketOff() async {
        let (model, _) = await makeModel()
        for mode in [DriveMode.burst, .interval] {
            await model.send(.manual(.setBracket(.standard)))
            await model.send(.drive(.setMode(mode)))
            #expect(model.manual.bracket == nil, "\(mode)")
            #expect(!model.isBracketOn)
        }
        // Without a bracket, choosing a mode changes nothing else.
        await model.send(.drive(.setMode(.single)))
        #expect(model.bracketStartDelay == nil)
    }

    @Test func singleAndTheTimerAreTheBracketsStartDelay() async {
        let (model, _) = await makeModel()
        await model.send(.manual(.setBracket(.standard)))
        #expect(model.bracketDriveMode == .single)
        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        #expect(model.manual.bracket == .standard)
        #expect(model.bracketStartDelay == .threeSeconds)
        #expect(model.bracketDriveMode == .timer(.threeSeconds))
        await model.send(.drive(.setMode(.single)))
        #expect(model.bracketStartDelay == nil)
        #expect(model.bracketDriveMode == .single)
    }

    @Test func turningABracketOnKeepsAModeItCanUse() async {
        let (model, _) = await makeModel()
        await model.send(.drive(.setMode(.burst)))
        await model.send(.manual(.setBracket(.standard)))
        #expect(model.drive.mode == .single)
        #expect(model.bracketStartDelay == nil)
        await model.send(.manual(.setBracket(nil)))
        await model.send(.drive(.setMode(.interval)))
        await model.send(.manual(.setBracket(.standard)))
        #expect(model.drive.mode == .single)
        await model.send(.manual(.setBracket(nil)))
        await model.send(.drive(.setMode(.timer(.tenSeconds))))
        await model.send(.manual(.setBracket(.standard)))
        #expect(model.drive.mode == .timer(.tenSeconds))
        #expect(model.bracketStartDelay == .tenSeconds)
        // Another intent leaves the mode alone.
        await model.send(.manual(.setBracket(nil)))
        #expect(model.drive.mode == .timer(.tenSeconds))
    }

    @Test func aBracketWithAStartDelayCountsDownFirst() async {
        let (model, backend) = await makeModel()
        await model.send(.manual(.setBracket(.standard)))
        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        await model.send(.capture)
        while model.drive.countdown.isRunning || model.captureStatus == .capturing || model.captureStatus == .saving {
            await Task.yield()
        }
        #expect(await backend.brackets.count == 1)
    }

    @Test func theLastBracketIsKeptAndFittedToTheLens() async {
        let (model, _) = await makeModel()
        #expect(model.manual.lastBracket == .standard)
        #expect(model.bracketToTurnOn == .standard)
        let five = BracketSettings(frameCount: 5, step: 2, order: .brightestFirst)
        await model.send(.manual(.setBracket(five)))
        await model.send(.manual(.setBracket(nil)))
        #expect(model.manual.lastBracket == five)
        #expect(model.bracketToTurnOn == five)
        // The basic lens takes at most 3 frames.
        await model.send(.selectLens("basic"))
        #expect(model.bracketToTurnOn == five.with(frameCount: 3))
        await model.send(.selectLens("bare"))
        #expect(model.bracketToTurnOn == nil)
    }

    @Test func aLensThatCantBracketChoosesSingle() async {
        let (model, _) = await makeModel()
        await model.send(.manual(.setBracket(.standard)))
        await model.send(.drive(.setMode(.timer(.tenSeconds))))
        await model.send(.selectLens("basic"))
        #expect(model.manual.bracket == .standard)
        #expect(model.drive.mode == .timer(.tenSeconds))
        await model.send(.selectLens("bare"))
        #expect(model.manual.bracket == nil)
        #expect(model.drive.mode == .single)
        // Without a bracket, a lens change leaves the mode alone.
        await model.send(.drive(.setMode(.burst)))
        await model.send(.selectLens("wide"))
        #expect(model.drive.mode == .burst)
    }

    @Test func anIntervalSeriesNeverTakesABracket() async {
        let (model, backend) = await makeModel()
        await model.send(.manual(.setBracket(.standard)))
        await model.send(.manual(.setInterval(IntervalSettings(interval: 1, count: 2))))
        await model.send(.manual(.startInterval))
        while model.manual.intervalProgress != nil { await Task.yield() }
        #expect(await backend.captureCount == 2)
        #expect(await backend.brackets.isEmpty)
    }
}

/// Presets and Take Bracket with the order (docs/design/BRACKETING.md, section 7).
@MainActor
struct BracketPresetAndShortcutTests {
    @Test func aPresetWithoutAnOrderIsDarkestFirst() throws {
        let old = Data(#"{"frameCount":5,"step":2}"#.utf8)
        let value = try JSONDecoder().decode(CameraSetup.BracketValue.self, from: old)
        #expect(value.settings == BracketSettings(frameCount: 5, step: 2, order: .darkestFirst))
        let unknown = Data(#"{"frameCount":3,"step":1,"order":"sideways"}"#.utf8)
        #expect(try JSONDecoder().decode(CameraSetup.BracketValue.self, from: unknown).order == .darkestFirst)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CameraSetup.BracketValue.self, from: Data(#"{"step":1}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CameraSetup.BracketValue.self, from: Data(#"{"frameCount":3}"#.utf8))
        }
    }

    @Test func aPresetKeepsTheOrder() throws {
        let value = CameraSetup.BracketValue(BracketSettings(frameCount: 3, step: 1, order: .meteredFirst))
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(CameraSetup.BracketValue.self, from: data) == value)
        #expect(value.settings.order == .meteredFirst)
    }

    @Test func anOldPresetWithABracketAppliesAndShowsBracket() async throws {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        // Saved by an earlier version: no order, and the bracket with an interval series.
        let json = #"{"drive":"interval","bracket":{"frameCount":3,"step":1}}"#
        let setup = try JSONDecoder().decode(CameraSetup.self, from: Data(json.utf8))
        let notices = await model.applyCameraSetup(setup, manualControlsOn: false)
        #expect(model.manual.bracket == .standard)
        #expect(model.isBracketOn)
        #expect(model.drive.mode == .single)
        // An interval series with a bracket no longer exists, so the drive mode differs.
        #expect(notices == [.cameraValuesAdjusted])
        #expect(model.cameraSetup.bracket?.order == .darkestFirst)
    }

    @Test func takeBracketHasAnOrder() async throws {
        #expect(BracketShortcut(frameCount: 3, step: 1).bracket.order == .darkestFirst)
        let request = BracketShortcut(frameCount: 3, step: 1, order: .brightestFirst, delaySeconds: 0)
        #expect(request.bracket == BracketSettings(frameCount: 3, step: 1, order: .brightestFirst))
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        await model.manual.record(ManualFixtures.reading)
        await model.capture(onceBracket: request.bracket)
        #expect(await backend.brackets.first?.map(\.exposureDuration) == [0.02, 0.01, 0.005])
        // Taken once: the app's own bracket is unchanged.
        #expect(model.manual.bracket == nil)
    }
}
