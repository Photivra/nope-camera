import Foundation
import NopeCore

/// Writes the one file PhotoKit needs on disk, the alternate of a RAW pair
/// (``PhotoKitMapping/Resource/addsFromFile``), and deletes it again.
///
/// Privacy (AGENTS.md, "Photos never linger"): the file is written with complete file
/// protection, under a random name in the app's temporary directory, and Photos moves it into
/// the library (`PHAssetResourceCreationOptions.shouldMoveFile`). ``PhotoKitLibrary`` deletes
/// whatever is left as soon as the change ends, whether or not it succeeded.
struct ResourceStaging: Sendable {
    /// The directory the files are written to.
    let directory: URL

    /// Creates a stager.
    ///
    /// - Parameter directory: The directory to write to. Defaults to the app's temporary
    ///   directory.
    init(directory: URL = FileManager.default.temporaryDirectory) {
        self.directory = directory
    }

    /// Writes a file with complete file protection, never over an existing file.
    ///
    /// - Parameter file: The file to write.
    /// - Returns: Where it was written.
    /// - Throws: The file system's error, for example while the device is locked.
    func stage(_ file: PhotoFile) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(PhotoKitMapping.fileExtension(for: file.format))
        try file.data.write(to: url, options: [.completeFileProtection, .withoutOverwriting])
        return url
    }

    /// Deletes staged files. A file Photos already moved is skipped.
    ///
    /// - Parameter urls: The staged files.
    func remove(_ urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
