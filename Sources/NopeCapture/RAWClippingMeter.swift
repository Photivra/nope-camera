import Foundation
import NopeCore

/// Counts a RAW photo's clipped photosites from its Bayer sensor buffer (issue #53).
///
/// The hardware adapter reads each 16-bit sample of `AVCapturePhoto.pixelBuffer` through the
/// `sample` closure of ``measure(pixelFormat:versatileBayerPattern:width:height:dng:sample:)``,
/// and passes the read-back of the camera's own DNG for the size, active area, bit depth, and
/// black and white levels. Every photosite of the active area is counted once, into a
/// histogram per position of the 2 × 2 color filter pattern; the clipping is then read from the
/// histograms (`RAWClipping`).
///
/// The buffer and the DNG hold the same photo but are written separately, so the meter checks
/// that they agree before comparing: the same size, and buffer values that fit the DNG's
/// white level, either as they are or shifted up by the difference in bit depth (all low bits
/// zero). Anything else gives a `RAWClippingFailure` instead of a guess.
///
/// References: CoreVideo `CVPixelBuffer.h` (the 14-bit Bayer formats, "packed in 16-bits", and
/// `kCVPixelFormatType_16VersatileBayer` with its `kCVPixelBufferVersatileBayerKey_BayerPattern`
/// attachment); DNG 1.7 (`ActiveArea`, `BlackLevelRepeatDim`, `BlackLevel`, whose pattern
/// starts at the top-left corner of the active area, `WhiteLevel`, `LinearizationTable`,
/// `BlackLevelDeltaH` and `BlackLevelDeltaV`).
enum RAWClippingMeter {
    /// The layout of a Bayer sensor buffer.
    struct Layout: Equatable {
        /// The colors of the 2 × 2 pattern at the buffer's top-left corner, row by row, such as
        /// `[.red, .green, .green, .blue]` for RGGB.
        let colors: [CFAColor]
        /// The significant bits of each 16-bit sample.
        let bitsPerSample: Int

        /// Creates a layout.
        ///
        /// - Parameters:
        ///   - pattern: Four letters, such as `RGGB`.
        ///   - bitsPerSample: The significant bits of each sample.
        init(pattern: String, bitsPerSample: Int) {
            colors = pattern.compactMap { CFAColor(rawValue: String($0)) }
            self.bitsPerSample = bitsPerSample
        }
    }

    /// The 14-bit Bayer formats, each with its pattern (`CVPixelBuffer.h`).
    static let fourteenBitPatterns: [String: String] = ["rgg4": "RGGB", "grb4": "GRBG", "bgg4": "BGGR", "gbr4": "GBRG"]

    /// The patterns of a versatile Bayer buffer, by its pattern attachment's value
    /// (`kCVVersatileBayer_BayerPattern_RGGB` 0, `GRBG` 1, `GBRG` 2, `BGGR` 3).
    static let versatilePatterns = ["RGGB", "GRBG", "GBRG", "BGGR"]

    /// The layout of a buffer's pixel format.
    ///
    /// - Parameters:
    ///   - pixelFormat: The buffer's pixel format code.
    ///   - versatileBayerPattern: The buffer's Bayer pattern attachment, or `nil` without one.
    /// - Returns: The layout, or `nil` for a format the meter doesn't read (any other format,
    ///   including the packed 12-bit one).
    static func layout(pixelFormat: UInt32, versatileBayerPattern: Int?) -> Layout? {
        let name = FourCharacterCode.string(pixelFormat)
        if let pattern = fourteenBitPatterns[name] { return Layout(pattern: pattern, bitsPerSample: 14) }
        guard name == "bp16", let index = versatileBayerPattern, versatilePatterns.indices.contains(index) else { return nil }
        return Layout(pattern: versatilePatterns[index], bitsPerSample: 16)
    }

    /// A rectangle of photosites: rows `top..<bottom`, columns `left..<right`.
    struct Area: Equatable {
        /// The first row.
        let top: Int
        /// The first column.
        let left: Int
        /// The row after the last.
        let bottom: Int
        /// The column after the last.
        let right: Int

