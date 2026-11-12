import Foundation
import NopeCore

@testable import NopeSigning

/// Small synthetic files of every kind nope. signs. They are generated here, not captured, so
/// the tests carry no one's photos (AGENTS.md, "Test files and samples").
enum SyntheticPhotos {
    /// A file for each kind.
    ///
    /// - Parameter file: The kind of file.
    /// - Returns: The bytes.
    static func data(for file: SignableFile) -> Data {
        switch file.format {
        case .raw: dng()
        case .heif: heif
        case .jpeg: jpeg
        }
    }

    /// A 16 × 16 gradient as HEIF, encoded once with ImageIO (the system HEVC encoder) on a Mac
    /// and stored here. Encoding at test time would need the hardware HEVC encoder, which a virtual
    /// CI runner may not have.
    static let heif = Data(
        base64Encoded: [
            "AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAABjG1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBp",
            "Y3QAAAAAAAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEA",
            "AAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAOxpcHJwAAAAy2lwY28AAAATY29scm5jbHgAAgAC",
            "AAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAAAAAAEAAAABAAAAAJaXJvdAAAAAAQcGl4aQAAAAADCAgIAAAAd2h2",
            "Y0MBAWAAAACwAAAAAAAe8AD8/fj4AAAPA6AAAQAXQAEMAf//AWAAAAMAsAAAAwAAAwAeLAmhAAEAIUIBAQFgAAAD",
            "ALAAAAMAAAMAHqCIRZy5JEpJcTcCAgYAgKIAAQARRAHAYRJMBOkRESRJEkSRKkAAAAAZaXBtYQAAAAAAAAABAAEG",
            "gQIDBYaEAAAAHmlsb2MAAAAARAAAAQABAAAAAQAAAcAAAAAuAAAAAW1kYXQAAAAAAAAAPgAAAComAa3A8PnoggHF",
            "Mnap2C+R0dUvUOva3dnG8O8Ua7Z/B5/G3TbAg8zrxPA=",
        ].joined())!

    /// The same gradient as JPEG, encoded once with ImageIO and stored here, so every run signs
    /// identical bytes.
    static let jpeg = Data(
        base64Encoded: [
            "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMA",
            "AAABAAEAAKACAAQAAAABAAAAEKADAAQAAAABAAAAEAAAAAD/wAARCAAQABADASIAAhEBAxEB/8QAHwAAAQUB",
            "AQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJx",
            "FDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlq",
            "c3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi",
            "4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQD",
            "BAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2",
            "Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmq",
            "srO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9sAQwACAgICAgIDAgIDBQMD",
            "AwUGBQUFBQYIBgYGBgYICggICAgICAoKCgoKCgoKDAwMDAwMDg4ODg4PDw8PDw8PDw8P/9sAQwECAgIEBAQH",
            "BAQHEAsJCxAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ/90ABAAB",
            "/9oADAMBAAIRAxEAPwD4A8KfCr7n7n9K+mfCfwp+5+5/SvpPwn8Kvufuf0r6a8KfCn7n7n07V6HGPjBv74vo",
            "2+PX8P8Aedj/2Q==",
        ].joined())!

    /// A minimal little-endian DNG: one IFD holding a 4 × 4, 16-bit Bayer (CFA) image.
    ///
    /// Tags follow the DNG specification 1.7.1.0 and TIFF 6.0; only those a reader needs are written.
    static func dng() -> Data {
        let width: UInt32 = 4
        let height: UInt32 = 4
        let pixelBytes = Int(width * height) * 2
        // (tag, type, count, value-or-offset bytes)
        typealias Entry = (tag: UInt16, type: UInt16, count: UInt32, value: [UInt8])
        func short(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) + [0, 0] }
        func long(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        let entryCount = 14
        let ifdOffset: UInt32 = 8
        let ifdSize = 2 + entryCount * 12 + 4
        let pixelOffset = UInt32(8 + ifdSize)
        let entries: [Entry] = [
            (254, 4, 1, long(0)),  // NewSubFileType: main image
            (256, 4, 1, long(width)),  // ImageWidth
            (257, 4, 1, long(height)),  // ImageLength
            (258, 3, 1, short(16)),  // BitsPerSample
            (259, 3, 1, short(1)),  // Compression: none
            (262, 3, 1, short(32803)),  // PhotometricInterpretation: CFA
            (273, 4, 1, long(pixelOffset)),  // StripOffsets
            (277, 3, 1, short(1)),  // SamplesPerPixel
            (278, 4, 1, long(height)),  // RowsPerStrip
            (279, 4, 1, long(UInt32(pixelBytes))),  // StripByteCounts
            (33421, 3, 2, [2, 0, 2, 0]),  // CFARepeatPatternDim: 2 × 2
            (33422, 1, 4, [0, 1, 1, 2]),  // CFAPattern: RGGB
            (50706, 1, 4, [1, 4, 0, 0]),  // DNGVersion 1.4
            (50708, 2, 4, Array("nop\0".utf8)),  // UniqueCameraModel (generic)
        ]
        precondition(entries.count == entryCount)
        var bytes: [UInt8] = Array("II".utf8) + [42, 0] + long(ifdOffset)
        bytes += withUnsafeBytes(of: UInt16(entryCount).littleEndian, Array.init)
        for entry in entries {
            bytes += withUnsafeBytes(of: entry.tag.littleEndian, Array.init)
            bytes += withUnsafeBytes(of: entry.type.littleEndian, Array.init)
            bytes += long(entry.count)
            bytes += entry.value
        }
        bytes += long(0)  // no next IFD
        for i in 0..<Int(width * height) {
            bytes += withUnsafeBytes(of: UInt16(512 + i * 64).littleEndian, Array.init)
        }
        return Data(bytes)
    }
}
