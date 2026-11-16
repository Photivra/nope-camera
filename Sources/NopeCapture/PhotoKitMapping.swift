import Foundation
import NopeCore
import Photos

/// The PhotoKit decisions behind ``PhotoKitLibrary``, as plain functions so they are tested
/// without a photo library.
enum PhotoKitMapping {
    /// One resource to add to a new asset.
    struct Resource: Equatable {
        /// The resource type: `.photo` for the asset's main file, `.alternatePhoto` for the
        /// processed file paired with a RAW.
        let type: PHAssetResourceType
        /// The file.
        let file: PhotoFile
        /// The file's uniform type identifier, passed as
        /// `PHAssetResourceCreationOptions.uniformTypeIdentifier`.
        let typeIdentifier: String

        /// Creates a resource.
        ///
        /// - Parameters:
        ///   - type: The resource type.
        ///   - file: The file.
        ///   - typeIdentifier: The file's uniform type identifier.
        init(type: PHAssetResourceType, file: PhotoFile, typeIdentifier: String) {
            self.type = type
            self.file = file
            self.typeIdentifier = typeIdentifier
        }

        /// Whether the resource must be added from a file (`addResource(with:fileURL:options:)`)
        /// instead of from memory (`addResource(with:data:options:)`).
        ///
        /// Only the alternate of a pair is. Measured on 2026-11-15 in the iOS 27.2 Simulator,
        /// and matching the failure on an iPhone 16 Pro Max (iOS 27.2.1): a request with a
        /// `.photo` and an `.alternatePhoto` fails with `PHPhotosErrorDomain` 3300
        /// (`PHPhotosErrorChangeNotSupported`) whenever the alternate is added from memory, for
        /// a DNG with a HEIF or a JPEG, in either order, with any `originalResourceChoice`,
        /// type identifier or file name; it succeeds when the alternate is added from a file,
        /// whether the main file comes from memory or from a file. A single resource added from
        /// memory succeeds. Apple documents none of this; its RAW capture article adds the
        /// alternate from memory, and that shape fails too. See docs/TESTING.md, "RAW pairs not
        /// saved (PhotoKit error 3300)".
        var addsFromFile: Bool { type == .alternatePhoto }
    }

    /// Where a prepared resource's bytes come from.
    enum Source: Equatable {
        /// From memory.
        case data(Data)
        /// From a staged file, which Photos moves into the library.
        case file(URL)
    }

    /// One resource, ready to add: its type, type identifier and source.
    struct PreparedResource: Equatable {
        /// The resource type.
        let type: PHAssetResourceType
        /// The file's uniform type identifier.
        let typeIdentifier: String
        /// Where the bytes come from.
        let source: Source

        /// Creates a prepared resource.
        ///
        /// - Parameters:
        ///   - type: The resource type.
        ///   - typeIdentifier: The file's uniform type identifier.
        ///   - source: Where the bytes come from.
        init(type: PHAssetResourceType, typeIdentifier: String, source: Source) {
            self.type = type
            self.typeIdentifier = typeIdentifier
            self.source = source
        }
    }

    /// The creation requests for one change, and the files staged for them.
    struct PreparedChange: Equatable {
        /// One entry for each `PHAssetCreationRequest`: its resources, main file first.
        let requests: [[PreparedResource]]
        /// Every staged file. The caller deletes each one after the change, whether or not it
        /// succeeded: Photos moves the files of a change that succeeds, so deleting what is left
        /// is a no-op then.
        let stagedFiles: [URL]
        /// Whether an alternate couldn't be staged, so its pair was saved as two assets.
        let unpairedBecauseStagingFailed: Bool

        /// Creates a prepared change.
        ///
        /// - Parameters:
        ///   - requests: The resources of each creation request.
        ///   - stagedFiles: Every staged file.
        ///   - unpairedBecauseStagingFailed: Whether a pair was split because staging failed.
        init(requests: [[PreparedResource]], stagedFiles: [URL], unpairedBecauseStagingFailed: Bool) {
            self.requests = requests
            self.stagedFiles = stagedFiles
            self.unpairedBecauseStagingFailed = unpairedBecauseStagingFailed
        }
    }

