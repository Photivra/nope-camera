import Foundation
import ImageIO
import NopeCore

/// The read-back for every finished file: the project's own tag reader plus ImageIO's view of
/// the file (AGENTS.md, "Fail closed").
///
/// `MetadataFileReader` (in `NopeCore`) lists every tag, block and property from the bytes.
/// ImageIO then opens the file the way Photos and other apps will: it must hold exactly one
/// image of the expected type, and every key in its property dictionaries is reported, so a
/// value ImageIO understands but the byte reader files elsewhere is checked too.
public struct ImageIOReadBack: MetadataReading {
    /// Creates the read-back.
    public init() {}

    /// The uniform type identifier ImageIO must report for a format
    /// (`CGImageSourceGetType`): `com.adobe.raw-image` for DNG, `public.heic`, `public.jpeg`.
    ///
    /// - Parameter format: The file's format.
    /// - Returns: The type identifier.
    static func expectedType(of format: PhotoFormat) -> String {
        switch format {
        case .raw: "com.adobe.raw-image"
        case .heif: "public.heic"
        case .jpeg: "public.jpeg"
        }
    }

    /// Reads a file back.
    ///
    /// - Parameter file: The finished file.
    /// - Returns: The byte reader's result and ImageIO's property keys.
    /// - Throws: `CaptureError.metadataNotAllowed` if ImageIO can't open the file as exactly one
    ///   image of its format.
    public func readBack(_ file: PhotoFile) throws(CaptureError) -> MetadataReadBack {
        guard let source = CGImageSourceCreateWithData(file.data as CFData, nil),
            CGImageSourceGetType(source) as String? == Self.expectedType(of: file.format),
            CGImageSourceGetCount(source) == 1,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { throw .metadataNotAllowed }
        return MetadataReadBack(
            file: MetadataFileReader.read(file.data, format: file.format), imageIOKeys: Self.keys(of: properties))
    }

    /// Every key of an ImageIO property dictionary: top-level keys, and each key of a
    /// sub-dictionary as `{Dictionary}.Key`.
    ///
    /// - Parameter properties: The image's properties.
    /// - Returns: The keys, sorted.
    static func keys(of properties: [String: Any]) -> [ImageIOKey] {
        properties.flatMap { name, value -> [ImageIOKey] in
            guard let dictionary = value as? [String: Any] else { return [ImageIOKey(nil, name)] }
            return dictionary.keys.map { ImageIOKey(name, $0) }
        }
        .sorted { $0.description < $1.description }
    }
}
