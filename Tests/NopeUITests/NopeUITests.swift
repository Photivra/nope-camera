import Foundation
import SwiftUI
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

struct CameraLayoutTests {
    @Test func tallPhoneSpaceStacksOrScrolls() {
        let phone = CGSize(width: 402, height: 778)
        #expect(CameraLayout.arrangement(for: phone, isAccessibilitySize: false, isRegularSize: false) == .stacked)
        #expect(CameraLayout.arrangement(for: phone, isAccessibilitySize: true, isRegularSize: false) == .scrolling)
    }

    @Test func wideSpaceOrFullIPadUsesTheColumn() {
        let landscape = CGSize(width: 874, height: 402)
        #expect(CameraLayout.arrangement(for: landscape, isAccessibilitySize: false, isRegularSize: false) == .column)
        #expect(CameraLayout.arrangement(for: landscape, isAccessibilitySize: true, isRegularSize: false) == .column)
        let iPadPortrait = CGSize(width: 820, height: 1160)
        #expect(CameraLayout.arrangement(for: iPadPortrait, isAccessibilitySize: false, isRegularSize: true) == .column)
        #expect(CameraLayout.arrangement(for: iPadPortrait, isAccessibilitySize: true, isRegularSize: true) == .scrolling)
    }

    @Test func bandsFitBelowThePictureOnALargePhoneButOverlayOnA47InchPhone() {
        // iPhone 16 Pro: 874 pt tall, minus the safe area (62 + 34), the top bar and the shutter row.
        let large = CGSize(width: 402, height: 874 - 96 - CameraLayout.topBarHeight - CameraLayout.shutterRowHeight)
        #expect(!CameraLayout.bandsOverlayPicture(in: large, bandsHeight: 88))
        // 4.7-inch iPhone: 667 pt tall, a 20-point status bar, no home indicator.
        let small = CGSize(width: 375, height: 667 - 20 - CameraLayout.topBarHeight - CameraLayout.shutterRowHeight)
        #expect(CameraLayout.bandsOverlayPicture(in: small, bandsHeight: 44))
    }

    @Test func pictureFollowsTheWindowShape() {
        #expect(CameraLayout.pictureHeight(forWidth: 300) == 400)
        #expect(CameraLayout.pictureAspectRatio(in: CGSize(width: 300, height: 600)) == 0.75)
        #expect(CameraLayout.pictureAspectRatio(in: CGSize(width: 600, height: 300)) == CameraLayout.photoAspectRatio)
    }

    @Test func uprightRotationTurnsAQuarterTurn() {
        #expect(UprightRotation.portrait.angle == .zero)
        #expect(UprightRotation.landscapeLeft.angle == .degrees(90))
        #expect(UprightRotation.landscapeRight.angle == .degrees(-90))
        #expect(!UprightRotation.portrait.isSideways)
        #expect(UprightRotation.landscapeLeft.isSideways)
    }
}

@MainActor
struct CaptureFeedbackTests {
    static let signed = SavedPhoto(formats: [.raw, .heif], isProcessedFallback: false, signature: .signed, metadata: [:])
    static let unsigned = SavedPhoto(
        formats: [.raw, .heif], isProcessedFallback: false, signature: .unsigned(.failed), metadata: [:])

    @Test func everyFailureHasOneActionOrNone() {
        #expect(FailureAction(for: .photosAccessDenied) == .openSettings)
        for error in [CaptureError.configurationFailed, .captureFailed, .developmentFailed, .metadataNotAllowed, .saveFailed] {
            #expect(FailureAction(for: error) == .tryAgain)
        }
        for error in [CaptureError.notRunning, .blankPicture, .savingUnavailable] {
            #expect(FailureAction(for: error) == nil)
        }
    }

    @Test func savedMessagesNeverHideAMissingSignature() {
        #expect(CaptureMessages.message(forSaved: [Self.signed]) == "Saved and signed.")
        #expect(CaptureMessages.message(forSaved: [Self.signed, Self.signed, Self.signed]) == "3 photos saved and signed.")
        #expect(CaptureMessages.message(forSaved: [Self.signed, Self.unsigned]).hasPrefix("Saved. Not signed"))
    }

