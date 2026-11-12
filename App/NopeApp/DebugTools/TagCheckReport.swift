#if DEBUG
// Debug-only metadata tag check (issue #1, step 2): the JSON report contents.
// Records no device name, user name or location: only the model identifier, the OS version and
// camera properties.

import AVFoundation
import CoreMedia
import Foundation

/// Builds the JSON dictionaries in the tag check reports.
enum TagCheckReport {
    /// The device model identifier (for example `iPhone18,1`) and the OS version.
    static func deviceInfo() -> [String: Any] {
        [
            "deviceModelIdentifier": modelIdentifier(),
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
    }

    /// Describes a configured camera and photo output: type, position, active format, RAW
    /// formats, exposure and aperture ranges, and the output's processing switches.
    /// - Parameters:
    ///   - device: The camera, after the session is configured.
    ///   - output: The photo output attached to it.
    static func describe(device: AVCaptureDevice, output: AVCapturePhotoOutput) -> [String: Any] {
        let format = device.activeFormat
        var formatInfo: [String: Any] = [
            "dimensions": dimensions(CMVideoFormatDescriptionGetDimensions(format.formatDescription)),
            "supportedMaxPhotoDimensions": format.supportedMaxPhotoDimensions.map(dimensions),
            "minISO": format.minISO,
            "maxISO": format.maxISO,
            "minExposureDurationSeconds": format.minExposureDuration.seconds,
            "maxExposureDurationSeconds": format.maxExposureDuration.seconds,
        ]
        if #available(iOS 27.0, *) {
            formatInfo["minLensAperture"] = format.minLensAperture
            formatInfo["maxLensAperture"] = format.maxLensAperture
            formatInfo["defaultLensAperture"] = format.defaultLensAperture
            formatInfo["recommendedLensApertureStops"] = format.recommendedLensApertureStops
        }
        return [
            "deviceType": device.deviceType.rawValue,
            "position": device.position == .front ? "front" : "back",
            "isVirtualDevice": device.isVirtualDevice,
            "videoZoomFactor": device.videoZoomFactor,
            "lensAperture": device.lensAperture,
            "geometricDistortionCorrectionEnabled": device.isGeometricDistortionCorrectionSupported
                ? device.isGeometricDistortionCorrectionEnabled : "unsupported",
            "activeFormat": formatInfo,
            // Every entry, untruncated, also at the top level so it is easy to find.
            "supportedMaxPhotoDimensions": format.supportedMaxPhotoDimensions.map(dimensions),
            "supportedMaxPhotoDimensionsCount": format.supportedMaxPhotoDimensions.count,
            "rawFormats": output.availableRawPhotoPixelFormatTypes.map(rawFormat),
            "photoOutput": [
                "maxPhotoQualityPrioritization": name(of: output.maxPhotoQualityPrioritization),
                "maxPhotoDimensions": dimensions(output.maxPhotoDimensions),
                "maxBracketedCapturePhotoCount": output.maxBracketedCapturePhotoCount,
                "isAppleProRAWEnabled": output.isAppleProRAWEnabled,
                "isAutoDeferredPhotoDeliveryEnabled": output.isAutoDeferredPhotoDeliveryEnabled,
                "isConstantColorEnabled": output.isConstantColorEnabled,
                "isContentAwareDistortionCorrectionEnabled": output.isContentAwareDistortionCorrectionEnabled,
                "isZeroShutterLagEnabled": output.isZeroShutterLagEnabled,
                "isResponsiveCaptureEnabled": output.isResponsiveCaptureEnabled,
                "isFastCapturePrioritizationEnabled": output.isFastCapturePrioritizationEnabled,
                "availablePhotoCodecTypes": output.availablePhotoCodecTypes.map(\.rawValue),
            ] as [String: Any],
        ]
    }

    /// The camera's exposure state, read just before a capture: exposure duration (seconds),
    /// ISO, aperture (f-number), exposure target offset (EV), lens position (0 to 1), white
    /// balance gains and the auto modes.
    /// - Parameter device: The camera.
    static func exposureState(of device: AVCaptureDevice) -> [String: Any] {
        let gains = device.deviceWhiteBalanceGains
        return [
            "exposureDurationSeconds": device.exposureDuration.seconds,
            "iso": device.iso,
            "lensAperture": device.lensAperture,
            "exposureTargetOffset": device.exposureTargetOffset,
            "lensPosition": device.lensPosition,
            "whiteBalanceGains": ["red": gains.redGain, "green": gains.greenGain, "blue": gains.blueGain],
            "exposureMode": device.exposureMode.rawValue,
            "focusMode": device.focusMode.rawValue,
            "whiteBalanceMode": device.whiteBalanceMode.rawValue,
            "isAdjustingExposure": device.isAdjustingExposure,
            "isAdjustingFocus": device.isAdjustingFocus,
            "isAdjustingWhiteBalance": device.isAdjustingWhiteBalance,
        ]
    }

