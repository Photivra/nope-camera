import Foundation
import NopeCore
import SwiftUI
import Testing

@testable import NopeUI

/// The quick menu's tile values and the measurements behind its column count
/// (docs/design/BUILD-SPEC.md, 3.6).
@MainActor
struct QuickPanelTests {
    /// Lays out words the way text wraps: greedily between words, and a word wider than the
    /// line broken between characters. Returns the widest line.
    ///
    /// - Parameters:
    ///   - words: Each word's width, in characters.
    ///   - offered: The width offered, in points.
    ///   - character: Each character's width, in points.
    static func laidOutWidth(words: [Int], offered: CGFloat, character: CGFloat = 7) -> CGFloat {
        let space = character
        var widest: CGFloat = 0
        var line: CGFloat = 0
        for word in words {
            var remaining = CGFloat(word) * character
            let needed = line == 0 ? remaining : line + space + remaining
            if needed <= offered {
                line = needed
                widest = max(widest, line)
                continue
            }
            if line > 0 { widest = max(widest, line) }
            line = 0
            // A word wider than the line fills whole lines with characters.
            let perLine = max(floor(offered / character), 1) * character
            while remaining > offered {
                widest = max(widest, perLine)
                remaining -= perLine
            }
            line = remaining
            widest = max(widest, line)
        }
        return widest
    }

    /// The word-safe width of words, as the grid works it out.
    static func wordSafeWidth(_ words: [Int], character: CGFloat = 7) -> CGFloat {
        let single = laidOutWidth(words: words, offered: .infinity, character: character)
        return QuickTileMetrics.wordSafeWidth(singleLineWidth: single, characterWidth: character * 2) { offered in
            laidOutWidth(words: words, offered: offered, character: character)
        }
    }

    @Test func wordSafeWidthIsTheLongestWord() {
        // "Kurze Verschlusszeit": the longest word, not the whole name, and not less.
        #expect(Self.wordSafeWidth([5, 14]) == 98)
        // "Close-Up", one word: its whole width.
        #expect(Self.wordSafeWidth([8]) == 56)
        // "Night Mode": the longer of two words.
        #expect(Self.wordSafeWidth([5, 4]) == 35)
        // Three words, the longest last.
        #expect(Self.wordSafeWidth([2, 3, 9]) == 63)
    }

    @Test func wordSafeWidthIsNeverNarrowerThanTheLongestWord() {
        for words in [[1], [3, 3], [12, 1, 1], [1, 12], [4, 4, 4, 4], [20], [2, 18, 2]] {
            let longest = CGFloat(words.max()!) * 7
            #expect(Self.wordSafeWidth(words) >= longest)
        }
    }

    @Test func wordSafeWidthStopsAtATinyWidth() {
        #expect(QuickTileMetrics.wordSafeWidth(singleLineWidth: 10, characterWidth: 20) { $0 } == 10)
        #expect(QuickTileMetrics.wordSafeWidth(singleLineWidth: 0, characterWidth: 0) { $0 } == 0)
    }

    @Test func columnCountDropsWhenATileDoesNotFit() {
        // 327 points at 8-point gaps: three columns of 103.67, two of 159.5.
        #expect(QuickTileMetrics.columnCount(requiredWidths: [60, 100, 90], width: 327, spacing: 8) == 3)
        #expect(QuickTileMetrics.columnCount(requiredWidths: [60, 120], width: 327, spacing: 8) == 2)
        #expect(QuickTileMetrics.columnCount(requiredWidths: [200], width: 327, spacing: 8) == 1)
        #expect(QuickTileMetrics.columnCount(requiredWidths: [400], width: 327, spacing: 8) == 1)
        #expect(QuickTileMetrics.columnCount(requiredWidths: [], width: 327, spacing: 8) == 3)
    }

    @Test func columnWidthShareTheWidth() {
        #expect(QuickTileMetrics.columnWidth(columns: 3, width: 316, spacing: 8) == 100)
        #expect(QuickTileMetrics.columnWidth(columns: 1, width: 50, spacing: 8) == 50)
        #expect(QuickTileMetrics.columnWidth(columns: 0, width: 50, spacing: 8) == 50)
        #expect(QuickTileMetrics.columnWidth(columns: 3, width: 4, spacing: 8) == 0)
    }

    @Test func rowsFillFromTheStart() {
        #expect(QuickTileMetrics.rows(count: 13, columns: 3) == [0..<3, 3..<6, 6..<9, 9..<12, 12..<13])
        #expect(QuickTileMetrics.rows(count: 2, columns: 3) == [0..<2])
        #expect(QuickTileMetrics.rows(count: 0, columns: 3).isEmpty)
        #expect(QuickTileMetrics.rows(count: 2, columns: 0) == [0..<1, 1..<2])
    }

