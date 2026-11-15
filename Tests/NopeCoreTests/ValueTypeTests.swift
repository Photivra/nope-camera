import Foundation
import NopeCore
import Testing

struct DeviceCapabilitiesTests {
    static let front = Lens(id: "front", kind: .front, bayerRAWFormat: nil)
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")
    static let ultraWide = Lens(id: "ultra", kind: .ultraWide, bayerRAWFormat: "rgg4")

    @Test func noneHasNoCamera() {
        #expect(!DeviceCapabilities.none.hasCamera)
        #expect(!DeviceCapabilities.none.supportsBayerRAW)
        #expect(DeviceCapabilities.none.defaultLens == nil)
    }

    @Test func rawSupportComesFromAnyLens() {
        #expect(DeviceCapabilities(lenses: [Self.front]).hasCamera)
        #expect(!DeviceCapabilities(lenses: [Self.front]).supportsBayerRAW)
        #expect(DeviceCapabilities(lenses: [Self.front, Self.wide]).supportsBayerRAW)
    }

    @Test func defaultLensPrefersWide() {
        #expect(DeviceCapabilities(lenses: [Self.ultraWide, Self.wide, Self.front]).defaultLens == Self.wide)
        #expect(DeviceCapabilities(lenses: [Self.front, Self.ultraWide]).defaultLens == Self.front)
    }

    @Test func findsLensByID() {
        let capabilities = DeviceCapabilities(lenses: [Self.ultraWide, Self.wide])
        #expect(capabilities.lens(withID: "wide") == Self.wide)
        #expect(capabilities.lens(withID: "missing") == nil)
    }
}

struct LensTests {
    @Test func defaultsAreUnknown() {
        let lens = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: "rgg4")
        #expect(lens.id == "tele")
        #expect(lens.kind == .telephoto)
        #expect(lens.supportsBayerRAW)
        #expect(lens.bayerRAWFormat == "rgg4")
        #expect(lens.processedFallback == .heif)
        #expect(lens.magnification == nil)
        #expect(lens.isoRange == nil)
        #expect(lens.exposureDurationRange == nil)
        #expect(lens.aperture == nil)
        #expect(lens.maxBracketedPhotoCount == 0)
        #expect(lens.photoDimensions.isEmpty)
        #expect(Lens.Kind.allCases.count == 4)
    }

    @Test func keepsEveryCapability() {
        let size = PhotoDimensions(width: 4032, height: 3024)
        let lens = Lens(
            id: "wide", kind: .wide, bayerRAWFormat: nil, processedFallback: .jpeg, magnification: 1,
            isoRange: 50...12800, exposureDurationRange: 0.000014...1, aperture: .fixed(1.78),
            maxBracketedPhotoCount: 8, photoDimensions: [size])
        #expect(!lens.supportsBayerRAW)
        #expect(lens.processedFallback == .jpeg)
        #expect(lens.magnification == 1)
        #expect(lens.isoRange == 50...12800)
        #expect(lens.exposureDurationRange == 0.000014...1)
        #expect(lens.aperture == .fixed(1.78))
        #expect(lens.maxBracketedPhotoCount == 8)
        #expect(lens.photoDimensions == [size])
        #expect(ProcessedFallback.allCases == [.heif, .jpeg])
    }
}

struct PhotoDimensionsAndApertureTests {
    @Test func pixelCount() {
        let size = PhotoDimensions(width: 4032, height: 3024)
        #expect(size.width == 4032 && size.height == 3024)
        #expect(size.pixelCount == 12_192_768)
    }

    @Test func fixedAndVariableApertures() {
        let fixed = ApertureRange.fixed(2.8)
        #expect(fixed.minimumFNumber == 2.8 && fixed.maximumFNumber == 2.8)
        #expect(fixed.recommendedStops == [2.8])
        #expect(!fixed.isVariable)
        let variable = ApertureRange(minimumFNumber: 1.4, maximumFNumber: 8, recommendedStops: [1.4, 2.8, 8])
        #expect(variable.isVariable)
    }
}

struct CaptureFormatTests {
    @Test func bayerLensGivesRAW() {
        let request = CaptureRequest(lens: Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4"))
        #expect(request.format == .bayerRAW(pixelFormat: "bgg4"))
        #expect(request.format.isBayerRAW)
        #expect(request.lens.id == "wide")
    }

    @Test func explicitFormatOverridesTheLensChoice() {
        let lens = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")
        let request = CaptureRequest(lens: lens, format: .processedFallback(.heif))
        #expect(request.lens == lens)
        #expect(request.format == .processedFallback(.heif))
        #expect(request != CaptureRequest(lens: lens))
    }

    @Test(arguments: ProcessedFallback.allCases)
    func lensWithoutRAWGivesItsFallback(fallback: ProcessedFallback) {
        let format = CaptureFormat(for: Lens(id: "t", kind: .telephoto, bayerRAWFormat: nil, processedFallback: fallback))
        #expect(format == .processedFallback(fallback))
        #expect(!format.isBayerRAW)
    }

    @Test func capturedPhotoKeepsItsValues() {
        let photo = CapturedPhoto(
            data: Data([1, 2]), format: .processedFallback(.heif), lensID: "t",
            dimensions: PhotoDimensions(width: 2, height: 1), exposureDuration: 0.01, iso: 200)
        #expect(photo.data == Data([1, 2]))
        #expect(photo.format == .processedFallback(.heif))
        #expect(photo.lensID == "t")
        #expect(photo.dimensions == PhotoDimensions(width: 2, height: 1))
        #expect(photo.exposureDuration == 0.01)
        #expect(photo.iso == 200)
        #expect(photo.rawImageData == nil)
    }

    @Test func savedPhotoAndFilesKeepTheirValues() {
        let saved = SavedPhoto(formats: [.heif], isProcessedFallback: true, signature: .signed, metadata: [:])
        #expect(saved.formats == [.heif])
        #expect(saved.isProcessedFallback)
        #expect(saved.signature == .signed)
        #expect(SignatureStatus.UnsignedReason.allCases.count == 4)
        let file = PhotoFile(format: .raw, data: Data([1]))
        #expect(file.format == .raw && file.data == Data([1]))
        let request = CaptureRequest(lens: Lens(id: "t", kind: .telephoto, bayerRAWFormat: nil), format: .processedFallback(.jpeg))
        #expect(request.metadata == MetadataPlan())
    }
}

struct StatusTests {
    @Test func onlyCriticalHeatPauses() {
        #expect(HeatLevel.allCases.filter(\.requiresPause) == [.critical])
        #expect(HeatLevel.nominal < HeatLevel.critical)
    }

    @Test func onlyRunningCanCapture() {
        let statuses: [SessionStatus] = [
            .stopped, .starting, .running, .interrupted(.other), .pausedForHeat, .failed(.configurationFailed),
            .noPicture,
        ]
        #expect(statuses.filter(\.canCapture) == [.running])
        #expect(InterruptionReason.allCases.count == 5)
        #expect(CaptureError.allCases.count == 9)
    }
}

struct PermissionTests {
    @Test func permissionCasesAreComplete() {
        #expect(CameraPermission.allCases.count == 4)
    }
}

struct PhotoFormatTests {
    @Test func defaultIsRAWAndHEIF() {
        #expect(PhotoFormat.defaultSelection == [.raw, .heif])
    }

    @Test(arguments: [(PhotoFormat.raw, false), (.heif, true), (.jpeg, true)])
    func developedFormats(format: PhotoFormat, developed: Bool) {
        #expect(format.isDevelopedFromRAW == developed)
    }
}
