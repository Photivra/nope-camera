import Foundation
import NopeCore
import Testing

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
}
