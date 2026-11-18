import NopeCore
import SwiftUI

/// The processing note of a lens without Bayer RAW (issue #80; docs/design/BUILD-SPEC.md, 3.2),
/// opened from the "Processed" marker: what the phone does on this lens, then what the app does.
///
/// Two sections, each paragraph its own row, so VoiceOver reads them one at a time and the form
/// scrolls between them at the largest text sizes:
/// - **What the Phone Does on This Lens**: the phone's camera processes the file before the app
///   receives it, and the app can't turn that off (AVFoundation offers no switch for a processed
///   photo's pipeline). Then the lens's distortion correction as the camera reports it
///   (`Lens/distortionCorrection`). No processing step is named unless it is verified.
/// - **What nope. Does**: nothing more to this lens's file (`PhotoSaver` saves the camera's file
///   as it is); HEIF and JPEG copies developed from a RAW get the chosen look (`DevelopedLook`).
///
/// The wording is a processing claim, so it lives in `Honesty.xcstrings` (AGENTS.md, "Honesty
/// wording is kept apart"); it is a draft for the Honesty review (BUILD-SPEC.md, section 5).
struct ProcessingNote: View {
    /// Whether the lens lets the app turn off distortion correction.
    let distortionCorrection: DistortionCorrection

    /// The look of the HEIF and JPEG copies developed from a RAW.
    let look: DevelopedLook

    /// Creates the note.
    ///
    /// - Parameters:
    ///   - distortionCorrection: Whether the lens lets the app turn off distortion correction.
    ///   - look: The look of the HEIF and JPEG copies developed from a RAW.
    init(distortionCorrection: DistortionCorrection, look: DevelopedLook) {
        self.distortionCorrection = distortionCorrection
        self.look = look
    }

    /// The note's two sections.
    var body: some View {
        Section {
            Group {
                byThePhone
                Self.distortion(distortionCorrection)
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(
                "What the Phone Does on This Lens", tableName: "Honesty", bundle: .module,
                comment: "Heading in the processing note of a lens that can't save RAW: what the phone's camera does to the file. Honesty wording: a fluent human must review every translation before release.")
        }
        Section {
            byTheApp
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(
                "What nope. Does", tableName: "Honesty", bundle: .module,
                comment: "Heading in the processing note of a lens that can't save RAW: what nope. itself does to the file. Keep \"nope.\" unchanged. Honesty wording: a fluent human must review every translation before release.")
        }
    }

    /// The phone's processing, in one sentence.
    private var byThePhone: Text {
        Text(
            "The phone's camera processes this file before nope. receives it. nope. can't turn that processing off.",
            tableName: "Honesty", bundle: .module,
            comment: "Processing note of a lens that can't save RAW. Must not name any processing step: it says only that the phone processes the file and that nope. can't turn it off. Keep \"nope.\" unchanged. Draft wording for the Honesty review (docs/design/BUILD-SPEC.md, section 5). Honesty wording: a fluent human must review every translation before release.")
    }

    /// What the app does to this lens's file and to the copies it develops from a RAW.
    private var byTheApp: Text {
        switch look {
        case .standard:
            Text(
                "Nothing more to this lens's file. HEIF and JPEG copies that nope. develops from a RAW get the Standard look: one overall tone curve, and no noise reduction, sharpening or local tone mapping.",
                tableName: "Honesty", bundle: .module,
                comment: "Processing note of a lens that can't save RAW, while the HEIF and JPEG look is Standard: nope. adds no processing to this lens's file, and what it does to copies developed from a RAW. HEIF, JPEG and RAW are file format names; Standard is the name of the look in Settings, use its translation. Must not claim more than the English. Keep \"nope.\" unchanged. Draft wording for the Honesty review (docs/design/BUILD-SPEC.md, section 5). Honesty wording: a fluent human must review every translation before release.")
        case .flat:
            Text(
                "Nothing more to this lens's file. HEIF and JPEG copies that nope. develops from a RAW get the Flat look: no contrast curve, and no noise reduction, sharpening or local tone mapping.",
                tableName: "Honesty", bundle: .module,
                comment: "Processing note of a lens that can't save RAW, while the HEIF and JPEG look is Flat: nope. adds no processing to this lens's file, and what it does to copies developed from a RAW. HEIF, JPEG and RAW are file format names; Flat is the name of the look in Settings, use its translation. Must not claim more than the English. Keep \"nope.\" unchanged. Draft wording for the Honesty review (docs/design/BUILD-SPEC.md, section 5). Honesty wording: a fluent human must review every translation before release.")
        }
    }

    /// Whether a lens lets the app turn off distortion correction, in plain words. Also used in
    /// the photo's details.
    ///
    /// - Parameter correction: The lens's distortion correction.
    /// - Returns: The sentence.
    static func distortion(_ correction: DistortionCorrection) -> Text {
        switch correction {
        case .turnedOff:
            Text(
                "Distortion correction: this lens lets apps turn it off, and nope. does.",
                tableName: "Honesty", bundle: .module,
                comment: "Processing note and photo details: the lens lets the app turn off the camera's geometric distortion correction, which reshapes the picture. Keep \"nope.\" unchanged. Must not claim more than the English.")
        case .notSwitchable:
            Text(
                "Distortion correction: this lens doesn't let apps turn it off or report whether it's used, so its photos may be corrected for lens distortion.",
                tableName: "Honesty", bundle: .module,
                comment: "Processing note and photo details: the lens offers no switch for the camera's geometric distortion correction, which reshapes the picture. Keep \"may\": it isn't known whether the correction is applied.")
        }
    }
}
