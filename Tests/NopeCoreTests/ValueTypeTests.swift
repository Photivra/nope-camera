import NopeCore
import Testing

struct DeviceCapabilitiesTests {
    @Test func noneHasNoCamera() {
        #expect(!DeviceCapabilities.none.hasCamera)
        #expect(!DeviceCapabilities.none.supportsBayerRAW)
    }

    @Test func rawSupportComesFromAnyLens() {
        let front = Lens(id: "front", kind: .front, supportsBayerRAW: false)
        let wide = Lens(id: "wide", kind: .wide, supportsBayerRAW: true)
        #expect(DeviceCapabilities(lenses: [front]).hasCamera)
        #expect(!DeviceCapabilities(lenses: [front]).supportsBayerRAW)
        #expect(DeviceCapabilities(lenses: [front, wide]).supportsBayerRAW)
    }

    @Test func lensKeepsItsValues() {
        let lens = Lens(id: "tele", kind: .telephoto, supportsBayerRAW: true)
        #expect(lens.id == "tele")
        #expect(lens.kind == .telephoto)
        #expect(lens.supportsBayerRAW)
        #expect(Lens.Kind.allCases.count == 4)
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

struct SimulatedCaptureBackendTests {
    @Test func requestDefaultsToCurrentPermission() async {
        let backend = SimulatedCaptureBackend(permission: .denied)
        #expect(backend.permissionAfterRequest == .denied)
        #expect(await backend.requestPermission() == .denied)
        #expect(await backend.currentPermission() == .denied)
        #expect(await backend.deviceCapabilities() == .none)
        #expect(backend.capabilities == .none)
        #expect(backend.permission == .denied)
    }

    @Test func permissionCasesAreComplete() {
        #expect(CameraPermission.allCases.count == 4)
    }
}
