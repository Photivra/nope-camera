import Foundation
import Testing

@testable import NopeCore

// Tests for the RAW pairing (issue #50), front camera mirroring (issue #45), the developed
// file options (issue #57) and location tagging (issue #43).

struct SaveSettingsOptionTests {
    @Test func defaultsAreTheEarlierBehavior() {
        let settings = SaveSettings()
        #expect(settings.rawPairing == .heif)
        #expect(!settings.mirrorsFrontCamera)
        #expect(settings.fileOptions == DevelopedFileOptions())
        #expect(settings.fileOptions.isDefault)
        #expect(!settings.offersRAWPairingChoice)
    }

    /// Settings saved before these options existed still decode, with every option at its default.
    @Test func settingsSavedBeforeTheOptionsStillDecode() throws {
        let old = #"{"formats":["raw","heif","jpeg"],"metadata":{"removesAllOptionalDetails":true,"enabledItems":[],"signsPhotos":true,"ownerName":"","copyrightNotice":""},"developedLook":"flat"}"#
        let settings = try JSONDecoder().decode(SaveSettings.self, from: Data(old.utf8))
        #expect(settings.formats == [.raw, .heif, .jpeg])
        #expect(settings.developedLook == .flat)
        #expect(settings.rawPairing == .heif)
        #expect(!settings.mirrorsFrontCamera)
        #expect(settings.fileOptions.isDefault)
    }

    @Test func changedOptionsRoundTripAndDefaultsCompareEqual() throws {
        var settings = SaveSettings()
        settings.rawPairing = .jpeg
        settings.mirrorsFrontCamera = true
        var options = DevelopedFileOptions()
        options.heifBitDepth = .eight
        options.colorSpace = .sRGB
        options.heifQuality = .high
        options.jpegQuality = .medium
        settings.fileOptions = options
        let decoded = try JSONDecoder().decode(SaveSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.rawPairing == .jpeg)
        #expect(decoded.mirrorsFrontCamera)
        #expect(decoded.fileOptions == options)
        #expect(!decoded.fileOptions.isDefault)

        // Setting each option back to its default gives settings equal to the first launch.
        settings.rawPairing = .heif
        settings.mirrorsFrontCamera = false
        settings.fileOptions = DevelopedFileOptions()
        #expect(settings == SaveSettings())
    }

    @Test func thePairingChoiceAppliesOnlyWithAllThreeFormats() {
        var settings = SaveSettings()
        settings.setFormat(.jpeg, isSelected: true)
        #expect(settings.offersRAWPairingChoice)
        settings.setFormat(.raw, isSelected: false)
        #expect(!settings.offersRAWPairingChoice)
        #expect(RAWPairing.heif.format == .heif)
        #expect(RAWPairing.jpeg.format == .jpeg)
    }

    @Test func fileOptionValues() {
        let options = DevelopedFileOptions()
        #expect(options.quality(for: .heif) == .systemDefault)
        #expect(options.quality(for: .jpeg) == .maximum)
        #expect(options.quality(for: .raw) == .maximum)
        #expect(options.heifBitDepth == .ten)
        #expect(options.colorSpace == .displayP3)
        #expect(CompressionQuality.allCases.map(\.lossyCompressionQuality) == [nil, 1.0, 0.9, 0.7])
        #expect(HEIFBitDepth.allCases.map(\.rawValue) == [8, 10])
        #expect(OutputColorSpace.allCases == [.displayP3, .sRGB])
    }
}

@MainActor
struct NopeSettingsOptionTests {
    @Test func optionsAreSavedAndReloaded() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.rawPairing == .heif)
        #expect(!settings.mirrorsFrontCamera)
        #expect(settings.fileOptions.isDefault)
        #expect(!settings.offersRAWPairingChoice(deviceSupportsBayerRAW: true))
        settings.setFormat(.jpeg, isSelected: true)
        #expect(settings.offersRAWPairingChoice(deviceSupportsBayerRAW: true))
        #expect(!settings.offersRAWPairingChoice(deviceSupportsBayerRAW: false))
        settings.setRAWPairing(.jpeg)
        settings.setMirrorsFrontCamera(true)
        var options = DevelopedFileOptions()
        options.colorSpace = .sRGB
        settings.setFileOptions(options)

        let reloaded = NopeSettings(defaults: scratch.defaults)
        #expect(reloaded.rawPairing == .jpeg)
        #expect(reloaded.mirrorsFrontCamera)
        #expect(reloaded.fileOptions.colorSpace == .sRGB)
    }
}

