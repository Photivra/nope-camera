import NopeCore
import SwiftUI

/// Says what the next photo will be: single-frame RAW, or the labeled processed fallback.
///
/// The wording is an honesty claim, so it lives in `Honesty.xcstrings` (AGENTS.md,
/// "Honesty wording is kept apart"). Teal marks only a fact the camera reported (the lens gives
/// Bayer RAW); the fallback uses a warning symbol and a plain explanation. Each status has text
/// and a symbol, never color alone. The badge has a solid backing over the viewfinder.
struct FormatBadge: View {
    /// The format of the next photo.
    let format: CaptureFormat

    /// Creates the badge.
    ///
    /// - Parameter format: The format of the next photo.
    init(format: CaptureFormat) {
        self.format = format
    }

    /// The badge, and for the fallback an explanation below it.
    var body: some View {
        VStack(spacing: 4) {
            if format.isBayerRAW {
                Label {
                    Text("RAW · Single frame", tableName: "Honesty", bundle: .module, comment: "Badge: the next photo is one unprocessed RAW frame from the sensor. RAW is a file format name.")
                } icon: {
                    Image(systemName: "checkmark.seal")
                }
                .foregroundStyle(.teal)
            } else {
                Label {
                    Text("No RAW on This Lens", tableName: "Honesty", bundle: .module, comment: "Badge: the selected lens can't save RAW, so photos get device processing.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.yellow)
                Text(
                    "This lens can't save unprocessed RAW. Its photos have some device processing.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Explains the no-RAW fallback. Must not claim more than the English: the photo IS processed by the device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
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
