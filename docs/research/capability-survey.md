# Research: device capability survey

Status: research, 2026-11-11, iOS/iPadOS 18 minimum, current release 27. No code. **C** = confirmed in Apple documentation or by Apple engineers. **I** = inferred: verify on a device. The app reads every capability at run time; this table is for planning only.

## Device × feature table

| Device group | Rear lenses expected to give Bayer RAW | RAW size | Front RAW | Variable aperture | Camera Control | Action button | LiDAR |
|---|---|---|---|---|---|---|---|
| iPhone XS / XS Max / XR | Wide; 2× tele (XS) | 12 MP | No (C) | No | No | No | No |
| iPhone 11 series, SE 2/3 | Wide, tele; ultra wide likely not (I) | 12 MP | No | No | No | No | No |
| iPhone 12 / 13 | Wide, ultra wide (I), tele (Pro) | 12 MP | No | No | No | No | Pro |
| iPhone 14 / 14 Plus | Wide, ultra wide | 12 MP | No | No | No | No | No |
| iPhone 14 Pro – 15 Pro Max | 48 MP wide (12 MP binned RAW), ultra wide, tele | 12 MP | No | No | No | 15 Pro | Pro |
| iPhone 16 / 16 Plus / 16e | Wide (binned), ultra wide (not 16e) | 12 MP | No | No | Yes (not 16e) | Yes | No |
| iPhone 16 Pro / Pro Max | Wide, ultra wide, 5× tele | 12 MP | No | No | Yes | Yes | Yes |
| iPhone 17 / Air / 17 Pro / Pro Max | Wide, ultra wide (not Air), tele (Pro) | 12 MP | Possibly, front ultra wide (I) | No | Yes | Yes | Pro |
| iPhone 18 Pro / Pro Max | As 17 Pro | 12 MP (I) | As 17 (I) | Yes (iOS 27) | Yes | Yes | Yes |
| iPad Pro (M4/M5, 2020–2022) | Wide; ultra wide on older Pro (I) | 12 MP (I) | No (I) | No | No | No | Yes |
| iPad Air, iPad, iPad mini | Wide (I) | 12 MP (I) | No (I) | No | No | No | No |

## Findings by feature

1. **Bayer RAW.**
   - **API:** pick the format where `AVCapturePhotoOutput.isBayerRAWPixelFormat(_:)` is true, and keep `isAppleProRAWEnabled = false`. `fileDataRepresentation()` gives a DNG (C).
   - **Devices:** only single physical cameras, not virtual multi-camera devices, at zoom 1.0 (I).
   - **Resolution:** 48 MP sensors give **12 MP binned** RAW. No public API offers full-resolution quad-Bayer data (C); 48 MP is available only as ProRAW, which processes the image.
   - **Bit depth:** read the black and white levels from each DNG rather than assuming a value (I).
2. **Exposure.**
   - **API:** `setExposureModeCustom(duration:iso:)`, with ranges from `activeFormat` (C). Also `exposureTargetBias`, `exposurePointOfInterest` and `exposureRectOfInterest`, and the `.locked` mode (C). Recent rear cameras reach about 1 s (I).
   - **Critical:** manual values survive capture only with `photoQualityPrioritization = .speed`. Other settings can let the system override ISO and shutter (C).
3. **Focus.**
   - **API:** `setFocusModeLocked(lensPosition:)`, focus point and rect, and `autoFocusRangeRestriction` (C).
   - **No distance:** `lensPosition` is a unitless 0–1 value that differs between devices, so there is **no calibrated distance** (C). The interface uses a relative Closest–Far scale.
4. **White balance.**
   - **API:** device gains, temperature and tint conversion, gray-world gains, and lock (C).
   - **RAW:** for Bayer RAW it changes only the DNG's as-shot neutral, not the pixels (I).
5. **Variable aperture (iPhone 18 Pro, iOS 27).**
   - **API:** `setExposureModeCustom(lensAperture:duration:iso:)`, with `autoLensAperture` and `currentLensAperture` (C). Range and stops come from `minLensAperture`, `maxLensAperture` and `recommendedLensApertureStops`, and `supportsExposureModeCustom(lensAperture:duration:iso:)` checks a combination (C).
   - **Values:** the API accepts continuous values; whether the lens holds in-between values is untested (I).
6. **Bracketing.**
   - **API:** `AVCapturePhotoBracketSettings` with manual exposure brackets supports RAW, and each frame is delivered separately (C).
   - **Count:** read it from `maxBracketedCapturePhotoCount`; typically 3 (I).
   - **Not allowed in brackets:** flash, auto stabilization and Live Photos (C).
7. **Stabilization.** There is no public switch to turn off optical or sensor-shift stabilization for single stills (I). It moves the lens or sensor and doesn't process pixels, but the Honesty screen should mention it.
8. **Flash.** Supported with RAW (I). One report says flash `.on` overrides locked focus (I). There is no public front screen-flash API, so the app lights the screen itself (I).
9. **Launch surfaces.**
   - **Lock screen, Control Center, Action button:** LockedCameraCapture (iOS 18). The capture extension plus a WidgetKit control using `CameraCaptureIntent` covers all three (C).
     - **Extension limits:** no network and no App Group container. The extension must show a live camera through `AVCaptureEventInteraction`.
     - **Saving:** to `sessionContentURL` or PhotoKit (C).
   - **Camera Control:** `AVCaptureSlider`, `AVCaptureIndexPicker` and the system exposure-bias slider (C).
   - **Hardware shutter:** volume buttons and Camera Control through `AVCaptureEventInteraction` or SwiftUI `onCameraCaptureEvent` (C).
