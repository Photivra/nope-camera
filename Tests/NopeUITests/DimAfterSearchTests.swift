import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The Dim After row in Settings and its search entry (issue #119; `docs/design/finish-1.0.md`,
/// section 4).
@MainActor
struct DimAfterSearchTests {
    @Test func theRowIsInTheScreenGroupWithAStableIdentifier() {
        #expect(SettingsID.dimAfter.rawValue == "settings.dimAfter")
        #expect(SettingsID.dimAfter.group == .screen)
        #expect(SettingsID.dimAfter.page == nil)
        #expect(SettingsID.dimAfter.navigationPath.isEmpty)
        #expect(SettingsID.dimAfter.scrollTarget == .dimAfter)
        #expect(String(localized: SettingsText.title(of: .dimAfter)) == "Dim After")
        #expect(SettingsSearch.place(of: .dimAfter) == String(localized: SettingsText.screen))
    }

    @Test(arguments: ["Dim After", "dim", "brightness", "bright", "never", "battery", "heat", "warm"])
    func searchFindsTheRow(_ word: String) {
        #expect(SettingsSearch.settings(matching: word, availability: .init()).contains(.dimAfter), "\(word)")
    }

    @Test func theEntryExistsOnlyWhereKeepScreenOnIsOffered() {
        #expect(SettingsSearch.Availability().offers(.dimAfter))
        let lockScreen = SettingsSearch.Availability(offersKeepScreenOn: false)
        #expect(!lockScreen.offers(.dimAfter))
        #expect(!SettingsSearch.settings(matching: "dim", availability: lockScreen).contains(.dimAfter))
    }

    @Test func theChoicesAndNotesReadAsDesigned() {
        #expect(String(localized: "Dim After: Never", defaultValue: "Never", bundle: .module) == "Never")
        #expect(String(localized: "\(1) Minutes", bundle: .module) == "1 Minute")
        #expect(String(localized: "\(2) Minutes", bundle: .module) == "2 Minutes")
        #expect(String(localized: "\(5) Minutes", bundle: .module) == "5 Minutes")
        let never = String(
            localized: "Never uses more battery and can warm the phone. The screen still dims in Low Power Mode and when the phone is hot.",
            table: "Honesty", bundle: .module)
        #expect(never.contains("Low Power Mode"))
    }
}