struct RAWPairingAssetTests {
    static func file(_ format: PhotoFormat) -> PhotoFile {
        PhotoFile(format: format, data: Data(format.rawValue.utf8))
    }

    /// Every format combination, with each pairing: a RAW is paired with the chosen copy when
    /// both exist, otherwise with the one there is; every other file is its own asset.
    @Test(arguments: RAWPairing.allCases)
    func everyFormatCombination(pairing: RAWPairing) {
        let combinations: [[PhotoFormat]] = [
            [.raw], [.heif], [.jpeg], [.raw, .heif], [.raw, .jpeg], [.heif, .jpeg], [.raw, .heif, .jpeg],
        ]
        for formats in combinations {
            let assets = PhotoLibraryAsset.assets(for: formats.map(Self.file), pairing: pairing)
            let description = "\(formats), \(pairing)"
            guard formats.contains(.raw) else {
                #expect(assets.map(\.primary.format) == formats, "\(description)")
                #expect(assets.allSatisfy { $0.alternate == nil }, "\(description)")
                continue
            }
            let processed = formats.filter { $0 != .raw }
            let partner: PhotoFormat? = processed.contains(pairing.format) ? pairing.format : processed.first
            #expect(assets.first?.primary.format == .raw, "\(description)")
            #expect(assets.first?.alternate?.format == partner, "\(description)")
            #expect(assets.dropFirst().map(\.primary.format) == processed.filter { $0 != partner }, "\(description)")
            #expect(assets.dropFirst().allSatisfy { $0.alternate == nil }, "\(description)")
        }
    }

    @Test func theDefaultPairingIsHEIF() {
        let assets = PhotoLibraryAsset.assets(for: [.raw, .heif, .jpeg].map(Self.file))
        #expect(assets.first?.alternate?.format == .heif)
    }
}

/// Records the options a developer was asked for.
actor OptionsRecorder {
    private(set) var options: [DevelopedFileOptions] = []

    func record(_ value: DevelopedFileOptions) {
        options.append(value)
    }
}

/// A developer that takes the encoding options, recording them.
struct OptionsDeveloper: PhotoDeveloping {
    let recorder = OptionsRecorder()

    func develop(_ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, metadata: MetadataPlan)
        async throws(CaptureError) -> PhotoFile
    {
        try await FakeDeveloper().develop(raw, to: format, look: look, metadata: metadata)
    }

    func develop(
        _ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, options: DevelopedFileOptions,
        metadata: MetadataPlan
    ) async throws(CaptureError) -> PhotoFile {
        await recorder.record(options)
        return try await develop(raw, to: format, look: look, metadata: metadata)
    }
}

struct PhotoSaverOptionTests {
    @Test(arguments: RAWPairing.allCases)
    func theChosenCopyIsPairedWithTheRAW(pairing: RAWPairing) async throws {
        let library = FakeLibrary()
        var settings = SaveSettings()
        settings.setFormat(.jpeg, isSelected: true)
        settings.rawPairing = pairing
        let saved = try await PhotoSaverTests.saver(library: library).save(PhotoSaverTests.rawPhoto(), settings: settings)
        #expect(saved.formats == [.raw, .heif, .jpeg])
        let assets = await library.added.first ?? []
        #expect(assets.count == 2)
        #expect(assets.first?.primary.format == .raw)
        #expect(assets.first?.alternate?.format == pairing.format)
        #expect(assets.last?.primary.format == (pairing == .heif ? .jpeg : .heif))
    }

    @Test func theFileOptionsArePassedToTheDeveloper() async throws {
        let developer = OptionsDeveloper()
        var settings = SaveSettings()
        settings.setFormat(.jpeg, isSelected: true)
        var options = DevelopedFileOptions()
        options.heifBitDepth = .eight
        settings.fileOptions = options
        let saver = PhotoSaver(
            developer: developer, signer: nil, reader: BytesReader(), library: FakeLibrary(), appVersion: "0.2.0")
        _ = try await saver.save(PhotoSaverTests.rawPhoto(), settings: settings)
        #expect(await developer.recorder.options == [options, options])
    }
}

