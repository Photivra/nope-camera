import CoreGraphics
import XCTest

/// Measures the contrast of an element from a screenshot of its frame, for the rule that sets
/// aside a contrast finding the measurement contradicts (docs/TESTING.md, "Contrast findings
/// set aside by measurement").
///
/// The accessibility audit of the iOS 26.5 Simulator reported text as low in contrast that
/// screenshots show far above WCAG 2.2's minimum: the "Guides" header of Viewfinder Overlays,
/// black on `#EFEFF3`, about 18:1. A finding is set aside only when the measured ratio is at
/// least ``setAsideMinimum``, 7:1, which is WCAG 2.2's enhanced level for text (1.4.6) and well
/// above the 4.5:1 minimum (1.4.3), so text that is really low in contrast still fails.
///
/// The measurement takes the frame's most common color as the background, and as the
/// foreground the color that a share of the frame's pixels reach (``foregroundShare``): the
/// ratio is the lowest contrast against the background among the pixels of highest contrast.
/// A few stray pixels, such as a sliver of a neighboring view, can't raise the result;
/// anti-aliased edges only lower it, toward keeping the finding.
enum MeasuredContrast {
    /// The lowest measured ratio at which a contrast finding is set aside: WCAG 2.2's enhanced
    /// contrast for text, 7:1 (success criterion 1.4.6).
    static let setAsideMinimum = 7.0

    /// The share of a frame's pixels that must reach a contrast for it to count as the
    /// foreground's: 0.5%, far less than the strokes of a line of text cover in its frame.
    static let foregroundShare = 0.005

    /// The fewest pixels that count as the foreground, for a small frame.
    static let minimumForegroundPixels = 9

    /// The relative luminance of an 8-bit sRGB color, as WCAG 2.2 defines it ("relative
    /// luminance", with the sRGB transfer threshold 0.04045).
    ///
    /// - Parameters:
    ///   - red: The red component, 0 to 255.
    ///   - green: The green component, 0 to 255.
    ///   - blue: The blue component, 0 to 255.
    /// - Returns: The luminance, 0 for black to 1 for white.
    static func relativeLuminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG 2.2 contrast ratio of two relative luminances, 1 to 21, in either order.
    ///
    /// - Parameters:
    ///   - first: One relative luminance.
    ///   - second: The other.
    static func ratio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// The measured contrast of pixels in 8-bit RGBA order (alpha ignored: screenshots are
    /// opaque), or `nil` when there are no pixels, or too few pixels differ from the background
    /// to count as a foreground.
    ///
    /// - Parameter bytes: Four bytes per pixel: red, green, blue, alpha.
    static func ratio(ofRGBA bytes: [UInt8]) -> Double? {
        let count = bytes.count / 4
        guard count > 0 else { return nil }
        var colors: [UInt32: Int] = [:]
        for index in 0..<count {
            let offset = index * 4
            let key = UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2])
            colors[key, default: 0] += 1
        }
        guard colors.count > 1, let background = colors.max(by: { $0.value < $1.value })?.key else { return nil }
        let backgroundLuminance = luminance(of: background)
        // Each other color's contrast against the background, highest first, with its pixel count.
        let contrasts = colors.filter { $0.key != background }
            .map { (ratio(luminance(of: $0.key), backgroundLuminance), $0.value) }
            .sorted { $0.0 > $1.0 }
        let needed = max(minimumForegroundPixels, Int((Double(count) * foregroundShare).rounded(.up)))
        var reached = 0
        for (contrast, pixels) in contrasts {
            reached += pixels
            if reached >= needed { return contrast }
        }
        return nil
    }

    /// The measured contrast of an image, drawn into an 8-bit sRGB bitmap, or `nil` when it
    /// can't be drawn or has a single color.
    ///
    /// - Parameter image: The image, such as an element's screenshot.
    static func ratio(of image: CGImage) -> Double? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ratio(ofRGBA: bytes) : nil
    }

    /// The relative luminance of a color packed as `0xRRGGBB`.
    private static func luminance(of packed: UInt32) -> Double {
        relativeLuminance(red: UInt8(packed >> 16 & 0xFF), green: UInt8(packed >> 8 & 0xFF), blue: UInt8(packed & 0xFF))
    }
}

extension XCUIApplication {
    /// Whether a contrast finding is set aside because the element, measured from a screenshot
    /// of its frame, has a contrast of at least ``MeasuredContrast/setAsideMinimum`` (7:1). Each
    /// finding set aside is written to the test log with the element, the measured ratio and the
    /// iOS version, and its screenshot is attached to the test result.
    ///
    /// Only a contrast finding on an element that exists and lies wholly in the window is
    /// measured; any other finding, and one below 7:1, is never set aside.
    ///
    /// - Parameter issue: A finding of the accessibility audit.
    @MainActor
    func isSetAsideByMeasuredContrast(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .contrast, let live = issue.element, let element = issue.currentElement else { return false }
        let frame = element.frame
        guard !frame.isEmpty, windows.firstMatch.frame.contains(frame) else { return false }
        let screenshot = live.screenshot()
        guard let image = screenshot.image.cgImage, let measured = MeasuredContrast.ratio(of: image) else { return false }
        let system = "iOS \(UIDevice.current.systemVersion)"
        guard measured >= MeasuredContrast.setAsideMinimum else {
            NSLog(
                "Contrast finding kept: \"%@\" (%@) at %@, measured %.2f:1, below %.0f:1, %@", element.label,
                element.identifier, "\(frame)", measured, MeasuredContrast.setAsideMinimum, system)
            return false
        }
        NSLog(
            "Contrast finding set aside: %@ on \"%@\" (%@) at %@, measured %.2f:1, %@", issue.compactDescription,
            element.label, element.identifier, "\(frame)", measured, system)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = String(format: "Contrast set aside, %.2f to 1, %@: %@", measured, system, element.label)
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Contrast finding set aside: \(element.label), \(String(format: "%.2f", measured)):1, \(system)") {
            $0.add(attachment)
        }
        return true
    }
}