        /// Creates an area.
        ///
        /// - Parameters:
        ///   - top: The first row.
        ///   - left: The first column.
        ///   - bottom: The row after the last.
        ///   - right: The column after the last.
        init(top: Int, left: Int, bottom: Int, right: Int) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }
    }

    /// What the camera's DNG says about its RAW samples.
    struct Levels: Equatable {
        /// `ImageWidth`.
        let width: Int
        /// `ImageLength`.
        let height: Int
        /// `ActiveArea`, or the whole image without one.
        let activeArea: Area
        /// `BitsPerSample`.
        let bitsPerSample: Int
        /// `WhiteLevel`.
        let whiteLevel: Double
        /// `BlackLevel`, row by row over ``repeatRows`` × ``repeatColumns``.
        let blackLevels: [Double]
        /// The black level pattern's rows: 1 or 2.
        let repeatRows: Int
        /// The black level pattern's columns: 1 or 2.
        let repeatColumns: Int

        /// Creates the levels.
        ///
        /// - Parameters:
        ///   - width: `ImageWidth`.
        ///   - height: `ImageLength`.
        ///   - activeArea: The active area.
        ///   - bitsPerSample: `BitsPerSample`.
        ///   - whiteLevel: `WhiteLevel`.
        ///   - blackLevels: The black levels, row by row.
        ///   - repeatRows: The black level pattern's rows.
        ///   - repeatColumns: The black level pattern's columns.
        init(
            width: Int, height: Int, activeArea: Area, bitsPerSample: Int, whiteLevel: Double, blackLevels: [Double],
            repeatRows: Int, repeatColumns: Int
        ) {
            self.width = width
            self.height = height
            self.activeArea = activeArea
            self.bitsPerSample = bitsPerSample
            self.whiteLevel = whiteLevel
            self.blackLevels = blackLevels
            self.repeatRows = repeatRows
            self.repeatColumns = repeatColumns
        }

        /// The black level of a position of the 2 × 2 color filter pattern, counted from the
        /// buffer's top-left corner; the black level pattern starts at the active area's.
        ///
        /// - Parameters:
        ///   - row: 0 or 1.
        ///   - column: 0 or 1.
        /// - Returns: The black level.
        func blackLevel(row: Int, column: Int) -> Double {
            let patternRow = ((row - activeArea.top) % 2 + 2) % 2 % repeatRows
            let patternColumn = ((column - activeArea.left) % 2 + 2) % 2 % repeatColumns
            return blackLevels[patternRow * repeatColumns + patternColumn]
        }
    }

    /// DNG tag numbers (DNG 1.7, TIFF 6.0).
    enum Tag {
        /// `ImageWidth`.
        static let imageWidth: UInt16 = 0x0100
        /// `ImageLength`.
        static let imageLength: UInt16 = 0x0101
        /// `BitsPerSample`.
        static let bitsPerSample: UInt16 = 0x0102
        /// `LinearizationTable`.
        static let linearizationTable: UInt16 = 0xC618
        /// `BlackLevelRepeatDim`.
        static let blackLevelRepeatDim: UInt16 = 0xC619
        /// `BlackLevel`.
        static let blackLevel: UInt16 = 0xC61A
        /// `BlackLevelDeltaH`.
        static let blackLevelDeltaH: UInt16 = 0xC61B
        /// `BlackLevelDeltaV`.
        static let blackLevelDeltaV: UInt16 = 0xC61C
        /// `WhiteLevel`.
        static let whiteLevel: UInt16 = 0xC61D
        /// `ActiveArea`.
        static let activeArea: UInt16 = 0xC68D
    }

    /// The levels a DNG's IFD0 records.
    ///
    /// A pattern of black levels larger than 2 × 2 is used only when all its values are equal.
    ///
    /// - Parameter inventory: The read-back of the camera's DNG.
    /// - Returns: The levels, or `nil` without a size, bit depth or white level, with a
    ///   linearization table or nonzero black level deltas, with black levels that don't match
    ///   their pattern, an active area outside the image, or a white level not above every
    ///   black level.
    static func levels(in inventory: MetadataInventory) -> Levels? {
        func values(_ tag: UInt16) -> [Double] {
            inventory.tags.first { $0.directory == .primary && $0.tag == tag }?.values ?? []
        }
        guard let width = values(Tag.imageWidth).first.map(Int.init), let height = values(Tag.imageLength).first.map(Int.init),
            let bits = values(Tag.bitsPerSample).first.map(Int.init), let white = values(Tag.whiteLevel).first,
            values(Tag.linearizationTable).isEmpty,
            (values(Tag.blackLevelDeltaH) + values(Tag.blackLevelDeltaV)).allSatisfy({ $0 == 0 })
        else { return nil }
        let dimensions = values(Tag.blackLevelRepeatDim).map(Int.init)
        let rows = dimensions.count == 2 ? dimensions[0] : 1
        let columns = dimensions.count == 2 ? dimensions[1] : 1
        // DNG's default black level is 0.
        let recorded = values(Tag.blackLevel)
        let black = recorded.isEmpty && dimensions.isEmpty ? [0] : recorded
        guard black.count == rows * columns, let highestBlack = black.max(), white > highestBlack else { return nil }
        let isSmallPattern = (1...2).contains(rows) && (1...2).contains(columns)
        guard isSmallPattern || Set(black).count == 1 else { return nil }
        let area = values(Tag.activeArea).map(Int.init)
        let active =
            area.count == 4
            ? Area(top: area[0], left: area[1], bottom: area[2], right: area[3])
            : Area(top: 0, left: 0, bottom: height, right: width)
        guard active.top >= 0, active.left >= 0, active.top < active.bottom, active.left < active.right,
            active.bottom <= height, active.right <= width
        else { return nil }
        return Levels(
            width: width, height: height, activeArea: active, bitsPerSample: bits, whiteLevel: white,
            blackLevels: isSmallPattern ? black : [black[0]], repeatRows: isSmallPattern ? rows : 1,
            repeatColumns: isSmallPattern ? columns : 1)
    }

    /// How many photosites hold each value, for each position of the 2 × 2 pattern.
    struct Histogram: Equatable {
        /// The bins per position: every 16-bit value.
        static let binCount = 1 << 16

        /// The counts: position `p`'s bin for value `v` is at `p × binCount + v`.
        private(set) var counts: [UInt32]

        /// Creates an empty histogram.
        init() {
            counts = [UInt32](repeating: 0, count: 4 * Self.binCount)
        }

        /// Counts one photosite.
        ///
        /// - Parameters:
        ///   - value: Its value.
        ///   - position: Its position in the 2 × 2 pattern, `row × 2 + column`.
        mutating func add(_ value: UInt16, position: Int) {
            counts[position * Self.binCount + Int(value)] &+= 1
        }

        /// The photosites of a position whose values are in a range.
        ///
        /// - Parameters:
        ///   - position: The position in the 2 × 2 pattern.
        ///   - range: The values, within 0...65535.
        /// - Returns: The count.
        func count(position: Int, in range: ClosedRange<Int>) -> Int {
            let start = position * Self.binCount
            return counts[(start + range.lowerBound)...(start + range.upperBound)].reduce(0) { $0 + Int($1) }
        }

        /// Every photosite counted.
        var total: Int { counts.reduce(0) { $0 + Int($1) } }

        /// The largest value counted and the bits set in any value counted; both 0 when nothing
        /// was counted.
        var extent: (maximum: Int, bits: Int) {
            var maximum = 0
            var bits = 0
            for (index, count) in counts.enumerated() where count > 0 {
                let value = index % Self.binCount
                maximum = max(maximum, value)
                bits |= value
            }
            return (maximum, bits)
        }
    }

    /// Counts every photosite of an area.
    ///
    /// - Parameters:
    ///   - area: The rows and columns, inside the buffer.
    ///   - sample: Reads the sample at a row and column.
    /// - Returns: The histogram.
    static func histogram(of area: Area, sample: (_ row: Int, _ column: Int) -> UInt16) -> Histogram {
        var histogram = Histogram()
        for row in area.top..<area.bottom {
            let rowPosition = (row & 1) * 2
            for column in area.left..<area.right {
                histogram.add(sample(row, column), position: rowPosition + (column & 1))
            }
        }
        return histogram
    }

    /// The factor that turns the DNG's levels into buffer values: 1 when the buffer's values fit
    /// the white level as they are, or 2 to the power of the difference in bit depth when every
    /// value has those low bits zero (shifted up) and fits the shifted white level.
    ///
    /// Assumption: a buffer that holds the DNG's values unshifted has sensor noise in its low
    /// bits, so its values are never all multiples of the shift (the same reasoning as
    /// ``PictureCheck``).
    ///
    /// - Parameters:
    ///   - histogram: The counted photosites.
    ///   - layout: The buffer's layout.
    ///   - levels: The DNG's levels.
    /// - Returns: The factor, or `nil` when the values fit neither way.
    static func scale(of histogram: Histogram, layout: Layout, levels: Levels) -> Double? {
        let extent = histogram.extent
        let shift = layout.bitsPerSample - levels.bitsPerSample
        if shift > 0, extent.bits & ((1 << shift) - 1) == 0, Double(extent.maximum) <= levels.whiteLevel * Double(1 << shift) {
            return Double(1 << shift)
        }
        return Double(extent.maximum) <= levels.whiteLevel ? 1 : nil
    }

    /// The clipping a histogram shows (`RAWClipping`, "Definition").
    ///
    /// - Parameters:
    ///   - histogram: The counted photosites.
    ///   - layout: The buffer's layout.
    ///   - levels: The DNG's levels.
    /// - Returns: The clipping, or why it can't be read.
    static func clipping(of histogram: Histogram, layout: Layout, levels: Levels) -> RAWClippingResult {
        guard histogram.total > 0 else { return .notMeasured(.noSamples) }
        guard let scale = scale(of: histogram, layout: layout, levels: levels) else { return .notMeasured(.scaleMismatch) }
        let top = Histogram.binCount - 1
        var channels: [CFAColor: RAWClipping.Channel] = [:]
        for (position, color) in layout.colors.enumerated() {
            let black = levels.blackLevel(row: position / 2, column: position % 2)
            let margin = RAWClipping.margin * (levels.whiteLevel - black)
            let highlightStart = min(top, Int(((levels.whiteLevel - margin) * scale).rounded(.up)))
            let shadowEnd = min(top, max(0, Int(((black + margin) * scale).rounded(.down))))
            let previous = channels[color] ?? RAWClipping.Channel(color: color, photosites: 0, highlights: 0, shadows: 0)
            channels[color] = RAWClipping.Channel(
                color: color, photosites: previous.photosites + histogram.count(position: position, in: 0...top),
                highlights: previous.highlights + histogram.count(position: position, in: highlightStart...top),
                shadows: previous.shadows + histogram.count(position: position, in: 0...shadowEnd))
        }
        return .measured(RAWClipping(channels: CFAColor.allCases.compactMap { channels[$0] }))
    }

    /// Measures a photo's clipping.
    ///
    /// - Parameters:
    ///   - pixelFormat: The sensor buffer's pixel format code.
    ///   - versatileBayerPattern: The buffer's Bayer pattern attachment, or `nil`.
    ///   - width: The buffer's width, in photosites.
    ///   - height: The buffer's height, in photosites.
    ///   - dng: The read-back of the camera's own DNG of the same photo.
    ///   - sample: Reads the 16-bit sample at a row and column; called only for rows below
    ///     `height` and columns below `width`.
    /// - Returns: The clipping, or why it wasn't measured.
    static func measure(
        pixelFormat: UInt32, versatileBayerPattern: Int?, width: Int, height: Int, dng: MetadataInventory,
        sample: (_ row: Int, _ column: Int) -> UInt16
    ) -> RAWClippingResult {
        guard let layout = layout(pixelFormat: pixelFormat, versatileBayerPattern: versatileBayerPattern) else {
            return .notMeasured(.unsupportedLayout)
        }
        guard let levels = levels(in: dng) else { return .notMeasured(.levelsUnreadable) }
        guard levels.width == width, levels.height == height else { return .notMeasured(.sizeMismatch) }
        return clipping(of: histogram(of: levels.activeArea, sample: sample), layout: layout, levels: levels)
    }
}