struct MirroredOrientationTests {
    /// TIFF 6.0 and EXIF orientation values: mirroring swaps 1↔2, 3↔4, 5↔6 and 7↔8.
    @Test func eachOrientationHasItsMirror() {
        let expected = [1: 2, 2: 1, 3: 4, 4: 3, 5: 6, 6: 5, 7: 8, 8: 7]
        for (value, mirrored) in expected {
            #expect(MetadataPlan.mirroredOrientation(value) == mirrored, "\(value)")
            #expect(MetadataPlan.mirroredOrientation(MetadataPlan.mirroredOrientation(value)) == value)
        }
        #expect(MetadataPlan.mirroredOrientation(0) == 2)
        #expect(MetadataPlan.mirroredOrientation(9) == 2)
    }

    /// Every device orientation's capture angle gives a system orientation value (1, 3, 6 or 8
    /// for the front camera), and each is mirrored in every format the backend writes.
    @Test(arguments: [1, 3, 6, 8])
    func everyFormatCarriesTheMirroredValue(system: Int) {
        var plan = MetadataPlan()
        plan.mirrorsHorizontally = true
        let source: [String: Any] = ["Orientation": system, "{TIFF}": ["Orientation": system]]
        for format in PhotoFormat.allCases {
            let properties = plan.properties(for: format, from: source)
            #expect(properties["Orientation"] as? Int == MetadataPlan.mirroredOrientation(system), "\(format)")
            #expect((properties["{TIFF}"] as? [String: Any])?["Orientation"] as? Int == MetadataPlan.mirroredOrientation(system))
        }
        // Off, the system's value is kept.
        #expect(MetadataPlan().properties(for: .raw, from: source)["Orientation"] as? Int == system)
    }

    @Test func aMissingOrientationIsMirroredFromUpright() {
        var plan = MetadataPlan()
        plan.mirrorsHorizontally = true
        #expect(plan.properties(for: .raw, from: [:])["Orientation"] as? Int == 2)
        // A TIFF-only value is used when the top-level one is missing.
        #expect(plan.properties(for: .raw, from: ["{TIFF}": ["Orientation": 3]])["Orientation"] as? Int == 4)
    }

    /// A developed copy is rendered upright, so its explicit orientation wins over mirroring.
    @Test func anExplicitOrientationWins() {
        var plan = MetadataPlan()
        plan.mirrorsHorizontally = true
        #expect(plan.properties(for: .heif, from: ["Orientation": 6], orientation: 1)["Orientation"] as? Int == 1)
    }

    /// The read-back accepts every mirrored value: Orientation is a locked tag, and no value
    /// rule applies to it.
    @Test(arguments: [2, 4, 5, 7])
    func theReadBackAcceptsMirroredValues(value: Int) {
        let allowlist = MetadataPlan().allowlist(for: .raw, signed: false)
        let root = CleanFiles.tiff(for: allowlist)
        root.entries.removeAll { $0.0 == 0x0112 }
        root.entries.append((0x0112, .short([UInt16(value)])))
        let readBack = MetadataReadBack(file: MetadataFileReader.read(Data(TIFFBuilder.build(root)), format: .raw), imageIOKeys: [])
        let violations = MetadataVerifier.violations(
            in: readBack, allowlist: allowlist, expectedRawImageData: Data(CleanFiles.rawImageData))
        #expect(violations.isEmpty, "\(violations)")
    }
}

struct PhotoLocationTests {
    @Test func northEastIsPositiveWithReferences() {
        let gps = PhotoLocation(latitude: 52.37, longitude: 4.89, altitude: 12.5).gpsProperties
        #expect(gps["LatitudeRef"] as? String == "N")
        #expect(gps["Latitude"] as? Double == 52.37)
        #expect(gps["LongitudeRef"] as? String == "E")
        #expect(gps["Longitude"] as? Double == 4.89)
        #expect(gps["AltitudeRef"] as? Int == 0)
        #expect(gps["Altitude"] as? Double == 12.5)
        #expect(gps.count == 6)
    }

    @Test func southWestAndBelowSeaLevel() {
        let gps = PhotoLocation(latitude: -33.9, longitude: -70.6, altitude: -28).gpsProperties
        #expect(gps["LatitudeRef"] as? String == "S")
        #expect(gps["Latitude"] as? Double == 33.9)
        #expect(gps["LongitudeRef"] as? String == "W")
        #expect(gps["Longitude"] as? Double == 70.6)
        #expect(gps["AltitudeRef"] as? Int == 1)
        #expect(gps["Altitude"] as? Double == 28)
    }

    @Test func noAltitudeWritesNone() {
        let gps = PhotoLocation(latitude: 1, longitude: 2).gpsProperties
        #expect(Set(gps.keys) == ["LatitudeRef", "Latitude", "LongitudeRef", "Longitude"])
    }