    @Test func statusesReadAsSavesOrErrors() {
        #expect(CaptureMessages.savedPhotos(in: .saved(Self.signed)) == [Self.signed])
        #expect(CaptureMessages.savedPhotos(in: .savedBracket([Self.signed])) == [Self.signed])
        #expect(CaptureMessages.savedPhotos(in: .savedBurst([Self.signed, Self.signed])) == [Self.signed, Self.signed])
        #expect(CaptureMessages.savedPhotos(in: .saving) == nil)
        #expect(CaptureMessages.error(in: .failed(.saveFailed)) == .saveFailed)
        #expect(CaptureMessages.error(in: .idle) == nil)
    }

    @Test func formatNamesJoinWithPlus() {
        #expect(FormatChip.names(of: [.raw, .heif]) == "RAW + HEIF")
        #expect(FormatChip.names(of: [.jpeg]) == "JPEG")
    }
}

@MainActor
struct RegistryTests {
    /// A context with a manual-capable simulated camera and fresh settings.
    static func context(suite: String) -> CameraControlContext {
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        return CameraControlContext(model: model, settings: NopeSettings(defaults: store))
    }

    @Test func defaultsShowNoPillsAndNoWarnings() {
        let context = Self.context(suite: "RegistryTests.defaults")
        #expect(StatePills.current(context).isEmpty)
        #expect(CameraWarnings.current(context, lastSignature: nil).isEmpty)
        #expect(CameraWarnings.current(context, lastSignature: .signed).isEmpty)
        #expect(CameraWarnings.current(context, lastSignature: .unsigned(.turnedOff)).isEmpty)
    }

    @Test func signingOffOrFailedIsAWarning() {
        let context = Self.context(suite: "RegistryTests.signing")
        #expect(CameraWarnings.current(context, lastSignature: .unsigned(.failed)).map(\.id) == ["signing"])
        context.settings.setSignsPhotos(false)
        #expect(CameraWarnings.current(context, lastSignature: nil).map(\.id) == ["signing"])
    }

    @Test func trayEndsWithHideControls() {
        let context = Self.context(suite: "RegistryTests.tray")
        let items = QuickControls.current(context)
        #expect(items.last?.id == "hideControls")
        #expect(items.allSatisfy { !$0.isOn })
    }

    @Test func trayItemsReportWhetherTheyAreOn() {
        let on = QuickControlItem(id: "a", title: Text(verbatim: "A"), systemImage: "a.circle", kind: .toggle(isOn: true, set: { _ in }))
        #expect(on.isOn)
        let options = [
            QuickControlItem.Option(id: "off", title: Text(verbatim: "Off"), isSelected: false, select: {}),
            QuickControlItem.Option(id: "3", title: Text(verbatim: "3 s"), isSelected: true, select: {}),
        ]
        #expect(QuickControlItem(id: "b", title: Text(verbatim: "B"), systemImage: "b.circle", kind: .menu(options)).isOn)
        #expect(!QuickControlItem(id: "c", title: Text(verbatim: "C"), systemImage: "c.circle", kind: .menu([])).isOn)
    }
}

@MainActor
struct DriveTextTests {
    @Test func burstEndsArePlainSentences() {
        #expect(DriveText.endMessage(BurstResult(end: .stopped, saved: 3)) == nil)
        #expect(DriveText.endMessage(BurstResult(end: .failed, saved: 3)) == nil)
        #expect(DriveText.endMessage(BurstResult(end: .limitReached, saved: 50)) == "Burst stopped at 50 photos, the most one burst takes.")
        #expect(DriveText.endMessage(BurstResult(end: .storageFull, saved: 2)) == "Burst stopped: storage is full.")
        #expect(DriveText.endMessage(BurstResult(end: .cameraStopped, saved: 2)) == "Burst stopped: the camera stopped.")
    }

    @Test func secondsUseSystemFormatting() {
        #expect(DriveText.shortSeconds(3).contains("3"))
        #expect(DriveText.spokenSeconds(10).contains("10"))
        #expect(DriveText.systemImage(for: .burst) != DriveText.systemImage(for: .single))
    }
}
