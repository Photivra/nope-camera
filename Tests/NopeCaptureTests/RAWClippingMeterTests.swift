import Foundation
import NopeCore
import Testing

@testable import NopeCapture

/// The RAW clipping meter (issue #53), against synthetic Bayer buffers in every pattern and bit
/// depth the meter reads, with DNG read-backs like the camera's.
struct RAWClippingMeterTests {
    typealias Tag = MetadataInventory.Tag

    /// The code of a pixel format name.
    static func code(_ name: String) -> UInt32 {
        FourCharacterCode.code(name) ?? 0
    }

    /// A DNG read-back with a size, bit depth and levels, and optional extra tags.
    static func dng(
        width: Int = 8, height: Int = 6, bits: Int = 12, black: [Double] = [528], white: Double = 4095,
        repeatDim: [Double]? = nil, activeArea: [Double]? = nil, extra: [Tag] = []
    ) -> MetadataInventory {
        var tags = [
            Tag(directory: .primary, tag: 0x0100, values: [Double(width)]),
            Tag(directory: .primary, tag: 0x0101, values: [Double(height)]),
            Tag(directory: .primary, tag: 0x0102, values: [Double(bits)]),
            Tag(directory: .primary, tag: 0xC61D, values: [white]),
        ]
        if !black.isEmpty { tags.append(Tag(directory: .primary, tag: 0xC61A, values: black)) }
        if let repeatDim { tags.append(Tag(directory: .primary, tag: 0xC619, values: repeatDim)) }
        if let activeArea { tags.append(Tag(directory: .primary, tag: 0xC68D, values: activeArea)) }
        return MetadataInventory(tags: tags + extra)
    }

    /// A synthetic buffer: a value for each row and column.
    struct Buffer {
        let width: Int
        let height: Int
        let values: [UInt16]

        init(width: Int, height: Int, value: (Int, Int) -> UInt16) {
            self.width = width
            self.height = height
            values = (0..<height).flatMap { row in (0..<width).map { value(row, $0) } }
        }

        func sample(_ row: Int, _ column: Int) -> UInt16 {
            values[row * width + column]
        }
    }

    /// Measures a buffer.
    static func measure(
        _ buffer: Buffer, format: String = "rgg4", pattern: Int? = nil, dng: MetadataInventory
    ) -> RAWClippingResult {
        RAWClippingMeter.measure(
            pixelFormat: code(format), versatileBayerPattern: pattern, width: buffer.width, height: buffer.height, dng: dng,
            sample: buffer.sample)
    }

    /// The clipping, or a failed expectation.
    static func clipping(_ result: RAWClippingResult) -> RAWClipping? {
        guard case .measured(let clipping) = result else { return nil }
        return clipping
    }

    // MARK: - Layouts

    @Test(arguments: [
        ("rgg4", [CFAColor.red, .green, .green, .blue]), ("grb4", [.green, .red, .blue, .green]),
        ("bgg4", [.blue, .green, .green, .red]), ("gbr4", [.green, .blue, .red, .green]),
    ])
    func fourteenBitFormatsHaveTheirPatterns(format: String, colors: [CFAColor]) {
        let layout = RAWClippingMeter.layout(pixelFormat: Self.code(format), versatileBayerPattern: nil)
        #expect(layout?.colors == colors)
        #expect(layout?.bitsPerSample == 14)
    }

    @Test(arguments: [
        (0, [CFAColor.red, .green, .green, .blue]), (1, [.green, .red, .blue, .green]),
        (2, [.green, .blue, .red, .green]), (3, [.blue, .green, .green, .red]),
    ])
    func versatileBayerUsesItsPatternAttachment(pattern: Int, colors: [CFAColor]) {
        let layout = RAWClippingMeter.layout(pixelFormat: Self.code("bp16"), versatileBayerPattern: pattern)
        #expect(layout?.colors == colors)
        #expect(layout?.bitsPerSample == 16)
    }