10. **iPad.**
    - **Multitasking:** the camera works in multitasking only with Stage Manager on an external display, the multitasking camera access entitlement (requested from Apple), or a VoIP background mode, which nope. won't claim (C).
    - **Center Stage:** front camera only; turn it off for stills (I).
    - **LiDAR:** a virtual device, so no Bayer RAW (I).
11. **Output.** 10-bit HEIF through `CIContext.heif10Representation` (I). No gain maps.
12. **Avoiding processing.**
    - **Capture setup:**
      - a RAW-only capture, `AVCapturePhotoSettings(rawPixelFormatType:)`, with no processed format;
      - `photoQualityPrioritization` and `maxPhotoQualityPrioritization` set to `.speed`;
      - deferred delivery, ProRAW, constant color and content-aware distortion correction off;
      - a physical device at zoom 1.0.
    - **Smart HDR and Deep Fusion:** no public switches, but Apple states that standard RAW bypasses advanced processing (C). Check `AVCaptureResolvedPhotoSettings` on every capture.
13. **Depth.** Bayer RAW with depth works only on the iPhone 17 front ultra wide (C). Depth carries face shape, so leave it out.

## Plan for v1.0

**In v1.0:**
- Bayer RAW on every rear physical lens that reports it;
- manual ISO, shutter, exposure compensation, AE lock and exposure point;
- manual focus (relative scale) and white balance;
- the hardware shutter;
- the variable aperture on iPhone 18 Pro (iOS 27);
- Camera Control sliders;
- lock screen, Control Center and Action button capture.

**After v1.0:**
- manual exposure bracketing;
- flash (after the focus-override question);
- front RAW on iPhone 17 and later;
- the iPad multitasking entitlement.

Depth: not planned.

## Real-device questions

1. Which lens and device combinations list a Bayer format? In particular the iPhone 11/12 ultra wide, iPads, and the iPhone 17/18 front cameras.
2. DNG size, black and white levels, color pattern, and whether lens shading is applied to the pixels or stored as DNG opcodes.
3. Aperture: the values of `recommendedLensApertureStops`, and whether the lens holds in-between values.
4. The real shutter and ISO range per lens in the photo preset. Does a long shutter survive a `.speed` capture?
5. Is binned RAW ever replaced by a remosaiced or fused frame?
6. Does flash `.on` keep a locked focus?
7. Is front-camera custom exposure ignored on iOS 27?
8. `maxBracketedCapturePhotoCount` with RAW.
9. Does a RAW capture in the lock-screen extension save correctly?

## Sources

- **Apple documentation:**
  - [Capturing photos in RAW and Apple ProRAW formats](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats)
  - [AVCapturePhotoOutput](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput)
  - [AVCapturePhotoBracketSettings](https://developer.apple.com/documentation/avfoundation/avcapturephotobracketsettings)
  - [Capture device exposure](https://developer.apple.com/documentation/avfoundation/capture-device-exposure)
  - [setExposureModeCustom(lensAperture:…)](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(lensaperture:duration:iso:completionhandler:))
  - [AVCaptureDevice.Format](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format)
  - [Capture device focus](https://developer.apple.com/documentation/avfoundation/capture-device-focus)
  - [lensPosition](https://developer.apple.com/documentation/avfoundation/avcapturedevice/lensposition)
  - [isMultitaskingCameraAccessSupported](https://developer.apple.com/documentation/avfoundation/avcapturesession/ismultitaskingcameraaccesssupported)
  - [LockedCameraCapture](https://developer.apple.com/documentation/lockedcameracapture)
  - [AVCaptureControl](https://developer.apple.com/documentation/avfoundation/avcapturecontrol)
  - [AVCaptureEventInteraction](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction)
- **WWDC sessions:** [WWDC26 304](https://developer.apple.com/videos/play/wwdc2026/304), [WWDC25 253](https://developer.apple.com/videos/play/wwdc2025/253), [WWDC21 10160](https://developer.apple.com/videos/play/wwdc2021/10160/)
- **Apple Developer Forums:**
  - [845302](https://developer.apple.com/forums/thread/845302) and [845196](https://developer.apple.com/forums/thread/845196): aperture
  - [853978](https://developer.apple.com/forums/thread/853978): quad-Bayer
  - [826469](https://developer.apple.com/forums/thread/826469): RAW and depth
  - [841311](https://developer.apple.com/forums/thread/841311): flash and focus
  - [848520](https://developer.apple.com/forums/thread/848520): exposure cap
  - [844226](https://developer.apple.com/forums/thread/844226): front exposure
  - [113033](https://developer.apple.com/forums/thread/113033): front RAW
