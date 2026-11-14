import NopeCore
import SwiftUI

/// The histogram (issue #47) and the live camera readout (issue #52), each on a dark backing,
/// stacked. The camera shows it over the picture's top trailing corner, and below the picture at
/// accessibility text sizes. It shows nothing while neither is on.
struct LiveAidsPanel: View {
    /// The camera model.
    let model: CameraModel

    /// The person's settings.
    let settings: NopeSettings

    /// Creates the panel.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings.
    init(model: CameraModel, settings: NopeSettings) {
        self.model = model
        self.settings = settings
    }

    /// Whether the panel has anything to show, so a layout can leave it out (and its spacing)
    /// otherwise.
    ///
    /// - Parameter model: The camera model.
    static func isShown(_ model: CameraModel) -> Bool {
        model.live.needs.contains(.histogram) || model.live.showsStats
    }

    /// The histogram and the readout.
    var body: some View {
        VStack(alignment: .trailing, spacing: CameraStyle.targetSpacing) {
            if model.live.needs.contains(.histogram), let histogram = model.live.analysis?.histogram {
                HistogramView(histogram: histogram)
            }
            if model.live.showsStats, let stats = model.live.stats {
                LiveReadoutView(rows: LiveReadoutText.rows(for: stats, lens: model.selectedLens, format: model.captureFormat))
            }
        }
    }
}

/// The live histogram with its clipping indicators: white bars on a dark backing, "Preview"
/// under it because it measures the processed preview, not the RAW, and a warning with a symbol
/// and words for clipped highlights or shadows (issue #47).
///
/// VoiceOver reads it as one element whose value says what is clipped, on request; changes
/// aren't announced.
struct HistogramView: View {
    /// The histogram.
    let histogram: Histogram

    /// The size of the graph, in points; it grows with the text size.
    @ScaledMetric(relativeTo: .caption2) private var graphWidth: CGFloat = 128

    /// The graph's height, in points.
    @ScaledMetric(relativeTo: .caption2) private var graphHeight: CGFloat = 48

    /// Creates the view.
    ///
    /// - Parameter histogram: The histogram.
    init(histogram: Histogram) {
        self.histogram = histogram
    }

    /// The graph, its caption and the clipping warnings.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            graph
                .frame(width: graphWidth, height: graphHeight)
            Text("Preview", bundle: .module, comment: "Caption under the live histogram: it measures the live preview, not the RAW file.")
                .font(.caption2)
                .foregroundStyle(.white)
            let clipping = histogram.clipping
            if clipping.highlights {
                warning(Text("Highlights clipped", bundle: .module, comment: "Warning under the live histogram: part of the preview is pure white."), systemImage: "sun.max.trianglebadge.exclamationmark")
            }
            if clipping.shadows {
                warning(Text("Shadows clipped", bundle: .module, comment: "Warning under the live histogram: part of the preview is pure black."), systemImage: "moon.circle")
            }
        }
        .padding(CameraStyle.targetSpacing)
        .darkBacking()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Histogram", bundle: .module, comment: "Name of the live brightness histogram shown with the manual controls, and of its switch."))
        .accessibilityValue(HistogramText.description(of: histogram.clipping))
    }

    /// The bars, each bin's height relative to the tallest.
    private var graph: some View {
        Canvas { context, size in
            let bins = histogram.bins
            let tallest = bins.max() ?? 0
            guard tallest > 0 else { return }
            let width = size.width / CGFloat(bins.count)
            var path = Path()
            for (index, share) in bins.enumerated() {
                let height = size.height * CGFloat(share / tallest)
                path.addRect(CGRect(x: CGFloat(index) * width, y: size.height - height, width: width, height: height))
            }
            context.fill(path, with: .color(.white.opacity(0.85)))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.5)).frame(height: 1) }
    }

    /// One clipping warning: amber, with a symbol and words.
    ///
    /// - Parameters:
    ///   - text: The words.
    ///   - systemImage: The SF Symbol.
    private func warning(_ text: Text, systemImage: String) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(CameraStyle.warning)
    }
}

