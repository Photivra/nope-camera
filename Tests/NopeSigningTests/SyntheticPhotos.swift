import CoreGraphics
import Foundation
import ImageIO
import NopeCore
import UniformTypeIdentifiers

/// Small synthetic files of every kind nope. signs. They are generated here, not captured, so
/// the tests carry no one's photos (AGENTS.md, "Test files and samples").
enum SyntheticPhotos {
    /// A file for each kind.
    ///
    /// - Parameter file: The kind of file.
    /// - Returns: The bytes.
    static func data(for file: SignableFile) -> Data {
        switch file.container {
        case .dng: dng()
        case .heif: encoded(UTType.heic)
        case .jpeg: encoded(UTType.jpeg)
        }
    }

    /// A 16 × 16 gradient.
    static func image() -> CGImage {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(x * 16)
                pixels[i + 1] = UInt8(y * 16)
                pixels[i + 2] = 128
                pixels[i + 3] = 255
            }
        }
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// The gradient encoded by ImageIO.
    static func encoded(_ type: UTType) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(), nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

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
