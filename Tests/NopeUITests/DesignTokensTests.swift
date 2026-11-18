import Foundation
import SwiftUI
import Testing

@testable import NopeUI

/// The tokens in `DesignTokens.swift` match docs/design/tokens.md one to one, by name and value,
/// and the color pairs the design relies on meet WCAG 2.2 contrast.
struct DesignTokensTests {
    /// The repository root, found from this file's path.
    static let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The rows of the table under the tokens.md heading that contains `heading`: each row's
    /// backticked name in the first column and the text of the second column.
    static func rows(under heading: String) throws -> [(name: String, value: String)] {
        let text = try String(
            contentsOf: repositoryRoot.appending(path: "docs/design/tokens.md"), encoding: .utf8)
        var inSection = false
        var rows: [(String, String)] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                inSection = line.contains(heading)
                continue
            }
            guard inSection, line.hasPrefix("| `") else { continue }
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 2, let name = cells[0].split(separator: "`").first else { continue }
            rows.append((String(name), cells[1]))
        }
        return rows
    }

    /// The first number in a cell, such as 36 in "36 high, 40 wide at least".
    static func firstNumber(in cell: String) -> CGFloat? {
        let digits = cell.prefix { $0.isNumber || $0 == "." }
        return Double(digits).map { CGFloat($0) }
    }

    @Test(arguments: [
        ("enum NopeSpace", NopeSpace.all), ("enum NopeRadius", NopeRadius.all), ("enum NopeSize", NopeSize.all),
    ])
    func numericTokensMatchTheDesign(heading: String, tokens: [(name: String, value: CGFloat)]) throws {
        let documented = try Self.rows(under: heading)
        #expect(!documented.isEmpty, "no table under \(heading)")
        #expect(documented.map(\.name) == tokens.map(\.name))
        for row in documented {
            let value = tokens.first { $0.name == row.name }?.value
            #expect(value == Self.firstNumber(in: row.value), "\(row.name)")
        }
    }

    @Test func sizesNamedInTheNotesMatchTheDesign() {
        // tokens.md: "Take Photo (`shutterRing` 4, `shutterDisc` 60)", "(`capsuleLarge` 44 in the
        // Q foot)", "36 high, 40 wide at least".
        #expect(NopeSize.shutterRing == 4)
        #expect(NopeSize.shutterDisc == 60)
        #expect(NopeSize.shutterDisc + 2 * NopeSize.shutterRing <= NopeSize.shutter)
        #expect(NopeSize.shutterDiscHeld == 50)
        #expect(NopeSize.shutterDiscHeld < NopeSize.shutterDisc)
        #expect(NopeSize.capsuleLarge == 44)
        #expect(NopeSize.lensItemMinWidth == 40)
        let names = Set(NopeSize.all.map(\.name))
        for extra in NopeSize.additional {
            #expect(!names.contains(extra.name), "\(extra.name) is listed twice")
        }
    }

    @Test func spacingIsOnTheFourPointGrid() {
        for token in NopeSpace.all {
            #expect(token.value.truncatingRemainder(dividingBy: 4) == 0, "\(token.name)")
        }
        #expect(NopeSpace.all.map(\.value) == NopeSpace.all.map(\.value).sorted())
    }

    @Test func everyTargetIsAtLeastTheMinimum() {
        #expect(NopeSize.minTarget == 44)
        for target in [NopeSize.iconButton, NopeSize.quick, NopeSize.capsuleLarge, NopeSize.shutter, NopeSize.thumbnail] {
            #expect(target >= NopeSize.minTarget)
        }
        #expect(NopeSize.targetGap == NopeSpace.xs)
    }

    @Test func typeTokensMatchTheDesign() throws {
        let documented = try Self.rows(under: "enum NopeFont")
        #expect(documented.map(\.name) == NopeFont.all.map(\.name))
        #expect(NopeFont.status == .subheadline.weight(.semibold))
        #expect(NopeFont.pill == .footnote.weight(.semibold))
        #expect(NopeFont.tileName == .caption.weight(.medium))
        #expect(NopeFont.tileValue == .subheadline.weight(.semibold))
        #expect(NopeFont.readoutMode == .caption2.weight(.bold))
        #expect(NopeFont.dialValue == .body.weight(.semibold).monospacedDigit())
        #expect(NopeFont.lens == .footnote.weight(.semibold).monospacedDigit())
        #expect(NopeFont.q == .title3.weight(.bold))
        #expect(NopeFont.countdown == .system(size: 96, weight: .bold))
        #expect(NopeFont.countdownSize == 96)
        #expect(NopeFont.countdown(size: 120) == .system(size: 120, weight: .bold))
    }

    @Test func colorTokensMatchTheDesign() throws {
        let documented = try Self.rows(under: "enum NopeColor")
        #expect(documented.map(\.name) == NopeColor.all.map(\.name))
        let all = Set(NopeColor.all.map(\.name))
        for extra in NopeColor.additional {
            #expect(!all.contains(extra.name), "\(extra.name) is listed twice")
        }
        #expect(NopeColor.fact == .teal)
        #expect(NopeColor.warning == .orange)
        #expect(Self.hex(NopeColor.controlFill) == "#333333FF")
        #expect(Self.hex(NopeColor.selectedFill) == "#FFFFFFFF")
        #expect(Self.hex(NopeColor.label) == "#FFFFFFFF")
        #expect(Self.hex(NopeColor.night) == "#FF0000FF")
        #expect(Self.hex(NopeColor.nightOutline) == "#B3201AFF")
        #expect(Self.hex(NopeColor.peaking) == "#FF33D9FF")
        #expect(Self.hex(NopeColor.selectedLabel) == "#000000FF")
        #expect(NightStyle.red == NopeColor.night)
    }

    @Test func materialTokensMatchTheDesign() throws {
        let documented = try Self.rows(under: "enum NopeMaterial")
        #expect(documented.map(\.name) == NopeMaterial.allCases.map(\.name))
        #expect(NopeMaterial.tileFillOpacity == 0.3)
        #expect(NopeMaterial.rowOverlayOpacity == 0.72)
        // Kept at the 0.3.0 value that passed the iPad audit; tokens.md says 86%.
        #expect(NopeMaterial.backingDimming == 0.9)
    }

    @Test(arguments: [false, true])
    func materialsTurnSolidWithReduceTransparencyOrIncreaseContrast(isOn: Bool) {
        for material in [NopeMaterial.backing, .tile] {
            #expect(material.isSolid(reduceTransparency: isOn, increaseContrast: false) == isOn)
            #expect(material.isSolid(reduceTransparency: false, increaseContrast: isOn) == isOn)
        }
        #expect(NopeMaterial.solid.isSolid(reduceTransparency: isOn, increaseContrast: isOn))
        #expect(!NopeMaterial.rowOverlay.isSolid(reduceTransparency: isOn, increaseContrast: isOn))
    }

    @Test func motionTokensMatchTheDesign() throws {
        let documented = try Self.rows(under: "enum NopeMotion")
        #expect(documented.map(\.name) == NopeMotion.all.map(\.name))
        #expect(NopeMotion.panel == .snappy(duration: 0.3))
        #expect(NopeMotion.select == .snappy(duration: 0.2))
        #expect(NopeMotion.fade == .easeInOut(duration: 0.2))
    }

    @Test func reduceMotionCrossfadesAndStopsSliding() {
        #expect(NopeMotion.panel(reduceMotion: false) == NopeMotion.panel)
        #expect(NopeMotion.panel(reduceMotion: true) == .easeInOut(duration: 0.2))
        #expect(NopeMotion.select(reduceMotion: false) == NopeMotion.select)
        #expect(NopeMotion.select(reduceMotion: true) == nil)
        _ = NopeMotion.panelTransition(reduceMotion: true)
        _ = NopeMotion.panelTransition(reduceMotion: false)
    }

    @Test func pressedAndDisabledStates() {
        #expect(NopeMotion.opacity(isPressed: false, isEnabled: true) == 1)
        #expect(NopeMotion.opacity(isPressed: true, isEnabled: true) == 0.7)
        #expect(NopeMotion.opacity(isPressed: false, isEnabled: false) == 0.4)
        #expect(NopeMotion.opacity(isPressed: true, isEnabled: false) == 0.4)
        #expect(NopeMotion.scale(isPressed: true, reduceMotion: false) == 0.97)
        #expect(NopeMotion.scale(isPressed: true, reduceMotion: true) == 1)
        #expect(NopeMotion.scale(isPressed: false, reduceMotion: false) == 1)
    }

    @Test func hapticsMatchTheDesign() {
        #expect(NopeHaptic.shutter == .impact)
        #expect(NopeHaptic.saved == .impact(weight: .light))
        #expect(NopeHaptic.notSaved == .error)
        #expect(NopeHaptic.lensChanged == .selection)
        #expect(NopeHaptic.countdownSecond == .impact(weight: .light))
        #expect(NopeHaptic.levelFlat == .alignment)
        #expect(NopeHaptic.allAuto == .success)
        #expect(NopeHaptic.driveModeChanged == .selection)
        #expect(NopeHaptic.manualControlsChanged == .selection)
        #expect(NopeHaptic.burstFrame == .impact(weight: .light, intensity: 0.6))
    }

    // MARK: - Contrast (WCAG 2.2: 4.5:1 for text, 1.4.3; 3:1 for symbols and outlines, 1.4.11)

    /// A color's sRGB hex value, resolved in the dark appearance.
    static func hex(_ color: Color) -> String {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        return color.resolve(in: environment).description
    }

    /// WCAG 2.2 relative luminance of a color resolved in the dark appearance, after multiplying
    /// it by `multiply` (pure red for night mode's `NightModeStyle`, white otherwise).
    static func luminance(_ color: Color, multiply: Color = .white) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let resolved = color.resolve(in: environment)
        let filter = multiply.resolve(in: environment)
        return 0.2126 * Double(resolved.linearRed * filter.linearRed)
            + 0.7152 * Double(resolved.linearGreen * filter.linearGreen)
            + 0.0722 * Double(resolved.linearBlue * filter.linearBlue)
    }

    /// The WCAG 2.2 contrast ratio of two colors.
    static func contrast(_ first: Color, _ second: Color, multiply: Color = .white) -> Double {
        let a = luminance(first, multiply: multiply)
        let b = luminance(second, multiply: multiply)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test func textOnTheCameraMeetsContrast() {
        #expect(Self.contrast(NopeColor.label, .black) >= 4.5)
        #expect(Self.contrast(NopeColor.label, NopeColor.controlFill) >= 4.5)
        #expect(Self.contrast(NopeColor.labelSecondary, .black) >= 4.5)
        #expect(Self.contrast(NopeColor.labelSecondary, NopeColor.controlFill) >= 4.5)
        #expect(Self.contrast(NopeColor.stripIdle, .black) >= 4.5)
        #expect(Self.contrast(NopeColor.selectedLabel, NopeColor.selectedFill) >= 4.5)
        #expect(Self.contrast(NopeColor.selectedLabelSecondary, NopeColor.selectedFill) >= 4.5)
        #expect(Self.contrast(NopeColor.destructive, NopeColor.controlFill) >= 4.5)
        #expect(Self.contrast(NopeColor.peaking, .black) >= 3)
    }

    @Test func nightModeMeetsContrast() {
        let red = NopeColor.night
        // White is drawn as the night red under the multiply.
        #expect(Self.contrast(.white, .black, multiply: red) >= 4.5)
        #expect(Self.contrast(.white, NopeColor.controlFillNight, multiply: red) >= 4.5)
        #expect(Self.contrast(NopeColor.selectedLabel, NopeColor.selectedFill, multiply: red) >= 4.5)
        #expect(Self.contrast(NopeColor.nightOutlineUnderMultiply, .black, multiply: red) >= 3)
        #expect(Self.contrast(NopeColor.nightOutlineUnderMultiply, NopeColor.controlFillNight, multiply: red) >= 3)
        #expect(Self.contrast(NopeColor.nightOutline, .black) >= 3)
        #expect(Self.contrast(NopeColor.night, .black) >= 4.5)
    }
}