    /// Describes one capture: the requested settings, the resolved settings, and the photo's
    /// metadata dictionary exactly as AVFoundation reports it (`AVCapturePhoto.metadata`).
    /// - Parameter capture: A finished capture.
    static func describe(_ capture: PhotoCaptureWaiter) -> [String: Any] {
        let requested = capture.requestedSettings
        var entry: [String: Any] = [
            "deviceStateAtCapture": capture.deviceStateAtCapture,
            "requestedSettings": [
                // AVCaptureResolvedPhotoSettings has no photoQualityPrioritization, so the
                // requested value is recorded; the resolved dimensions and timing are below.
                "photoQualityPrioritization": name(of: requested.photoQualityPrioritization),
                "rawPhotoPixelFormatType": fourCharacterCode(requested.rawPhotoPixelFormatType),
                "maxPhotoDimensions": dimensions(requested.maxPhotoDimensions),
                "flashMode": requested.flashMode.rawValue,
            ] as [String: Any],
        ]
        if let resolved = capture.resolvedSettings {
            entry["resolvedSettings"] = [
                "photoDimensions": dimensions(resolved.photoDimensions),
                "rawPhotoDimensions": dimensions(resolved.rawPhotoDimensions),
                "embeddedThumbnailDimensions": dimensions(resolved.embeddedThumbnailDimensions),
                "rawEmbeddedThumbnailDimensions": dimensions(resolved.rawEmbeddedThumbnailDimensions),
                "deferredPhotoProxyDimensions": dimensions(resolved.deferredPhotoProxyDimensions),
                "expectedPhotoCount": resolved.expectedPhotoCount,
                "photoProcessingTimeRangeStartSeconds": resolved.photoProcessingTimeRange.start.seconds,
                "photoProcessingTimeRangeDurationSeconds": resolved.photoProcessingTimeRange.duration.seconds,
                "isFlashEnabled": resolved.isFlashEnabled,
                "isContentAwareDistortionCorrectionEnabled": resolved.isContentAwareDistortionCorrectionEnabled,
                "isFastCapturePrioritizationEnabled": resolved.isFastCapturePrioritizationEnabled,
                "isVirtualDeviceFusionEnabled": resolved.isVirtualDeviceFusionEnabled,
            ] as [String: Any]
        }
        if let photo = capture.photo {
            entry["photo"] = [
                "isRawPhoto": photo.isRawPhoto,
                "photoCount": photo.photoCount,
                "sourceDeviceType": photo.sourceDeviceType?.rawValue ?? "none",
                "pixelFormatType": fourCharacterCode(photo.pixelBuffer.map(CVPixelBufferGetPixelFormatType) ?? 0),
            ] as [String: Any]
            entry["metadata"] = photo.metadata
        }
        return entry
    }

    /// Converts any property-list-like value into one `JSONSerialization` accepts: data becomes
    /// its length and a hex prefix, non-finite numbers become strings, and anything else
    /// unrecognized becomes its description.
    /// - Parameter value: A dictionary, array, string, number, data, date or other value.
    static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.mapValues(jsonSafe)
        case let array as [Any]:
            return array.map(jsonSafe)
        case let string as String:
            return string
        case let number as NSNumber:
            return number.doubleValue.isFinite ? number : "\(number)"
        case let data as Data:
            return ["bytes": data.count, "hexPrefix": data.prefix(32).map { String(format: "%02x", $0) }.joined()]
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        default:
            return "\(value)"
        }
    }

    /// The prioritization's name: `speed`, `balanced` or `quality` (raw values 1, 2 and 3 in
    /// AVCapturePhotoOutput.h).
    private static func name(of prioritization: AVCapturePhotoOutput.QualityPrioritization) -> String {
        switch prioritization {
        case .speed: "speed"
        case .balanced: "balanced"
        case .quality: "quality"
        @unknown default: "unknown (\(prioritization.rawValue))"
        }
    }

    /// `{"width": w, "height": h}`.
    private static func dimensions(_ value: CMVideoDimensions) -> [String: Int32] {
        ["width": value.width, "height": value.height]
    }

    /// One RAW pixel format, with whether it is Bayer RAW or Apple ProRAW.
    private static func rawFormat(_ type: OSType) -> [String: Any] {
        [
            "fourCC": fourCharacterCode(type),
            "code": type,
            "isBayerRAW": AVCapturePhotoOutput.isBayerRAWPixelFormat(type),
            "isAppleProRAW": AVCapturePhotoOutput.isAppleProRAWPixelFormat(type),
        ]
    }

    /// A pixel format code as its four characters where printable, else as hex.
    static func fourCharacterCode(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(format: "0x%08x", code) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The hardware model identifier from `uname`, for example `iPhone18,1`. Not the device's
    /// user-visible name, which is never recorded.
    private static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let bytes = Mirror(reflecting: info.machine).children.compactMap { $0.value as? CChar }
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
#endif
