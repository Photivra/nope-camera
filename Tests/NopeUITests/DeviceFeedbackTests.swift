import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The interface rules of docs/design/device-feedback-1.0.md: what the Last Photo spot holds,
/// how long "Hold it steady or use a tripod." stays and when it is announced, when the focus
/// square and Lock fade, and how Settings reaches the Honesty entry on close-up focus.
@MainActor
struct DeviceFeedbackTests {
    // MARK: - 1. The Last Photo spot

    @Test func theSpotHoldsOpenPhotosBeforeTheFirstPhoto() {
        #expect(LastPhotoSpot.content(hasPhotos: false, isBusy: false, isSeriesRunning: false, isCleanView: false, canOpenPhotos: true) == .openPhotos)
    }

    @Test func theSpinnerAndTheLastPhotoTakeTheSpot() {
        // A photo being taken or saved: the spinner, before and after the first photo.
        #expect(LastPhotoSpot.content(hasPhotos: false, isBusy: true, isSeriesRunning: false, isCleanView: false, canOpenPhotos: true) == .saving)
        #expect(LastPhotoSpot.content(hasPhotos: true, isBusy: true, isSeriesRunning: true, isCleanView: false, canOpenPhotos: true) == .saving)
        // Once a photo is saved, Last Photo, during a series too, and in the Lock Screen camera.
        #expect(LastPhotoSpot.content(hasPhotos: true, isBusy: false, isSeriesRunning: false, isCleanView: false, canOpenPhotos: true) == .lastPhoto)
        #expect(LastPhotoSpot.content(hasPhotos: true, isBusy: false, isSeriesRunning: true, isCleanView: false, canOpenPhotos: false) == .lastPhoto)
    }

    @Test func nothingDuringASeriesInCleanViewOrWherePhotosCantOpen() {
        // A countdown or series: a press would leave the app and interrupt it (decision 4).
        #expect(LastPhotoSpot.content(hasPhotos: false, isBusy: false, isSeriesRunning: true, isCleanView: false, canOpenPhotos: true) == .nothing)
        // The Lock Screen camera can't open Photos (decision 5).
        #expect(LastPhotoSpot.content(hasPhotos: false, isBusy: false, isSeriesRunning: false, isCleanView: false, canOpenPhotos: false) == .nothing)
        // Clean view: Show Controls has the spot, whatever else holds.
        for hasPhotos in [false, true] {
            for isBusy in [false, true] {
                #expect(LastPhotoSpot.content(hasPhotos: hasPhotos, isBusy: isBusy, isSeriesRunning: false, isCleanView: true, canOpenPhotos: true) == .nothing)
            }
        }
    }

    // MARK: - 4. The steady hint's timing

    @Test func theSteadyHintStaysAtLeastTwoSeconds() {
        let start = ContinuousClock.now
        var timing = SteadyHintTiming()
        #expect(timing.remainingMinimum(at: start) == nil)
        let announced = timing.appear(at: start)
        #expect(announced)
        #expect(timing.shownSince == start)
        #expect(timing.remainingMinimum(at: start + .milliseconds(500)) == .milliseconds(1500))
        #expect(timing.remainingMinimum(at: start + .seconds(2)) == nil)
        #expect(timing.remainingMinimum(at: start + .seconds(5)) == nil)
        timing.disappear()
        #expect(timing.shownSince == nil)
        #expect(SteadyHintTiming.minimumShown == .seconds(2))
    }

    @Test func theSteadyHintIsAnnouncedAtMostOnceInTenSeconds() {
        let start = ContinuousClock.now
        var timing = SteadyHintTiming()
        let first = timing.appear(at: start)
        #expect(first)
        timing.disappear()
        // Back within 10 seconds: shown, not announced again.
        let withinTheGap = timing.appear(at: start + .seconds(4))
        #expect(!withinTheGap)
        #expect(timing.lastAnnouncement == start)
        timing.disappear()
        // 10 seconds after the last announcement: announced.
        let afterTheGap = timing.appear(at: start + .seconds(10))
        #expect(afterTheGap)
        #expect(timing.lastAnnouncement == start + .seconds(10))
        #expect(SteadyHintTiming.announcementGap == .seconds(10))
    }

    // MARK: - 5. The focus square and Lock

    /// A tapped, unlocked target.
    static let tapped = FocusTarget(viewfinderPoint: FramePoint(x: 0.3, y: 0.4), devicePoint: FramePoint(x: 0.4, y: 0.7), isLocked: false)

