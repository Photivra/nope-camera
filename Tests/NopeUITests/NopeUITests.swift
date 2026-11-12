import Foundation
import NopeCore
import Testing

@testable import NopeUI

struct LocalizationTests {
    static let launchLocales = ["en", "ja", "es", "fr", "de", "ko", "zh-Hant", "zh-Hans", "pt-BR", "it", "nl"]

    @Test func bundleShipsEveryLaunchLocale() {
        let available = Set(Bundle.module.localizations.map { $0.lowercased() })
        for locale in Self.launchLocales {
            #expect(available.contains(locale.lowercased()), "missing \(locale)")
        }
    }

    @Test(arguments: launchLocales.filter { $0 != "en" })
    func stringsAreTranslated(locale: String) throws {
        let path = try #require(Bundle.module.path(forResource: locale, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let value = bundle.localizedString(forKey: "Allow Camera Access", value: "MISSING", table: nil)
        #expect(value != "MISSING")
        #expect(value != "Allow Camera Access")
        let honesty = bundle.localizedString(forKey: "No RAW on This Lens", value: "MISSING", table: "Honesty")
        #expect(honesty != "MISSING")
        #expect(honesty != "No RAW on This Lens")
    }
}

@MainActor
struct CameraScreenTests {
    @Test func screenCanBeCreatedForAModel() {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .notDetermined))
        let store = UserDefaults(suiteName: "CameraScreenTests")!
        _ = CameraScreen(model: model, settings: NopeSettings(defaults: store))
        #expect(model.state == .starting)
    }
}

struct CameraLayoutTests {
    @Test(arguments: [CGSize(width: 400, height: 800), CGSize(width: 500, height: 500), CGSize(width: 820, height: 1180)])
    func tallOrSquareSpaceStacks(size: CGSize) {
        #expect(CameraLayout.arrangement(for: size, isAccessibilitySize: false) == .stacked)
        #expect(CameraLayout.arrangement(for: size, isAccessibilitySize: true) == .stacked)
    }

    @Test func freeWidthBeyondTheMinimumGoesToTheColumn() {
        // Wide and short: a full-height 4:3 viewfinder leaves more than the minimum column.
        let size = CGSize(width: 1000, height: 450)
        let columnWidth = 1000 - 450 * CameraLayout.photoAspectRatio - CameraLayout.spacing
        #expect(columnWidth > CameraLayout.minimumColumnWidth)
        #expect(CameraLayout.arrangement(for: size, isAccessibilitySize: false) == .sideBySide(columnWidth: columnWidth))
    }

    @Test func wideSpaceKeepsTheMinimumColumn() {
        // An iPad and an iPhone Pro Max in landscape, inside the safe area and padding: a
        // full-height 4:3 viewfinder leaves less than the minimum.
        for size in [CGSize(width: 1148, height: 760), CGSize(width: 776, height: 377)] {
            #expect(CameraLayout.arrangement(for: size, isAccessibilitySize: false) == .sideBySide(columnWidth: 300))
        }
        // At accessibility sizes the iPad gets the wider minimum; the iPhone is capped at 45%.
        #expect(
            CameraLayout.arrangement(for: CGSize(width: 1148, height: 760), isAccessibilitySize: true)
                == .sideBySide(columnWidth: 360))
        #expect(
            CameraLayout.arrangement(for: CGSize(width: 776, height: 377), isAccessibilitySize: true)
                == .sideBySide(columnWidth: 776 * CameraLayout.maximumColumnFraction))
    }

    @Test func narrowSpaceCapsTheColumn() {
        // Too narrow for the minimum: the viewfinder keeps more than half the width.
        let size = CGSize(width: 300, height: 200)
        #expect(CameraLayout.arrangement(for: size, isAccessibilitySize: false) == .sideBySide(columnWidth: 300 * 0.45))
    }

    @Test func rowsKeepOrderAndShortenTheLastRow() {
        #expect(CameraLayout.rows(of: [1, 2, 3, 4], perRow: 2) == [[1, 2], [3, 4]])
        #expect(CameraLayout.rows(of: [1, 2, 3], perRow: 2) == [[1, 2], [3]])
        #expect(CameraLayout.rows(of: [Int](), perRow: 2).isEmpty)
        #expect(CameraLayout.rows(of: [1, 2], perRow: 0) == [[1], [2]])
    }
}

@MainActor
struct AboutScreenTests {
    /// The repository root, found from this file's path.
    static let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test(arguments: [("GPL-3.0", "LICENSE"), ("NOTICE", "NOTICE")])
    func bundledLegalTextsMatchTheRepository(resource: String, repositoryFile: String) throws {
        let original = try String(contentsOf: Self.repositoryRoot.appending(path: repositoryFile), encoding: .utf8)
        #expect(LegalTextView.text(named: resource) == original)
    }

    @Test func sourceLinkIsHTTPS() {
        #expect(AboutScreen.sourceURL.scheme == "https")
        #expect(AboutScreen.sourceURL.absoluteString == "https://github.com/Photivra/nope-camera")
    }

    @Test func noticeCarriesTheDNGNotice() {
        #expect(LegalTextView.text(named: "NOTICE").contains(AboutScreen.dngNotice))
    }

    @Test func missingTextIsEmpty() {
        #expect(LegalTextView.text(named: "missing").isEmpty)
    }

    @Test func paragraphsSplitAtBlankLines() {
        #expect(LegalTextView.paragraphs(of: "  One\n line \n\n\n        Two\n\n") == ["One\nline", "Two"])
        let wrapped = String(repeating: "word ", count: 13)
        #expect(LegalTextView.paragraphs(of: "  \(wrapped)\n  end") == ["\(wrapped.trimmingCharacters(in: .whitespaces)) end"])
    }

    @Test func versionReadsTheInfoDictionary() {
        #expect(AboutScreen.version(from: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"]) == "0.1.0 (7)")
        #expect(AboutScreen.version(from: ["CFBundleShortVersionString": "0.1.0"]) == "0.1.0")
        #expect(AboutScreen.version(from: ["CFBundleVersion": "7"]) == "(7)")
        #expect(AboutScreen.version(from: [:]).isEmpty)
    }
}

@MainActor
struct SettingsTextTests {
    @Test func formatSummaryListsAvailableFormats() {
        let store = UserDefaults(suiteName: "SettingsTextTests")!
        store.removePersistentDomain(forName: "SettingsTextTests")
        let settings = NopeSettings(defaults: store)
        #expect(FormatsSettingsView.summary(of: settings, deviceSupportsBayerRAW: false) == "HEIF")
        #expect(FormatsSettingsView.summary(of: settings, deviceSupportsBayerRAW: true).contains("RAW (DNG)"))
        #expect(FormatsSettingsView.name(of: .jpeg) == "JPEG")
    }

    @Test(arguments: LocalizationTests.launchLocales)
    func privacyTextsAreTranslated(locale: String) {
        var resources = MetadataItem.allCases.flatMap { [PrivacySettingsView.title(of: $0), PrivacySettingsView.explanation(of: $0)] }
        resources += LockedMetadataItem.allCases.flatMap { [PrivacySettingsView.title(of: $0), PrivacySettingsView.explanation(of: $0)] }
        for var resource in resources {
            let english = String(localized: resource)
            resource.locale = Locale(identifier: locale)
            let translated = String(localized: resource)
            #expect(!translated.isEmpty)
            if locale != "en" {
                #expect(translated != english || english == "Orientation", "\(english) in \(locale)")
            }
        }
    }
}
