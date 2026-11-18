import Foundation
import NopeCore
import Photos
import os

/// Adds photos to the photo library with add-only access (PhotoKit).
///
/// Thin adapter: asking for access shows a system prompt and adding changes the person's
/// library, so a unit test can't run it. It is excluded from the coverage gate and verified on a
/// device (docs/TESTING.md); its decisions are in ``PhotoKitMapping``.
///
/// - Access: `PHPhotoLibrary.requestAuthorization(for: .addOnly)`, which uses the localized
///   `NSPhotoLibraryAddUsageDescription`. Add-only access can't read the library.
/// - Adding: one `PHPhotoLibrary.performChanges` call; each `PhotoLibraryAsset` becomes one
///   `PHAssetCreationRequest`. Every file is added from memory
///   (`addResource(with:data:options:)`) except the alternate of a RAW pair, which PhotoKit
///   accepts only from a file (``PhotoKitMapping/Resource/addsFromFile``): it is written with
///   complete file protection (``ResourceStaging``), moved into the library
///   (`shouldMoveFile`), and anything left is deleted when the change ends. No location or
///   creation date is set on the asset.
/// - Failures: the error's domain and code (never its description or user info) are logged,
///   marked private, so a failed save on a device can be diagnosed from a Debug build's console.
///   The person sees only the plain banner for `CaptureError.saveFailed`.
public struct PhotoKitLibrary: PhotoLibrary {
    /// Writes and deletes the alternate files.
    private let staging = ResourceStaging()
    /// Logs why a save failed.
    private let logger = Logger(subsystem: "com.photivra.nope", category: "Photos")

    /// Creates the library adapter.
    public init() {}

    /// Asks for add-only access if it hasn't been asked yet, then adds every asset in one change.
    ///
    /// - Parameter assets: The assets to add.
    /// - Throws: `CaptureError.photosAccessDenied` without access, or `CaptureError.saveFailed`
    ///   if PhotoKit reports an error.
    public func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard PhotoKitMapping.canAdd(status) else { throw .photosAccessDenied }
        let change = PhotoKitMapping.prepare(assets, stage: staging.stage)
        defer { staging.remove(change.stagedFiles) }
        if change.unpairedBecauseStagingFailed {
            logger.notice("A pair's alternate couldn't be staged; saving the pair as two photos")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for resources in change.requests {
                    let request = PHAssetCreationRequest.forAsset()
                    for resource in resources {
                        let options = PHAssetResourceCreationOptions()
                        options.uniformTypeIdentifier = resource.typeIdentifier
                        switch resource.source {
                        case .data(let data):
                            request.addResource(with: resource.type, data: data, options: options)
                        case .file(let url):
                            options.shouldMoveFile = true
                            request.addResource(with: resource.type, fileURL: url, options: options)
                        }
                    }
                }
            }
        } catch {
            let reason = PhotoKitMapping.logDescription(of: error)
            let shape = PhotoKitMapping.shapeDescription(of: change)
            logger.error("Adding to Photos failed: \(reason, privacy: .private) for \(shape, privacy: .private)")
            throw .saveFailed
        }
    }
}
