# Capture and file settings an app can control (issue #57)

The owner principle (issue #57, AGENTS.md "Code"): anything about the file or the exposure that
the device lets an app control should be controllable by the person, behind the manual or
advanced options, with full auto as the default; and every file nope. can save must open. This
page lists every capture and file setting AVFoundation and ImageIO expose to an app on iOS 18 to
27, what nope. offers, and why anything isn't offered. Keep it current when an SDK adds a setting.

Sources are the iOS 27.2 SDK headers (Xcode 27.2): `AVFoundation/AVCapturePhotoOutput.h`
(`AVCapturePhotoOutput`, `AVCapturePhotoSettings`), `AVFoundation/AVCaptureDevice.h`,
`AVFoundation/AVCaptureSession.h` (`AVCaptureConnection`) and `ImageIO/CGImageDestination.h`.
"Offered" means a control in nope. today; "fixed" means nope. sets it to one value on purpose;
"not offered" gives the reason. Status as of 0.2.0.

Each status is per lens and per format at run time (AGENTS.md, "Progressive enhancement"): a
control appears only where the lens's active format reports it (`ManualCapabilities`,
`DeviceControls`).

## File settings

| Setting (API) | nope. | Why |
|---|---|---|
| RAW format: Bayer RAW DNG (`rawPhotoPixelFormatType`, `rawFileType: .dng`) | Fixed | Single-frame Bayer RAW is the product (AGENTS.md, "Honesty"). |
| Apple ProRAW (`isAppleProRAWEnabled`, `AVVideoAppleProRAWBitDepthKey`) | Not offered | Multi-frame and processed; ruled out by AGENTS.md. Its bit depth and quality keys apply only to ProRAW. |
| Bayer RAW compression or bit depth | Not offered | No API: `rawFileFormat` takes codec and quality keys for ProRAW only. The device's DNG is 12-bit lossless JPEG (docs/PRIVACY.md, "Results"). |
| Formats RAW, HEIF, JPEG (any combination) | Offered | Settings › Formats (issue #1). |
| Which copy is paired with the RAW in Photos | Offered | Settings › Formats › Paired with RAW, when RAW, HEIF and JPEG are all saved (issue #50). |
| HEIF and JPEG look (tone curve) | Offered | Settings › Look: Standard or Flat (`DevelopedLook`). |
| HEIF and JPEG compression (`kCGImageDestinationLossyCompressionQuality`) | Offered | Settings › File Options: System Default, Maximum, High (0.9), Medium (0.7); HEIF defaults to the encoder's own quality and JPEG to maximum, as before (`DevelopedFileOptions`). |
| HEIF bit depth (10-bit from a 16-bit image, or 8-bit) | Offered | File Options: 10-bit (default) or 8-bit. ImageIO writes a 16-bit image as 10-bit HEIF on the iOS 27 Simulator and macOS 27 (`PhotoEncoder`). JPEG has only 8 bits. |
| Color space of the developed copies (Display P3 or sRGB) | Offered | File Options. sRGB is converted by Core Graphics when drawing, not relabeled. |
| HDR gain map / ISO HDR (`kCGImageDestinationEncodeRequest`, `…EncodeToISOHDR`, `…EncodeToISOGainmap`) | Not offered | The RAW developer outputs an SDR image; a gain map is an auxiliary image the read-back rejects (`heif:item:tmap`, `auxl`) and would need its own allowlist and research. Candidate for later. |
| Embedded thumbnail (`kCGImageDestinationEmbedThumbnail`, `embeddedThumbnailPhotoFormat`, `rawEmbeddedThumbnailPhotoFormat`) | Fixed off | Privacy: a thumbnail is a second copy that keeps pixels after an edit, and the allowlist has no thumbnail blocks. |
| Preview image (`previewPhotoFormat`) | Not offered | Only in memory; nope. doesn't use it. |
| Downscaled size (`kCGImageDestinationImageMaxPixelSize`) | Not offered | Not yet. It would make smaller copies; it is safe to add later (files open). |
| Photo dimensions (`maxPhotoDimensions` from `activeFormat.supportedMaxPhotoDimensions`) | Fixed | The active format's size the backend picks (`SessionConfiguration.maxPhotoDimensions`). The Bayer RAW was 12 MP on every lens of the device measured (docs/PRIVACY.md, "Results"). Whether any lens offers a second Bayer RAW size, and a size choice for the processed fallback, isn't measured yet: a device check before it can be offered. |
| Optimize color for sharing (`kCGImageDestinationOptimizeColorForSharing`) | Not offered | The sRGB option covers the case explicitly. |
| Metadata (`AVCapturePhotoSettings.metadata`, `kCGImageDestinationMetadata`) | Fixed | Built from the allowlist (docs/PRIVACY.md); location from `LocationTagging` (issue #43). |
| Orientation, mirroring (`AVCaptureConnection.videoMirrored`, Orientation tag) | Offered | Settings › Mirror Front Camera (issue #45): through the Orientation value only; the photo output's own mirroring is turned off. |
| Live Photo, depth, portrait matte, semantic mattes, camera calibration data (`livePhotoMovieFileURL`, `isDepthDataDeliveryEnabled`, `isPortraitEffectsMatteDeliveryEnabled`, `enabledSemanticSegmentationMatteTypes`, `isCameraCalibrationDataDeliveryEnabled`) | Not offered | Processed or extra data, not single-frame RAW; auxiliary images fail the read-back. |
| Shutter sound (`isShutterSoundSuppressionEnabled`) | Not offered | The shutter sound follows the system (AGENTS.md, "Hearing"). |
| Quality prioritization (`photoQualityPrioritization`, `maxPhotoQualityPrioritization`) | Fixed `.speed` | `CapturePolicy`: the least processing for the fallback; the header documents `.balanced` and `.quality` as allowing more processing time. Its effect on Bayer RAW data isn't measured. |
| Content-aware distortion correction, geometric distortion correction, constant color, auto red-eye reduction, virtual device fusion, still image stabilization | Fixed off | Each changes pixels; nope. stores lens corrections as DNG opcodes instead (docs/PRIVACY.md). |
| Zero shutter lag, responsive capture, fast capture prioritization, deferred delivery (`isZeroShutterLagEnabled`, `isResponsiveCaptureEnabled`, `isFastCapturePrioritizationEnabled`, `isAutoDeferredPhotoDeliveryEnabled`) | Fixed (`CapturePolicy`) | Timing and processing pipeline choices, not file or exposure settings; deferred delivery is off so the file is never processed later. |

## Exposure settings

| Setting (API) | nope. | Why |
|---|---|---|
| ISO and shutter speed (`setExposureModeCustom(duration:iso:)`, `activeFormat.minISO…maxISO`, `minExposureDuration…maxExposureDuration`) | Offered | Manual controls, clamped to the active format's ranges per lens (`ControlScale`, `ManualControlSupport`). |
| Exposure modes P, S, I, M (iOS 27 priority modes) | Offered | Where the format reports them. |
| Exposure compensation (`exposureTargetBias`, `minExposureTargetBias…max`) | Offered | ±3 EV in thirds within the lens's range. |
| Metering (`exposureRectOfInterest`, center, spot, whole frame) | Offered | Spot and whole frame need iOS 26. |
| Focus and exposure point (`focusPointOfInterest`, `exposurePointOfInterest`) | Offered | Tap to focus and expose, with a lock (issues #35, #41, #51, #56). |
| AE lock, AF lock | Offered | |
| Focus position (`setFocusModeLocked(lensPosition:)`) | Offered | Where the lens supports manual focus. |
| Focus range restriction (`autoFocusRangeRestriction`) | Offered (near) | Close-up aids (issues #35, #41, #51, #56): the near limit, where the lens supports it. Far isn't offered. |
| Smooth autofocus, face-driven AE/AF (`isSmoothAutoFocusEnabled`, `isFaceDrivenAutoExposureEnabled`, `isFaceDrivenAutoFocusEnabled`) | Not offered | System defaults in full auto; face-driven exposure is a candidate behind Pro Tools. |
| White balance temperature and tint, presets, gains (`setWhiteBalanceModeLocked(with:)`, `deviceWhiteBalanceGains`) | Offered | Temperature and tint (2500–10,000 K) are converted to gains within `maxWhiteBalanceGain`; direct gains aren't shown, because temperature and tint describe the same values. |
| Aperture (`lensAperture`, iOS 27 variable aperture) | Offered | Where the lens has more than one stop. |
| Max exposure duration in auto (`activeMaxExposureDuration`) | Offered | Fast Shutter in Settings (issues #35, #41, #51, #56): a shutter limit for auto exposure. |
| Exposure bracket (`AVCaptureManualExposureBracketedStillImageSettings`) | Offered | Pro Tools; each frame a separate single-frame photo. |
| Low-light boost (`automaticallyEnablesLowLightBoostWhenAvailable`) | Not offered | Never turned on by nope.; it is documented for low-light frame rates, and its effect on photos isn't measured. |
| Global tone mapping, video HDR, Center Stage | Not offered | Video and preview processing, not the RAW. |
| Flash and torch (`flashMode`, `setTorchModeOn(level:)`) | Offered | Issue #38: the Flash menu (the modes the photo output reports for the lens) and the Light switch in the quick-controls tray. |
| Zoom (`videoZoomFactor`) | Fixed 1.0 | Bayer RAW requires a zoom factor of 1.0 ("Bayer RAW rules", `AVCapturePhotoOutput.h`); each lens is its own button. |

## Files must open

Every option in File Options is encoded and opened again by `NopeDevelopTests`
(`FileOptionsEncodingTests`): each HEIF and JPEG combination of compression, bit depth and color
space opens as one image of its format, passes the metadata read-back, and has the chosen depth
and color space. On a device, the same combinations must open in Photos and a RAW editor before
release (docs/TESTING.md, "File options, pairing, mirroring and location").
