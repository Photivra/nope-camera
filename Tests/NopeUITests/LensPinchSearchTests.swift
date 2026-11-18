import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The Pinch setting in Settings and its search entry (issue #95; docs/design/pinch-lens.md,
/// section 11, unit test 9), and the lens label's text.
@MainActor
struct LensPinchSearchTests {
    /// What a device with two or more rear lenses offers.
    static let withPinch = SettingsSearch.Availability(offersPinch: true)

    @Test func theRowIsInTheCameraGroupWithAStableIdentifier() {
        #expect(SettingsID.pinch.rawValue == "settings.pinch")
        #expect(SettingsID.pinch.group == .camera)
        #expect(SettingsID.pinch.page == nil)
        #expect(SettingsID.pinch.navigationPath.isEmpty)
        #expect(SettingsID.pinch.scrollTarget == .pinch)
        #expect(String(localized: SettingsText.title(of: .pinch)) == "Pinch")
        #expect(SettingsSearch.place(of: .pinch) == String(localized: SettingsText.camera))
    }

    @Test(arguments: ["pinch", "zoom", "lens", "lenses", "gesture", "two fingers"])
    func searchFindsTheRow(_ word: String) {
        #expect(SettingsSearch.settings(matching: word, availability: Self.withPinch).contains(.pinch), "\(word)")
    }

    @Test func theEntryExistsOnlyWithTwoOrMoreRearLenses() {
        #expect(!SettingsSearch.settings(matching: "pinch", availability: .init()).contains(.pinch))
        #expect(SettingsSearch.Availability(offersPinch: true).offers(.pinch))
        #expect(!SettingsSearch.Availability().offers(.pinch))
        let oneRear = [Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4"), Lens(id: "front", kind: .front, bayerRAWFormat: "bgg4")]
        #expect(!LensPinch.isOffered(on: oneRear))
    }

    @Test func visibleTextNeverSaysZoom() {
        let visible = [
            String(localized: SettingsText.pinch),
            String(localized: "Switch Lenses", bundle: .module),
            String(localized: "Pinch: Off", defaultValue: "Off", bundle: .module),
            String(
                localized: "Spread two fingers on the picture for the next longer lens, or pinch for the next wider one. nope. never enlarges or crops the picture.",
                table: "Honesty", bundle: .module),
            String(
                localized: "Used only on the rear cameras. Not used in Astro, while photos are being taken, or at the largest text sizes.",
                table: "Honesty", bundle: .module),
        ]
        for text in visible {
            #expect(!text.localizedCaseInsensitiveContains("zoom"), "\(text)")
        }
    }

    @Test func theLabelUsesTheLensButtonsMultiplier() {
        #expect(LensPinchLabel.magnification(of: Lens(id: "u", kind: .ultraWide, bayerRAWFormat: nil, magnification: 0.5)) == "0.5×")
        #expect(LensPinchLabel.magnification(of: Lens(id: "w", kind: .wide, bayerRAWFormat: nil, magnification: 1)) == "1×")
        #expect(LensPinchLabel.magnification(of: Lens(id: "t", kind: .telephoto, bayerRAWFormat: nil)) == nil)
    }
}