    @Test func onlyJapaneseAndChineseBreakAnywhere() {
        #expect(QuickTileMetrics.breaksAnywhere(languageCode: "ja"))
        #expect(QuickTileMetrics.breaksAnywhere(languageCode: "zh"))
        for code in ["en", "de", "ko", "fr", "nl", nil] {
            #expect(!QuickTileMetrics.breaksAnywhere(languageCode: code))
        }
    }

    @Test func itemsShowTheirKindsValue() {
        let toggle = QuickControlItem(id: "a", title: Text(verbatim: "A"), systemImage: "a.circle", kind: .toggle(isOn: true, set: { _ in }))
        #expect(toggle.value == QuickControlsText.on)
        #expect(!toggle.closesPanel)
        let off = QuickControlItem(id: "a", title: Text(verbatim: "A"), systemImage: "a.circle", kind: .toggle(isOn: false, set: { _ in }))
        #expect(off.value == QuickControlsText.off)
        let options = [
            QuickControlItem.Option(id: "off", title: Text(verbatim: "Off"), isSelected: false, select: {}),
            QuickControlItem.Option(id: "thirds", title: Text(verbatim: "Thirds"), isSelected: true, select: {}),
        ]
        let menu = QuickControlItem(id: "b", title: Text(verbatim: "B"), systemImage: "b.circle", kind: .menu(options))
        #expect(menu.value == Text(verbatim: "Thirds"))
        #expect(!menu.closesPanel)
        let button = QuickControlItem(id: "c", title: Text(verbatim: "C"), systemImage: "c.circle", kind: .button {})
        #expect(button.value == nil)
        #expect(button.closesPanel)
        #expect(!button.isOn)
    }

    @Test func itemsCanOverrideValueAndState() {
        let item = QuickControlItem(
            id: "c", title: Text(verbatim: "C"), systemImage: "c.circle", kind: .button {}, value: Text(verbatim: "+0.7"), isOn: true)
        #expect(item.value == Text(verbatim: "+0.7"))
        #expect(item.isOn)
    }

    @Test func shortValues() {
        #expect(QuickControlsText.shortName(of: FlashMode.off) == QuickControlsText.off)
        #expect(QuickControlsText.shortName(of: FlashMode.on) == QuickControlsText.on)
        #expect(QuickControlsText.shortName(of: FlashMode.auto) != QuickControlsText.on)
        #expect(QuickControlsText.shortName(of: FastShutter.freezeMotion) == Text(verbatim: "1/500"))
        #expect(QuickControlsText.shortName(of: FastShutter.freezeFastMotion) == Text(verbatim: "1/1000"))
        #expect(QuickControlsText.shortName(of: FastShutter.handheld) == FastShutterText.name(.handheld))
        #expect(QuickControlsText.lightValue(.off, requestedLevel: 0.25) == QuickControlsText.off)
        #expect(QuickControlsText.lightValue(.on(level: 0.5), requestedLevel: 0.25) == Text(0.5, format: .percent.precision(.fractionLength(0))))
        #expect(QuickControlsText.lightValue(.pending, requestedLevel: 0.25) == Text(0.25, format: .percent.precision(.fractionLength(0))))
        #expect(QuickControlsText.lightValue(.unavailable, requestedLevel: 0.25) != QuickControlsText.off)
        #expect(QuickControlsText.saved(0) != QuickControlsText.saved(2))
    }

    @Test func readoutTileSaysPinned() {
        let context = RegistryTests.context(suite: "QuickPanelTests.readout")
        #expect(QuickControls.readoutValue(context) == QuickControlsText.off)
        context.settings.setShowsLiveReadout(true)
        #expect(QuickControls.readoutValue(context) == QuickControlsText.on)
        context.settings.setPinsLiveReadout(true)
        #expect(QuickControls.readoutValue(context) == QuickControlsText.pinned)
        #expect(QuickControls.presetsValue(context) == QuickControlsText.saved(0))
    }

    @Test func withValueReplacesTheValue() {
        let context = RegistryTests.context(suite: "QuickPanelTests.withValue")
        let builder = QuickControls.withValue(QuickControls.level) { _ in Text(verbatim: "X") }
        #expect(builder(context)?.value == Text(verbatim: "X"))
        let none = QuickControls.withValue({ _ in nil }) { _ in Text(verbatim: "X") }
        #expect(none(context) == nil)
    }

    @Test func hideControlsIsAButton() {
        let context = RegistryTests.context(suite: "QuickPanelTests.hide")
        #expect(QuickControls.hideControls(context).closesPanel)
    }
}
