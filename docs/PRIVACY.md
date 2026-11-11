# Privacy

How nope. handles every metadata item it writes or removes. Status: scaffold (0.1.0). nope.
doesn't capture or save photos yet, so nothing is written. The list below is the plan from
issue #1, "Privacy"; every item is **to be confirmed by the device tag check** (issue #1, step 2):
a dump of every tag in a real saved DNG and HEIF. Wording for any user-facing claim comes from
[`docs/research/privacy-claims.md`](research/privacy-claims.md).

## What the app does today

- **Network:** none. The app contains no networking code; `scripts/check-security.sh` fails a
  pull request that adds any.
- **Data collected:** none. `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no
  collected data types and no required-reason APIs.
- **Permissions:** the usage strings for the camera (`NSCameraUsageDescription`) and add-only
  Photos access (`NSPhotoLibraryAddUsageDescription`) are present and localized. The development
  build uses a simulated backend and doesn't show a system prompt. No location permission is
  requested.
- **Entitlements:** none.
- **Files and logs:** Release builds write no files and log nothing. Debug builds include the
  tag check (below), which writes test captures to the app's container only when launched with
  `-NopeTagCheck`; it isn't compiled into Release builds.

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

**Results:** to be filled in after the first device run (device model, iOS version, tags found
per format, and what the removal path removed).

## Metadata plan (to be confirmed by the device tag check)

With "Remove private details" on (the default):

| Item | Default | Status |
|---|---|---|
| Location, altitude and direction | Removed | To be confirmed |
| Time zone offset | Removed | To be confirmed |
| Phone and lens serial numbers | Removed | To be confirmed |
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
