import Foundation

extension SimulatedCaptureBackend: ComparisonCaptureBackend {
    /// The bytes of every simulated phone-processed photo. They are not an image file.
    public static let placeholderComparisonData = Data("simulated phone processing".utf8)

    /// The metadata of every simulated phone-processed photo: a mix of what a phone's own file
    /// carries by default (camera, software version, time zone offset, sub-second time, maker
    /// note, a unique ID) and two image items, with made-up values.
    public static let placeholderComparisonMetadata = MetadataInventory(
        tags: [
            MetadataInventory.Tag(directory: .primary, tag: 0x010F, text: "Simulated Maker"),
            MetadataInventory.Tag(directory: .primary, tag: 0x0110, text: "Simulated Phone"),
            MetadataInventory.Tag(directory: .primary, tag: 0x0131, text: "26.1"),
            MetadataInventory.Tag(directory: .primary, tag: 0x0112, values: [1]),
            MetadataInventory.Tag(directory: .exif, tag: 0x829A, values: [1.0 / 60.0]),
            MetadataInventory.Tag(directory: .exif, tag: 0x8827, values: [100]),
            MetadataInventory.Tag(directory: .exif, tag: 0x9010, text: "+01:00"),
            MetadataInventory.Tag(directory: .exif, tag: 0x9290, text: "123"),
            MetadataInventory.Tag(directory: .exif, tag: 0x927C),
            MetadataInventory.Tag(directory: .exif, tag: 0xA420, text: "0A1B2C3D4E5F6071"),
        ],
        blocks: ["heif:item:hvc1", "heif:item:hvc1", "heif:item:Exif"])

    /// Returns a placeholder phone-processed photo for the request, or throws
    /// ``comparisonError``.
    ///
    /// - Parameter request: the app's request.
    /// - Returns: ``placeholderComparisonData`` as a HEIF (a JPEG for a lens whose fallback is
    ///   JPEG), the lens's largest photo size (or ``placeholderDimensions``), and
    ///   ``placeholderComparisonMetadata``.
    /// - Throws: ``comparisonError``.
    public func captureComparison(_ request: CaptureRequest) async throws(CaptureError) -> PhoneProcessedPhoto {
        if let comparisonError { throw comparisonError }
        return PhoneProcessedPhoto(
            data: Self.placeholderComparisonData,
            format: request.format == .processedFallback(.jpeg) ? .jpeg : .heif,
            dimensions: request.lens.photoDimensions.last ?? Self.placeholderDimensions,
            metadata: Self.placeholderComparisonMetadata)
    }
}
