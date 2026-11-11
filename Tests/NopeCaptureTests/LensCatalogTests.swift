import NopeCore
import Testing

@testable import NopeCapture

/// Builds a camera description with plausible iPhone values.
func camera(
    _ id: String, _ type: CameraDeviceDescription.DeviceType, _ position: CameraDeviceDescription.Position = .back,
    fieldOfView: Double = 70, virtual: Bool = false,
    raw: [CameraDeviceDescription.RAWPixelFormat] = [.init(code: 0x6267_6734, isBayer: true)], hevc: Bool = true
) -> CameraDeviceDescription {
    CameraDeviceDescription(
        uniqueID: id, deviceType: type, position: position, isVirtual: virtual, rawPixelFormats: raw,
        supportsHEVC: hevc, isoRange: 50...12800, exposureDurationRange: 0.000014...1, aperture: .fixed(1.78),
        maxBracketedPhotoCount: 8,
        photoDimensions: [PhotoDimensions(width: 8064, height: 6048), PhotoDimensions(width: 4032, height: 3024)],
        fieldOfViewDegrees: fieldOfView)
}

struct LensCatalogTests {
    @Test func keepsPhysicalCamerasInDisplayOrder() {
        let lenses = LensCatalog.lenses(from: [
            camera("front", .wideAngle, .front, fieldOfView: 80),
            camera("tele", .telephoto, fieldOfView: 15.6),
            camera("triple", .other),
            camera("virtual-wide", .wideAngle, virtual: true),
            camera("wide", .wideAngle, fieldOfView: 70.3),
            camera("ultra", .ultraWide, fieldOfView: 106.2),
        ])
        #expect(lenses.map(\.id) == ["ultra", "wide", "tele", "front"])
        #expect(lenses.map(\.kind) == [.ultraWide, .wide, .telephoto, .front])
        #expect(lenses.map(\.magnification) == [0.5, 1, 5, nil])
    }

    @Test func copiesCapabilities() throws {
        let lens = try #require(LensCatalog.lenses(from: [camera("wide", .wideAngle)]).first)
        #expect(lens.bayerRAWFormat == "bgg4")
        #expect(lens.processedFallback == .heif)
        #expect(lens.isoRange == 50...12800)
        #expect(lens.exposureDurationRange == 0.000014...1)
        #expect(lens.aperture == .fixed(1.78))
        #expect(lens.maxBracketedPhotoCount == 8)
        #expect(lens.photoDimensions.first == PhotoDimensions(width: 4032, height: 3024))
    }

    @Test func proRAWIsNotBayerRAW() throws {
        let proRAW = CameraDeviceDescription.RAWPixelFormat(code: 0x6C36_3472, isBayer: false)
        let lens = try #require(
            LensCatalog.lenses(from: [camera("tele", .telephoto, raw: [proRAW], hevc: false)]).first)
        #expect(!lens.supportsBayerRAW)
        #expect(lens.processedFallback == .jpeg)
    }

    @Test func firstBayerFormatWins() throws {
        let formats: [CameraDeviceDescription.RAWPixelFormat] = [
            .init(code: 0x6C36_3472, isBayer: false), .init(code: 0x7267_6734, isBayer: true),
        ]
        let lens = try #require(LensCatalog.lenses(from: [camera("ultra", .ultraWide, raw: formats)]).first)
        #expect(lens.bayerRAWFormat == "rgg4")
    }

    @Test func withoutARearWideCameraMagnificationIsUnknown() {
        let lenses = LensCatalog.lenses(from: [
            camera("front", .wideAngle, .front), camera("ultra", .ultraWide), camera("tele", .telephoto),
        ])
        #expect(lenses.map(\.id) == ["ultra", "tele", "front"])
        #expect(lenses.allSatisfy { $0.magnification == nil })
    }

    @Test func unspecifiedPositionCountsAsRear() {
        let lenses = LensCatalog.lenses(from: [camera("wide", .wideAngle, .unspecified)])
        #expect(lenses.first?.kind == .wide)
        #expect(lenses.first?.magnification == 1)
    }

    @Test(arguments: [
        (106.2, 70.3, 0.5), (70.3, 70.3, 1.0), (31.0, 70.3, 2.5), (26.4, 70.3, 3.0), (15.6, 70.3, 5.0),
    ])
    func magnificationIsRoundedForLabels(fieldOfView: Double, reference: Double, expected: Double) {
        #expect(LensCatalog.magnification(fieldOfView: fieldOfView, reference: reference) == expected)
    }

    @Test(arguments: [(0.0, 70.0), (70.0, 0.0), (180.0, 70.0), (70.0, -1.0)])
    func invalidAnglesGiveNoMagnification(fieldOfView: Double, reference: Double) {
        #expect(LensCatalog.magnification(fieldOfView: fieldOfView, reference: reference) == nil)
    }
}