/// The states of the custom button types, resolved from the tokens.
struct NopeControlAppearanceTests {
    @Test(arguments: [NopeIdleFill.control, .tile, .backing, .none], [false, true])
    func selectedIsFilledWhiteWithABlackLabel(idleFill: NopeIdleFill, isNightMode: Bool) {
        let appearance = NopeControlAppearance.resolve(
            isSelected: true, idleFill: idleFill, isNightMode: isNightMode, increaseContrast: true)
        #expect(appearance.fill == .color(NopeColor.selectedFill))
        #expect(appearance.label == NopeColor.selectedLabel)
        #expect(appearance.secondaryLabel == (isNightMode ? NopeColor.selectedLabel : NopeColor.selectedLabelSecondary))
        #expect(appearance.outline == nil)
    }

    @Test func unselectedFillsFollowTheirPlace() {
        func fill(_ idleFill: NopeIdleFill) -> NopeControlAppearance.Fill {
            NopeControlAppearance.resolve(isSelected: false, idleFill: idleFill, isNightMode: false, increaseContrast: false)
                .fill
        }
        #expect(fill(.control) == .color(NopeColor.controlFill))
        #expect(fill(.tile) == .material(.tile))
        #expect(fill(.backing) == .material(.backing))
        #expect(fill(.none) == .none)
    }

