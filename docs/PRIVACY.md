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
  `-NopeTagCheck`; it isn't compiled into Release builds. The `-NopeCameraProbe` diagnostic
  also saves one live video frame as a JPEG, to check exposure (see [`TESTING.md`](TESTING.md),
  "Black frames").

## Content Credentials (signing)

nope. can sign each saved file (DNG, HEIF, JPEG) with C2PA Content Credentials. Status: the
signer (`NopeSigning`) is built and tested; the save pipeline that calls it comes next, so no
saved photo is signed yet. Signing has its own switch (`SigningSettings`), on by default, outside
the "Remove all optional details" master switch.

**What it proves.** The signature proves the file hasn't changed since nope. signed it. It
doesn't prove who took the photo or on which device. Each file is signed with a new key and a
certificate the key issues to itself, not one chained to a trusted certificate authority, so
validators report the signer as untrusted (`signingCredential.untrusted`, C2PA 2.2, §15.7) and
the file as valid. That is expected.

**How each file is signed.**

1. A new P-256 key is created for that file. On a device it is created in the Secure Enclave
   (CryptoKit `SecureEnclave.P256.Signing.PrivateKey`), with no keychain entry, and is released
   after the file is signed; it is never stored or used again. The Simulator has no Secure
   Enclave, so Simulator builds use a software key; that code is compiled only for the Simulator
   (`#if targetEnvironment(simulator)`) and isn't in any device build. A device whose Secure
   Enclave can't create a key gets no signature and a "not signed" message, never a software key.
2. The key signs a certificate for itself (below).
3. The C2PA library embeds a manifest and the key signs it (ES256). There is no timestamp
   authority, no certificate status check (OCSP), no remote manifest and no trust list. The
   library nope. links is built from source with every network feature off, and contains no
   networking code at all; CI checks the library and a linked iOS binary for networking symbols
   on every pull request (`c2pa-lib/README.md`). Its settings also turn every fetch off and allow
   no network host. No App Attest.

**What the signature contains.** Nothing in it identifies the person or the device, and nothing
links two files: every field is either the same for everyone running that version of nope., or
random and made for that file alone.

| Item | Value | Same for everyone, or per file |
|---|---|---|
| Claim generator | "Photivra Nope Camera" and the app version (for example `0.1.0`); the C2PA library adds its own name and version (`org.contentauth.c2pa_rs`) | Same for everyone on that version |
| Action | One `c2pa.created` action, digital source type `digitalCapture` (IPTC), and a fixed description (below) | Same for every file of that kind |
| Instance ID | `xmp:iid:` and a random UUID | Random, per file |
| Hash binding | A SHA-256 hash of the file's bytes, excluding the manifest itself (`c2pa.hash.data` for DNG and JPEG, `c2pa.hash.bmff.v3` for HEIF) | Depends only on the file |
| Signature | ES256 by the file's own key | Per file |
| Certificate subject and issuer | Common name "Photivra Nope Camera anonymous signer" only: no organization, email, location or device | Same for everyone |
| Certificate validity | 2000-01-01 to 2099-12-31 | Same for everyone, so it doesn't reveal the capture time |
| Certificate serial number | 20 random bytes | Random, per file |
| Certificate public key and key identifiers | The file's one-use public key and its SHA-1 hash | Per file |

Not written: no time (`when`) on the action, no timestamp, no title, no thumbnail, no ingredient,
no creator, no location, no device model, no operating system, no device ID, no stable key.

Descriptions (written into the file in English; owner-approved wording pending):

- DNG: "Captured by Photivra Nope Camera as a single frame of RAW sensor data, with as little processing as the
  phone allows."
- HEIF or JPEG developed from the RAW: "Developed by Photivra Nope Camera on the phone from a single frame of
  RAW sensor data."
- HEIF or JPEG from a lens without Bayer RAW: "Captured by Photivra Nope Camera and processed by the phone's
  camera, because this lens can't save RAW."