/// The histogram's words for VoiceOver.
enum HistogramText {
    /// What is clipped, such as "Highlights clipped", or "No clipping".
    ///
    /// - Parameter clipping: The clipping.
    static func description(of clipping: ClippingState) -> Text {
        switch (clipping.highlights, clipping.shadows) {
        case (true, true):
            Text("Highlights and shadows clipped", bundle: .module, comment: "VoiceOver value of the live histogram: parts of the preview are pure white and parts pure black.")
        case (true, false):
            Text("Highlights clipped", bundle: .module, comment: "Warning under the live histogram: part of the preview is pure white.")
        case (false, true):
            Text("Shadows clipped", bundle: .module, comment: "Warning under the live histogram: part of the preview is pure black.")
        case (false, false):
            Text("No clipping", bundle: .module, comment: "VoiceOver value of the live histogram when no part of the preview is pure white or pure black.")
        }
    }
}

/// The live camera readout ("stats for nerds", issue #52): one name and value per line, in small
/// type with tabular digits, on a dark backing.
///
/// VoiceOver reads it as a list on request (each line is one element, name then value); changes
/// aren't announced.
struct LiveReadoutView: View {
    /// The lines.
    let rows: [LiveReadoutText.Row]

    /// Creates the readout.
    ///
    /// - Parameter rows: The lines.
    init(rows: [LiveReadoutText.Row]) {
        self.rows = rows
    }

    /// The lines.
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: CameraStyle.targetSpacing, verticalSpacing: 1) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.name)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(row.value)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.caption2)
        .padding(CameraStyle.targetSpacing)
        .darkBacking()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LiveReadoutText.title)
    }
}

/// The live readout's lines: names and values in words, from what the hardware reports.
@MainActor
enum LiveReadoutText {
    /// One line of the readout.
    struct Row: Identifiable, Equatable {
        /// A stable identifier, such as "iso".
        let id: String
        /// The value's name.
        let name: String
        /// The value.
        let value: String