    @Test func unknownLayoutsAreNotRead() {
        #expect(RAWClippingMeter.layout(pixelFormat: Self.code("bp16"), versatileBayerPattern: nil) == nil)
        #expect(RAWClippingMeter.layout(pixelFormat: Self.code("bp16"), versatileBayerPattern: 4) == nil)
        #expect(RAWClippingMeter.layout(pixelFormat: Self.code("btp2"), versatileBayerPattern: 0) == nil)
        #expect(RAWClippingMeter.layout(pixelFormat: Self.code("420f"), versatileBayerPattern: nil) == nil)
        let buffer = Buffer(width: 8, height: 6) { _, _ in 1000 }
        #expect(Self.measure(buffer, format: "btp2", dng: Self.dng()) == .notMeasured(.unsupportedLayout))
    }

    // MARK: - Counting

    /// Every pattern, at 14 bits holding 12-bit values as they are: the photosites of one color
    /// at the white level, another at the black level, the rest mid-gray. The camera's own DNG
    /// levels (black 528, white 4095).
    @Test(arguments: ["rgg4", "grb4", "bgg4", "gbr4"])
    func countsEachColorAtFourteenBits(format: String) throws {
        let layout = try #require(RAWClippingMeter.layout(pixelFormat: Self.code(format), versatileBayerPattern: nil))
        let buffer = Buffer(width: 8, height: 6) { row, column in
            switch layout.colors[(row % 2) * 2 + column % 2] {
            case .red: 4095
            case .blue: 527
            case .green: 2001
            }
        }
        let clipping = try #require(Self.clipping(Self.measure(buffer, format: format, dng: Self.dng())))
        #expect(clipping.channels.map(\.color) == [.red, .green, .blue])
        #expect(clipping.photosites == 48)
        #expect(clipping.channels[0] == RAWClipping.Channel(color: .red, photosites: 12, highlights: 12, shadows: 0))
        #expect(clipping.channels[1] == RAWClipping.Channel(color: .green, photosites: 24, highlights: 0, shadows: 0))
        #expect(clipping.channels[2] == RAWClipping.Channel(color: .blue, photosites: 12, highlights: 0, shadows: 12))
        #expect(clipping.highlightShare == 0.25)
        #expect(clipping.shadowShare == 0.25)
    }

    /// 16-bit versatile Bayer in every pattern, with 16-bit DNG levels.
    @Test(arguments: [0, 1, 2, 3])
    func countsAtSixteenBits(pattern: Int) throws {
        let layout = try #require(RAWClippingMeter.layout(pixelFormat: Self.code("bp16"), versatileBayerPattern: pattern))
        let buffer = Buffer(width: 4, height: 4) { row, column in
            layout.colors[(row % 2) * 2 + column % 2] == .green ? 65535 : 30000
        }
        let dng = Self.dng(width: 4, height: 4, bits: 16, black: [0], white: 65535)
        let clipping = try #require(Self.clipping(Self.measure(buffer, format: "bp16", pattern: pattern, dng: dng)))
        #expect(clipping.channels.map(\.highlights) == [0, 8, 0])
        #expect(clipping.shadows == 0)
    }

    /// The margin: 0.5% of the range between the levels. Range 3567, margin 17.835: highlights
    /// from 4078 (4077.165 rounded up), shadows up to 545 (545.835 rounded down).
    @Test func countsWithinTheMargin() throws {
        let values: [UInt16] = [4077, 4078, 4095, 545, 546, 0, 2000, 2000]
        let buffer = Buffer(width: 8, height: 1) { _, column in values[column] }
        let clipping = try #require(Self.clipping(Self.measure(buffer, dng: Self.dng(height: 1))))
        #expect(clipping.highlights == 2)
        #expect(clipping.shadows == 2)
        #expect(clipping.photosites == 8)
    }

    /// A 14-bit buffer holding the 12-bit values shifted up by two bits (every value a multiple of
    /// four) is compared with the levels shifted the same way.
    @Test func readsValuesShiftedUpToTheContainer() throws {
        let buffer = Buffer(width: 4, height: 2) { row, column in
            row == 0 && column == 0 ? 4095 << 2 : row == 1 && column == 1 ? 528 << 2 : 2000 << 2
        }
        let clipping = try #require(Self.clipping(Self.measure(buffer, dng: Self.dng(width: 4, height: 2))))
        #expect(clipping.highlights == 1)
        #expect(clipping.shadows == 1)
    }