**What signing adds to each file.** Exactly one item, checked by the tests on synthetic files
and with c2patool 0.28.6; the metadata read-back allowlist must permit it for signed files
(`ContentCredentialsStore` in `NopeCore`):

| Format | Added | Notes |
|---|---|---|
| DNG | TIFF tag 52545 (`0xCD41`), type `UNDEFINED`, in IFD0 | The C2PA library writes a new IFD0 (the old tags plus this one) at the end of the file and points the header at it. The original IFD0 bytes stay in the file, unreferenced; they hold the same allowlisted tags. The hash excludes the manifest and the 4-byte offset of tag 52545 |
| HEIF | One top-level `uuid` box, UUID `D8FEC3D6-1B0E-483C-9297-5828877EC481`, after `ftyp` | No other box changes type or order. The hash excludes `/uuid`, `/ftyp`, `/mfra`, `/free` and `/skip`, the C2PA default exclusions for this format |
| JPEG | APP11 (`0xFFEB`) segments with JUMBF (common identifier `JP`), after APP0 | No other segment changes. The hash excludes only the APP11 segments |

ImageIO reports no new property for the signed HEIF and JPEG (only the file size changes).

**Signing must be the last change.** Any later change to the bytes (an edit in Photos, export,
re-encoding by a sharing app) breaks the signature or removes it.

## Tag check

The metadata plan below is confirmed by dumping every tag from real files captured on a device.

- **Capture:** a debug-only mode (`-NopeTagCheck`, Debug builds only) captures, with each
  physical camera, a Bayer RAW DNG and a processed HEIF through the app's own capture backend,
  so the files carry exactly what the app's captures carry: `.speed` prioritization, no ProRAW,
  zoom 1.0, no deferred delivery, constant color or distortion correction, and no location
  supplied. The first runs also wrote the same RAW through the system removal path
  (`AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata`, removing
  `{MakerApple}`, `{GPS}` and every serial number and unique ID key); that needed a separate
  capture session and was removed with it (`TESTING.md`, "Black frames"). The removal path
  will be checked again when it is built into the backend.
- **Dump:** `scripts/dump-tags.swift` lists every ImageIO property, every XMP tag and, for DNG,
  every TIFF tag ID in every IFD, including the EXIF and GPS IFDs and SubIFDs.
- **Comparison:** in the first runs, the plain and stripped DNGs showed which tags the system
  removal path removes; the HEIF shows what a processed photo carries.

How to run it is in [`TESTING.md`](TESTING.md), "Tag check". Captured files and reports are
never committed: they contain serial numbers.

**Results (device runs on 2026-11-11 and 2026-11-12, an iPhone 16 Pro Max on iOS 27.2.1):** the
metadata results below are consistent across three runs. In the first two runs every image was
blank: a Mac was viewing and controlling the phone's screen, which blanks the camera picture for
apps other than Apple's own (see [`TESTING.md`](TESTING.md), "Black frames"). The third run,
with that session stopped, produced real images on every lens (RAW and HEIF), and confirmed the
exposure tags.

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
| Exposure settings (shutter, ISO, aperture, focal length) | On | You can't see later how the photo was taken | Present (`ExposureTime`, `ISOSpeedRatings`, `FNumber`, `FocalLength` and related EXIF tags, in RAW and HEIF) |
| iOS version | Off | Nothing visible | Present (`Software`, XMP `CreatorTool`) |
| Maker notes (Apple) | Off | Nothing visible; they hold time since restart and per-photo IDs | Present (`0x927C`) |
| Your name and copyright | Off | Nothing; only written if you enter them | Not written by the system |
| App name and version (nope.) | On | Apps can't show what made the file | Written by nope. |
| Content Credentials signature (outside the master switch) | On | The photo can't be checked for changes. The signature never has a timestamp (see "Content Credentials") | Written by nope. |

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
