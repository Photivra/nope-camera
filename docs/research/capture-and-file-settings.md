# Capture and file settings an app can control (issue #57)

The owner principle (issue #57, AGENTS.md "Code"): anything about the file or the exposure that the
device lets an app control should be controllable by the person, behind the manual or advanced
options, with full auto as the default; and every file Photivra Nope Camera can save must open. This
page lists every capture and file setting AVFoundation and ImageIO expose to an app on iOS 26 and 27,
what the app offers, and why anything isn't offered. Keep it current when an SDK adds a setting.

Sources are the iOS 27.2 SDK headers (Xcode 27.2): `AVFoundation/AVCapturePhotoOutput.h`
(`AVCapturePhotoOutput`, `AVCapturePhotoSettings`), `AVFoundation/AVCaptureDevice.h`,
`AVFoundation/AVCaptureSession.h` (`AVCaptureConnection`) and `ImageIO/CGImageDestination.h`.
"Offered" means a control in the app today; "fixed" means the app sets it to one value on purpose;
"not offered" gives the reason. Status as of 0.3.0 (the rows changed since 0.2.0 name the
release).

Each status is per lens and per format at run time (AGENTS.md, "Progressive enhancement"): a
control appears only where the lens's active format reports it (`ManualCapabilities`,
`DeviceControls`).

## File settings