    @Test func unselectedLabels() {
        let plain = NopeControlAppearance.resolve(isSelected: false, idleFill: .control, isNightMode: false, increaseContrast: false)
        #expect(plain.label == NopeColor.label)
        #expect(plain.secondaryLabel == NopeColor.stripIdle)
        #expect(plain.outline == nil)
        let word = NopeControlAppearance.resolve(isSelected: false, idleFill: .none, isNightMode: false, increaseContrast: false)
        #expect(word.label == NopeColor.stripIdle)
        let stop = NopeControlAppearance.resolve(
            isSelected: false, idleFill: .control, isDestructive: true, isNightMode: false, increaseContrast: false)
        #expect(stop.label == NopeColor.destructive)
    }

    @Test func increaseContrastOutlinesUnselectedControls() {
        let appearance = NopeControlAppearance.resolve(isSelected: false, idleFill: .tile, isNightMode: false, increaseContrast: true)
        #expect(appearance.outline == NopeColor.labelSecondary)
    }

    @Test(arguments: [NopeIdleFill.control, .tile, .backing, .none], [false, true])
    func nightModeOutlinesOffControlsInRed(idleFill: NopeIdleFill, isDestructive: Bool) {
        let appearance = NopeControlAppearance.resolve(
            isSelected: false, idleFill: idleFill, isDestructive: isDestructive, isNightMode: true, increaseContrast: false)
        #expect(appearance.fill == (idleFill == .none ? .none : .color(NopeColor.controlFillNight)))
        #expect(appearance.label == NopeColor.label)
        #expect(appearance.secondaryLabel == NopeColor.label)
        #expect(appearance.outline == NopeColor.nightOutlineUnderMultiply)
    }
}