        /// Creates a line.
        ///
        /// - Parameters:
        ///   - id: A stable identifier.
        ///   - name: The value's name.
        ///   - value: The value.
        init(id: String, name: String, value: String) {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    /// The readout's name, "Live Camera Readout".
    static var title: Text {
        Text("Live Camera Readout", bundle: .module, comment: "Name of the optional overlay that lists the camera's live technical values (shutter, ISO, focus, white balance, and so on), and of its switch.")
    }

    /// The readout's lines for a reading: several values share a line, separated by " · ", so
    /// the readout stays small over the picture.
    ///
    /// - Parameters:
    ///   - reading: The hardware's values.
    ///   - lens: The lens in use, or `nil`.
    ///   - format: The format of the next photo, or `nil`; its name says whether it is Bayer RAW.
    static func rows(for reading: CameraStatsReading, lens: Lens?, format: CaptureFormat?) -> [Row] {
        var rows = [exposureRow(reading), biasRow(reading), focusRow(reading), whiteBalanceRow(reading), gainsRow(reading)]
        let lensValues = [lens.map { LensName.string(for: $0.kind) }, zoom(reading.zoomFactor), format.map(FormatChip.spokenName(for:))]
        rows.append(Row(id: "lens", name: string("Lens", "Live readout line: the lens in use, the zoom factor and the format of the next photo."), value: joined(lensValues.compactMap { $0 })))
        rows.append(processingRow(reading))
        rows.append(Row(
            id: "status", name: string("Status", "Live readout line: whether the camera can take a photo now, and the camera system's pressure level from heat or power."),
            value: joined([reading.isReadyToCapture ? string("Ready", "Live readout value: the camera can take a photo now.") : string("Not Ready", "Live readout value: the camera can't take a photo yet."), name(of: reading.systemPressure)])))
        if reading.isLowPowerMode {
            rows.append(Row(id: "lowPower", name: string("Low Power Mode", "Live readout line: the device's Low Power Mode, shown only while it is on. Use the system's name for Low Power Mode."), value: on))
        }
        if let torch = reading.torchLevel {
            rows.append(Row(
                id: "torch", name: string("Torch", "Live readout line: the torch (steady light) level, as a percentage, or Off."),
                value: torch > 0 ? torch.formatted(.percent.precision(.fractionLength(0))) : off))
        }
        return rows
    }

    /// Shutter, ISO, aperture and exposure mode, such as "1/120 · ISO 100 · f/1.8 · Auto".
    ///
    /// - Parameter reading: The hardware's values.
    static func exposureRow(_ reading: CameraStatsReading) -> Row {
        // "ISO" is the same in every launch language.
        let values = [
            ControlText.shutter(reading.exposureDuration), "ISO " + ControlText.value(reading.iso, of: .iso),
            ControlText.value(reading.aperture, of: .aperture), name(of: reading.exposureMode),
        ]
        return Row(id: "exposure", name: string("Exposure", "Live readout line: shutter, ISO, aperture and how exposure is controlled now (Auto, Locked or Custom)."), value: joined(values))
    }

    /// The exposure bias and the meter offset, such as "+0.3 EV / −0.7 EV".
    ///
    /// - Parameter reading: The hardware's values.
    static func biasRow(_ reading: CameraStatsReading) -> Row {
        Row(
            id: "bias", name: string("Bias / Offset", "Live readout line: the exposure compensation set, then how far the metered exposure is from the camera's target, both in EV."),
            value: ControlText.meter(reading.exposureBias) + " / " + ControlText.meter(reading.exposureOffset))
    }

    /// The relative focus position, the focus mode and the near focus limit when it is on.
    ///
    /// - Parameter reading: The hardware's values.
    static func focusRow(_ reading: CameraStatsReading) -> Row {
        var values = [reading.lensPosition.formatted(.number.precision(.fractionLength(2))), focusModeName(reading)]
        if reading.focusRange == .near {
            values.append(string("Near Limit", "Live readout value: autofocus is limited to near subjects."))
        }
        return Row(id: "focus", name: ControlText.name(.focus), value: joined(values))
    }

    /// The white balance temperature and tint and its mode, such as "5,200 K / +3 · Auto".
    ///
    /// - Parameter reading: The hardware's values.
    static func whiteBalanceRow(_ reading: CameraStatsReading) -> Row {
        let temperatureAndTint = reading.whiteBalance.map {
            ControlText.value($0.temperature, of: .whiteBalance) + " / " + signed($0.tint, fractionLength: 0)
        } ?? notAvailable
        return Row(
            id: "whiteBalance", name: string("White Balance / Tint", "Live readout line: the white balance temperature in kelvin and the tint, then how white balance is controlled now (Auto or Locked)."),
            value: joined([temperatureAndTint, reading.whiteBalanceMode == .auto ? auto : locked]))
    }

    /// The white balance gains, such as "R 1.92 G 1.00 B 1.71".
    ///
    /// - Parameter reading: The hardware's values.
    static func gainsRow(_ reading: CameraStatsReading) -> Row {
        let gains = reading.gains
        // The channel letters R, G and B are the same in every launch language.
        return Row(
            id: "gains", name: string("Gains", "Live readout line: the white balance gains for the red, green and blue channels."),
            value: "R \(fixed(gains.red)) G \(fixed(gains.green)) B \(fixed(gains.blue))")
    }

    /// The processing features that are off: "All", or their names.
    ///
    /// - Parameter reading: The hardware's values.
    static func processingRow(_ reading: CameraStatsReading) -> Row {
        let off = reading.processingOff
        let value: String =
            if off.count == ProcessingFeature.allCases.count {
                string("All", "Live readout value: every listed processing feature is off.")
            } else if off.isEmpty {
                string("None", "Live readout value: no processing feature is off.")
            } else {
                off.map(name(of:)).formatted(.list(type: .and, width: .narrow))
            }
        return Row(id: "processingOff", name: string("Processing Off", "Live readout line: the camera processing features that are off, as the hardware reports them."), value: value)
    }

    /// A zoom factor, such as "1.0×".
    ///
    /// - Parameter factor: The zoom factor.
    static func zoom(_ factor: Double) -> String {
        // The × notation is the same in every launch language.
        fixed(factor, fractionLength: 1) + "×"
    }

    /// Values on one line, separated by " · ".
    ///
    /// - Parameter values: The values.
    static func joined(_ values: [String]) -> String {
        values.joined(separator: " · ")
    }

    /// The name of an exposure mode reading.
    ///
    /// - Parameter mode: The mode.
    static func name(of mode: ExposureModeReading) -> String {
        switch mode {
        case .auto: auto
        case .locked: locked
        case .custom: string("Custom", "Live readout value: exposure is set to a custom ISO and shutter (manual).")
        }
    }

    /// The focus mode, or "Moving" while the lens is moving.
    ///
    /// - Parameter reading: The hardware's values.
    static func focusModeName(_ reading: CameraStatsReading) -> String {
        if reading.isAdjustingFocus { return string("Moving", "Live readout value: the lens is moving to focus.") }
        switch reading.focusMode {
        case .continuousAuto: return string("Continuous", "Live readout value: continuous autofocus.")
        case .auto: return string("Single", "Live readout value: autofocus once, then hold.")
        case .locked: return locked
        }
    }

    /// The name of a pressure level.
    ///
    /// - Parameter pressure: The level.
    static func name(of pressure: SystemPressureReading) -> String {
        switch pressure {
        case .nominal: string("Nominal", "Live readout value: the camera system's pressure level is normal.")
        case .fair: string("Fair", "Live readout value: the camera system's pressure level is slightly raised.")
        case .serious: string("Serious", "Live readout value: the camera system's pressure level is high.")
        case .critical: string("Critical", "Live readout value: the camera system's pressure level is critical.")
        case .shutdown: string("Shutdown", "Live readout value: the camera system is stopping the camera because of pressure.")
        }
    }

    /// The short name of a processing feature.
    ///
    /// - Parameter feature: The feature.
    static func name(of feature: ProcessingFeature) -> String {
        switch feature {
        case .qualityPrioritization: string("Quality priority", "Live readout: the camera feature that favors quality over speed, which can merge several frames.")
        case .appleProRAW: string("Processed RAW", "Live readout: the camera's processed, demosaiced RAW format (not the single-frame Bayer RAW).")
        case .zeroShutterLag: string("Zero shutter lag", "Live readout: the camera feature that takes the photo from frames buffered before the press.")
        case .responsiveCapture: string("Responsive capture", "Live readout: the camera feature that overlaps captures for speed.")
        case .deferredDelivery: string("Deferred processing", "Live readout: the camera feature that finishes processing a photo later.")
        case .constantColor: string("Constant color", "Live readout: the camera feature that corrects colors under mixed light.")
        case .contentAwareDistortionCorrection: string("Content-aware distortion fix", "Live readout: the camera feature that corrects distortion based on what is in the picture.")
        case .geometricDistortionCorrection: string("Lens distortion fix", "Live readout: the camera feature that corrects the lens's geometric distortion.")
        }
    }

    /// A number with a fixed number of decimals, such as "1.92".
    ///
    /// - Parameters:
    ///   - value: The number.
    ///   - fractionLength: The decimals.
    static func fixed(_ value: Double, fractionLength: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(fractionLength)))
    }

    /// A number with its sign, such as "+3".
    ///
    /// - Parameters:
    ///   - value: The number.
    ///   - fractionLength: The decimals.
    static func signed(_ value: Double, fractionLength: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionLength)).sign(strategy: .always(includingZero: false)))
    }

    /// A localized string from this module's catalog.
    ///
    /// - Parameters:
    ///   - key: The English text, which is the key.
    ///   - comment: The translator comment.
    private static func string(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: key, bundle: .module, comment: comment)
    }

    /// "Auto".
    private static var auto: String { String(localized: "Auto", bundle: .module, comment: "A control set automatically by the camera.") }
    /// "Locked".
    private static var locked: String { string("Locked", "Live readout value: the control is locked at its current value.") }
    /// "On".
    private static var on: String { string("On", "Live readout value: a feature is on.") }
    /// "Off".
    private static var off: String { string("Off", "Live readout value: a feature is off.") }
    /// "Not available".
    private static var notAvailable: String { String(localized: "n/a", bundle: .module, comment: "Short for not available: this lens can't set this control. Shown in a small grid slot.") }
}
