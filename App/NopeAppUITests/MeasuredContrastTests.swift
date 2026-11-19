import CoreGraphics
import XCTest

/// Tests of ``MeasuredContrast``, the measurement behind the rule that sets aside a contrast
/// finding measured at 7:1 or more (docs/TESTING.md, "Contrast findings set aside by
/// measurement"). They draw their own images and launch no app.
final class MeasuredContrastTests: XCTestCase {
    /// An 8-bit sRGB color.
    private typealias RGB = (red: UInt8, green: UInt8, blue: UInt8)

    /// RGBA bytes of `total` pixels: `foreground` for the first `count`, `background` for the rest.
    private func pixels(_ background: RGB, _ foreground: [(RGB, Int)], total: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var used = 0
        for (color, count) in foreground {
            for _ in 0..<count { bytes += [color.red, color.green, color.blue, 255] }
            used += count
        }
        for _ in used..<total { bytes += [background.red, background.green, background.blue, 255] }
        return bytes
    }

    func testTheWCAGFormulasFixedPoints() {
        let white = MeasuredContrast.relativeLuminance(red: 255, green: 255, blue: 255)
        let black = MeasuredContrast.relativeLuminance(red: 0, green: 0, blue: 0)
        let red = MeasuredContrast.relativeLuminance(red: 255, green: 0, blue: 0)
        XCTAssertEqual(white, 1, accuracy: 1e-9)
        XCTAssertEqual(black, 0, accuracy: 1e-9)
        XCTAssertEqual(red, 0.2126, accuracy: 1e-9)
        XCTAssertEqual(MeasuredContrast.ratio(white, black), 21, accuracy: 1e-9)
        XCTAssertEqual(MeasuredContrast.ratio(black, white), 21, accuracy: 1e-9)
        XCTAssertEqual(MeasuredContrast.ratio(red, black), 5.252, accuracy: 0.001)
    }

    /// The night red on the night mode row before and after 2026-11-19 (docs/design/tokens.md).
    func testTheNightRedOnTheNightRows() {
        let red = MeasuredContrast.relativeLuminance(red: 255, green: 0, blue: 0)
        let oldRow = MeasuredContrast.relativeLuminance(red: 0x2C, green: 0, blue: 0)
        let row = MeasuredContrast.relativeLuminance(red: 0x1C, green: 0, blue: 0)
        XCTAssertEqual(MeasuredContrast.ratio(red, oldRow), 4.74, accuracy: 0.01)
        XCTAssertEqual(MeasuredContrast.ratio(red, row), 5.00, accuracy: 0.01)
        XCTAssertLessThan(MeasuredContrast.ratio(red, row), MeasuredContrast.setAsideMinimum, "night rows are never set aside")
    }

    func testTextOnAPlainBackground() throws {
        // Black text on #EFEFF3, the "Guides" header's colors: 5% of the pixels are text.
        let bytes = pixels((0xEF, 0xEF, 0xF3), [((0, 0, 0), 500)], total: 10_000)
        let ratio = try XCTUnwrap(MeasuredContrast.ratio(ofRGBA: bytes))
        XCTAssertEqual(ratio, 18.3, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(ratio, MeasuredContrast.setAsideMinimum)
    }

    func testTheBackgroundIsTheMostCommonColorWhicheverIsLighter() throws {
        // Light text on a dark background and dark text on a light one measure the same.
        let light = try XCTUnwrap(MeasuredContrast.ratio(ofRGBA: pixels((255, 255, 255), [((0, 0, 0), 300)], total: 10_000)))
        let dark = try XCTUnwrap(MeasuredContrast.ratio(ofRGBA: pixels((0, 0, 0), [((255, 255, 255), 300)], total: 10_000)))
        XCTAssertEqual(light, 21, accuracy: 1e-9)
        XCTAssertEqual(dark, 21, accuracy: 1e-9)
    }

    func testStrayPixelsDontRaiseTheResult() throws {
        // Mid-gray text (about 4:1) with a few black pixels, fewer than 0.5% of the frame.
        let gray: RGB = (0x76, 0x76, 0x76)
        let bytes = pixels((255, 255, 255), [((0, 0, 0), 20), (gray, 600)], total: 10_000)
        let ratio = try XCTUnwrap(MeasuredContrast.ratio(ofRGBA: bytes))
        let grayOnWhite = MeasuredContrast.ratio(MeasuredContrast.relativeLuminance(red: 0x76, green: 0x76, blue: 0x76), 1)
        XCTAssertEqual(ratio, grayOnWhite, accuracy: 1e-9)
        XCTAssertLessThan(ratio, MeasuredContrast.setAsideMinimum)
    }

    func testAntiAliasedEdgesCountTowardTheLowerContrast() throws {
        // 30 full black pixels and 40 lighter edge pixels: 50 are needed, so the edge color decides.
        let edge: RGB = (0x80, 0x80, 0x80)
        let bytes = pixels((255, 255, 255), [((0, 0, 0), 30), (edge, 40)], total: 10_000)
        let ratio = try XCTUnwrap(MeasuredContrast.ratio(ofRGBA: bytes))
        XCTAssertEqual(ratio, MeasuredContrast.ratio(MeasuredContrast.relativeLuminance(red: 0x80, green: 0x80, blue: 0x80), 1), accuracy: 1e-9)
    }

    func testAFrameWithOneColorOrNoPixelsHasNoMeasurement() {
        XCTAssertNil(MeasuredContrast.ratio(ofRGBA: []))
        XCTAssertNil(MeasuredContrast.ratio(ofRGBA: pixels((10, 20, 30), [], total: 100)))
    }

    func testTooFewForegroundPixelsHaveNoMeasurement() {
        // Fewer than nine pixels differ from the background.
        XCTAssertNil(MeasuredContrast.ratio(ofRGBA: pixels((255, 255, 255), [((0, 0, 0), 5)], total: 400)))
    }

    func testAnImageIsDrawnInSRGB() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 400, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0x1C / 255, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 30, height: 10))
        let image = try XCTUnwrap(context.makeImage())
        let ratio = try XCTUnwrap(MeasuredContrast.ratio(of: image))
        XCTAssertEqual(ratio, 5.00, accuracy: 0.01)
    }
}
