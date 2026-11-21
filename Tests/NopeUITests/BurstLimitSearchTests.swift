import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The Burst Limit row in Settings and its search entry (issue #121; `docs/design/finish-1.0.md`,
/// section 5.1).
@MainActor
struct BurstLimitSearchTests {
    @Test func theRowIsInTheCameraGroupWithAStableIdentifier() {
        #expect(SettingsID.burstLimit.rawValue == "settings.burstLimit")
        #expect(SettingsID.burstLimit.group == .camera)
        #expect(SettingsID.burstLimit.page == nil)
        #expect(SettingsID.burstLimit.navigationPath.isEmpty)
        #expect(SettingsID.burstLimit.scrollTarget == .burstLimit)
        #expect(String(localized: SettingsText.title(of: .burstLimit)) == "Burst Limit")
        #expect(SettingsSearch.place(of: .burstLimit) == String(localized: SettingsText.camera))
    }

    @Test(arguments: ["Burst Limit", "burst", "limit", "count", "frames", "series", "continuous"])
    func searchFindsTheRow(_ word: String) {
        #expect(SettingsSearch.settings(matching: word, availability: .init()).contains(.burstLimit), "\(word)")
    }

    @Test func theEntryIsOfferedEverywhereIncludingTheLockScreenCamera() {
        let lockScreen = SettingsSearch.Availability(hasPresets: false, offersKeepScreenOn: false, offersAssistantAccessPage: false)
        #expect(lockScreen.offers(.burstLimit))
        #expect(SettingsSearch.Availability().offers(.burstLimit))
    }

    @Test func theChoicesReadAsDesigned() {
        #expect(String(localized: "Burst Limit: Off", defaultValue: "Off", bundle: .module) == "Off")
        #expect(BurstLimit.allCases.compactMap(\.frameCount).map { $0.formatted(.number) } == ["3", "5", "10", "20", "50"])
    }
}