| Setting (API) | The app | Why |
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
| HDR gain map / ISO HDR (`kCGImageDestinationEncodeRequest`, `…EncodeToISOHDR`, `…EncodeToISOGainmap`) | Not offered (no-go, 0.3.0) | See "HDR gain maps" below: the files fail the fail-closed read-back, so they can't be written through the allowlist. |
| Embedded thumbnail (`kCGImageDestinationEmbedThumbnail`, `embeddedThumbnailPhotoFormat`, `rawEmbeddedThumbnailPhotoFormat`) | Fixed off | Privacy: a thumbnail is a second copy that keeps pixels after an edit, and the allowlist has no thumbnail blocks. |
| Preview image (`previewPhotoFormat`) | Not offered | Only in memory; the app doesn't use it. |
| Downscaled size of the HEIF and JPEG copies (`kCGImageDestinationImageMaxPixelSize`) | Offered (0.3.0) | File Options › Copy Size: Full Size (default), Half Size or Quarter Size of the RAW's width and height (`OutputSize`). The encoder draws the copy at its size with Core Graphics (high-quality interpolation) rather than passing `kCGImageDestinationImageMaxPixelSize`, so the exact size is known and EXIF `PixelXDimension`/`PixelYDimension` are set to it. The RAW keeps every pixel. Every size is in the file compatibility matrix. |
| Photo dimensions (`maxPhotoDimensions` from `activeFormat.supportedMaxPhotoDimensions`) | Offered per lens without Bayer RAW (0.3.0); fixed with Bayer RAW | Settings › Photos › Photo Size, only for a lens without Bayer RAW that reports more than one size (`Lens.photoSizeChoices`); the smallest size, the camera's own default (`AVCapturePhotoSettings.maxPhotoDimensions`), stays the default. The 24 MP size (5712 × 4284) is left out: `AVCapturePhotoOutput.h` says it "is only serviced as 24MP via deferred photo delivery", which the app turns off. A lens with Bayer RAW has no choice: 48 MP sensors give 12 MP binned Bayer RAW and no public API offers full-resolution quad-Bayer data (capability survey, item 1), and the RAW was 12 MP on every lens of the device measured (docs/PRIVACY.md, "Results"); its HEIF and JPEG are developed from that RAW, so their size is Copy Size. The larger fallback size is in the file compatibility matrix; that `maxPhotoDimensions` leaves the Bayer RAW at 12 MP, and the sizes each fallback lens reports, are device checks (docs/TESTING.md). |
| Optimize color for sharing (`kCGImageDestinationOptimizeColorForSharing`) | Not offered | The sRGB option covers the case explicitly. |
| Metadata (`AVCapturePhotoSettings.metadata`, `kCGImageDestinationMetadata`) | Fixed | Built from the allowlist (docs/PRIVACY.md); location from `LocationTagging` (issue #43). |
| Orientation, mirroring (`AVCaptureConnection.videoMirrored`, Orientation tag) | Offered | Settings › Mirror Front Camera (issue #45): through the Orientation value only; the photo output's own mirroring is turned off. |
| Live Photo, depth, portrait matte, semantic mattes, camera calibration data (`livePhotoMovieFileURL`, `isDepthDataDeliveryEnabled`, `isPortraitEffectsMatteDeliveryEnabled`, `enabledSemanticSegmentationMatteTypes`, `isCameraCalibrationDataDeliveryEnabled`) | Not offered | Processed or extra data, not single-frame RAW; auxiliary images fail the read-back. |
| Shutter sound (`isShutterSoundSuppressionEnabled`) | Not offered | The shutter sound follows the system (AGENTS.md, "Hearing"). |
| Quality prioritization (`photoQualityPrioritization`, `maxPhotoQualityPrioritization`) | Fixed `.speed` | `CapturePolicy`: the least processing for the fallback; the header documents `.balanced` and `.quality` as allowing more processing time. Its effect on Bayer RAW data isn't measured. |
| Content-aware distortion correction, geometric distortion correction, constant color, auto red-eye reduction, virtual device fusion, still image stabilization | Fixed off | Each changes pixels; the app stores lens corrections as DNG opcodes instead (docs/PRIVACY.md). Geometric distortion correction can be turned off only where the camera reports the switch (`isGeometricDistortionCorrectionSupported`); each lens's processing note says which (issue #80, docs/PRIVACY.md, "Processing"). |
| Zero shutter lag, responsive capture, fast capture prioritization, deferred delivery (`isZeroShutterLagEnabled`, `isResponsiveCaptureEnabled`, `isFastCapturePrioritizationEnabled`, `isAutoDeferredPhotoDeliveryEnabled`) | Fixed (`CapturePolicy`) | Timing and processing pipeline choices, not file or exposure settings; deferred delivery is off so the file is never processed later. |

## Exposure settings

| Setting (API) | The app | Why |
|---|---|---|
| ISO and shutter speed (`setExposureModeCustom(duration:iso:)`, `activeFormat.minISO…maxISO`, `minExposureDuration…maxExposureDuration`) | Offered | Manual controls, clamped to the active format's ranges per lens (`ControlScale`, `ManualControlSupport`). |
| Exposure modes P, S, I, M (iOS 27 priority modes) | Offered | Where the format reports them. |
| Exposure compensation (`exposureTargetBias`, `minExposureTargetBias…max`) | Offered | ±3 EV in thirds within the lens's range. |
| Metering (`exposureRectOfInterest`, center, spot, whole frame) | Offered | Spot and whole frame need iOS 26. |
| Focus and exposure point (`focusPointOfInterest`, `exposurePointOfInterest`) | Offered | Tap to focus and expose, with a lock (issues #35, #41, #51, #56). |
| AE lock, AF lock | Offered | |
| Focus position (`setFocusModeLocked(lensPosition:)`) | Offered | Where the lens supports manual focus. |
| Focus range restriction (`autoFocusRangeRestriction`) | Offered (near; far since 0.3.0) | Close-Up (issues #35, #41, #51, #56) is the near limit, in full auto too. Far Focus (`.far`, "subject matter that is far from the camera", `AVCaptureDevice.h`) is in the quick-controls tray with manual controls on, with a pill; the two replace each other, since the device has one restriction; All Auto clears both. Both need autofocus and `isAutoFocusRangeRestrictionSupported`. |
| Face-driven AE/AF (`automaticallyAdjustsFaceDrivenAutoFocusEnabled`, `isFaceDrivenAutoFocusEnabled`, and the exposure equivalents) | Offered (0.3.0) | Settings › Camera › Face Detection, off by default (issue #80): on leaves the system's automatic choice (`automaticallyAdjusts…` = YES, the default); off sets `automaticallyAdjusts…` to NO and the face-driven value to NO. Each is set only where the camera supports continuous autofocus or auto exposure, because AVFoundation raises an exception otherwise, and before the focus and exposure modes, which apply it (`AVCaptureDevice.h`). Applies only while focus or exposure is automatic. |
| Smooth autofocus (`isSmoothAutoFocusEnabled`) | Not offered | `AVCaptureDevice.h` documents it as "appropriate for movie recording": slower focusing, with no effect on a still photo's file or exposure. |
| White balance temperature and tint, presets, gains (`setWhiteBalanceModeLocked(with:)`, `deviceWhiteBalanceGains`) | Offered | Temperature and tint (2500–10,000 K) are converted to gains within `maxWhiteBalanceGain`; direct gains aren't shown, because temperature and tint describe the same values. |
| Aperture (`lensAperture`, iOS 27 variable aperture) | Offered | Where the lens has more than one stop. |
| Max exposure duration in auto (`activeMaxExposureDuration`) | Offered | Fast Shutter in Settings (issues #35, #41, #51, #56): a shutter limit for auto exposure. |
| Exposure bracket (`AVCaptureManualExposureBracketedStillImageSettings`) | Offered | Bracket on the drive strip, in full auto and with Manual Controls on (docs/design/BRACKETING.md); 3, 5 or 7 frames up to `maxBracketedCapturePhotoCount`, 1/3 to 2 EV apart, darkest, metered or brightest first (the frames are requested in the order of the array); each frame a separate single-frame photo. |
| Focus bracket (`setFocusModeLocked(lensPosition:completionHandler:)`) | Offered | Bracket › Type › Focus, where `isLockingFocusWithCustomLensPositionSupported` is true (issue #90, docs/design/BRACKETING.md, section 5): 3 to 50 separate single-frame photos at evenly spaced lens positions from the nearest to the farthest set, nearest or farthest first; each photo is taken after the handler reports the position applied. Positions are the lens's own 0 to 1 scale, not distances (Apple: "a given lens position value does not correspond to an exact physical distance"); `minimumFocusDistance` is not shown until device check D5 confirms it for a lens. |
| Longest exposure (`activeFormat.maxExposureDuration`) | Offered | Through the manual shutter; the Astro helper (issue #60) starts from it. The value per lens is still to be recorded on the test devices (`docs/TESTING.md`, "Astro helper on a device"). |
| Low-light boost (`automaticallyEnablesLowLightBoostWhenAvailable`) | Not offered | Never turned on by the app; it is documented for low-light frame rates, and its effect on photos isn't measured. |
| Global tone mapping, video HDR, Center Stage | Not offered | Video and preview processing, not the RAW. |
| Flash and torch (`flashMode`, `setTorchModeOn(level:)`) | Offered | Issue #38: the Flash menu (the modes the photo output reports for the lens) and the Light switch in the quick-controls tray. |
| Zoom (`videoZoomFactor`) | Fixed 1.0 | Bayer RAW requires a zoom factor of 1.0 ("Bayer RAW rules", `AVCapturePhotoOutput.h`); each lens is its own button. |

## HDR gain maps: no-go (issue #57, 0.3.0)

An HDR gain map (ISO 21496-1) or an ISO HDR file (`kCGImageDestinationEncodeRequest` with
`kCGImageDestinationEncodeToISOGainmap` or `…EncodeToISOHDR`, iOS 18 and later,
`ImageIO/CGImageDestination.h`) isn't offered, because such a file can't be written through the
metadata allowlist and pass the fail-closed read-back. Measured on 2026-11-16 on the iOS 27.2
Simulator with the app's own encoder (`PhotoEncoder.encode`), a 64 × 48 half-float image with
values above 1.0, and the first-launch metadata plan, for HEIF and JPEG, in extended linear
Display P3, BT.2100 PQ and BT.2100 HLG:

- **Gain map request:** `CGImageDestinationFinalize` failed for every color space and both
  formats when `kCGImageDestinationEncodeToISOGainmap` was passed with `CGImageDestinationAddImage`:
  no file was written. ImageIO doesn't make a gain map from one HDR image this way.
- **ISO HDR request (and an HDR image without a request):** a PQ or HLG HEIF carries
  `Headroom`, `AverageLightLevelNits` and the ICC `CLL` (content light level) key, and a PQ or HLG
  JPEG carries `Headroom`. Since 1.0.0 `Headroom` is allowed in a HEIF, by name and whatever its
  value (`MetadataPlan.heifDerivedImageIOKeys`), because the iOS 26.5 Simulator's reader reports
  it on every HEIF, SDR ones included. So in a PQ or HLG HEIF the read-back reports
  `AverageLightLevelNits` and the ICC `CLL` key as unexpected ImageIO keys
  (`MetadataViolation.unexpectedImageIOKey`), and in a PQ or HLG JPEG it reports `Headroom`;
  either way the photo wouldn't be saved. Not measured: which keys an HDR HEIF reports on
  iOS 26.5, where `Headroom` alone no longer stops it. An extended linear Display P3 image is
  written as an ordinary SDR file with no gain map.
- **The RAW developer is SDR:** `CoreImageRAWRenderer` renders the DNG to 16-bit Display P3 with
  the RAW filter's default (SDR) range, so there is no HDR rendition to map. Making one needs the
  RAW filter's extended dynamic range output, which is more processing than the app's neutral
  development.
- **What it would take:** a gain map is a second (auxiliary) image in the file, `tmap` and `auxl`
  items in a HEIF and an MPF secondary image with `hdrgm` XMP in a JPEG. Each would need its own
  allowlist entries, read-back rules and a check that the Content Credentials hash covers it, all
  reviewed changes to the allowlist (AGENTS.md, "Metadata is allowlisted"), and a device check that
  Photos and other apps show it. Not tried: Core Image's `CIContext` gain map writer
  (`CIImageRepresentationOption.hdrGainMapImage`).

Owner principle: a setting that makes a file that doesn't open, or can't be checked, isn't
shipped. Revisit if the allowlist is extended for gain maps by a reviewed change.

## Files must open

Every option in File Options is encoded and opened again by `NopeDevelopTests`
(`FileOptionsEncodingTests`): each HEIF and JPEG combination of compression, bit depth and color
space opens as one image of its format, passes the metadata read-back, and has the chosen depth
and color space; each copy size opens at its size with matching EXIF pixel dimensions. The file
compatibility matrix (`FileCompatibilityTests`, issue #58) saves every option through the full
pipeline, signed and unsigned, including each copy size and a processed fallback at a larger photo
size; `theMatrixCoversEveryOption` fails when an option has no fixture. Face Detection and Far
Focus change only how the camera focuses and exposes, not what is written, so they add no file
fixture. On a device, the same combinations must open in Photos and a RAW editor before
release (docs/TESTING.md, "File options, pairing, mirroring and location").
