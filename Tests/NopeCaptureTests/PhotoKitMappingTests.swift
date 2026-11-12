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
