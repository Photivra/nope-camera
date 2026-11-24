import Foundation
import Testing

@testable import NopeCore

/// One clock source for the camera model and what it owns (issue #107): the wall clock for dates,
/// the monotonic clock for time, replaced in tests as one value.
@MainActor
struct NopeClockTests {
    @Test func theSystemClockReadsTheSystemsClocks() async throws {
        let clock = NopeClock.system
        #expect(abs(clock.date().timeIntervalSinceNow) < 60)
        #expect(abs((clock.now() - ContinuousClock.now) / .seconds(1)) < 60)
        try await clock.sleep(seconds: 0)
        try await clock.sleep(clock.now() - .seconds(1))
    }

    @Test func aMomentsDateIsCountedFromNowsDate() {
        let fake = FakeClock(date: Date(timeIntervalSince1970: 1000))
        let clock = fake.clock
        #expect(clock.date(of: fake.now + .seconds(30)) == Date(timeIntervalSince1970: 1030))
        // A change of the device's time moves the date shown, not the moment.
        fake.moveDate(by: -3600)
        #expect(clock.date(of: fake.now + .seconds(30)) == Date(timeIntervalSince1970: -2570))
    }

    @Test func aWaitInSecondsWaitsOnTheMonotonicClock() async throws {
        let fake = FakeClock()
        let waited = Task { try await fake.clock.sleep(seconds: 5) }
        await waitForSleeps(fake)
        #expect(fake.requestedWakes.map { fake.seconds(at: $0) } == [5])
        fake.setDate(Date(timeIntervalSince1970: 0))
        #expect(fake.pendingSleeps == 1, "the wall clock doesn't wake it")
        fake.advance(by: 5)
        try await waited.value
    }

    @Test func aCancelledWaitThrows() async {
        let fake = FakeClock()
        let waited = Task { try await fake.clock.sleep(seconds: 5) }
        await waitForSleeps(fake)
        waited.cancel()
        await #expect(throws: CancellationError.self) { try await waited.value }
        #expect(fake.pendingSleeps == 0)
    }

    // MARK: - Stepped clocks, for the older seconds sleeps

    @Test func aSteppedClockMovesByEachCompletedWait() async throws {
        let asked = SleepLog()
        let clock = NopeClock.stepped { await asked.add($0) }
        let start = clock.now()
        try await clock.sleep(start + .seconds(1))
        #expect(clock.now() == start + .seconds(1))
        try await clock.sleep(seconds: 2)
        #expect(clock.now() == start + .seconds(3))
        try await clock.sleep(start)
        #expect(clock.now() == start + .seconds(3), "a moment already past doesn't move it back")
        #expect(await asked.values == [1, 2, 0], "whole seconds while on time")
    }

    @Test func aSteppedClockThatThrowsDoesNotMove() async {
        let clock = NopeClock.stepped { _ in throw CancellationError() }
        let start = clock.now()
        await #expect(throws: CancellationError.self) { try await clock.sleep(seconds: 1) }
        #expect(clock.now() == start)
    }

    @Test func aSteppedClockWithItsOwnTimeLeavesMovingItToTheSleep() async throws {
        let fake = FakeClock()
        let asked = SleepLog()
        let clock = NopeClock.stepped(by: { seconds in
            await asked.add(seconds)
            fake.advance(by: seconds)
        }, now: { fake.now })
        try await clock.sleep(seconds: 4)
        try await clock.sleep(fake.now - .seconds(1))
        #expect(fake.seconds(at: clock.now()) == 4)
        #expect(await asked.values == [4, 0])
    }

    // MARK: - One clock in the models

    @Test func theCameraModelPassesItsClockToWhatItOwns() async {
        let fake = FakeClock(date: Date(timeIntervalSince1970: 1_234_567))
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), clock: fake.clock)
        #expect(model.clock.date() == fake.date)
        #expect(model.manual.clock.date() == fake.date)
        #expect(model.manual.now() == fake.now)
        #expect(model.now() == fake.now)
        #expect(model.drive.now() == fake.now)

        // A photo's date is the wall clock's.
        await model.send(.start)
        await model.send(.capture)
        await waitUntil { model.sessionPhotos.photos.count == 1 }
        #expect(model.sessionPhotos.photos.first?.takenAt == fake.date)

        // The countdown and a Slow burst's wait both wait on it.
        model.drive.countdown.start(seconds: 1) {}
        await waitForSleeps(fake)
        let slow = Task { try await model.drive.sleep(2) }
        await waitForSleeps(fake, count: 2)
        fake.advance(by: 2)
        try? await slow.value
        await waitUntil { !model.drive.countdown.isRunning }
        #expect(fake.requestedWakes.map { fake.seconds(at: $0) } == [1, 2])
    }

    @Test func theModelsWithASecondsSleepKeepTheirOwnClocks() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), sleep: { _ in })
        let before = model.clock.now()
        try? await model.clock.sleep(seconds: 10)
        #expect(model.clock.now() == before + .seconds(10))
        // The model's own clock moved 10 s; captures read the system clock, so the reading lies
        // between two readings of the system clock, however long a loaded CI runner took.
        let earliest = ContinuousClock.now
        let measured = model.now()
        #expect(earliest <= measured && measured <= ContinuousClock.now, "captures are still timed on the system clock")

        let manual = ManualControlsModel(backend: nil, sleep: { _ in })
        let manualBefore = manual.clock.now()
        try? await manual.clock.sleep(seconds: 3)
        #expect(manual.clock.now() == manualBefore + .seconds(3))
    }

    @Test func theLiveActivityCoordinatorReadsTheSameClock() async {
        let fake = FakeClock()
        let model = CameraModel(
            backend: ScriptedManualBackend(lenses: [ManualFixtures.wide]), saver: CameraModelTests.saver(),
            clock: fake.clock)
        await model.send(.start)
        let presenter = FakeLiveActivities()
        let coordinator = LiveActivityCoordinator(presenter: presenter, backgroundTime: FakeBackgroundTime(), clock: fake.clock)
        coordinator.isEnabled = true
        model.drive.beginBurst()
        coordinator.apply(model)
        coordinator.isInForeground = false
        model.drive.endBurst(.stopped)
        coordinator.apply(model)
        #expect(
            presenter.ends.last?.dismissal
                == .after(fake.date.addingTimeInterval(LiveActivityCoordinator.endedActivityDuration)))
    }
}

/// Records the seconds a sleep was asked for, from any task.
actor SleepLog {
    private(set) var values: [Double] = []

    func add(_ seconds: Double) {
        values.append(seconds)
    }
}
