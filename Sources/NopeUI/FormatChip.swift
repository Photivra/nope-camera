import NopeCore
import SwiftUI

/// Says what the next photo will be, at the top of the camera: a teal seal and the formats it is
/// saved in ("RAW + HEIF") for a single-frame RAW, or an amber warning, "Processed: No RAW on This
/// Lens", for the labeled processed fallback: the "Processed" marker, shown before the photo is
/// taken (issue #80) unless the person turns it off in Settings
/// (`NopeSettings/showsProcessedMarker`). Tapping it opens the explanation, the lens's
/// processing note and the formats (``FormatDetailsSheet``).
///
/// The wording is an honesty claim, so it lives in `Honesty.xcstrings` (AGENTS.md, "Honesty
/// wording is kept apart"). Teal marks only the fact the camera reported (the lens gives Bayer
/// RAW); the fallback uses a warning symbol and words, never color alone. Format names are
/// Latin abbreviations, so they stay left to right in right-to-left layouts.
struct FormatChip: View {
    /// The format of the next photo.
    let format: CaptureFormat

    /// The formats each photo is saved in, in display order.
    let savedFormats: [PhotoFormat]

    /// Opens the explanation and the formats.
    let action: () -> Void

    /// Creates the chip.
    ///
    /// - Parameters:
    ///   - format: The format of the next photo.
    ///   - savedFormats: The formats each photo is saved in, in display order.
    ///   - action: Opens the explanation and the formats.
    init(format: CaptureFormat, savedFormats: [PhotoFormat], action: @escaping () -> Void) {
        self.format = format
        self.savedFormats = savedFormats
        self.action = action
    }

    /// The chip.
    var body: some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: format.isBayerRAW ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(format.isBayerRAW ? CameraStyle.fact : CameraStyle.warning)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.2), in: .capsule)
            .frame(minHeight: CameraStyle.minimumTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text("Photo Format", tableName: "Honesty", bundle: .module, comment: "VoiceOver and Voice Control name of the chip at the top of the camera that says what the next photo will be. Tapping it explains the format and lists the formats."))
        .accessibilityValue(spokenValue)
        .accessibilityInputLabels([
            Text("Photo Format", tableName: "Honesty", bundle: .module, comment: "VoiceOver and Voice Control name of the chip at the top of the camera that says what the next photo will be. Tapping it explains the format and lists the formats."),
            title,
        ])
        .accessibilityShowsLargeContentViewer()
    }

    /// "RAW + HEIF", or "Processed: No RAW on This Lens".
    private var title: Text {
        if format.isBayerRAW {
            // Left-to-right marks keep "RAW + HEIF" in reading order in right-to-left layouts.
            Text(verbatim: "\u{200E}" + Self.names(of: savedFormats) + "\u{200E}")
        } else {
            Text("Processed: No RAW on This Lens", tableName: "Honesty", bundle: .module, comment: "Marker on the camera before the photo is taken: the selected lens can't save RAW, so its photos are processed by the phone. RAW is a file format name.")
        }
    }

    /// "single-frame RAW, RAW + HEIF" for VoiceOver.
    private var spokenValue: Text {
        let spoken = Self.spokenName(for: format)
        return format.isBayerRAW ? Text(verbatim: "\(spoken), \(Self.names(of: savedFormats))") : Text(verbatim: spoken)
    }

    /// The formats' short names joined with plus signs, such as "RAW + HEIF". The names are the
    /// same in every language and aren't translated.
    ///
    /// - Parameter formats: The formats, in display order.
    /// - Returns: The joined names.
    static func names(of formats: [PhotoFormat]) -> String {
        formats.map { format in
            switch format {
            case .raw: "RAW"
            case .heif: "HEIF"
            case .jpeg: "JPEG"
            }
        }
        .joined(separator: " + ")
    }

    /// The format's name for VoiceOver, as a sentence fragment.
    ///
    /// - Parameter format: A capture format.
    /// - Returns: For example "single-frame RAW" or "HEIF with some device processing".
    static func spokenName(for format: CaptureFormat) -> String {
        switch format {
        case .bayerRAW:
            String(localized: "single-frame RAW", table: "Honesty", bundle: .module, comment: "Spoken format name in the viewfinder description. RAW is a file format name.")
        case .processedFallback(.heif):
            String(localized: "HEIF with some device processing", table: "Honesty", bundle: .module, comment: "Spoken format name for the no-RAW fallback. HEIF is a file format name.")
        case .processedFallback(.jpeg):
            String(localized: "JPEG with some device processing", table: "Honesty", bundle: .module, comment: "Spoken format name for the no-RAW fallback. JPEG is a file format name.")
        }
    }
}

/// The format chip's sheet: what the next photo is, in plain words, then the formats and the
/// look, the same controls as in Settings. For a lens without RAW, the explanation is followed by
/// the lens's processing note (``ProcessingNote``, issue #80). A popover on iPad, a sheet on
/// iPhone.
struct FormatDetailsSheet: View {
    /// The person's settings.
    let settings: NopeSettings

    /// The format of the next photo.
    let format: CaptureFormat

    /// The selected lens's distortion correction, for the processing note of a lens without RAW.
    let distortionCorrection: DistortionCorrection

    /// Whether any camera on the device gives Bayer RAW.
    let deviceSupportsBayerRAW: Bool

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - format: The format of the next photo.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    ///   - distortionCorrection: The selected lens's distortion correction
    ///     (`Lens/distortionCorrection`). Defaults to the value that claims least.
    init(
        settings: NopeSettings, format: CaptureFormat, deviceSupportsBayerRAW: Bool,
        distortionCorrection: DistortionCorrection = .notSwitchable
    ) {
        self.settings = settings
        self.format = format
        self.distortionCorrection = distortionCorrection
        self.deviceSupportsBayerRAW = deviceSupportsBayerRAW
    }

    /// The explanation and the formats, with a Done button.
    var body: some View {
        NavigationStack {
            FormatsSettingsView(
                settings: settings, deviceSupportsBayerRAW: deviceSupportsBayerRAW, explanation: AnyView(explanation),
                showsLookLink: true)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        DoneButton { dismiss() }
                    }
                }
        }
    }

    /// What the next photo is, in plain words, and for a lens without RAW its processing note.
    @ViewBuilder private var explanation: some View {
        summary
        if case .processedFallback(let fallback) = format {
            ProcessingNote(fallback: fallback, distortionCorrection: distortionCorrection)
        }
    }

    /// What the next photo is, in plain words, after a teal seal or an amber warning symbol.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: format.isBayerRAW ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(format.isBayerRAW ? CameraStyle.fact : CameraStyle.warning)
                .accessibilityHidden(true)
            Group {
                if format.isBayerRAW {
                    Text(
                        "Each photo is one frame from the sensor, saved as RAW with as little processing as this phone allows. HEIF and JPEG copies are developed from it.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the format chip on the camera. RAW, HEIF and JPEG are file format names. Must not claim more than the English: as little processing as the phone allows, not zero.")
                } else {
                    Text(
                        "This lens can't save unprocessed RAW. Its photos have some device processing.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the no-RAW fallback. Must not claim more than the English: the photo IS processed by the device.")
                }
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The confirm button of a sheet: the system checkmark, named "Done" for VoiceOver and Voice
/// Control, with the Large Content Viewer at accessibility text sizes.
struct DoneButton: View {
    /// Closes the sheet.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Closes the sheet.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                Text("Done", bundle: .module, comment: "Button that closes a sheet, such as Settings or Pro Tools.")
            } icon: {
                Image(systemName: "checkmark")
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityShowsLargeContentViewer()
    }
}
