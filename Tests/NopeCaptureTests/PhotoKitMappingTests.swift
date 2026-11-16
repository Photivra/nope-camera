import Foundation
import NopeCore
import Photos
import Testing

@testable import NopeCapture

struct PhotoKitMappingTests {
    @Test(arguments: [
        (PHAuthorizationStatus.authorized, true), (.limited, true), (.denied, false), (.restricted, false),
        (.notDetermined, false),
    ])
    func onlyAuthorizedAccessCanAdd(status: PHAuthorizationStatus, canAdd: Bool) {
        #expect(PhotoKitMapping.canAdd(status) == canAdd)
    }

    @Test func rawPairsUseTheDNGAsThePhotoAndTheProcessedFileAsTheAlternate() {
        let raw = PhotoFile(format: .raw, data: Data([1]))
        let heif = PhotoFile(format: .heif, data: Data([2]))
        let resources = PhotoKitMapping.resources(for: PhotoLibraryAsset(primary: raw, alternate: heif))
        #expect(
            resources == [
                PhotoKitMapping.Resource(type: .photo, file: raw, typeIdentifier: "com.adobe.raw-image"),
                PhotoKitMapping.Resource(type: .alternatePhoto, file: heif, typeIdentifier: "public.heic"),
            ])
        let jpeg = PhotoFile(format: .jpeg, data: Data([3]))
        #expect(
            PhotoKitMapping.resources(for: PhotoLibraryAsset(primary: jpeg))
                == [PhotoKitMapping.Resource(type: .photo, file: jpeg, typeIdentifier: "public.jpeg")])
    }
}

/// Every request ``PhotoKitMapping/prepare(_:stage:)`` builds must be a shape PhotoKit accepts
/// (docs/TESTING.md, "RAW pairs not saved (PhotoKit error 3300)").
struct PhotoKitRequestShapeTests {
    /// A stager that records each file and returns a made-up location.
    final class RecordingStager: @unchecked Sendable {
        private(set) var staged: [PhotoFile] = []
        func stage(_ file: PhotoFile) throws -> URL {
            staged.append(file)
            return URL(fileURLWithPath: "/staged/\(staged.count).\(PhotoKitMapping.fileExtension(for: file.format))")
        }
    }

    struct StagingFailed: Error {}

    static func file(_ format: PhotoFormat) -> PhotoFile {
        let byte: UInt8 =
            switch format {
            case .raw: 1
            case .heif: 2
            case .jpeg: 3
            }
        return PhotoFile(format: format, data: Data([byte]))
    }

    /// The files `PhotoSaver` saves for each choice of formats, RAW first, and for each
    /// processed fallback of a lens without RAW.
    static let fileSets: [[PhotoFormat]] = [
        [.raw], [.heif], [.jpeg], [.raw, .heif], [.raw, .jpeg], [.heif, .jpeg], [.raw, .heif, .jpeg],
    ]

    /// Whether a request is one PhotoKit accepts: one `.photo` first, from memory; at most one
    /// `.alternatePhoto`, from a file, only with a DNG as the main file and a HEIF or JPEG as
    /// the alternate; nothing else.
    static func isValidShape(_ request: [PhotoKitMapping.PreparedResource]) -> Bool {
        guard let main = request.first, main.type == .photo, case .data = main.source else { return false }
        let rest = request.dropFirst()
        guard rest.count <= 1 else { return false }
        guard let alternate = rest.first else { return true }
        guard alternate.type == .alternatePhoto, case .file = alternate.source else { return false }
        return main.typeIdentifier == "com.adobe.raw-image"
            && ["public.heic", "public.jpeg"].contains(alternate.typeIdentifier)
    }

    @Test(arguments: RAWPairing.allCases)
    func everyFormatCombinationGivesValidRequests(pairing: RAWPairing) {
        for formats in Self.fileSets {
            let stager = RecordingStager()
            let assets = PhotoLibraryAsset.assets(for: formats.map(Self.file), pairing: pairing)
            let change = PhotoKitMapping.prepare(assets, stage: stager.stage)
            let description = "\(formats), \(pairing)"
            #expect(change.requests.allSatisfy(Self.isValidShape), "\(description)")
            #expect(!change.unpairedBecauseStagingFailed, "\(description)")
            // Every file is saved exactly once.
            let identifiers = change.requests.flatMap { $0.map(\.typeIdentifier) }
            #expect(identifiers.sorted() == formats.map(PhotoKitMapping.typeIdentifier(for:)).sorted(), "\(description)")
            // A RAW with a processed copy is one pair; only its alternate is staged.
            let paired = formats.contains(.raw) && formats.count > 1
            #expect(change.requests.first?.count == (paired ? 2 : 1), "\(description)")
            #expect(change.stagedFiles.count == (paired ? 1 : 0), "\(description)")
            #expect(stager.staged.map(\.format) == (paired ? [assets[0].alternate!.format] : []), "\(description)")
            if paired {
                #expect(change.requests[0][1].source == .file(change.stagedFiles[0]), "\(description)")
            }
        }
    }