    /// The same target, locked.
    static let locked = FocusTarget(viewfinderPoint: FramePoint(x: 0.3, y: 0.4), devicePoint: FramePoint(x: 0.4, y: 0.7), isLocked: true)

    @Test func theFocusAidsShowForThreeSecondsAfterATap() {
        let tap = ContinuousClock.now
        var linger = FocusAidLinger()
        linger.restart(at: tap)
        #expect(linger.start == tap)
        #expect(linger.isShown(target: Self.tapped, at: tap, isHeld: false))
        #expect(linger.isShown(target: Self.tapped, at: tap + .milliseconds(2900), isHeld: false))
        #expect(!linger.isShown(target: Self.tapped, at: tap + .seconds(3), isHeld: false))
        #expect(linger.remaining(at: tap + .seconds(1)) == .seconds(2))
        #expect(linger.remaining(at: tap + .seconds(3)) == nil)
        // A second tap starts the clock again.
        linger.restart(at: tap + .seconds(4))
        #expect(linger.isShown(target: Self.tapped, at: tap + .seconds(6), isHeld: false))
        #expect(!linger.isShown(target: Self.tapped, at: tap + .seconds(7), isHeld: false))
        #expect(NopeMotion.focusAidLinger == .seconds(3))
    }

    @Test func aLockedSquareNeverFades() {
        let tap = ContinuousClock.now
        var linger = FocusAidLinger()
        linger.restart(at: tap)
        #expect(linger.isShown(target: Self.locked, at: tap + .seconds(60), isHeld: false))
    }

    @Test func nothingFadesWhileHeld() {
        // VoiceOver or Switch Control on, Lock pressed or focused, or the scrolling layout.
        let tap = ContinuousClock.now
        var linger = FocusAidLinger()
        linger.restart(at: tap)
        #expect(linger.isShown(target: Self.tapped, at: tap + .seconds(60), isHeld: true))
    }

    @Test func nothingShowsWithoutATarget() {
        // The scene changed or the lock was released: both leave at once.
        let tap = ContinuousClock.now
        var linger = FocusAidLinger()
        linger.restart(at: tap)
        #expect(!linger.isShown(target: nil, at: tap, isHeld: true))
        // A target set before any tap (a VoiceOver action) shows until the clock starts.
        #expect(FocusAidLinger().isShown(target: Self.tapped, at: tap, isHeld: false))
        #expect(FocusAidLinger().remaining(at: tap) == nil)
    }

    // MARK: - 3. Reaching the Honesty entry

    @Test func theCloseUpEntryIsOnTheHonestyPageAndNotASearchResult() {
        #expect(SettingsID.honestyCloseUpFocus.page == .honesty)
        #expect(SettingsID.honestyCloseUpFocus.group == .more)
        #expect(SettingsID.honestyCloseUpFocus.navigationPath == [.honesty])
        #expect(SettingsID.honestyCloseUpFocus.scrollTarget == .honestyCloseUpFocus)
        #expect(!SettingsSearch.searchable.contains(.honestyCloseUpFocus))
        #expect(SettingsSearch.searchable.contains(.honesty))
        #expect(String(localized: SettingsText.title(of: .honestyCloseUpFocus)) == "Lenses Never Switch on Their Own")
    }

    @Test func openingTheEntryScrollsAndFocusesIt() {
        let navigation = SettingsNavigation()
        navigation.open(.honestyCloseUpFocus)
        #expect(navigation.path == [.honesty])
        #expect(navigation.scrollTarget == .honestyCloseUpFocus)
        #expect(navigation.focusTarget == .honestyCloseUpFocus)
        // Another item asks for no focus; a reset forgets it.
        navigation.open(.detailsLocation)
        #expect(navigation.focusTarget == nil)
        navigation.open(.honestyCloseUpFocus)
        navigation.reset()
        #expect(navigation.focusTarget == nil)
    }

    @Test func searchFindsHonestyForACloseUpWord() throws {
        let keywords = try #require(SettingsText.keywords(of: .honesty))
        let list = SettingsSearch.keywords(from: String(localized: keywords))
        #expect(list == ["close-up", "macro", "close", "near", "blurry", "soft", "lens"])
        #expect(SettingsSearch.matches(["macro"], title: "Honesty", keywords: list))
    }

    @Test func theLensLabelIsTheLensButtonsLabel() {
        let ultraWide = Lens(id: "u", kind: .ultraWide, bayerRAWFormat: nil, magnification: 0.5)
        #expect(LensName.magnificationLabel(for: ultraWide) == "0.5×")
        #expect(LensName.magnificationLabel(for: Lens(id: "f", kind: .front, bayerRAWFormat: nil)) == nil)
    }
}
