import Foundation
import NopeCore
import SwiftUI
import Testing

@testable import NopeUI

@MainActor
struct LiveReadoutTextTests {
    static let lens = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1)

    @Test func readoutListsTheHardwaresValues() {
        let rows = LiveReadoutText.rows(
            for: SimulatedCaptureBackend.placeholderStats, lens: Self.lens, format: CaptureFormat(for: Self.lens))
        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.value) })
        #expect(rows.map(\.id) == ["exposure", "bias", "focus", "whiteBalance", "gains", "lens", "processingOff", "status"])
        #expect(values["exposure"] == "1/120 · ISO 100 · f/1.8 · Auto")
        #expect(values["bias"] == "0.0 EV / 0.0 EV")
        #expect(values["focus"] == "0.50 · Continuous")
        #expect(values["whiteBalance"] == "5,200 K / 0 · Auto")
        #expect(values["gains"] == "R 1.90 G 1.00 B 1.70")
        #expect(values["lens"] == "Wide · 1.0× · single-frame RAW")
        #expect(values["processingOff"] == "All")
        #expect(values["status"] == "Ready · Nominal")
    }

    @Test func optionalLinesAndOtherStates() {
        var stats = SimulatedCaptureBackend.placeholderStats
        stats.exposureMode = .custom
        stats.focusMode = .locked
        stats.focusRange = .near
        stats.whiteBalance = nil
        stats.whiteBalanceMode = .locked
        stats.processingOn = Set(ProcessingFeature.allCases).subtracting([.zeroShutterLag, .constantColor])
        stats.isReadyToCapture = false
        stats.systemPressure = .serious
        stats.isLowPowerMode = true
        stats.torchLevel = 0.5
        let rows = LiveReadoutText.rows(for: stats, lens: nil, format: nil)
        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.value) })
        #expect(values["exposure"]?.hasSuffix("Custom") == true)
        #expect(values["focus"] == "0.50 · Locked · Near Limit")
        #expect(values["whiteBalance"] == "n/a · Locked")
        #expect(values["processingOff"] == "Zero shutter lag, Constant color")
        #expect(values["lens"] == "1.0×")
        #expect(values["status"] == "Not Ready · Serious")
        #expect(values["lowPower"] == "On")
        #expect(values["torch"] == "50%")
        stats.torchLevel = 0
        stats.processingOn = Set(ProcessingFeature.allCases)
        stats.isAdjustingFocus = true
        let more = Dictionary(uniqueKeysWithValues: LiveReadoutText.rows(for: stats, lens: nil, format: nil).map { ($0.id, $0.value) })
        #expect(more["torch"] == "Off")
        #expect(more["processingOff"] == "None")
        #expect(more["focus"]?.contains("Moving") == true)
        stats.isAdjustingFocus = false
        stats.focusMode = .auto
        #expect(LiveReadoutText.focusModeName(stats) == "Single")
    }

    @Test func everyNameIsWords() {
        for feature in ProcessingFeature.allCases {
            #expect(!LiveReadoutText.name(of: feature).isEmpty)
        }
        let pressures: [SystemPressureReading] = [.nominal, .fair, .serious, .critical, .shutdown]
        #expect(Set(pressures.map(LiveReadoutText.name(of:))).count == 5)
        #expect(LiveReadoutText.name(of: ExposureModeReading.locked) == "Locked")
    }
}

@MainActor
struct OverlayDrawingTests {
    @Test func gridPathsCoverEveryStyle() {
        let size = CGSize(width: 300, height: 400)
        for style in GridStyle.allCases {
            let path = GridOverlay.path(style: style, placement: .standard, in: size)
            #expect(!path.isEmpty, "\(style)")
            #expect(path.boundingRect.width <= 300.5 && path.boundingRect.height <= 400.5)
        }
        #expect(GridOverlay.path(style: .square, placement: .standard, in: .zero).isEmpty)
    }

    @Test func levelAndHistogramDescriptions() {
        #expect(LevelText.degreesText(3.4) == "3°")
        _ = LevelText.description(of: nil)
        _ = LevelText.description(of: .horizon(rotationDegrees: 3, tiltDegrees: 3, isLevel: false))
        _ = LevelText.description(of: .horizon(rotationDegrees: -3, tiltDegrees: -3, isLevel: false))
        _ = LevelText.description(of: .horizon(rotationDegrees: 0, tiltDegrees: 0, isLevel: true))
        _ = LevelText.description(of: .flat(pitchDegrees: 0, rollDegrees: 0, isLevel: true))
        _ = LevelText.description(of: .flat(pitchDegrees: 5, rollDegrees: 0, isLevel: false))
        for highlights in [false, true] {
            for shadows in [false, true] {
                _ = HistogramText.description(of: ClippingState(highlights: highlights, shadows: shadows))
            }
        }
    }
}
