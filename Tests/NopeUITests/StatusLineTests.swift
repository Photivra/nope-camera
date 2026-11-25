import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The status line's rules (docs/design/BUILD-SPEC.md, 3.2, 3.3 and 3.7): what the format status
/// shows and says, which pills exist, and the thumbnail's badge.
@MainActor
struct StatusLineTests {
    static let raw = CaptureFormat.bayerRAW(pixelFormat: "bgg4")

    @Test func rawShowsTheSealAndTheSavedFormats() {
        #expect(FormatChip.presentation(for: Self.raw, showsProcessedMarker: true) == .raw)
        #expect(FormatChip.presentation(for: Self.raw, showsProcessedMarker: false) == .raw)
        #expect(FormatChip.files(for: Self.raw, savedFormats: [.raw, .heif]) == [.raw, .heif])
        #expect(FormatChip.spokenValue(for: Self.raw, savedFormats: [.raw, .heif]) == "single-frame RAW, RAW + HEIF")
    }

    @Test func processedShowsTheMarkerOrTheFileButAlwaysSaysProcessed() {
        let heif = CaptureFormat.processedFallback(.heif)
        let jpeg = CaptureFormat.processedFallback(.jpeg)
        #expect(FormatChip.presentation(for: heif, showsProcessedMarker: true) == .processedMarker)
        #expect(FormatChip.presentation(for: heif, showsProcessedMarker: false) == .processedName)
        // The lens saves only its processed file, whatever formats are selected for RAW.
        #expect(FormatChip.files(for: heif, savedFormats: [.raw, .jpeg]) == [.heif])
        #expect(FormatChip.files(for: jpeg, savedFormats: [.raw]) == [.jpeg])
        #expect(FormatChip.spokenValue(for: heif, savedFormats: [.raw]) == "Processed: no RAW on this lens, HEIF")
        #expect(FormatChip.spokenValue(for: jpeg, savedFormats: [.raw]) == "Processed: no RAW on this lens, JPEG")
    }

    @Test func cleanViewKeepsOnlyTheMarker() {
        let heif = CaptureFormat.processedFallback(.heif)
        for showsMarker in [true, false] {
            #expect(FormatChip.isShown(for: Self.raw, showsControls: true, showsProcessedMarker: showsMarker))
            #expect(!FormatChip.isShown(for: Self.raw, showsControls: false, showsProcessedMarker: showsMarker))
            #expect(FormatChip.isShown(for: heif, showsControls: true, showsProcessedMarker: showsMarker))
        }
        #expect(FormatChip.isShown(for: heif, showsControls: false, showsProcessedMarker: true))
        #expect(!FormatChip.isShown(for: heif, showsControls: false, showsProcessedMarker: false))
    }

    @Test func thumbnailBadgeOnlyForASignatureOrAFailure() {
        func photo(_ signature: SignatureStatus) -> SavedPhoto {
            SavedPhoto(formats: [.raw], isProcessedFallback: false, signature: signature, metadata: [:])
        }
        #expect(ThumbnailSlot.badge(for: []) == nil)
        #expect(ThumbnailSlot.badge(for: [photo(.signed), photo(.signed)]) == .signed)
        // Signing off by choice is not a warning (owner decision, 2026-11-17).
        #expect(ThumbnailSlot.badge(for: [photo(.unsigned(.turnedOff))]) == nil)
        #expect(ThumbnailSlot.badge(for: [photo(.unsigned(.failed))]) == .notSigned)
        #expect(ThumbnailSlot.badge(for: [photo(.unsigned(.signedFileFailedCheck))]) == .notSigned)
        #expect(ThumbnailSlot.badge(for: [photo(.unsigned(.unavailable))]) == .notSigned)
        #expect(ThumbnailSlot.badge(for: [photo(.signed), photo(.unsigned(.failed))]) == .notSigned)
    }

    @Test func noPillRepeatsTheManualControlsButtonOrTheDriveStrip() async {
        let store = UserDefaults(suiteName: "StatusLineTests.pills")!
        store.removePersistentDomain(forName: "StatusLineTests.pills")
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        let context = CameraControlContext(model: model, settings: NopeSettings(defaults: store))
        await model.send(.start)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.drive(.setMode(.burst)))
        #expect(model.manual.isEnabled)
        #expect(model.drive.mode == .burst)
        let ids = StatePills.current(context).map(\.id)
        #expect(!ids.contains("manual") && !ids.contains("drive") && !ids.contains("astro"))
    }
}
