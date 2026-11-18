import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The Settings identifiers, the search index and its matching (`docs/design/BUILD-SPEC.md`,
/// 3.10).
@MainActor
struct SettingsSearchTests {
    @Test func identifiersAreUniqueAndStable() {
        let raw = SettingsID.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { $0.hasPrefix("settings.") })
        // Identifiers other code and the design name.
        #expect(SettingsID.photos.rawValue == "settings.photos")
        #expect(SettingsID.copies.rawValue == "settings.copies")
        #expect(SettingsID.details.rawValue == "settings.details")
        #expect(SettingsID.detailsLocation.rawValue == "settings.details.location")
    }

    @Test func everyPageIsOpenedByARow() {
        for page in SettingsPage.allCases {
            #expect(page.id.rawValue == page.rawValue)
            #expect(page.id.opensPage == page)
            #expect(page.id.page == nil, "a page is one level below Settings")
        }
    }

    @Test func nothingIsDeeperThanTwoLevels() {
        for id in SettingsID.allCases {
            #expect(id.navigationPath.count <= 1, "\(id)")
            if let page = id.page {
                #expect(page.id.page == nil)
            }
        }
    }

    @Test func eachDetailHasItsRow() {
        for item in MetadataItem.allCases {
            let id = SettingsID.details(item)
            #expect((id != nil) == item.isOfferedInSettings, "\(item)")
            if let id { #expect(id.page == .details) }
        }
    }

    @Test func groupsScrollToTheirFirstRow() {
        #expect(SettingsID.photos.navigationPath.isEmpty)
        #expect(SettingsID.photos.scrollTarget == .formats)
        #expect(SettingsID.privacy.scrollTarget == .details)
        #expect(SettingsID.camera.scrollTarget == .fastShutter)
        #expect(SettingsID.screen.scrollTarget == .startInCleanView)
        #expect(SettingsID.more.scrollTarget == .accessibility)
        #expect(SettingsID.copies.navigationPath == [.copies])
        #expect(SettingsID.copies.scrollTarget == nil)
        #expect(SettingsID.detailsLocation.navigationPath == [.details])
        #expect(SettingsID.detailsLocation.scrollTarget == .detailsLocation)
        #expect(SettingsID.nightMode.navigationPath.isEmpty)
        #expect(SettingsID.nightMode.scrollTarget == .nightMode)
    }

    @Test func everyItemButPresetsHasAGroup() {
        for id in SettingsID.allCases where ![.presets, .factoryDefaults, .saveCurrentSettings].contains(id) {
            #expect(id.group != nil, "\(id)")
        }
    }

    @Test func navigationOpensAndResets() {
        let navigation = SettingsNavigation()
        navigation.searchText = "gps"
        navigation.open(.detailsLocation)
        #expect(navigation.path == [.details])
        #expect(navigation.scrollTarget == .detailsLocation)
        #expect(navigation.searchText.isEmpty)
        navigation.reset()
        #expect(navigation.path.isEmpty)
        #expect(navigation.scrollTarget == nil)
    }

    @Test func keywordListsSplitAtCommas() {
        #expect(SettingsSearch.keywords(from: "metadata, EXIF,GPS ;  place") == ["metadata", "EXIF", "GPS", "place"])
        #expect(SettingsSearch.keywords(from: "メタデータ、GPS，位置") == ["メタデータ", "GPS", "位置"])
        #expect(SettingsSearch.keywords(from: " , ").isEmpty)
    }

    @Test func matchingIgnoresCaseAndDiacriticsAndUsesAnyWord() {
        #expect(SettingsSearch.matches(["gps"], title: "Location", keywords: ["GPS"]))
        #expect(SettingsSearch.matches(["ubicacion"], title: "Ubicación", keywords: []))
        #expect(SettingsSearch.matches(["zzz", "loc"], title: "Location", keywords: []))
        #expect(!SettingsSearch.matches(["zzz"], title: "Location", keywords: ["GPS"]))
        #expect(!SettingsSearch.matches([], title: "Location", keywords: []))
        #expect(!SettingsSearch.matches(["zzz", "loc"], title: "Location", keywords: [], requiresAll: true))
        #expect(SettingsSearch.matches(["gps", "loc"], title: "Location", keywords: ["GPS"], requiresAll: true))
        #expect(!SettingsSearch.matches([], title: "Location", keywords: [], requiresAll: true))
        #expect(SettingsSearch.words(of: "  shutter   flash ") == ["shutter", "flash"])
        #expect(SettingsSearch.words(of: "   ").isEmpty)
    }

    @Test func gpsFindsLocationAndTheDetailsPage() {
        let found = SettingsSearch.settings(matching: "gps", availability: .init())
        #expect(found.contains(.detailsLocation))
        #expect(found.contains(.details))
    }

    /// The keywords in the string catalog are the ones the code documents: "heic", "jpg" and "mp"
    /// were missing from the catalog, which is what the app reads.
    @Test func fileFormatAbbreviationsFindTheirSettings() {
        #expect(SettingsSearch.settings(matching: "heic", availability: .init()).contains(.formats))
        #expect(SettingsSearch.settings(matching: "jpg", availability: .init()).contains(.copies))
        #expect(SettingsSearch.settings(matching: "mp", availability: .init(offersPhotoSize: true)).contains(.photoSize))
        #expect(SettingsSearch.settings(matching: "metadata", availability: .init()).contains(.detailsLocation))
    }

    @Test func resetFindsPresetsAndRestoreDefaults() {
        let found = SettingsSearch.settings(matching: "reset", availability: .init())
        #expect(found.contains(.presets))
        #expect(found.contains(.factoryDefaults))
        #expect(found.contains(.copiesRestoreDefaults))
    }

    @Test func manualPointsToTheCamera() {
        let pointers = SettingsSearch.pointers(matching: "manual")
        #expect(pointers.map(\.id) == ["manualControls"])
        #expect(pointers.first?.place == .besideLenses)
        // "flashlight" is a keyword of Light.
        #expect(SettingsSearch.pointers(matching: "flash").map(\.id) == ["flash", "light"])
        #expect(SettingsSearch.pointers(matching: "").isEmpty)
        #expect(SettingsSearch.settings(matching: "", availability: .init()).isEmpty)
    }

    @Test func everyWordNarrowsAndAnyWordWidens() {
        // Every word: one result.
        #expect(SettingsSearch.settings(matching: "focus on faces", availability: .init()) == [.focusOnFaces])
        #expect(SettingsSearch.pointers(matching: "focus on faces").isEmpty)
        // No item has every word: each thing searched for is listed, as drawn.
        let mixed = SettingsSearch.results(for: "shutter flash manual", availability: .init())
        #expect(mixed.pointers.map(\.id).contains("manualControls"))
        #expect(mixed.pointers.map(\.id).contains("flash"))
        #expect(mixed.pointers.map(\.id).contains("selfTimer"))
        #expect(mixed.settings.contains(.fastShutter))
        #expect(SettingsSearch.results(for: "zqxj", availability: .init()).settings.isEmpty)
    }

    @Test func everyPointerHasAPlace() {
        let ids = CameraPointer.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(
            Set(ids)
                == [
                    "manualControls", "selfTimer", "burst", "interval", "astro", "flash", "light", "exposure", "closeUp",
                    "farFocus", "magnify", "grid", "level", "compare",
                ])
    }

    @Test func everyRowIsFoundByItsOwnTitle() {
        let all = SettingsSearch.Availability(
            hasPresets: true, offersPhotoSize: true, hasFrontCamera: true, offersLocation: true,
            offersProcessedMarker: true, offersLiveActivity: true)
        for id in SettingsSearch.searchable {
            let title = String(localized: SettingsText.title(of: id))
            #expect(SettingsSearch.settings(matching: title, availability: all).contains(id), "\(id): \(title)")
        }
    }

    @Test func itemsTheDeviceDoesNotShowAreNotFound() {
        let none = SettingsSearch.Availability(
            hasPresets: false, offersPhotoSize: false, hasFrontCamera: false, offersLocation: false,
            offersProcessedMarker: false, offersLiveActivity: false)
        for (query, id) in [
            ("Presets", SettingsID.presets), ("Photo Size", .photoSize), ("Mirror", .mirrorFrontCamera),
            ("gps", .detailsLocation), ("Processed", .showProcessedMarker), ("Live Activity", .liveActivity),
        ] {
            #expect(!SettingsSearch.settings(matching: query, availability: none).contains(id), "\(id)")
        }
    }

    @Test func placesNameTheGroupAndThePage() {
        #expect(SettingsSearch.place(of: .detailsLocation) == "Privacy › Details in Each Photo")
        #expect(SettingsSearch.place(of: .details) == "Privacy")
        #expect(SettingsSearch.place(of: .factoryDefaults) == "Presets")
        #expect(SettingsSearch.place(of: .presets) == "Settings")
        #expect(SettingsSearch.spokenPlace(of: .detailsLocation) == "Privacy, Details in Each Photo")
        #expect(SettingsSearch.spokenPlace(of: .factoryDefaults) == "Presets")
        #expect(SettingsSearch.spokenPlace(of: .nightMode) == "Screen")
        #expect(SettingsText.spokenResult("Location", "Privacy, Details in Each Photo") == "Location, in Privacy, Details in Each Photo")
    }

    @Test func overlayValueNamesWhatIsOn() {
        var options = OverlayOptions()
        #expect(OverlaySettingsView.onNames(of: options).isEmpty)
        options.showsGrid = true
        options.showsLiveReadout = true
        #expect(OverlaySettingsView.onNames(of: options).map { String(localized: $0) } == ["Grid", "Live Camera Readout"])
        options.showsLevel = true
        options.showsFocusPeaking = true
        options.showsHistogram = true
        #expect(OverlaySettingsView.onNames(of: options).count == 5)
    }

    @Test func signatureRowIsInformationWhenSigningIsOff() {
        #expect(PhotoDetailsSections.signatureSymbol(.signed) == "checkmark.seal.fill")
        #expect(PhotoDetailsSections.signatureSymbol(.unsigned(.turnedOff)) == "info.circle")
        for reason in [SignatureStatus.UnsignedReason.unavailable, .failed, .signedFileFailedCheck] {
            #expect(PhotoDetailsSections.signatureSymbol(.unsigned(reason)) == "exclamationmark.triangle.fill")
        }
    }
}
