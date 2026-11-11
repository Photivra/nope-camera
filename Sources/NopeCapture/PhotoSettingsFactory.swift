import AVFoundation
import NopeCore

/// Builds `AVCapturePhotoSettings` from a ``PhotoSettingsPlan``.
///
/// Creating settings needs no camera, so this is tested; the hardware adapter only passes the
/// result to `capturePhoto(with:delegate:)` or `setPreparedPhotoSettingsArray`.
enum PhotoSettingsFactory {
    /// Creates settings for one photo. Settings can't be reused, so call it for every capture.
    ///
    /// - A RAW plan gives a RAW-only capture, written as DNG (`rawFileType: .dng`), with no
    ///   processed image and no embedded thumbnail.
    /// - A fallback plan gives one HEVC (HEIF) or JPEG image in its file container.
    ///
    /// Every photo uses the plan's prioritization (`.speed`), the flash off, and content-aware
    /// distortion correction and constant color off. No location is supplied, so no GPS
    /// metadata is written by the app.
    ///
    /// - Parameters:
    ///   - plan: What to capture.
    ///   - maxPhotoDimensions: The photo output's `maxPhotoDimensions`, or `nil` to keep the
    ///     default.
    /// - Returns: New settings.
    static func makeSettings(
        for plan: PhotoSettingsPlan, maxPhotoDimensions: PhotoDimensions?
    ) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if let raw = plan.rawPixelFormat {
            settings = AVCapturePhotoSettings(
                rawPixelFormatType: raw, rawFileType: .dng, processedFormat: nil, processedFileType: nil)
        } else {
            let processed = plan.processedFormat ?? .heif
            settings = AVCapturePhotoSettings(
                rawPixelFormatType: 0, rawFileType: nil,
                processedFormat: [AVVideoCodecKey: codec(for: processed)],
                processedFileType: fileType(for: processed))
        }
        settings.photoQualityPrioritization = plan.switches.qualityPrioritization
        settings.flashMode = plan.switches.flashMode
        settings.isAutoContentAwareDistortionCorrectionEnabled = plan.switches.contentAwareDistortionCorrection
        settings.isConstantColorEnabled = plan.switches.constantColor
        if let maxPhotoDimensions {
            settings.maxPhotoDimensions = CMVideoDimensions(
                width: Int32(maxPhotoDimensions.width), height: Int32(maxPhotoDimensions.height))
        }
        return settings
    }

    /// The codec for a processed format: HEVC for HEIF, JPEG for JPEG.
    ///
    /// - Parameter format: The processed format.
    static func codec(for format: ProcessedFallback) -> AVVideoCodecType {
        format == .heif ? .hevc : .jpeg
    }

    /// The file container for a processed format: HEIC for HEIF, JPEG for JPEG.
    ///
    /// - Parameter format: The processed format.
    static func fileType(for format: ProcessedFallback) -> AVFileType {
        format == .heif ? .heic : .jpg
    }
}