    @Test func theAlternateIsTheOnlyResourceAddedFromAFile() {
        let raw = Self.file(.raw)
        let heif = Self.file(.heif)
        #expect(PhotoKitMapping.resources(for: PhotoLibraryAsset(primary: raw, alternate: heif)).map(\.addsFromFile) == [false, true])
        #expect(PhotoKitMapping.resources(for: PhotoLibraryAsset(primary: heif)).map(\.addsFromFile) == [false])
    }

    @Test(arguments: RAWPairing.allCases)
    func aPairWhoseAlternateCantBeStagedIsSavedAsSeparatePhotos(pairing: RAWPairing) {
        for formats in Self.fileSets {
            let assets = PhotoLibraryAsset.assets(for: formats.map(Self.file), pairing: pairing)
            let change = PhotoKitMapping.prepare(assets) { _ throws -> URL in throw StagingFailed() }
            let description = "\(formats), \(pairing)"
            let paired = formats.contains(.raw) && formats.count > 1
            #expect(change.unpairedBecauseStagingFailed == paired, "\(description)")
            #expect(change.stagedFiles.isEmpty, "\(description)")
            #expect(change.requests.allSatisfy { $0.count == 1 && Self.isValidShape($0) }, "\(description)")
            #expect(change.requests.count == formats.count, "\(description)")
            #expect(
                change.requests.flatMap { $0.map(\.typeIdentifier) }.sorted()
                    == formats.map(PhotoKitMapping.typeIdentifier(for:)).sorted(), "\(description)")
        }
    }

    @Test func theStagedFileHoldsTheFilesBytes() throws {
        let file = PhotoFile(format: .heif, data: Data([9, 8, 7]))
        let change = PhotoKitMapping.prepare([PhotoLibraryAsset(primary: Self.file(.raw), alternate: file)]) { staged in
            #expect(staged == file)
            return URL(fileURLWithPath: "/staged/a.heic")
        }
        #expect(
            change.requests == [
                [
                    PhotoKitMapping.PreparedResource(
                        type: .photo, typeIdentifier: "com.adobe.raw-image", source: .data(Data([1]))),
                    PhotoKitMapping.PreparedResource(
                        type: .alternatePhoto, typeIdentifier: "public.heic",
                        source: .file(URL(fileURLWithPath: "/staged/a.heic"))),
                ]
            ])
    }

    @Test func fileExtensions() {
        #expect([PhotoFormat.raw, .heif, .jpeg].map(PhotoKitMapping.fileExtension(for:)) == ["dng", "heic", "jpg"])
    }

    @Test func theLogDescribesTheErrorAndTheShapeOnly() {
        let plain = NSError(domain: "PHPhotosErrorDomain", code: 3300, userInfo: ["path": "/private/x"])
        #expect(PhotoKitMapping.logDescription(of: plain) == "PHPhotosErrorDomain 3300")
        let wrapped = NSError(
            domain: "PHPhotosErrorDomain", code: 3302,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: 4)])
        #expect(PhotoKitMapping.logDescription(of: wrapped) == "PHPhotosErrorDomain 3302 (underlying NSCocoaErrorDomain 4)")
        let assets = PhotoLibraryAsset.assets(for: [.raw, .heif, .jpeg].map(Self.file))
        let change = PhotoKitMapping.prepare(assets) { _ in URL(fileURLWithPath: "/staged/a.heic") }
        #expect(PhotoKitMapping.shapeDescription(of: change) == "com.adobe.raw-image+public.heic(file), public.jpeg")
    }
}

struct ResourceStagingTests {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func stagesWithTheFormatsExtensionAndRemovesAfterwards() throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = ResourceStaging(directory: directory)
        let heif = try staging.stage(PhotoFile(format: .heif, data: Data([1, 2])))
        let jpeg = try staging.stage(PhotoFile(format: .jpeg, data: Data([3])))
        #expect(heif.pathExtension == "heic")
        #expect(jpeg.pathExtension == "jpg")
        #expect(heif.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(try Data(contentsOf: heif) == Data([1, 2]))
        #expect(heif != jpeg)
        // A file Photos already moved is skipped.
        try FileManager.default.removeItem(at: jpeg)
        staging.remove([heif, jpeg])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func stagingFailsWhenTheDirectoryIsMissing() {
        let staging = ResourceStaging(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(throws: (any Error).self) { try staging.stage(PhotoFile(format: .heif, data: Data([1]))) }
    }

    @Test func theDefaultDirectoryIsTheTemporaryDirectory() {
        #expect(ResourceStaging().directory == FileManager.default.temporaryDirectory)
    }
}
