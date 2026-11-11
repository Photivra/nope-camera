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
- **Files and logs:** the app writes no files and logs nothing.

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
