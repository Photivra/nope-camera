import Foundation

/// The project's own tag reader: reads a saved file's bytes back and lists everything
/// metadata-like in it (AGENTS.md, "Fail closed").
///
/// It dispatches on the file's format: the TIFF structure of a DNG (``TIFFReader``), the
/// segments of a JPEG (``JPEGReader``) or the boxes and items of a HEIF (``HEIFReader``). Each
/// reader lists every tag, block and property it meets, known or not, so a tag a future iOS adds
/// is reported and rejected rather than missed. ``MetadataVerifier`` then compares the result
/// with the allowlist.
public enum MetadataFileReader {
    /// What reading one file produced.
    public struct Result: Equatable, Sendable {
        /// Every tag, block and property, and any problem.
        public let inventory: MetadataInventory
        /// For a DNG, the RAW image data (IFD0's tiles or strips, concatenated); otherwise
        /// `nil`. Compared with the sensor data the camera returned to prove the pixels didn't
        /// change.
        public let rawImageData: Data?

        /// Creates a result.
        ///
        /// - Parameters:
        ///   - inventory: Everything found.
        ///   - rawImageData: The RAW image data, or `nil`.
        public init(inventory: MetadataInventory, rawImageData: Data?) {
            self.inventory = inventory
            self.rawImageData = rawImageData
        }
    }

    /// Reads a file.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - format: The file's format.
    /// - Returns: Everything found, and the RAW image data for a DNG.
    public static func read(_ data: Data, format: PhotoFormat) -> Result {
        let bytes = [UInt8](data)
        switch format {
        case .raw:
            let tiff = TIFFReader.read(bytes, extractImageData: true)
            return Result(inventory: tiff.inventory, rawImageData: tiff.primaryImageData)
        case .heif:
            return Result(inventory: HEIFReader.read(bytes), rawImageData: nil)
        case .jpeg:
            return Result(inventory: JPEGReader.read(bytes), rawImageData: nil)
        }
    }

    /// The RAW image data of a DNG: IFD0's tiles or strips, concatenated.
    ///
    /// The capture adapter uses it to keep a reference copy of the sensor data from the system's
    /// own DNG, before nope. writes its metadata.
    ///
    /// - Parameter data: The DNG's bytes.
    /// - Returns: The image data, or `nil` if the file has none that can be read.
    public static func rawImageData(ofDNG data: Data) -> Data? {
        TIFFReader.read([UInt8](data), extractImageData: true).primaryImageData
    }
}
