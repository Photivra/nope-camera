import Foundation
import NopeCore
import Photos

/// Adds photos to the photo library with add-only access (PhotoKit).
///
/// Thin adapter: asking for access shows a system prompt and adding changes the person's
/// library, so a unit test can't run it. It is excluded from the coverage gate and verified on a
/// device (docs/TESTING.md); its decisions are in ``PhotoKitMapping``.
///
/// - Access: `PHPhotoLibrary.requestAuthorization(for: .addOnly)`, which uses the localized
///   `NSPhotoLibraryAddUsageDescription`. Add-only access can't read the library.
/// - Adding: one `PHPhotoLibrary.performChanges` call; each `PhotoLibraryAsset` becomes one
///   `PHAssetCreationRequest` with its files added from memory
///   (`addResource(with:data:options:)`), so no temporary file is written. No location or
///   creation date is set on the asset.
public struct PhotoKitLibrary: PhotoLibrary {
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
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for asset in assets {
                    let request = PHAssetCreationRequest.forAsset()
                    for resource in PhotoKitMapping.resources(for: asset) {
                        let options = PHAssetResourceCreationOptions()
                        options.uniformTypeIdentifier = resource.typeIdentifier
                        request.addResource(with: resource.type, data: resource.file.data, options: options)
                    }
                }
            }
        } catch {
            throw .saveFailed
        }
    }
}
