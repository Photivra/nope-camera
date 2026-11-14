import Foundation
import NopeCore

/// The brightness plane of one live video frame, read one byte at a time.
///
/// ``SystemCaptureHardware`` makes it from the Y plane of a preview-sized video frame; tests make
/// it from an array. Privacy rule: it is read once for one analysis and never copied whole,
/// stored or logged.
struct LumaPlane {
    /// The width in pixels.
    let width: Int

    /// The height in pixels.
    let height: Int

    /// The bytes from the start of one row to the start of the next.
    let bytesPerRow: Int

    /// Whether the plane is video range (16 black to 235 white) rather than full range (0 to
    /// 255), as `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` is.
    let isVideoRange: Bool

    /// Reads the byte at an offset from the start of the plane.
    let read: (Int) -> UInt8

    /// Creates a plane.
    ///
    /// - Parameters:
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    ///   - bytesPerRow: The bytes from the start of one row to the start of the next.
    ///   - isVideoRange: Whether the plane is video range.
    ///   - read: Reads the byte at an offset; called only with offsets inside the plane.
    init(width: Int, height: Int, bytesPerRow: Int, isVideoRange: Bool, read: @escaping (Int) -> UInt8) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.isVideoRange = isVideoRange
        self.read = read
    }

    /// The full-range brightness of one pixel, 0 to 255.
    ///
    /// - Parameters:
    ///   - x: The column, 0 to `width` − 1.
    ///   - y: The row, 0 to `height` − 1.
    func brightness(x: Int, y: Int) -> Int {
        let value = Int(read(y * bytesPerRow + x))
        guard isVideoRange else { return value }
        // Video range puts black at 16 and white at 235 (ITU-R BT.601 and BT.709).
        return min(max((value - 16) * 255 / 219, 0), 255)
    }
}

/// Samples a small grid from a live frame's brightness plane, for the histogram and focus
/// peaking (issues #47 and #51).
///
/// Only about 160 × 120 pixels of a preview-sized frame are read, so an analysis costs little
/// (AGENTS.md, "Battery"). Each cell takes the brightness of one pixel and, for its sharpness,
/// the brightness differences to its neighbors right and below in the full frame, so fine detail
/// still counts although the grid is small.
enum LumaSampler {
    /// The cells along the frame's long side. A tool setting: about 2.5 points per cell on a
    /// phone's viewfinder, fine enough to show which edges are sharp.
    static let longSideCells = 160

    /// Samples a plane.
    ///
    /// - Parameter plane: The plane.
    /// - Returns: The grid, in the plane's orientation; empty for a plane smaller than 3 × 3
    ///   pixels.
    static func sample(_ plane: LumaPlane) -> LumaFrame {
        guard plane.width >= 3, plane.height >= 3 else { return LumaFrame(width: 0, height: 0, luma: [], edges: []) }
        let longSide = max(plane.width, plane.height)
        let cells = min(longSideCells, longSide - 2)
        let columns = max(1, plane.width * cells / longSide)
        let rows = max(1, plane.height * cells / longSide)
        var luma: [UInt8] = []
        var edges: [UInt8] = []
        luma.reserveCapacity(columns * rows)
        edges.reserveCapacity(columns * rows)
        for row in 0..<rows {
            let y = position(of: row, count: rows, length: plane.height)
            for column in 0..<columns {
                let x = position(of: column, count: columns, length: plane.width)
                let center = plane.brightness(x: x, y: y)
                luma.append(UInt8(center))
                // Differences to the next pixel right and below catch detail one pixel wide.
                let horizontal = abs(plane.brightness(x: x + 1, y: y) - center)
                let vertical = abs(plane.brightness(x: x, y: y + 1) - center)
                edges.append(UInt8(min(horizontal + vertical, 255)))
            }
        }
        return LumaFrame(width: columns, height: rows, luma: luma, edges: edges)
    }

    /// The pixel at the middle of a cell, kept one pixel inside the edges so its neighbors
    /// exist.
    ///
    /// - Parameters:
    ///   - cell: The cell, 0 to `count` − 1.
    ///   - count: The cells along this side.
    ///   - length: The pixels along this side, at least 3.
    static func position(of cell: Int, count: Int, length: Int) -> Int {
        min(max((2 * cell + 1) * length / (2 * count), 1), length - 2)
    }
}