    /// The location is written only with the switch on, as exactly the location's fields; a
    /// GPS key the system or a file adds that isn't on the allowlist is never copied.
    @Test(arguments: PhotoFormat.allCases)
    func theLocationIsWrittenOnlyWhenOn(format: PhotoFormat) {
        let place = PhotoLocation(latitude: 10, longitude: 20, altitude: 30)
        let source: [String: Any] = ["{GPS}": ["Speed": 4.0, "ImgDirection": 90.0, "Latitude": 1.0] as [String: Any]]
        var off = MetadataPlan()
        off.location = place
        #expect(off.properties(for: format, from: source)["{GPS}"] == nil)

        var settings = MetadataSettings()
        settings.set(.location, isOn: true)
        var on = MetadataPlan(settings: settings)
        on.location = place
        let gps = on.properties(for: format, from: source)["{GPS}"] as? [String: Any]
        #expect(gps?.count == 6)
        #expect(gps?["Latitude"] as? Double == 10)
        #expect(gps?["Speed"] == nil)

        // A developed copy without a location of its own takes the allowlisted GPS fields of
        // its DNG, and nothing else.
        let developed = MetadataPlan(settings: settings).properties(for: format, from: source, orientation: 1)
        let copied = developed["{GPS}"] as? [String: Any]
        #expect(copied?.keys.sorted() == ["Latitude"])
    }

    /// The tags written match the allowlist: a file built from the location's tags passes.
    @Test func theGPSFieldsAreOnTheAllowlist() {
        var settings = MetadataSettings()
        settings.set(.location, isOn: true)
        let plan = MetadataPlan(settings: settings)
        for format in PhotoFormat.allCases {
            let allowlist = plan.allowlist(for: format, signed: false)
            for field in MetadataField.gpsFields {
                #expect(allowlist.allows(MetadataAllowlist.TagID(.gps, field.tag)))
                #expect(field.imageIOKeys.allSatisfy(allowlist.allows))
            }
            #expect(!MetadataPlan().allowlist(for: format, signed: false).allows(MetadataAllowlist.TagID(.gps, 0x0002)))
        }
    }
}

/// A location service a test controls.
actor FakeLocationProvider: LocationProviding {
    /// The access before asking.
    private var access: LocationAccess
    /// The access after asking.
    private let afterRequest: LocationAccess
    /// How many times access was asked for.
    private(set) var requests = 0
    /// The locations each stream gives.
    nonisolated let places: [PhotoLocation]

    init(access: LocationAccess, afterRequest: LocationAccess? = nil, places: [PhotoLocation] = []) {
        self.access = access
        self.afterRequest = afterRequest ?? access
        self.places = places
    }

    func setAccess(_ value: LocationAccess) {
        access = value
    }

    func currentAccess() async -> LocationAccess {
        access
    }

    func requestAccess() async -> LocationAccess {
        requests += 1
        if access == .notDetermined { access = afterRequest }
        return access
    }

    nonisolated func locations() -> AsyncStream<PhotoLocation> {
        let places = places
        return AsyncStream { continuation in
            for place in places { continuation.yield(place) }
        }
    }
}

@MainActor
struct LocationTaggingTests {
    static let place = PhotoLocation(latitude: 1, longitude: 2, altitude: 3)

    /// Waits until the tagging has a location, for at most a second.
    static func waitForLocation(_ tagging: LocationTagging) async {
        for _ in 0..<100 where tagging.latestLocation == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func turningOnAsksFirstAndTurnsOnWhenAllowed() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let provider = FakeLocationProvider(access: .notDetermined, afterRequest: .allowed)
        let tagging = LocationTagging(provider: provider)
        #expect(tagging.access == .notDetermined)
        #expect(await tagging.turnOn(in: settings))
        #expect(settings.metadata.isOn(.location))
        #expect(tagging.access == .allowed)
        #expect(await provider.requests == 1)
    }

