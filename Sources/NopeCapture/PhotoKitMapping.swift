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
    }

    /// Whether an add-only authorization status lets nope. add photos.
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
}
