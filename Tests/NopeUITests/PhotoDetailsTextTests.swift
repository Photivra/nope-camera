import Foundation
import NopeCore
import Testing
import UIKit

@testable import NopeUI

/// The words and formats of What's in This Photo (`docs/design/BUILD-SPEC.md`, 3.15): EXIF
/// names, the app's own words where it has a control for the same thing, numbers kept for codes
/// the core doesn't name, and the Every Tag search.
@MainActor
struct PhotoDetailsTextTests {
    @Test func exifValuesUseTheAppsWordsOrTheStandardsTerms() {
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureModeValue.auto) == ControlText.mode(isManual: false))
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureModeValue.manual) == ControlText.mode(isManual: true))
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureModeValue.autoBracket) == "Auto bracket")
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureModeValue.other(7)) == "7")
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureProgramValue.normal) == "Normal program")
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureProgramValue.manual) == "Manual")
        #expect(PhotoDetailsText.name(of: PhotoDetails.ExposureProgramValue.other(12)) == "12")
        #expect(PhotoDetailsText.name(of: PhotoDetails.MeteringValue.centerWeighted) == ControlText.name(MeteringMode.center))
        #expect(PhotoDetailsText.name(of: PhotoDetails.MeteringValue.spot) == ControlText.name(MeteringMode.spot))
        #expect(PhotoDetailsText.name(of: PhotoDetails.MeteringValue.pattern) == "Pattern")
        #expect(PhotoDetailsText.name(of: PhotoDetails.MeteringValue.otherMode) == "Other")
        #expect(PhotoDetailsText.name(of: PhotoDetails.MeteringValue.other(9)) == "9")
    }

    @Test func everyTagSearchMatchesNamesIgnoringCase() {
        let entries = ["ExposureTime", "FNumber", "DNGVersion"].map { name in
            PhotoDetails.TagEntry(
                id: name, name: name, place: .exif, value: .present, tagNumber: nil, control: .alwaysSaved,
                isIdentifying: false)
        }
        #expect(EveryTagPage.matching(entries, query: "").count == 3)
        #expect(EveryTagPage.matching(entries, query: "  ").count == 3)
        #expect(EveryTagPage.matching(entries, query: "exposure").map(\.name) == ["ExposureTime"])
        #expect(EveryTagPage.matching(entries, query: "zzz").isEmpty)
    }

    @Test func numbersAndLengthsUseTheSystemFormats() {
        #expect(ExposureSection.millimeters(6.86).contains("6.86"))
        #expect(PhotoDetailsText.numbers([528, 528]).contains("528"))
        let file = PhotoDetails.File(
            format: .raw, byteCount: 1, pixelWidth: 4032, pixelHeight: 3024, bitDepth: 12, colorFilterPattern: nil,
            blackLevels: [], whiteLevels: [], storesLensCorrections: false, processing: .none, contentCredentials: nil,
            contents: [])
        #expect(PhotoDetailsText.pixels(of: file) == "4032 × 3024 pixels")
    }

    @Test func aLensIsNamedByItsZoomOrItsKind() {
        let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1)
        let front = Lens(id: "front", kind: .front, bayerRAWFormat: nil)
        #expect(PhotoDetailsText.name(of: wide) == "1×")
        #expect(PhotoDetailsText.name(of: front) == LensName.string(for: .front))
    }

    // MARK: - The summary card (issue #118; docs/design/finish-1.0.md, section 3)

    static func file(_ format: PhotoFormat, _ processing: PhotoDetails.Processing) -> PhotoDetails.File {
        PhotoDetails.File(
            format: format, byteCount: 1, pixelWidth: 4032, pixelHeight: 3024, bitDepth: nil, colorFilterPattern: nil,
            blackLevels: [], whiteLevels: [], storesLensCorrections: false, processing: processing, contentCredentials: nil,
            contents: [])
    }

    static func details(
        _ files: [PhotoDetails.File], signature: SignatureStatus = .unsigned(.turnedOff), items: [PhotoDetails.ItemReceipt] = []
    ) -> PhotoDetails {
        PhotoDetails(files: files, exposure: nil, items: items, lockedItems: [], signature: signature, timings: SaveTimings())
    }

    /// "iPhone" reads "iPad" on an iPad (the catalog's device variations).
    static var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    @Test func summaryRowsAreInTheirFixedOrder() {
        let rows = PhotoSummaryCard.rows(of: Self.details([Self.file(.raw, .none)]))
        #expect(rows.map(\.id) == [.kind, .signature, .details, .location])
        // Every row has a symbol, so every row's words start in the symbol column's width.
        #expect(rows.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test func summaryKindRowSaysWhatTheFileIs() {
        let raw = PhotoSummaryCard.rows(of: Self.details([Self.file(.raw, .none)]))[0]
        #expect(raw == .init(id: .kind, symbol: "camera", tone: .plain, title: "RAW: one frame of sensor data", detail: nil))
        let copy = PhotoSummaryCard.rows(of: Self.details([Self.file(.raw, .none), Self.file(.heif, .developed(.standard))]))[0]
        #expect(copy.title == "RAW: one frame of sensor data, and a HEIF copy developed by nope.")
        let processed = PhotoSummaryCard.rows(of: Self.details([Self.file(.heif, .byDevice)]))[0]
        #expect(
            processed
                == .init(
                    id: .kind, symbol: "exclamationmark.triangle.fill", tone: .warning, title: "Processed by this \(Self.device)",
                    detail: "This lens can't save RAW"))
        #expect(processed.spokenLabel == "Warning, Processed by this \(Self.device), This lens can't save RAW")
    }

    @Test func summarySignatureRowIsAStateAndItsReason() {
        func row(_ signature: SignatureStatus) -> PhotoSummaryCard.Row {
            PhotoSummaryCard.rows(of: Self.details([Self.file(.raw, .none)], signature: signature))[1]
        }
        #expect(row(.signed) == .init(id: .signature, symbol: "checkmark.seal.fill", tone: .fact, title: "Signed", detail: nil))
        #expect(row(.signed).spokenLabel == "Signed")
        let off = row(.unsigned(.turnedOff))
        #expect(off == .init(id: .signature, symbol: "info.circle", tone: .plain, title: "Not signed", detail: "Signing is off in Settings"))
        // Signing off is the person's choice, not a warning.
        #expect(off.spokenLabel == "Not signed, Signing is off in Settings")
        let failed = row(.unsigned(.failed))
        #expect(
            failed
                == .init(
                    id: .signature, symbol: "exclamationmark.triangle.fill", tone: .warning, title: "Not signed",
                    detail: "The signature couldn't be made"))
        #expect(failed.spokenLabel == "Warning, Not signed, The signature couldn't be made")
        #expect(row(.unsigned(.unavailable)).detail == "This version of the app can't sign photos")
        #expect(row(.unsigned(.signedFileFailedCheck)).detail == "The signed file didn't pass the check")
        #expect(row(.unsigned(.unavailable)).tone == .warning)
        // "Saved." is gone: every photo in the sheet was saved.
        for signature in [SignatureStatus.signed, .unsigned(.turnedOff), .unsigned(.failed)] {
            #expect(!row(signature).spokenLabel.contains("Saved"))
        }
    }

    @Test func summaryDetailsAndLocationRows() {
        let none = PhotoSummaryCard.rows(of: Self.details([Self.file(.raw, .none)]))
        #expect(none[2] == .init(id: .details, symbol: "list.bullet", tone: .plain, title: "No optional details in the files", detail: nil))
        #expect(none[3] == .init(id: .location, symbol: "location.slash", tone: .plain, title: "No location in the files", detail: nil))
        let kept = PhotoSummaryCard.rows(
            of: Self.details(
                [Self.file(.raw, .none)],
                items: [
                    .init(item: .location, state: .written), .init(item: .dateAndTime, state: .written),
                    .init(item: .cameraMakeAndModel, state: .written),
                ]))
        #expect(kept[2].title == "2 optional details in the files")
        #expect(
            kept[3] == .init(id: .location, symbol: "exclamationmark.triangle.fill", tone: .warning, title: "Location is in the files", detail: nil))
        #expect(kept[3].spokenLabel == "Warning, Location is in the files")
    }
}
