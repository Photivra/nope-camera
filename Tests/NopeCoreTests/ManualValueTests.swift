import Foundation
import Testing

@testable import NopeCore

struct ManualSettingsTests {
    @Test func automaticIsTheDefault() {
        let settings = ManualSettings()
        #expect(settings == .automatic)
        #expect(settings.isAutomatic)
        #expect(settings.manualControlCount == 0)
        #expect(settings.exposureMode == .program)
        #expect(ManualControl.allCases.allSatisfy { !settings.isManual($0) })
        #expect(settings.metering == .center)
    }

    @Test func eachControlCountsAsManual() {
        let settings = ManualSettings(
            iso: 200, shutter: 0.01, aperture: 2.8, exposureCompensation: -1, focus: 0.3,
            whiteBalance: WhiteBalance(temperature: 3200), metering: .spot, exposureLocked: true, focusLocked: true)
        #expect(ManualControl.allCases.allSatisfy { settings.isManual($0) })
        #expect(settings.manualControlCount == 6)
        #expect(!settings.isAutomatic)
    }

    @Test func lockOrMeteringAloneIsNotAutomatic() {
        #expect(!ManualSettings(metering: .spot).isAutomatic)
        #expect(!ManualSettings(exposureLocked: true).isAutomatic)
        #expect(ManualSettings(metering: .spot).manualControlCount == 0)
    }

    @Test func exposureModeFollowsISOAndShutter() {
        #expect(ManualSettings(shutter: 0.01).exposureMode == .shutterPriority)
        #expect(ManualSettings(iso: 100).exposureMode == .isoPriority)
        #expect(ManualSettings(iso: 100, shutter: 0.01).exposureMode == .manual)
    }

    @Test func availabilityAdjustable() {
        #expect(ControlAvailability.adjustable.isAdjustable)
        #expect(!ControlAvailability.fixed(1.8).isAdjustable)
        #expect(!ControlAvailability.blockedByManualExposure.isAdjustable)
        #expect(!ControlAvailability.unavailable.isAdjustable)
    }

    @Test func capabilitiesListSupportedModes() {
        #expect(ManualFixtures.full.exposureModes == [.program, .shutterPriority, .isoPriority, .manual])
        #expect(ManualFixtures.basic.exposureModes == [.program, .manual])
        #expect(ManualCapabilities.none.exposureModes == [.program])
        #expect(ManualFixtures.wide.manualControls == ManualFixtures.full)
        #expect(Lens(id: "x", kind: .wide, bayerRAWFormat: nil).manualControls == .none)
    }

    @Test func readingKeepsItsValues() {
        let reading = ManualFixtures.reading
        #expect(reading.iso == 200)
        #expect(reading.exposureDuration == 0.01)
        #expect(reading.exposureOffset == 0.5)
        #expect(reading.lensPosition == 0.8)
        #expect(reading.aperture == 1.5)
        #expect(reading.whiteBalance == WhiteBalance(temperature: 4000, tint: 10))
    }
}

struct WhiteBalanceTests {
    @Test func limitsTemperatureAndTint() {
        #expect(WhiteBalance(temperature: 100, tint: -500).limited == WhiteBalance(temperature: 2500, tint: -150))
        #expect(WhiteBalance(temperature: 20_000, tint: 500).limited == WhiteBalance(temperature: 10_000, tint: 150))
        #expect(WhiteBalance(temperature: 5000).limited == WhiteBalance(temperature: 5000, tint: 0))
    }

    @Test func presetsUseConventionalTemperatures() {
        let temperatures = WhiteBalancePreset.allCases.map(\.whiteBalance.temperature)
        #expect(temperatures == [3200, 4000, 5500, 6500, 7500])
        #expect(WhiteBalancePreset.allCases.allSatisfy { $0.whiteBalance.tint == 0 })
    }
}