    /// Whether an add-only authorization status lets the app add photos.
    ///
    /// `PHAuthorizationStatus.limited` is reported only for read-write access, so for add-only
    /// access `.authorized` is the only status that allows adding (`PHPhotoLibrary.h`); both are
    /// accepted here to stay correct if that changes.
    ///
    /// - Parameter status: The status for `PHAccessLevel.addOnly`.
    /// - Returns: `true` if photos can be added.
    static func canAdd(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    /// The uniform type identifier of a format's file.
    ///
    /// - Parameter format: The format.
    /// - Returns: `com.adobe.raw-image` for DNG, `public.heic` or `public.jpeg`.
    static func typeIdentifier(for format: PhotoFormat) -> String {
        switch format {
        case .raw: "com.adobe.raw-image"
        case .heif: "public.heic"
        case .jpeg: "public.jpeg"
        }
    }

    /// The file name extension of a format's staged file.
    ///
    /// - Parameter format: The format.
    /// - Returns: `dng`, `heic` or `jpg`.
    static func fileExtension(for format: PhotoFormat) -> String {
        switch format {
        case .raw: "dng"
        case .heif: "heic"
        case .jpeg: "jpg"
        }
    }

    /// The resources of one asset: the main file as `.photo`, and a paired processed file as
    /// `.alternatePhoto`, as Apple's RAW capture article does ("Capturing Photos in RAW and
    /// Apple ProRAW Formats", "Save the photos to the photos library").
    ///
    /// - Parameter asset: The asset.
    /// - Returns: The resources, main file first.
    static func resources(for asset: PhotoLibraryAsset) -> [Resource] {
        var resources = [
            Resource(type: .photo, file: asset.primary, typeIdentifier: typeIdentifier(for: asset.primary.format))
        ]
        if let alternate = asset.alternate {
            resources.append(
                Resource(type: .alternatePhoto, file: alternate, typeIdentifier: typeIdentifier(for: alternate.format)))
        }
        return resources
    }

    /// Prepares the creation requests for a change: every resource from memory, except each
    /// pair's alternate, which is staged as a file (``Resource/addsFromFile``).
    ///
    /// If an alternate can't be staged (for example, while the device is locked a file with
    /// complete protection can't be created), its pair is saved as two assets from memory
    /// instead, so the photo is still saved; the files are unchanged.
    ///
    /// - Parameters:
    ///   - assets: The assets to add.
    ///   - stage: Writes one file and returns its location, or throws.
    /// - Returns: The requests and the staged files.
    static func prepare(_ assets: [PhotoLibraryAsset], stage: (PhotoFile) throws -> URL) -> PreparedChange {
        var requests: [[PreparedResource]] = []
        var staged: [URL] = []
        var unpaired = false
        for asset in assets {
            var request: [PreparedResource] = []
            var split: [[PreparedResource]] = []
            for resource in resources(for: asset) {
                guard resource.addsFromFile else {
                    request.append(fromMemory(resource.file, as: resource.type))
                    continue
                }
                do {
                    let url = try stage(resource.file)
                    staged.append(url)
                    request.append(
                        PreparedResource(type: resource.type, typeIdentifier: resource.typeIdentifier, source: .file(url)))
                } catch {
                    unpaired = true
                    split.append([fromMemory(resource.file, as: .photo)])
                }
            }
            requests.append(request)
            requests += split
        }
        return PreparedChange(requests: requests, stagedFiles: staged, unpairedBecauseStagingFailed: unpaired)
    }

    /// A resource added from memory.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - type: The resource type.
    /// - Returns: The prepared resource.
    private static func fromMemory(_ file: PhotoFile, as type: PHAssetResourceType) -> PreparedResource {
        PreparedResource(type: type, typeIdentifier: typeIdentifier(for: file.format), source: .data(file.data))
    }

    /// The shape of a change, for the log: each request's resources by type identifier, with
    /// `(file)` after a staged one.
    ///
    /// - Parameter change: The prepared change.
    /// - Returns: For example `com.adobe.raw-image+public.heic(file), public.jpeg`.
    static func shapeDescription(of change: PreparedChange) -> String {
        change.requests.map { request in
            request.map { resource in
                switch resource.source {
                case .data: resource.typeIdentifier
                case .file: resource.typeIdentifier + "(file)"
                }
            }
            .joined(separator: "+")
        }
        .joined(separator: ", ")
    }

    /// The part of an error that is safe and useful to log: its domain and code, and those of
    /// its underlying error, never its description or user info (which can hold file paths).
    ///
    /// - Parameter error: The error PhotoKit or the file system reported.
    /// - Returns: For example `PHPhotosErrorDomain 3300` or
    ///   `PHPhotosErrorDomain 3302 (underlying NSCocoaErrorDomain 4)`.
    static func logDescription(of error: any Error) -> String {
        let error = error as NSError
        var text = "\(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (underlying \(underlying.domain) \(underlying.code))"
        }
        return text
    }
}
