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
        // At accessibility sizes every window scrolls: the column has no room for the enlarged
        // manual controls list, so it offered only All Auto and Pro Tools.
        #expect(CameraLayout.arrangement(for: landscape, isAccessibilitySize: true, isRegularSize: false) == .scrolling)
        let iPadLandscape = CGSize(width: 1180, height: 820)
        #expect(CameraLayout.arrangement(for: iPadLandscape, isAccessibilitySize: false, isRegularSize: true) == .column)
        #expect(CameraLayout.arrangement(for: iPadLandscape, isAccessibilitySize: true, isRegularSize: true) == .scrolling)
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

    // iPhone Duo, measured on its Simulator (iOS 27.2): the space inside the safe area and the
    // size classes on each display.

    @Test func duoOuterDisplayStacksInBothOrientations() {
        // 466 × 678 pt, with the status bar in a trailing strip: 382 × 644 inside the safe area,
        // compact width and regular height. The interface stays portrait when the phone turns,
        // so the space is the same sideways.
        let outer = CGSize(width: 382, height: 644)
        let isRegular = CameraLayout.isRegularSize(horizontal: .compact, vertical: .regular)
        #expect(!isRegular)
        #expect(CameraLayout.arrangement(for: outer, isAccessibilitySize: false, isRegularSize: isRegular) == .stacked)
        #expect(CameraLayout.arrangement(for: outer, isAccessibilitySize: true, isRegularSize: isRegular) == .scrolling)
        // The whole 4:3 picture and the bands don't fit one above the other, so the bands
        // overlay the picture's bottom, as on a 4.7-inch iPhone.
        let space = CGSize(width: 382, height: 644 - CameraLayout.topBarHeight - CameraLayout.shutterRowHeight)
        #expect(CameraLayout.bandsOverlayPicture(in: space, bandsHeight: 88))
        // Icons and text turn upright on the outer display.
        #expect(UprightRotation.landscapeLeft.inWindow(isRegularSize: isRegular) == .landscapeLeft)
        #expect(UprightRotation.landscapeRight.inWindow(isRegularSize: isRegular) == .landscapeRight)
    }

    @Test func duoInnerDisplayUsesTheColumnAndRotatesForReal() {
        // 951 × 669 pt held like a book (867 × 635 inside the safe area), 669 × 951 turned
        // (669 × 835): regular in both size classes, so the window rotates as on iPad.
        let isRegular = CameraLayout.isRegularSize(horizontal: .regular, vertical: .regular)
        #expect(isRegular)
        let wide = CGSize(width: 867, height: 635)
        let tall = CGSize(width: 669, height: 835)
        #expect(CameraLayout.arrangement(for: wide, isAccessibilitySize: false, isRegularSize: isRegular) == .column)
        #expect(CameraLayout.arrangement(for: tall, isAccessibilitySize: false, isRegularSize: isRegular) == .column)
        #expect(CameraLayout.arrangement(for: wide, isAccessibilitySize: true, isRegularSize: isRegular) == .scrolling)
        #expect(CameraLayout.arrangement(for: tall, isAccessibilitySize: true, isRegularSize: isRegular) == .scrolling)
        #expect(CameraLayout.pictureAspectRatio(in: wide) == CameraLayout.photoAspectRatio)
        #expect(CameraLayout.pictureAspectRatio(in: tall) == 1 / CameraLayout.photoAspectRatio)
        // The interface already turns with the device, so nothing turns again as an upright unit.
        #expect(UprightRotation.landscapeLeft.inWindow(isRegularSize: isRegular) == .portrait)
        #expect(UprightRotation.landscapeRight.inWindow(isRegularSize: isRegular) == .portrait)
        #expect(UprightRotation.portrait.inWindow(isRegularSize: isRegular) == .portrait)
    }

    @Test func viewfinderStaysInsideTheScrollView() {
        let picture = CGRect(x: 40, y: 300, width: 210, height: 280)
        // Not clipped outside the scrolling layout.
        #expect(ViewfinderAnchors.visibleFrame(of: picture, in: nil) == picture)
        // An iPhone SE at the largest text size: the scroll view ends at 520, above the pinned
        // shutter row, so only the picture's top 220 points show.
        let scrollView = CGRect(x: 0, y: 20, width: 375, height: 500)
        #expect(ViewfinderAnchors.visibleFrame(of: picture, in: scrollView) == CGRect(x: 40, y: 300, width: 210, height: 220))
        // Scrolled up past the top: only the part still in the scroll view.
        let scrolledUp = picture.offsetBy(dx: 0, dy: -400)
        #expect(ViewfinderAnchors.visibleFrame(of: scrolledUp, in: scrollView) == CGRect(x: 40, y: 20, width: 210, height: 160))
        // Scrolled out of view: nothing.
        #expect(ViewfinderAnchors.visibleFrame(of: picture.offsetBy(dx: 0, dy: -700), in: scrollView) == .zero)
    }

    @Test func regularSizeNeedsBothSizeClasses() {
        #expect(!CameraLayout.isRegularSize(horizontal: .regular, vertical: .compact))
        #expect(!CameraLayout.isRegularSize(horizontal: .compact, vertical: .compact))
        #expect(!CameraLayout.isRegularSize(horizontal: nil, vertical: .regular))
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

/// Night mode's colors after the red multiply meet WCAG 2.2 contrast (issue #61).
@MainActor
struct NightStyleContrastTests {
    /// The WCAG 2.2 relative luminance of a color after night mode's multiply by pure red: only
    /// its red channel is left.
    static func nightLuminance(_ color: Color) -> Double {
        0.2126 * Double(color.resolve(in: EnvironmentValues()).linearRed)
    }

    /// The WCAG 2.2 contrast ratio of two relative luminances.
    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Tinted text and icons (a back button, a checkmark) are the full red, at least 4.5:1 on
    /// black; a mid gray tint showed as about 1.9:1.
    @Test func tintedTextAndIconsAreTheFullRed() {
        let tint = Self.nightLuminance(NightStyle.controlTint)
        #expect(tint == Self.nightLuminance(.white))
        #expect(Self.contrast(tint, 0) >= 4.5)
        #expect(Self.contrast(Self.nightLuminance(Color(white: 0.5)), 0) < 3)
    }

    /// A switch's knob and a slider's thumb (white, shown as the full red) stand out from their
    /// filled track by at least 3:1, as WCAG 2.2 asks of a control's parts (1.4.11).
    @Test func knobsStandOutFromTheirTracks() {
        let knob = Self.nightLuminance(.white)
        let track = Self.nightLuminance(NightStyle.trackTint)
        #expect(Self.contrast(knob, track) >= 3)
        #expect(track > 0, "the track still shows as a dark red")
    }
}