struct ControlScaleTests {
    @Test func emptyValuesGiveNoScale() {
        #expect(ControlScale(values: []) == nil)
        #expect(ControlScale.scale(for: .aperture, on: Lens(
            id: "a", kind: .wide, bayerRAWFormat: nil,
            aperture: ApertureRange(minimumFNumber: 1, maximumFNumber: 2, recommendedStops: []))) == nil)
    }

    @Test func nearestUsesStopsForPositiveValuesAndDistanceOtherwise() throws {
        let iso = try #require(ControlScale(values: [100, 200, 400]))
        #expect(iso.nearestIndex(to: 141) == 0)
        #expect(iso.nearestIndex(to: 290) == 2)
        let ev = try #require(ControlScale(values: [-1, 0, 1]))
        #expect(ev.nearestIndex(to: -0.6) == 0)
        #expect(ev.nearestIndex(to: 0.4) == 1)
        let positive = try #require(ControlScale(values: [1, 2]))
        #expect(positive.nearestIndex(to: -5) == 0)
    }

    @Test func steppingStopsAtTheEnds() throws {
        let scale = try #require(ControlScale(values: [3, 1, 2, 2]))
        #expect(scale.values == [1, 2, 3])
        #expect(scale.range == 1...3)
        #expect(scale.value(from: 2, steppedBy: 1) == 3)
        #expect(scale.value(from: 2, steppedBy: 5) == 3)
        #expect(scale.value(from: 2, steppedBy: -5) == 1)
    }

    @Test func isoScaleKeepsTheLensLimits() throws {
        let scale = try #require(ControlScale.scale(for: .iso, on: ManualFixtures.wide))
        #expect(scale.values.first == 50)
        #expect(scale.values.last == 6400)
        #expect(scale.values.contains(64))
        let odd = Lens(id: "o", kind: .wide, bayerRAWFormat: nil, isoRange: 54...12_096)
        let oddScale = try #require(ControlScale.scale(for: .iso, on: odd))
        #expect(oddScale.values.first == 54)
        #expect(oddScale.values.last == 12_096)
        #expect(oddScale.values.contains(10_000))
    }

    @Test func shutterScaleUsesMarkedSpeeds() throws {
        let scale = try #require(ControlScale.scale(for: .shutter, on: ManualFixtures.wide))
        #expect(scale.values.first == 0.0001)
        #expect(scale.values.last == 1)
        #expect(scale.values.contains(1.0 / 500))
        #expect(scale.values.contains(0.3))
    }

    @Test func compensationScaleIsThirdsWithinThreeStops() throws {
        let scale = try #require(ControlScale.scale(for: .exposureCompensation, on: ManualFixtures.wide))
        #expect(scale.values.count == 19)
        #expect(scale.range == -3...3)
        func lens(_ range: ClosedRange<Double>?) -> Lens {
            Lens(
                id: "c", kind: .wide, bayerRAWFormat: nil,
                manualControls: ManualCapabilities(
                    supportsManualExposure: false, supportsShutterPriority: false, supportsISOPriority: false,
                    supportsAperturePriority: false, exposureCompensationRange: range, supportsExposureLock: false,
                    supportsAutoFocus: false, supportsFocusLock: false, supportsManualFocus: false,
                    supportsManualWhiteBalance: false, meteringModes: []))
        }
        #expect(ControlScale.scale(for: .exposureCompensation, on: lens(-1...1))?.values.count == 7)
        #expect(ControlScale.scale(for: .exposureCompensation, on: lens(0.1...0.2))?.values == [0.1, 0.2])
        #expect(ControlScale.scale(for: .exposureCompensation, on: lens(5...8)) == nil)
        #expect(ControlScale.scale(for: .exposureCompensation, on: lens(nil)) == nil)
    }

    @Test func otherScales() throws {
        let aperture = try #require(ControlScale.scale(for: .aperture, on: ManualFixtures.wide))
        #expect(aperture.values == [1.5, 2, 2.8, 4])
        let focus = try #require(ControlScale.scale(for: .focus, on: ManualFixtures.bare))
        #expect(focus.values.count == 21)
        #expect(focus.range == 0...1)
        let temperature = try #require(ControlScale.scale(for: .whiteBalance, on: ManualFixtures.bare))
        #expect(temperature.range == 2500...10_000)
        #expect(temperature.values.count == 76)
        #expect(ControlScale.tint.range == -150...150)
        #expect(ControlScale.tint.values.count == 61)
        for control in [ManualControl.iso, .shutter, .aperture, .exposureCompensation] {
            #expect(ControlScale.scale(for: control, on: ManualFixtures.bare) == nil)
        }
    }
}

struct BracketTests {
    @Test func offsetsAreCentered() {
        #expect(BracketSettings(frameCount: 3, step: 1).offsets == [-1, 0, 1])
        #expect(BracketSettings(frameCount: 5, step: 2).offsets == [-4, -2, 0, 2, 4])
    }

    @Test func frameCountsFollowTheLens() {
        #expect(BracketSettings.frameCounts(for: ManualFixtures.wide) == [3, 5])
        #expect(BracketSettings.frameCounts(for: ManualFixtures.bare).isEmpty)
        #expect(BracketSettings.steps.count == 4)
    }

    @Test func shutterFirstThenISO() {
        let frames = BracketFrame.plan(
            offsets: [-1, 0, 2], base: BracketFrame(iso: 100, exposureDuration: 0.5), shutterFirst: true,
            isoRange: 50...800, durationRange: 0.001...1)
        #expect(frames[0] == BracketFrame(iso: 100, exposureDuration: 0.25))
        #expect(frames[1] == BracketFrame(iso: 100, exposureDuration: 0.5))
        // +2 EV: the shutter stops at 1 s, ISO makes up the other stop.
        #expect(frames[2] == BracketFrame(iso: 200, exposureDuration: 1))
    }

    @Test func isoFirstThenShutter() {
        let frames = BracketFrame.plan(
            offsets: [-2, 1], base: BracketFrame(iso: 100, exposureDuration: 0.01), shutterFirst: false,
            isoRange: 50...800, durationRange: 0.001...1)
        // −2 EV: ISO stops at 50, the shutter makes up the other stop.
        #expect(frames[0] == BracketFrame(iso: 50, exposureDuration: 0.005))
        #expect(frames[1] == BracketFrame(iso: 200, exposureDuration: 0.01))
    }