    @Test(arguments: [LocationAccess.denied, .restricted])
    func turningOnWithoutAccessLeavesItOff(access: LocationAccess) async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let tagging = LocationTagging(provider: FakeLocationProvider(access: .notDetermined, afterRequest: access))
        #expect(!(await tagging.turnOn(in: settings)))
        #expect(!settings.metadata.isOn(.location))
        #expect(settings.metadata.removesAllOptionalDetails)
        #expect(tagging.access == access)
        #expect(!access.isAllowed)
    }

    @Test func updatesRunOnlyWhileOnAndTheCameraRuns() async {
        let tagging = LocationTagging(provider: FakeLocationProvider(access: .allowed, places: [Self.place]))
        await tagging.update(isOn: false, cameraIsRunning: true)
        #expect(!tagging.isUpdating)
        await tagging.update(isOn: true, cameraIsRunning: false)
        #expect(!tagging.isUpdating)

        await tagging.update(isOn: true, cameraIsRunning: true)
        #expect(tagging.isUpdating)
        await Self.waitForLocation(tagging)
        #expect(tagging.latestLocation == Self.place)
        #expect(tagging.location(isOn: true) == Self.place)
        #expect(tagging.location(isOn: false) == nil)

        // A second call while running keeps the same updates.
        await tagging.update(isOn: true, cameraIsRunning: true)
        #expect(tagging.isUpdating)
        #expect(tagging.latestLocation == Self.place)

        // The camera stops: updates stop and the last location is forgotten.
        await tagging.update(isOn: true, cameraIsRunning: false)
        #expect(!tagging.isUpdating)
        #expect(tagging.latestLocation == nil)
    }

    @Test func noUpdatesWithoutAccess() async {
        let provider = FakeLocationProvider(access: .denied, places: [Self.place])
        let tagging = LocationTagging(provider: provider)
        await tagging.update(isOn: true, cameraIsRunning: true)
        #expect(!tagging.isUpdating)
        #expect(tagging.access == .denied)

        await provider.setAccess(.allowed)
        await tagging.refreshAccess()
        #expect(tagging.access == .allowed)
    }

    /// A call whose task was cancelled while it waited (a replaced SwiftUI task) starts nothing.
    @Test func aCancelledUpdateStartsNothing() async {
        let tagging = LocationTagging(provider: FakeLocationProvider(access: .allowed, places: [Self.place]))
        let task = Task { await tagging.update(isOn: true, cameraIsRunning: true) }
        task.cancel()
        await task.value
        #expect(!tagging.isUpdating)
    }
}

@MainActor
struct CameraModelLocationAndMirrorTests {
    static let front = Lens(id: "front", kind: .front, bayerRAWFormat: "bgg4")
    static let capabilities = DeviceCapabilities(lenses: [CameraModelTests.wideRAW, front])

    @Test func onlyFrontCameraPhotosAreMirroredWhenOn() async {
        let backend = ScriptedBackend(capabilities: Self.capabilities)
        let model = await CameraModelTests.runningModel(backend)
        #expect(model.capabilities?.hasFrontCamera == true)
        model.saveSettings.mirrorsFrontCamera = true
        await model.send(.capture)
        await model.send(.selectLens("front"))
        await model.send(.capture)
        model.saveSettings.mirrorsFrontCamera = false
        await model.send(.capture)
        let mirrored = await backend.captureRequests.map(\.metadata.mirrorsHorizontally)
        #expect(mirrored == [false, true, false])
        #expect(!DeviceCapabilities(lenses: [CameraModelTests.wideRAW]).hasFrontCamera)
    }

    @Test func thePhotoGetsTheLatestLocationOnlyWhenOn() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await CameraModelTests.runningModel(backend)
        let place = LocationTaggingTests.place
        let tagging = LocationTagging(provider: FakeLocationProvider(access: .allowed, places: [place]))
        model.location = tagging
        await tagging.update(isOn: true, cameraIsRunning: true)
        await LocationTaggingTests.waitForLocation(tagging)

        await model.send(.capture)
        model.saveSettings.metadata.set(.location, isOn: true)
        await model.send(.capture)
        let locations = await backend.captureRequests.map(\.metadata.location)
        #expect(locations == [nil, place])
        guard case .saved = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
    }
}

struct GPSDirectoryReaderTests {
    /// A pointer stored as SHORT is followed like a LONG one (TIFF 6.0 allows both for offsets);
    /// a zero offset ends the chain at once. The GPS files above no longer reach this path by
    /// chance, so it is tested directly.
    @Test func aShortPointerIsRead() {
        let bytes = TIFFBuilder.build(TIFFBuilder.Directory([(0x8825, .short([0]))]))
        let result = MetadataFileReader.read(Data(bytes), format: .raw)
        #expect(result.inventory.tags.contains { $0.directory == .primary && $0.tag == 0x8825 })
        #expect(!result.inventory.tags.contains { $0.directory == .gps })
    }
}
