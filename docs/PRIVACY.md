# Privacy

How nope. handles every metadata item it writes or removes. Status: capture core, in
development. nope. captures photos into memory but doesn't save them yet, so no photo is
written. The list below is the plan from
issue #1, "Privacy"; every item is **to be confirmed by the device tag check** (issue #1, step 2):
a dump of every tag in a real saved DNG and HEIF. Wording for any user-facing claim comes from
[`docs/research/privacy-claims.md`](research/privacy-claims.md).

## What the app does today

- **Network:** none. The app contains no networking code; `scripts/check-security.sh` fails a
  pull request that adds any.
- **Data collected:** none. `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no
  collected data types and no required-reason APIs.
- **Permissions:** the usage strings for the camera (`NSCameraUsageDescription`) and add-only
  Photos access (`NSPhotoLibraryAddUsageDescription`) are present and localized. The app asks
  for camera access when the person presses "Allow Camera Access". No location permission is
  requested, and no location is supplied to the camera.
- **Photos:** a capture is held in memory only, until the next capture replaces it or the app
  quits. It isn't written to a file or added to Photos; the screen says "Captured (not saved
  yet: development build)". Saving comes with the metadata allowlist and read-back
  verification.
- **Entitlements:** none.
- **Files and logs:** Release builds write no files and log nothing. Debug builds include the
  tag check (below), which writes test captures to the app's container only when launched with
  `-NopeTagCheck`; it isn't compiled into Release builds. It also saves one live video frame
  per lens as a JPEG, to check exposure (see [`TESTING.md`](TESTING.md), "Black frames").

## Tag check

The metadata plan below is confirmed by dumping every tag from real files captured on a device.

- **Capture:** a debug-only mode (`-NopeTagCheck`, Debug builds only) captures, with each
  physical camera, a Bayer RAW DNG, the same RAW written through the system removal path
  (`AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata`, removing
  `{MakerApple}`, `{GPS}` and every serial number and unique ID key), and a processed HEIF.
  The setup is the planned one: `.speed` prioritization, no ProRAW, zoom 1.0, no deferred
  delivery, constant color or distortion correction, and no location supplied.
- **Dump:** `scripts/dump-tags.swift` lists every ImageIO property, every XMP tag and, for DNG,
  every TIFF tag ID in every IFD, including the EXIF and GPS IFDs and SubIFDs.
- **Comparison:** the plain and stripped DNGs show which tags the system removal path actually
  removes, and the HEIF shows what a processed photo carries.

How to run it is in [`TESTING.md`](TESTING.md), "Tag check". Captured files and reports are
never committed: they contain serial numbers.

**Results (first device runs, 2026-11-11, an iPhone 16 Pro Max on iOS 27.2.1):** the metadata
results below are consistent across two runs. The image data in those runs was dark: the debug
capture setup produced empty frames (a constant fill, not a sensor readout). The diagnosis and
the fix are in [`TESTING.md`](TESTING.md), "Black frames"; the exposure tags (exposure time,
ISO) still need confirming on a real image from the next run.

- **Bayer RAW on every physical camera,** including the front camera. The wide and front
  cameras give `bgg4`, and the ultra wide and telephoto give `rgg4`. RAW is 12 MP
  (4032 × 3024 within a 4224-wide active area) and 12-bit (black level 528, white level
  4095), as lossless JPEG (TIFF compression 7) in DNG 1.3, with lens corrections stored in
  `OpcodeList3`, not applied to the pixels.
- **Already absent from every file:** GPS, body, lens and camera serial numbers,
  `ImageUniqueID` and `RawDataUniqueID`. The system adds none of them unless the app
  supplies them.
- **Present in the system's RAW DNG, and able to identify or link photos:**
  - **Apple maker note (`0x927C`, `{MakerApple}`):**
    - key 3 is the time since the device last restarted, which links photos taken in one
      session;
    - keys 32 and 43 are per-photo UUIDs.
  - **Software version:** `Software` (`0x0131`) and XMP `CreatorTool` (for example,
    "27.2.1").
  - **Time zone:** `OffsetTime`, `OffsetTimeOriginal` and `OffsetTimeDigitized`.
  - **Sub-second timestamps:** `SubSecTimeOriginal` and `SubSecTimeDigitized`.
  - **Exact model:** `Make`, `Model`, `UniqueCameraModel` (with the model identifier),
    `LensMake` and `LensModel`.
  - **XMP dates:** `CreateDate`, `ModifyDate` and `photoshop:DateCreated`.
- **The system's HEIF adds:** `HostComputer` (the model), and a `LensModel` that includes
  the focal length and aperture.
- **The system removal path removed the maker note** when asked, but kept everything else.
  This confirms the rule in `AGENTS.md`: build each file's metadata from the allowlist, never
  by deleting known tags.

## Metadata plan (to be confirmed by the device tag check)

With "Remove private details" on (the default):

| Item | Default | Status |
|---|---|---|
| Location, altitude and direction | Removed | Not written by the system; confirmed absent |
| Time zone offset | Removed | Present in system output (`OffsetTime*`); dropped by the allowlist |
| Phone and lens serial numbers | Removed | Not written by the system; confirmed absent |
| Unique image ID | Removed | To be confirmed |
| Maker notes | Removed | To be confirmed |
| iOS version | Removed | To be confirmed |
| Owner name and copyright | Removed | To be confirmed |
| Date and time | Kept (own switch) | To be confirmed |
| Camera make and model, lens model | Kept | To be confirmed |
| Exposure settings | Kept | To be confirmed |
| App name and version | Kept | To be confirmed |
| C2PA signature | Kept; without a timestamp when the date is off | To be confirmed |
| Data needed to open the RAW (color calibration, black and white levels, color pattern, as-shot white balance, DNG camera name, orientation, lens correction opcodes) | Locked | To be confirmed |

This page will list the exact tags for each format and switch, with the metadata tests that
assert them, as each part is built.
