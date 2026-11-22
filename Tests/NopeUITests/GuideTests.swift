import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The how-to-use guide's pages, words and rows (issue #117; `docs/design/finish-1.0.md`,
/// section 2).
@MainActor
struct GuideTests {
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1)
    static let ultraWide = Lens(id: "ultra", kind: .ultraWide, bayerRAWFormat: "bgg4", magnification: 0.5)
    static let front = Lens(id: "front", kind: .front, bayerRAWFormat: nil)
    static let wideNoRAW = Lens(id: "wide-no-raw", kind: .wide, bayerRAWFormat: nil)

    @Test func sevenPagesOneIdeaEachInTheOwnersOrder() {
        #expect(GuidePage.allCases == [.takePhoto, .unprocessed, .privacy, .lenses, .autoAndManual, .driveModes, .quickMenu])
        #expect(GuidePage.allCases.map(\.number) == Array(1...7))
        let titles = GuidePage.allCases.map { String(localized: $0.title) }
        #expect(titles == [
            "Take a photo", "Photos as the camera took them", "Private by design", "Lenses", "Auto and manual",
            "One photo or a series", "Q and Settings",
        ])
    }

    @Test func theTwoKeyIdeasAreOneSentenceAndOneLinkEach() {
        let lenses = GuideLenses([Self.wide])
        #expect(
            String(localized: GuidePage.unprocessed.text(lenses: lenses))
                == "nope. saves each photo with as little processing as the camera allows, so it can look flatter or noisier at first.")
        #expect(
            String(localized: GuidePage.privacy.text(lenses: lenses))
                == "nope. never connects to the internet, and you choose which details each photo keeps.")
        #expect(GuidePage.unprocessed.link?.destination == .honesty)
        #expect(GuidePage.unprocessed.link.map { String(localized: $0.title) } == "About processing")
        #expect(GuidePage.privacy.link?.destination == .details)
        #expect(GuidePage.privacy.link.map { String(localized: $0.title) } == "Details in Each Photo")
        let withoutLinks = GuidePage.allCases.filter { $0.link == nil }
        #expect(withoutLinks == [.takePhoto, .lenses, .autoAndManual, .driveModes, .quickMenu])
    }

    @Test func theKeyIdeasAreHonestyStrings() {
        #expect(GuideText.unprocessedTitle.table == "Honesty")
        #expect(GuideText.unprocessedText.table == "Honesty")
        #expect(GuideText.privacyTitle.table == "Honesty")
        #expect(GuideText.privacyText.table == "Honesty")
        #expect(GuideText.processed.table == "Honesty")
    }

    @Test func theOtherPagesReadAsBuilt() {
        let lenses = GuideLenses([])
        #expect(String(localized: GuidePage.takePhoto.text(lenses: lenses)) == "Press the shutter or a volume button. Photos are saved to the Photos app.")
        #expect(
            String(localized: GuidePage.autoAndManual.text(lenses: lenses))
                == "Tap Auto to set the exposure and focus yourself. Tap Manual to go back to full auto.")
        #expect(
            String(localized: GuidePage.driveModes.text(lenses: lenses))
                == "Single, Timer, Burst and the other modes choose what a press does: one photo, a timer or a series.")
        #expect(String(localized: GuidePage.quickMenu.text(lenses: lenses)) == "Tap Q to open the Quick Menu. Everything else is in Settings.")
    }

    @Test func theLensPageNamesOnlyWhatTheDeviceHas() {
        let twoAndFront = GuideLenses([Self.ultraWide, Self.wide, Self.front])
        #expect(twoAndFront.offersLensChoice && twoAndFront.hasFrontCamera)
        #expect(
            String(localized: GuidePage.lenses.text(lenses: twoAndFront))
                == "Tap a lens to switch to it. Switch Camera turns to the front camera and back.")
        #expect(String(localized: GuidePage.lenses.text(lenses: GuideLenses([Self.ultraWide, Self.wide]))) == "Tap a lens to switch to it.")
        #expect(
            String(localized: GuidePage.lenses.text(lenses: GuideLenses([Self.wide, Self.front])))
                == "Switch Camera turns to the front camera and back.")
        #expect(String(localized: GuidePage.lenses.text(lenses: GuideLenses([Self.wide]))) == "nope. uses this device's one camera.")
    }

    @Test func unknownLensesDescribeTheCommonDevice() {
        let unknown = GuideLenses([])
        #expect(unknown.rear.isEmpty)
        #expect(unknown.offersLensChoice)
        #expect(unknown.hasFrontCamera)
        #expect(unknown.supportsBayerRAW)
    }

    @Test func thePictureOfTheFormatFollowsRAW() {
        #expect(GuideLenses([Self.wide]).supportsBayerRAW)
        #expect(!GuideLenses([Self.wideNoRAW, Self.front]).supportsBayerRAW)
        #expect(String(localized: GuideText.processed) == "Processed")
    }

    @Test func pagesStepForwardAndBack() {
        #expect(GuidePage.takePhoto.previous == nil)
        #expect(GuidePage.takePhoto.next == .unprocessed)
        #expect(GuidePage.quickMenu.next == nil)
        #expect(GuidePage.quickMenu.previous == .driveModes)
    }

    @Test func thePageNumberIsShownAndSpoken() {
        #expect(String(localized: GuideText.pageNumber(2, of: 7)) == "2 of 7")
        #expect(String(localized: GuideText.page) == "Page")
        #expect(GuideText.announcement(for: .unprocessed) == "Page 2 of 7: Photos as the camera took them")
    }

    @Test func theCardAndButtonsReadAsDesigned() {
        #expect(String(localized: GuideText.cardTitle) == "How to use nope.")
        #expect(String(localized: GuideText.title) == "How to Use nope.")
        #expect(String(localized: GuideText.open) == "Open")
        #expect(String(localized: GuideText.dismiss) == "Dismiss")
        #expect(String(localized: GuideText.next) == "Next")
        #expect(String(localized: GuideText.back) == "Back")
        #expect(String(localized: GuideText.done) == "Done")
        #expect(String(localized: GuideText.close) == "Close")
    }

    @Test func theRowIsFirstInMoreWithAStableIdentifier() {
        #expect(SettingsID.howToUse.rawValue == "settings.howToUse")
        #expect(SettingsID.howToUse.group == .more)
        #expect(SettingsID.howToUse.page == nil)
        #expect(SettingsID.howToUse.opensPage == nil)
        #expect(SettingsID.howToUse.navigationPath.isEmpty)
        #expect(SettingsID.howToUse.scrollTarget == .howToUse)
        #expect(SettingsID.more.scrollTarget == .howToUse)
        #expect(String(localized: SettingsText.title(of: .howToUse)) == "How to Use nope.")
        #expect(SettingsSearch.place(of: .howToUse) == String(localized: SettingsText.more))
    }

    @Test func theAboutRowHasTheSameTitleAndIsntASecondResult() {
        #expect(SettingsID.aboutHowToUse.rawValue == "settings.about.howToUse")
        #expect(SettingsID.aboutHowToUse.page == .about)
        #expect(SettingsID.aboutHowToUse.group == .more)
        #expect(String(localized: SettingsText.title(of: .aboutHowToUse)) == "How to Use nope.")
        #expect(!SettingsSearch.searchable.contains(.aboutHowToUse))
        #expect(SettingsSearch.settings(matching: "How to Use", availability: .init()) == [.howToUse])
    }

    @Test(arguments: ["How to Use nope.", "how", "help", "guide", "instructions", "tutorial", "start"])
    func searchFindsTheRow(_ word: String) {
        #expect(SettingsSearch.settings(matching: word, availability: .init()).contains(.howToUse), "\(word)")
    }

    @Test func theRowIsOfferedEverywhere() {
        #expect(SettingsSearch.Availability().offers(.howToUse))
        let lockScreen = SettingsSearch.Availability(hasPresets: false, offersKeepScreenOn: false, offersAssistantAccessPage: false)
        #expect(SettingsSearch.settings(matching: "guide", availability: lockScreen).contains(.howToUse))
    }
}
