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

## Metadata plan

**Rule:** every item that can be removed without breaking the photo is a switch the user
controls. Items a file can't be opened or displayed correctly without are locked, and the app
explains each one in plain words.

**Master switch: "Remove all optional details", on by default.**
- **When on,** every switch below is off, so files carry only the locked items, plus the
  Content Credentials signature, which has its own switch outside the master.
- **Turning on any single item** turns the master off, and the screen shows "Custom".
- **Turning the master back on** turns every item off again.
- **With the master off,** the user sets each item one by one.

The "Default" column below is each item's setting when the user first turns the master off.

### Switches (removing these never breaks the photo)

| Item | Default | What turning it off costs (shown in the app) | Device tag check |
|---|---|---|---|
| Location, altitude and direction | Off | Nothing. Location is only added if you turn it on | Not written by the system |
| Date and time taken | On | Photos sorts by the date you saved it instead | Present (`DateTime*`, XMP dates) |
| Sub-second time | Off | Nothing visible | Present (`SubSecTime*`) |
| Time zone | Off | The photo's local time can't be converted to other zones | Present (`OffsetTime*`) |
| Camera make and model | On | Apps can't show which phone took it | Present (`Make`, `Model`, HEIF `HostComputer`) |
| Lens make and model | On | Apps can't show which lens took it | Present (`LensMake`, `LensModel`) |
| Exact camera model for RAW editors (`UniqueCameraModel`) | On | Some RAW editors can't choose their camera-specific color profile and use the file's own color data instead. The DNG standard requires this tag, so when it's off, nope. writes a generic value rather than none | Present |
| Lens correction instructions (DNG opcodes) | On | Editors can't automatically correct this lens's distortion and vignetting. The pixels are never corrected either way | Present (`OpcodeList3`) |
| Exposure settings (shutter, ISO, aperture, focal length) | On | You can't see later how the photo was taken | To confirm on an exposed image |
| iOS version | Off | Nothing visible | Present (`Software`, XMP `CreatorTool`) |
| Maker notes (Apple) | Off | Nothing visible; they hold time since restart and per-photo IDs | Present (`0x927C`) |
| Your name and copyright | Off | Nothing; only written if you enter them | Not written by the system |
| App name and version (nope.) | On | Apps can't show what made the file | Written by nope. |
| Content Credentials signature (outside the master switch) | On | The photo can't be checked for changes; without a timestamp when the date is off | Written by nope. |

Serial numbers, unique image IDs and raw data IDs are never written, by the system or by nope.,
so they have no switch.

### Locked (the photo breaks without these)

| Item | Why it can't be removed (shown in the app) |
|---|---|
| Image size, bit depth, compression and data layout | Without them the file can't be read at all |
| Color filter pattern | Tells editors which pixels are red, green and blue; without it the RAW has no color |
| Black and white levels | Without them shadows and highlights come out wrong |
| Color matrices and as-shot white balance | Without them colors are wrong |
| DNG version | Required by the DNG standard; editors refuse the file without it |
| Orientation | Without it the photo shows sideways or upside down |
| Color profile (HEIF and JPEG) | Without it colors look washed out or oversaturated |

None of the locked items identify you or link your photos.

This page will list the exact tags for each format and switch, with the metadata tests that
assert them, as each part is built.
