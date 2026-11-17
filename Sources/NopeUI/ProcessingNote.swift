import NopeCore
import SwiftUI

/// The processing note of a lens without Bayer RAW (issue #80), opened from the "Processed"
/// marker: what the phone's camera does to that lens's photo, what the app turns off, whether
/// the lens lets the app turn off distortion correction, and what the app itself does to the
/// files it saves.
///
/// Each paragraph is its own row, so VoiceOver reads them one at a time and the form scrolls
/// between them at the largest text sizes. Every sentence describes the code as it is:
/// - the phone's processing is whatever the camera's pipeline applies to a processed photo,
///   which AVFoundation offers no switch for;
/// - the switches the app turns off are `ProcessingSwitches.leastProcessing` in `NopeCapture`;
/// - the distortion line is what the camera reports (`DistortionCorrection`);
/// - the fallback file is saved as the camera made it (`PhotoSaver`), and HEIF and JPEG copies
///   of a RAW are developed as `DevelopedLook` documents.
///
/// The wording is a processing claim, so it lives in `Honesty.xcstrings` (AGENTS.md, "Honesty
/// wording is kept apart").
struct ProcessingNote: View {
    /// The lens's processed format.
    let fallback: ProcessedFallback

    /// Whether the lens lets the app turn off distortion correction.
    let distortionCorrection: DistortionCorrection

    /// Creates the note.
    ///
    /// - Parameters:
    ///   - fallback: The lens's processed format.
    ///   - distortionCorrection: Whether the lens lets the app turn off distortion correction.
    init(fallback: ProcessedFallback, distortionCorrection: DistortionCorrection) {
        self.fallback = fallback
        self.distortionCorrection = distortionCorrection
    }

    /// The note's paragraphs, one row each.
    var body: some View {
        Group {
            byThePhone
            turnedOff
            Self.distortion(distortionCorrection)
            byTheApp
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What the phone's camera does to the photo.
    private var byThePhone: Text {
        let format = fallback == .heif ? "HEIF" : "JPEG"
        return Text(
            "The phone's camera makes this photo: it turns the sensor data into a finished image, choosing its colors and tone and any noise reduction and sharpening, and compresses it as \(format). Apps can't turn these steps off.",
            tableName: "Honesty", bundle: .module,
            comment: "Processing note of a lens without RAW. The placeholder is a file format name, HEIF or JPEG. Must not claim more than the English: it says what the phone may apply, not that it applies each step.")
    }

    /// The processing switches the app turns off.
    private var turnedOff: Text {
        Text(
            "nope. asks the camera to put speed before quality, and turns off what apps can: Apple ProRAW, zero shutter lag, responsive capture, deferred processing, constant color, content-aware distortion correction and digital zoom.",
            tableName: "Honesty", bundle: .module,
            comment: "Processing note of a lens without RAW: the camera features the app turns off. Apple ProRAW is Apple's name. Keep \"nope.\" unchanged. Must not claim more than the English.")
    }

    /// What the app does to the files it saves.
    private var byTheApp: Text {
        Text(
            "nope. saves the camera's file without changing its pixels. On a lens with RAW, nope. develops its own HEIF and JPEG copies from the RAW, with one overall tone curve (Standard) or none (Flat), and no noise reduction, sharpening or local tone mapping.",
            tableName: "Honesty", bundle: .module,
            comment: "Processing note of a lens without RAW: what the app itself does. RAW, HEIF and JPEG are file format names; Standard and Flat are the names of the two looks in Settings. Keep \"nope.\" unchanged. Must not claim more than the English.")
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
