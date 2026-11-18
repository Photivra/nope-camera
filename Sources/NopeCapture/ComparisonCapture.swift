import AVFoundation
import NopeCore

/// The camera call for the comparison shot's second photo (issue #55), behind a protocol so
/// ``AVFoundationCaptureBackend`` can be tested with a fake.
///
/// ``SystemCaptureHardware`` implements it and is verified on a device.
protocol ComparisonHardware: Sendable {
    /// Takes the phone's fully processed photo, with the system's own metadata, and then puts
    /// the photo output back as the app's photos need it.
    ///
    /// The photo output's `maxPhotoQualityPrioritization` is `.speed` for the app's own photos
    /// (Bayer RAW requires it). A `.quality` photo needs the maximum to be at least `.quality`
    /// (`AVCapturePhotoOutput.h`, `photoQualityPrioritization`), so it is raised only for this
    /// photo and set back to `.speed` afterwards, before the app's next photo; the session's other
    /// switches, and the app's photo just taken, are unchanged.
    ///
    /// - Parameters:
    ///   - plan: The comparison photo's settings (``CapturePolicy/comparisonPlan(for:)``).
    ///   - sessionPlan: The session's own photo settings, prepared again afterwards.
    /// - Returns: The file bytes from `AVCapturePhoto.fileDataRepresentation()`, with the
    ///   system's metadata, and the resolved size. No pixel sample and no RAW data.
    /// - Throws: `CaptureError.notRunning` if the session isn't running or the attached camera
    ///   isn't the plan's (`CapturePolicy.camera(_:matches:)`), or
    ///   `CaptureError.captureFailed` if the system reports an error or no file.
    func captureComparison(_ plan: PhotoSettingsPlan, restoring sessionPlan: PhotoSettingsPlan)
        async throws(CaptureError) -> HardwarePhoto
}

extension ProcessingSwitches {
    /// The switches for the comparison shot's second photo: the phone's processing at its
    /// highest setting for apps, `.quality` prioritization, which lets the system combine several
    /// frames where the device does that. Every other switch is the session's
    /// (``leastProcessing``): they are configured once for the session, so the app's own photos
    /// stay exactly as they are. This photo is never saved (issue #55).
    static let phoneProcessing = ProcessingSwitches(
        qualityPrioritization: .quality,
        appleProRAW: false,
        zeroShutterLag: false,
        responsiveCapture: false,
        deferredDelivery: false,
        constantColor: false,
        contentAwareDistortionCorrection: false,
        geometricDistortionCorrection: false,
        videoZoomFactor: 1.0,
        flashMode: .off
    )
}

extension CapturePolicy {
    /// The settings of the comparison shot's second photo: one processed photo at `.quality`
    /// prioritization, with the request's flash mode, as HEIF (JPEG on a lens whose fallback is
    /// JPEG, which offers no HEVC).
    ///
    /// - Parameter request: the app's request.
    /// - Returns: The plan.
    static func comparisonPlan(for request: CaptureRequest) -> PhotoSettingsPlan {
        let format: ProcessedFallback = request.format == .processedFallback(.jpeg) ? .jpeg : .heif
        return PhotoSettingsPlan(
            rawPixelFormat: nil, processedFormat: format,
            switches: ProcessingSwitches.phoneProcessing.withFlashMode(request.flashMode.captureFlashMode),
            deviceID: request.lens.id)
    }
}

extension AVFoundationCaptureBackend: ComparisonCaptureBackend {
    /// Takes the phone's fully processed photo, in memory only (issue #55).
    ///
    /// Privacy: the file keeps the system's own metadata, because showing it is the point; it
    /// is never saved, signed or logged. Its metadata is read with the project's own tag reader.
    ///
    /// - Parameter request: the app's request; must match the last ``startSession(_:)``.
    /// - Returns: The photo.
    /// - Throws: `CaptureError.notRunning` if the session isn't configured for this request,
    ///   `CaptureError.captureFailed` if the hardware can't take it, or the hardware's error.
    public func captureComparison(_ request: CaptureRequest) async throws(CaptureError) -> PhoneProcessedPhoto {
        guard let configuration = activeConfiguration,
            configuration == CapturePolicy.sessionConfiguration(for: request)
        else { throw .notRunning }
        guard let comparisonHardware else { throw .captureFailed }
        let plan = CapturePolicy.comparisonPlan(for: request)
        let photo = try await comparisonHardware.captureComparison(plan, restoring: configuration.photoSettings)
        let format = CapturePolicy.fileFormat(of: plan)
        return PhoneProcessedPhoto(
            data: photo.data, format: format, dimensions: photo.dimensions,
            metadata: MetadataFileReader.read(photo.data, format: format).inventory)
    }
}