/// The button styles and the deprecated 0.3.0 styles can be created with their defaults.
@MainActor
struct NopeButtonStylesTests {
    @Test func stylesHaveTheDesignDefaults() {
        #expect(NopeIconButtonStyle().size == NopeSize.iconButton)
        #expect(!NopeIconButtonStyle().isSelected)
        let capsule = NopeCapsuleStyle()
        #expect(capsule.size == NopeSize.capsule)
        #expect(!capsule.isSelected)
        #expect(capsule.role == nil)
        #expect(capsule.idleFill == .control)
        #expect(capsule.horizontalPadding == NopeSpace.m)
        #expect(NopeCapsuleStyle(isCompact: true).horizontalPadding == NopeSpace.s)
        // A lens: 4 points each side, as in the design's lens group.
        #expect(NopeCapsuleStyle(isCompact: true, labelPadding: NopeSpace.xxs).horizontalPadding == NopeSpace.xxs)
        #expect(NopeTileStyle(isOn: true).minHeight == NopeSize.tileMin)
        #expect(NopeTileStyle(isOn: true).alignment == .leading)
        #expect(!NopePillStyle().isSelected)
        #expect(!NopePillStyle().isOnPicture)
    }

    @Test func cameraColorsForwardToTheTokens() {
        #expect(CameraStyle.fact.color == NopeColor.fact)
        #expect(CameraStyle.warning.color == NopeColor.warning)
    }

    @Test func galleryCanBeCreated() {
        _ = NopeButtonGallery()
        _ = NopeButtonGallery(isNightMode: true).body
    }
}