    @Test func intervalSettingsStayInRange() {
        #expect(IntervalSettings(interval: 0, count: 0) == IntervalSettings(interval: 1, count: 2))
        #expect(IntervalSettings(interval: 99_999, count: 99_999) == IntervalSettings(interval: 3600, count: 999))
        #expect(IntervalSettings.standard.interval == 10)
        #expect(IntervalSettings.standard.count == 10)
        #expect(IntervalProgress(taken: 1, total: 3).taken == 1)
        #expect(IntervalProgress(taken: 1, total: 3).total == 3)
    }
}

struct DeviceControlsTests {
    typealias Fixtures = ManualFixtures

    @Test func automaticByDefault() {
        #expect(DeviceControls(settings: .automatic, lens: Fixtures.wide) == .automatic)
        #expect(DeviceControls(settings: .automatic, lens: Fixtures.bare) == .automatic)
    }

    @Test func compensationIsLimitedAndNeedsARange() {
        let controls = DeviceControls(settings: ManualSettings(exposureCompensation: 20), lens: Fixtures.wide)
        #expect(controls.exposure == .automatic(compensation: 8))
        let bare = DeviceControls(settings: ManualSettings(exposureCompensation: 2), lens: Fixtures.bare)
        #expect(bare.exposure == .automatic(compensation: 0))
    }

    @Test func exposureLockNeedsSupportAndFullAuto() {
        #expect(DeviceControls(settings: ManualSettings(exposureLocked: true), lens: Fixtures.wide).exposure == .locked)
        #expect(
            DeviceControls(settings: ManualSettings(exposureLocked: true), lens: Fixtures.bare).exposure
                == .automatic(compensation: 0))
    }

    @Test func priorityModesOnAFullLens() {
        let iso = DeviceControls(settings: ManualSettings(iso: 100_000, exposureCompensation: 1), lens: Fixtures.wide)
        #expect(iso.exposure == .custom(iso: .value(6400), duration: .auto, aperture: .auto, compensation: 1))
        let shutter = DeviceControls(settings: ManualSettings(shutter: 0.01), lens: Fixtures.wide)
        #expect(shutter.exposure == .custom(iso: .auto, duration: .value(0.01), aperture: .auto, compensation: 0))
        let manual = DeviceControls(
            settings: ManualSettings(iso: 100, shutter: 5, exposureCompensation: 1), lens: Fixtures.wide)
        #expect(manual.exposure == .custom(iso: .value(100), duration: .value(1), aperture: .current, compensation: 0))
        let aperture = DeviceControls(settings: ManualSettings(aperture: 9), lens: Fixtures.wide)
        #expect(aperture.exposure == .custom(iso: .auto, duration: .auto, aperture: .value(4), compensation: 0))
        let all = DeviceControls(settings: ManualSettings(iso: 100, shutter: 0.01, aperture: 2), lens: Fixtures.wide)
        #expect(all.exposure == .custom(iso: .value(100), duration: .value(0.01), aperture: .value(2), compensation: 0))
    }

    @Test func noPriorityModesBeforeIOS27() {
        #expect(
            DeviceControls(settings: ManualSettings(iso: 100), lens: Fixtures.basicLens).exposure
                == .automatic(compensation: 0))
        #expect(
            DeviceControls(settings: ManualSettings(shutter: 0.01), lens: Fixtures.basicLens).exposure
                == .automatic(compensation: 0))
        let manual = DeviceControls(
            settings: ManualSettings(iso: 100, shutter: 0.01, aperture: 2), lens: Fixtures.basicLens)
        #expect(manual.exposure == .custom(iso: .value(100), duration: .value(0.01), aperture: .current, compensation: 0))
        // No ranges: the manual values are dropped.
        #expect(
            DeviceControls(settings: ManualSettings(iso: 100, shutter: 0.01), lens: Fixtures.bare).exposure
                == .automatic(compensation: 0))
    }

    @Test func focusWhiteBalanceAndMetering() {
        let manual = DeviceControls(
            settings: ManualSettings(focus: 2, whiteBalance: WhiteBalance(temperature: 1000), metering: .spot),
            lens: Fixtures.wide)
        #expect(manual.focus == .lensPosition(1))
        #expect(manual.whiteBalance == .fixed(WhiteBalance(temperature: 2500)))
        #expect(manual.metering == .spot)
        let locked = DeviceControls(settings: ManualSettings(focusLocked: true), lens: Fixtures.wide)
        #expect(locked.focus == .locked)
        let bare = DeviceControls(
            settings: ManualSettings(
                focus: 0.5, whiteBalance: WhiteBalance(temperature: 3000), metering: .spot, focusLocked: true),
            lens: Fixtures.bare)
        #expect(bare.focus == .automatic)
        #expect(bare.whiteBalance == .automatic)
        #expect(bare.metering == .center)
    }
}