    /// Dark 12-bit values in a 14-bit buffer, with noise in their low bits, are read as they are,
    /// not as shifted.
    @Test func readsDarkUnshiftedValuesAsTheyAre() throws {
        let buffer = Buffer(width: 4, height: 2) { row, column in UInt16(529 + row * 4 + column) }
        let clipping = try #require(Self.clipping(Self.measure(buffer, dng: Self.dng(width: 4, height: 2))))
        #expect(clipping.shadows == 8)
        #expect(clipping.highlights == 0)
    }

    @Test func valuesAboveTheWhiteLevelAreAScaleMismatch() {
        let odd = Buffer(width: 4, height: 2) { _, _ in 5001 }
        #expect(Self.measure(odd, dng: Self.dng(width: 4, height: 2)) == .notMeasured(.scaleMismatch))
        // Shifted, but above even the shifted white level.
        let tooHigh = Buffer(width: 4, height: 2) { _, _ in 16384 + 4 }
        #expect(Self.measure(tooHigh, format: "bp16", pattern: 0, dng: Self.dng(width: 4, height: 2, bits: 14, white: 4095)) == .notMeasured(.scaleMismatch))
        // A 16-bit buffer and a 12-bit DNG: values that fit the white level shifted by four bits.
        let shifted = Buffer(width: 4, height: 2) { _, _ in 4095 << 4 }
        let clipping = Self.clipping(Self.measure(shifted, format: "bp16", pattern: 0, dng: Self.dng(width: 4, height: 2)))
        #expect(clipping?.highlights == 8)
    }

    /// Only the active area is counted, and the black level pattern starts at its corner.
    @Test func countsOnlyTheActiveAreaWithItsBlackLevelPattern() throws {
        // A 2 × 2 black level pattern: 100 at the active area's top-left position, 200 elsewhere.
        // The active area starts at row 1, column 1, so the buffer's (1, 1) parity has black 100.
        let dng = Self.dng(
            width: 6, height: 5, black: [100, 200, 200, 200], white: 4095, repeatDim: [2, 2], activeArea: [1, 1, 5, 5])
        let buffer = Buffer(width: 6, height: 5) { row, column in
            if row == 0 || column == 0 || column == 5 { return 4095 }  // masked margin: not counted
            return row % 2 == 1 && column % 2 == 1 ? 110 : 150
        }
        let clipping = try #require(Self.clipping(Self.measure(buffer, dng: dng)))
        #expect(clipping.photosites == 16)
        #expect(clipping.highlights == 0)
        // Shadows: 110 is within the margin of 100 (range 3995, margin 19.975); 150 is below 200.
        #expect(clipping.shadows == 16)
    }

    @Test func oneRowOrOneColumnBlackLevelPatterns() throws {
        let rows = Self.dng(width: 2, height: 2, black: [100, 500], repeatDim: [2, 1])
        let columns = Self.dng(width: 2, height: 2, black: [100, 500], repeatDim: [1, 2])
        // 301, not 300: a value whose low bits are all zero would read as shifted.
        let buffer = Buffer(width: 2, height: 2) { _, _ in 301 }
        #expect(Self.clipping(Self.measure(buffer, dng: rows))?.shadows == 2)
        #expect(Self.clipping(Self.measure(buffer, dng: columns))?.shadows == 2)
    }

    @Test func aLargerBlackLevelPatternIsUsedOnlyWhenEven() throws {
        let even = try #require(RAWClippingMeter.levels(in: Self.dng(black: Array(repeating: 64, count: 9), repeatDim: [3, 3])))
        #expect(even.blackLevels == [64])
        #expect(even.repeatRows == 1 && even.repeatColumns == 1)
        #expect(RAWClippingMeter.levels(in: Self.dng(black: [64, 64, 64, 64, 64, 64, 64, 64, 65], repeatDim: [3, 3])) == nil)
    }

    // MARK: - Levels the meter can't apply

    @Test func readsTheDefaultBlackLevelAndTheWholeImage() throws {
        let levels = try #require(RAWClippingMeter.levels(in: Self.dng(black: [])))
        #expect(levels.blackLevels == [0])
        #expect(levels.activeArea == RAWClippingMeter.Area(top: 0, left: 0, bottom: 6, right: 8))
    }

    @Test(arguments: [
        RAWClippingMeterTests.dng(black: [], repeatDim: [2, 2]),
        RAWClippingMeterTests.dng(black: [1, 2, 3], repeatDim: [2, 2]),
        RAWClippingMeterTests.dng(black: [5000]),
        RAWClippingMeterTests.dng(white: 528),
        RAWClippingMeterTests.dng(activeArea: [0, 0, 7, 8]),
        RAWClippingMeterTests.dng(activeArea: [0, 0, 6, 9]),
        RAWClippingMeterTests.dng(activeArea: [-1, 0, 6, 8]),
        RAWClippingMeterTests.dng(activeArea: [0, -1, 6, 8]),
        RAWClippingMeterTests.dng(activeArea: [3, 0, 3, 8]),
        RAWClippingMeterTests.dng(activeArea: [0, 4, 6, 4]),
        RAWClippingMeterTests.dng(extra: [MetadataInventory.Tag(directory: .primary, tag: 0xC618, values: [0, 1])]),
        RAWClippingMeterTests.dng(extra: [MetadataInventory.Tag(directory: .primary, tag: 0xC61B, values: [0, 2])]),
        RAWClippingMeterTests.dng(extra: [MetadataInventory.Tag(directory: .primary, tag: 0xC61C, values: [1])]),
        MetadataInventory(tags: [MetadataInventory.Tag(directory: .primary, tag: 0x0100, values: [8])]),
        MetadataInventory(tags: [
            MetadataInventory.Tag(directory: .primary, tag: 0x0100, values: [8]), MetadataInventory.Tag(directory: .primary, tag: 0x0101, values: [6]),
        ]),
        MetadataInventory(tags: [
            MetadataInventory.Tag(directory: .primary, tag: 0x0100, values: [8]), MetadataInventory.Tag(directory: .primary, tag: 0x0101, values: [6]),
            MetadataInventory.Tag(directory: .primary, tag: 0x0102, values: [12]),
        ]),
        MetadataInventory(),
    ])
    func unusableLevelsAreNotApplied(inventory: MetadataInventory) {
        #expect(RAWClippingMeter.levels(in: inventory) == nil)
        let buffer = Buffer(width: 8, height: 6) { _, _ in 1000 }
        #expect(Self.measure(buffer, dng: inventory) == .notMeasured(.levelsUnreadable))
    }

    @Test func zeroBlackLevelDeltasAndOtherDirectoriesAreFine() {
        let inventory = Self.dng(extra: [
            Tag(directory: .primary, tag: 0xC61B, values: [0, 0]), Tag(directory: .exif, tag: 0xC618, values: [1]),
        ])
        #expect(RAWClippingMeter.levels(in: inventory) != nil)
    }

    @Test func aBufferOfAnotherSizeIsASizeMismatch() {
        let wide = Buffer(width: 10, height: 6) { _, _ in 1000 }
        let tall = Buffer(width: 8, height: 7) { _, _ in 1000 }
        #expect(Self.measure(wide, dng: Self.dng()) == .notMeasured(.sizeMismatch))
        #expect(Self.measure(tall, dng: Self.dng()) == .notMeasured(.sizeMismatch))
    }

    @Test func anEmptyHistogramHasNoSamples() throws {
        let layout = try #require(RAWClippingMeter.layout(pixelFormat: Self.code("rgg4"), versatileBayerPattern: nil))
        let levels = try #require(RAWClippingMeter.levels(in: Self.dng()))
        #expect(
            RAWClippingMeter.clipping(of: RAWClippingMeter.Histogram(), layout: layout, levels: levels) == .notMeasured(.noSamples))
        #expect(RAWClippingMeter.Histogram().extent.maximum == 0)
        #expect(RAWClippingMeter.Histogram().extent.bits == 0)
    }

    @Test func theHistogramCountsByPosition() {
        var histogram = RAWClippingMeter.Histogram()
        histogram.add(7, position: 3)
        histogram.add(7, position: 3)
        histogram.add(65535, position: 0)
        #expect(histogram.count(position: 3, in: 7...7) == 2)
        #expect(histogram.count(position: 0, in: 0...65535) == 1)
        #expect(histogram.count(position: 1, in: 0...65535) == 0)
        #expect(histogram.total == 3)
        #expect(histogram.extent.maximum == 65535)
        #expect(histogram.extent.bits == 65535)
    }
}
