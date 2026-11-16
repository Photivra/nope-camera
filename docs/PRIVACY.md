# Privacy

How Photivra Nope Camera handles every metadata item it writes or removes. Status: in development.
The app saves photos to Photos with metadata built from the allowlist below and checked by reading
each file back; photos are not signed yet. The list follows issue #1, "Privacy"; the saved files are
**still to be confirmed by the device tag check** (issue #1, step 2; "Device checks" below). Wording
for any user-facing claim comes from
[`docs/research/privacy-claims.md`](research/privacy-claims.md).

## What the app does today

- **Network:** none. The app contains no networking code; `scripts/check-security.sh` fails a
  pull request that adds any.
- **Data collected:** none. `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains and
  no collected data types. Its only required-reason API is `UserDefaults` (`CA92.1` and
  `1C8F.1`), for the settings below.
- **Permissions:** the usage strings for the camera (`NSCameraUsageDescription`) and add-only
  Photos access (`NSPhotoLibraryAddUsageDescription`) are present and localized. The app asks
  for camera access when the person presses "Allow Camera Access", and for add-only Photos access
  the first time it saves a photo (`PHPhotoLibrary.requestAuthorization(for: .addOnly)`). Add-only
  access can't read the library. Location ("while using the app" only,
  `NSLocationWhenInUseUsageDescription`) is asked for only when the person turns on the Location
  switch, and never in the background (see "Location").
- **Photos:** each photo's files are built in memory with metadata from the allowlist (below),
  read back and checked, and added to Photos with add-only access. A RAW and its HEIF (or JPEG)
  are one Photos asset: the DNG is the main resource and the processed file the alternate, as
  Apple documents ("Capturing Photos in RAW and Apple ProRAW Formats"). With RAW, HEIF and JPEG
  all selected, Settings › Formats › Paired with RAW chooses which copy is the alternate (HEIF by
  default); the other is its own asset (issue #50). Pairing changes nothing in any file. The formats are RAW plus
  HEIF by default (`SaveSettings`); a lens without RAW saves its labeled processed fallback. If a
  file fails the check, nothing is saved and the screen says "Not saved: nope. couldn't confirm
  that the photo holds only the details you chose." Files aren't written to disk, with one
  exception PhotoKit requires: the processed copy paired with a RAW is added to Photos from a
  file, written with complete file protection under a random name in the app's temporary
  directory, moved into Photos, and deleted as soon as the save ends if anything is left
  (`docs/TESTING.md`, "RAW pairs not saved (PhotoKit error 3300)").
- **Signing:** every file is signed with Content Credentials when the signature switch is on
  (the default), and the screen says "Saved and signed." If signing fails, the photo is saved
  unsigned and the screen says "Saved. Not signed: the signature couldn't be created." Signing
  runs before the read-back, so a signed file is checked like any other (see "Content
  Credentials").
- **Last photo and its details:** after each save, the last-photo thumbnail beside the shutter
  is made from the saved HEIF or JPEG (or the DNG when only RAW is saved) with ImageIO, in memory
  (`ImageIOThumbnailer`, no cache). "What's in This Photo" (issue #53, opened from the
  thumbnail's long-press menu or its VoiceOver action) lists what the read-back found in each
  saved file (pixel size, bit depth, file size, the DNG's color filter pattern, black and white
  levels and whether it stores lens correction instructions; the share of clipped highlights and
  shadows counted from the RAW sensor buffer at capture time (counts only, `RAWClipping`; the
  samples are read once and never copied, stored or logged); the exposure tags as written; every
  tag, block and property by name), which optional details were written or left out and why, the
  signature (the manifest's claim generator and description, and the SHA-256 hash of the
  manifest store the C2PA library returned), and how long each step took. Both are kept in
  memory for this session only: never written to disk, logged or copied, and gone when the app
  quits. The app can't reopen older photos (add-only access). Tapping the thumbnail opens the
  Photos app with its `photos-redirect://` URL, only when the person taps; it reads nothing from
  Photos and makes no network request.
- **Settings:** the person's choices (formats, the RAW pairing, metadata switches, signing, the
  HEIF and JPEG look and file options, front camera mirroring, manual controls) are stored in
  `UserDefaults` on the device. They are never synced or sent. The name and copyright fields of
  `SaveSettings` stay empty: Settings has no text entry for them yet. The privacy manifest
  declares the `UserDefaults` required-reason API with reasons `CA92.1` (the app's own data) and
  `1C8F.1` (data shared with the app's own extensions through its App Group). See "Settings
  shared with the extensions" below.
- **Location:** off by default; see "Location" below. The location is never stored by the app
  outside the photo itself, never logged and never sent. The privacy manifest declares no
  collected data: Apple's "collected" means data transmitted off the device, and the location
  goes only into the person's own photos on the device.
- **Viewfinder overlays:** the level reads the motion sensors (Core Motion device motion, which
  needs no permission) only while it is shown; focus peaking and the histogram sample a few
  reduced preview frames a second in memory only while they are shown; the live camera readout
  reads values the camera reports. None of this is written to a photo, stored, logged or copied.
- **Comparison shot (issue #55):** off unless the person turns Compare on (quick-controls tray;
  not remembered). Each single or self-timer photo is then followed by a second photo with the
  phone's processing at `.quality` prioritization, which keeps the system's own metadata, so the
  compare view can show what it carries. That photo is never saved, signed, written to a file,
  shared, copied or logged: it is decoded into a picture and read by the app's tag reader in
  memory, and everything is dropped when the person closes the view. The app's own photo is saved
  exactly as without Compare. Identifying values (maker notes, location, unique IDs and serial
  numbers) are hidden until the person taps Show Value. The view's contents are hidden while
  the app isn't the active app. No network request is involved.
- **Live Activity (issue #64):** off by default (Settings › Camera › Live Activity). While it is
  on, an interval series, astro run, burst or self-timer shows a Live Activity on the Lock Screen
  and in the Dynamic Island: counts and status only ("Paused: 42 of 120 photos taken", "Saving: 4
  of 7 photos saved", whether the saved photos are signed), never image data, a thumbnail,
  location or metadata. It is updated by the app on the device only (ActivityKit local updates):
  the app never asks for a push token and sends nothing anywhere. Its content lives with the
  system's Live Activity until it ends; the app ends it when the run ends (at once in the
  foreground, two minutes later otherwise) and ends any left from an earlier launch. Whether the
  switch is on or off, when the app leaves the foreground while photos are still being taken or
  saved, it asks iOS for a little time to finish saving them
  (`UIApplication.beginBackgroundTask`), which is not a background mode.
- **Apple Watch app (issue #63):** the watch app sends the iPhone app only commands (the
  status, take a photo after none, 3 or 10 seconds, cancel the timer) and gets back only short
  status: whether the camera is ready, the seconds left, and whether a photo was saved and signed
  or why not. No image data, preview, thumbnail or metadata goes to the watch. The messages go
  through WatchConnectivity (`WCSession.sendMessageData`), which watchOS and iOS carry on their own
  connection between the paired devices; neither app opens a network connection, and
  `scripts/check-no-networking.sh` checks the watch app's binary too. The watch app stores nothing
  (the delay is kept only while it runs), logs nothing and has no entitlements. Its privacy
  manifest declares no tracking, no tracking domains and no collected data; it declares
  `UserDefaults` (`CA92.1`) because the shared `NopeCore` code linked into it contains the
  iPhone app's settings code, which the watch app never runs.
- **Entitlements:** none.
- **Files and logs:** Release builds write no files except the paired copy above, which
  Photos moves into the library (photos otherwise go from memory to Photos). They log only why
  adding to Photos failed: the error's domain and code and the resource types, marked private;
  never photo data or metadata. Debug builds include the
  tag check (below), which writes test captures to the app's container only when launched with
  `-NopeTagCheck`; it isn't compiled into Release builds. The `-NopeCameraProbe` diagnostic
  also saves one live video frame as a JPEG, to check exposure (see [`TESTING.md`](TESTING.md),
  "Black frames").

## Settings shared with the extensions

Since 0.3.0 the settings are kept in the `UserDefaults` of the app's App Group
(`group.<bundle identifier>`, for example `group.com.photivra.nope.dev` in development builds),
so the app and its Control Center and Lock Screen controls read the same values (issue #42).

- **What is shared:** only the settings listed above, under keys that start with
  `NopeSettings.`: Booleans, the names of choices (formats, flash mode, look) and numbers (torch
  brightness). No photo, thumbnail, metadata value, location, file name, date of use, counter or
  identifier is stored or shared.
- **Who can read it:** the app and its own extensions signed by the same team: today the
  controls extension (`NopeControls`), which reads and writes night mode. Another app can't read
  an App Group it doesn't belong to.
- **It stays on the device.** The App Group container is local: it isn't synced through iCloud,
  and nothing in it is sent anywhere. Device backups include it as they include the app's own
  preferences.
- **Moving the old settings:** on the first launch of 0.3.0 the app copies its settings from its
  own `UserDefaults` into the App Group's once (`SharedSettingsStore.migrate`); the old copy is
  left in place and no longer read.
- **Change signal:** when a setting changes, the process that changed it posts a Darwin
  notification named `<App Group>.settings-changed`. It carries no data; the app and the controls
  read the store again when they hear it.
- **The Lock Screen camera** (`NopeCaptureExtension`) can't open the App Group: Apple's
  LockedCameraCapture documentation says a capture extension "can't read from or write to the App
  Group's shared container". So the app (and the night mode control) hand it a copy of the same
  settings through the `appContext` of the "Open nope." intent (`NopeSettingsSnapshot`, at most
  4 KB, kept by the system on the device). The Lock Screen camera reads it when it opens; changes
  made there last until it closes, because the system erases the extension's own container. Its
  restrictions are unchanged: it has no location reader and no storage or battery reader, so a
  photo taken there never carries a location even if the Location switch is on.

## Settings presets

Presets (issue #72) are named copies of the settings above plus the camera's lens, exposure,
drive and astro values, saved when the person taps Save Current Settings.

- **What is stored:** the preset's name as typed, a random identifier, an encoding version, the
  same settings values as above and the camera values (lens identifier, kind and magnification,
  ISO, shutter, aperture, focus position, white balance, exposure compensation, metering, Close-Up,
  drive mode, bracket, interval and astro choices). No photo, location, date, counter or
  device identifier. The lens identifier is the app's own name for the lens on this device and is
  never written to a photo.
- **Where:** in the same on-device store as the settings (the App Group's `UserDefaults`, key
  `NopePresets.saved`). Presets are not part of the copy handed to the Lock Screen camera, are
  never synced through iCloud and never leave the device; device backups include them as they
  include the settings.
- **Permissions are never bypassed.** Applying a preset that has Location on asks for location
  access through the normal prompt; if access isn't allowed, Location stays off and the person
  is told. A preset can't grant camera or Photos access either: those prompts are unchanged.
- **Deleting** a preset removes it from the store; Factory Defaults resets every setting but
  keeps the saved presets.

## Content Credentials (signing)

The app signs each saved file (DNG, HEIF, JPEG) with C2PA Content Credentials
(`ContentCredentialsSigner` in `NopeSigning`, called by `PhotoSaver` before the read-back).
Signing has its own switch (`MetadataSettings.signsPhotos`), on by default, outside the "Remove
all optional details" master switch. If signing fails, the photo is saved unsigned and the
screen says so.

**What it proves.** The signature proves the file hasn't changed since the app signed it. It
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
   library the app links is built from source with every network feature off, and contains no
   networking code at all; CI checks the library and a linked iOS binary for networking symbols
   on every pull request (`c2pa-lib/README.md`). Its settings also turn every fetch off and allow
   no network host. No App Attest.

**What the signature contains.** Nothing in it identifies the person or the device, and nothing
links two files: every field is either the same for everyone running that version of the app, or
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
and with c2patool 0.28.6; the metadata read-back allowlist permits it for signed files only
(`MetadataPlan.allowlist(for:signed:)`), and `ReadBackTests` checks that a signed file passes the
read-back exactly as its unsigned original does:

| Format | Added | Notes |
|---|---|---|
| DNG | TIFF tag 52545 (`0xCD41`), type `UNDEFINED`, in IFD0, and the store at the end of the file | The app inserts the entry into IFD0 where it is, at its tag-number position, and moves every later byte (and every offset that points to it) 12 bytes on (`DNGManifestSlot`); no tag is removed or rewritten. The C2PA library then signs with its data-hash workflow, and the hash excludes only the store. (The library's own DNG writer moves IFD0 to the end of the file, and iOS can't open that file as a DNG: issue #66, `docs/TESTING.md`, "Signed DNG and ImageIO") |
| HEIF | One top-level `uuid` box, UUID `D8FEC3D6-1B0E-483C-9297-5828877EC481`, after `ftyp` | No other box changes type or order. The hash excludes `/uuid`, `/ftyp`, `/mfra`, `/free` and `/skip`, the C2PA default exclusions for this format |
| JPEG | APP11 (`0xFFEB`) segments with JUMBF (common identifier `JP`), after APP0 | No other segment changes. The hash excludes only the APP11 segments |

ImageIO reports no new property for the signed HEIF and JPEG (only the file size changes).
Every signed file must open in ImageIO as its own type with exactly one image, like every other
file. **A signed file that fails the read-back is never saved:** its unsigned file, which already
passed, is saved instead, and the status says "Saved. Not signed: the signed file didn't pass the
check." (`SignatureStatus.UnsignedReason.signedFileFailedCheck`).

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

The settings model is `MetadataSettings` in `NopeCore`; `MetadataPlan` turns it into each file's
allowlist and metadata.

**Master switch: "Remove all optional details", on by default.**
- **When on,** every switch below is off, so files carry only the locked items, plus the
  Content Credentials signature, which has its own switch outside the master.
- **Turning on any single item** turns the master off, and the screen shows "Custom".
- **Turning the master back on** turns every item off again.
- **With the master off,** the user sets each item one by one.

The "Default" column below is each item's setting when the user turns the master off. Because
turning the master on clears every item, turning it off always starts from these defaults.

### Switches (removing these never breaks the photo)

| Item | Default | What turning it off costs (shown in the app) | Device tag check |
|---|---|---|---|
| Location (latitude, longitude, altitude) | Off | Nothing. Location is only added if you turn it on | Not written by the system; written by the app from the device's location (see "Location") |
| Date and time taken | On | Photos sorts by the date you saved it instead | Present (`DateTime*`, XMP dates) |
| Sub-second time | Off | Nothing visible | Present (`SubSecTime*`) |
| Time zone | Off | The photo's local time can't be converted to other zones | Present (`OffsetTime*`) |
| Camera make and model | On | Apps can't show which phone took it | Present (`Make`, `Model`, HEIF `HostComputer`) |
| Lens make and model | On | Apps can't show which lens took it | Present (`LensMake`, `LensModel`) |
| Exact camera model for RAW editors (`UniqueCameraModel`) | On | Some RAW editors can't choose their camera-specific color profile and use the file's own color data instead. The DNG standard requires this tag, so when it's off, the app writes a generic value rather than none | Present |
| Lens correction instructions (DNG opcodes) | On | Editors can't automatically correct this lens's distortion and vignetting. The pixels are never corrected either way | Present (`OpcodeList3`) |
| Exposure settings (shutter, ISO, aperture, focal length) | On | You can't see later how the photo was taken | Present (`ExposureTime`, `ISOSpeedRatings`, `FNumber`, `FocalLength` and related EXIF tags, in RAW and HEIF) |
| iOS version | Off | Nothing visible | Present (`Software`, XMP `CreatorTool`) |
| Maker notes (Apple) | Off | Nothing visible; they hold time since restart and per-photo IDs | Present (`0x927C`) |
| Your name and copyright | Off | Nothing; only written if you enter them | Not written by the system |
| App name and version ("Photivra Nope Camera" and its version) | On | Apps can't show what made the file | Written by the app |
| Content Credentials signature (outside the master switch) | On | The photo can't be checked for changes. The signature never has a timestamp (see "Content Credentials") | Written by the app |

Serial numbers, unique image IDs and raw data IDs are never written, by the system or by the app,
so they have no switch.

**In the app:** Settings › Privacy shows the master switch, a switch for each item above with its
"what turning it off costs" text, the signing switch, and the locked items, each with its
reason (`NopeCore.MetadataSettings`, `NopeUI.PrivacySettingsView`). Location and "Your name and
copyright" has no switch yet, because text entry isn't built; it stays off. Location has its
switch and asks for location access when it is turned on (see "Location"). The app passes the settings to the save pipeline, which applies them to
the next photo.

### Location

The Location switch (issue #43) is off by default and outside nothing: "Remove all optional
details" turns it off like every other item.

- **Asking:** turning the switch on asks for "while using the app" location access first
  (`LocationTagging.turnOn(in:)`); if access is declined or restricted, the switch stays off and
  Choose Details says how to allow it in Settings. The app never asks for "always" access and has no
  background mode.
- **When it runs:** location updates run only while the switch is on, access is allowed and the
  camera is running (`LocationTagging.update(isOn:cameraIsRunning:)`); they stop on any
  interruption, in the background and when the camera stops, and the last location is then
  forgotten, so a photo never gets a location from an earlier session. A photo taken before the
  first location arrives has none. Core Location's `CLLocationUpdate.liveUpdates()` delivers
  updates only while it is iterated.
- **What is written:** exactly the GPS tags `GPSLatitudeRef`, `GPSLatitude`, `GPSLongitudeRef`,
  `GPSLongitude` and, when the system reports a valid altitude, `GPSAltitudeRef` and
  `GPSAltitude` (EXIF 3.0, 4.6.6), with the system's own values (`PhotoLocation`,
  `MetadataField.gpsFields`). `GPSVersionID` is allowed because EXIF requires it in a GPS
  directory and a writer may add it; ImageIO on the iOS 27.2 Simulator doesn't add it to HEIF or
  JPEG. **Not written:** direction, speed, accuracy, satellites, GPS date or time, area or
  destination. The read-back rejects any other GPS tag (the GPS directory is no longer allowed
  as a whole).
- **How:** the DNG and the processed fallback get the location in AVFoundation's replacement
  metadata, like every other tag; a developed HEIF or JPEG copies the same allowlisted GPS fields
  from its DNG. The location is never supplied to the camera itself.
- **On the camera:** while the switch is on, an amber "Location On" chip says so, also in clean
  view.

### Front camera mirroring

Settings › Camera › Mirror Front Camera (issue #45), off by default (owner decision): photos are
saved as others see you. When on, a front camera photo is saved as the viewfinder shows it,
through the Orientation tag only: the mirrored value of the system's orientation (1↔2, 3↔4,
5↔6, 7↔8; TIFF 6.0 `Orientation`), so the Bayer RAW sensor data is unchanged
(`MetadataPlan.mirroredOrientation(_:)`). The photo output's own mirroring is turned off
(`AVCaptureConnection.videoMirrored = false`), so every photo starts unmirrored. The viewfinder
stays mirrored either way. A developed HEIF or JPEG is rendered from the DNG with its
orientation applied, so it shows the same direction with Orientation 1, like every developed
copy. Orientation is a locked item and the read-back accepts all eight values.

### Developed file options

Settings › Photos › File Options (issue #57): the compression of the HEIF and JPEG copies, the
HEIF bit depth (10 or 8), the color space (Display P3 or sRGB) and the copy size (full, half or a
quarter of the RAW's width and height). They change only how the developed copies are encoded,
never the RAW; the only metadata they touch is EXIF `PixelXDimension` and `PixelYDimension` of a
smaller copy, set to its size. The defaults are the earlier encoding. Every combination is encoded and read back in the unit tests. The full list of what an
app can control, and what the app offers, is in
[`research/capture-and-file-settings.md`](research/capture-and-file-settings.md).

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

## How each file's metadata is built and checked

**Built from the allowlist, never by deleting.** `MetadataPlan.properties(for:from:)` starts
from an empty dictionary and copies in only the values of the tags below that the switches
allow, from the system's metadata. A tag the system adds that isn't listed here is never copied.

- **DNG:** written by AVFoundation with that dictionary as the replacement metadata
  (`AVCapturePhotoFileDataRepresentationCustomizer.replacementMetadata(for:)`;
  `AVCapturePhotoOutput.h`: "To replace metadata, pass a replacement dictionary"). ImageIO can't
  write DNG, and AVFoundation writes the RAW image data itself, so the sensor data is never
  re-encoded by the app (`docs/ARCHITECTURE.md`, "From capture to Photos").
- **HEIF and JPEG developed from the RAW:** encoded by ImageIO from a rendered image that has no
  metadata, with the dictionary built from the DNG's (already allowlisted) metadata, orientation
  "up", no embedded thumbnail, and the person's file options (compression, HEIF bit depth,
  color space; see "Developed file options"). Both looks (`SaveSettings.developedLook`, owner decision
  2026-11-12) demosaic the sensor data and apply the file's white balance and color matrices,
  with no noise reduction, sharpening, local contrast, local tone mapping or lens correction:
  - **Standard** (default): one global tone curve, Core Image's default for the camera, so the
    photo looks like a normal photo.
  - **Flat:** no tone curve; the image stays linear to the scene, and only Display P3's
    standard transfer function is applied when it is encoded. It looks flat and low in
    contrast, for editing afterwards.

  The look never changes the RAW. (`CoreImageRAWRenderer`; on-screen appearance is a device
  check.)
- **Processed fallback (a lens without RAW):** written by AVFoundation with the replacement
  dictionary, like the DNG.

**Read back before saving (fail closed).** Every finished file is read back before signing and,
when signed, again after signing, by
the project's own reader (`MetadataFileReader`): every tag in every TIFF directory (IFD0, EXIF,
GPS, interoperability, SubIFDs, and any chained IFD such as a thumbnail), every JPEG segment,
every HEIF box, item, item property and reference, and every XMP property. ImageIO then opens the
file as Photos would: it must be exactly one image of its format, and every key it reports must
be allowed. `MetadataVerifier` rejects the whole photo, and nothing is saved, if:

- any tag, block, XMP property or ImageIO key isn't on the allowlist, including one a future iOS
  adds;
- an allowed text has a value the app didn't write (for example the exact camera model when the
  generic one was asked for, or a date with a time zone when the time zone is off);
- a tag a DNG can't be opened without is missing (`DNGVersion`, `UniqueCameraModel`,
  `ColorMatrix1`, `CFARepeatPatternDim`, `CFAPattern`);
- the DNG's RAW image data (IFD0's tiles or strips) isn't byte-for-byte the data of the system's
  own DNG for the same capture;
- anything can't be read.

The fuzz and property tests (`MetadataFailClosedFuzzTests`) inject random tags, a simulated
future system tag (`0xC7FF`) in every format and directory, unexpected segments and items
(XMP, multi-picture, thumbnails, gain maps), and random byte damage, and check that every such
file is rejected and no input crashes the reader.

### Exact tags by format

Written by the system or by the app only when listed here. `MetadataPlanTests` asserts these sets
for all 8,192 switch combinations in every format.

| Group | DNG | HEIF and JPEG |
|---|---|---|
| Locked: image structure | IFD0 `NewSubfileType`, `ImageWidth`, `ImageLength`, `BitsPerSample`, `Compression`, `PhotometricInterpretation`, `StripOffsets`, `SamplesPerPixel`, `RowsPerStrip`, `StripByteCounts`, `PlanarConfiguration`, `TileWidth`, `TileLength`, `TileOffsets`, `TileByteCounts`, `DefaultCropOrigin`, `DefaultCropSize`, `ActiveArea`; EXIF `ExifVersion`, `PixelXDimension`, `PixelYDimension` | IFD0 `XResolution`, `YResolution`, `ResolutionUnit`, `YCbCrPositioning` (HEIF also `TileWidth`, `TileLength`); EXIF `ExifVersion`, `ComponentsConfiguration`, `FlashpixVersion`, `PixelXDimension`, `PixelYDimension` |
| Locked: color filter pattern | `CFARepeatPatternDim`, `CFAPattern`, `CFAPlaneColor`, `CFALayout` | — |
| Locked: levels | `BlackLevelRepeatDim`, `BlackLevel`, `WhiteLevel`, `BaselineExposure`, `NoiseProfile`, `NoiseReductionApplied` | — |
| Locked: color calibration | `ColorMatrix1`, `ColorMatrix2`, `AsShotNeutral`, `CalibrationIlluminant1`, `CalibrationIlluminant2` | — |
| Locked: DNG version | `DNGVersion`, `DNGBackwardVersion` | — |
| Locked: orientation | `Orientation` | `Orientation` |
| Locked: color profile | — | EXIF `ColorSpace`; the ICC profile (JPEG `APP2`, HEIF `colr`) |
| Exact camera model for RAW editors | `UniqueCameraModel`, always present; "Generic camera" when off | — |
| Location | the GPS directory pointer and, in it, only `GPSVersionID`, `GPSLatitudeRef`, `GPSLatitude`, `GPSLongitudeRef`, `GPSLongitude`, `GPSAltitudeRef`, `GPSAltitude` (see "Location") | same |
| Date and time taken | `DateTime`, `DateTimeOriginal`, `DateTimeDigitized` | same, plus HEIF XMP `photoshop:DateCreated`, `xmp:CreateDate`, `xmp:ModifyDate` (no fraction or zone unless those switches are on) |
| Sub-second time | `SubSecTime`, `SubSecTimeOriginal`, `SubSecTimeDigitized` | same |
| Time zone | `OffsetTime`, `OffsetTimeOriginal`, `OffsetTimeDigitized` | same |
| Camera make and model | `Make`, `Model`, `HostComputer` | same |
| Always in a DNG, empty when their switch is off | `DateTime`, `Make`, `Model`, `Software`: the value above when the switch is on, an empty text when it is off (see below) | — (left out when off) |
| Lens make and model | EXIF `LensMake`, `LensModel`, `LensSpecification`; DNG `LensInfo` | EXIF `LensMake`, `LensModel`, `LensSpecification` (never ImageIO's `{ExifAux}` copies, which it would write as XMP `aux:` properties) |
| Lens correction instructions | `OpcodeList1`, `OpcodeList2`, `OpcodeList3` | — |
| Exposure settings | EXIF `ExposureTime`, `FNumber`, `ExposureProgram`, `PhotographicSensitivity`, `SensitivityType`, `ShutterSpeedValue`, `ApertureValue`, `BrightnessValue`, `ExposureBiasValue`, `MaxApertureValue`, `MeteringMode`, `Flash`, `FocalLength`, `SubjectArea`, `SensingMethod`, `SceneType`, `ExposureMode`, `WhiteBalance`, `FocalLengthIn35mmFilm`, `SceneCaptureType` | same |
| iOS version / app name and version | `Software`: "Photivra Nope Camera 0.x.y" (app), the system's version (iOS), or "Photivra Nope Camera 0.x.y (27.2.1)" (both) | same, plus HEIF XMP `xmp:CreatorTool` with the same value. A HEIF or JPEG developed from the DNG takes the system's version back out of the DNG's value, so it never nests the app's name (`MetadataPlan.systemVersion(fromSoftware:)`) |
| Maker notes | EXIF `MakerNote` | same |
| Your name and copyright | `Artist`, `Copyright`, only when entered | same, plus HEIF XMP `dc:creator`, `dc:rights` with the same values |
| Content Credentials (signed files only) | IFD0 tag `0xCD41` | JPEG `APP11`; HEIF top-level `uuid` box (C2PA 2.1, appendix A) |

**Four TIFF fields every DNG carries (issue #65).** On an iPhone 16 Pro Max with iOS 27.2.1,
`AVCapturePhoto.fileDataRepresentation(with:)` returns no file at all for a Bayer RAW photo unless
the replacement metadata's `{TIFF}` dictionary has `DateTime`, `Make`, `Model` and `Software`
(measured with debug runs on the device; Apple doesn't document it). Leaving out any one fails;
`HostComputer` and the resolution keys aren't needed; an empty text for each of the four works,
and `NSNull` doesn't. So every DNG's dictionary has all four (`MetadataPlan.requiredRAWTIFFFields`):
the real value when the item's switch is on, and an empty text, never a placeholder, when it is
off. An empty field says nothing about the date, camera or software. The read-back accepts each
of the four when its switch is off only if it is empty: one NUL, a count of 0, only NULs, or the
tag left out (which of these AVFoundation writes is a device check below); any text fails. HEIF
and JPEG don't need them, so they leave them out when the switch is off. `UniqueCameraModel`
keeps its "Generic camera" value.

**Containers.** A JPEG may hold only `APP0` (JFIF), `APP1` (EXIF), `APP2` (ICC profile), the
empty IPTC record ImageIO always writes in `APP13` (no fields; checked byte for byte), and the
image's structure segments; no XMP segment, comments, other `APPn` segments or data after the
end of the image. A HEIF may hold only the image (`hvc1` items, or a `grid` of them), its `Exif`
item, the XMP item when an XMP property above is on, and the image's layout properties; no
thumbnails (`thmb`) or auxiliary images (`auxl`, such as depth or gain maps).

### Device checks

The checks above run on every saved file. These still need a real device, because the
Simulator has no camera and no real DNG can be made in a unit test:

- the saved DNG passes the read-back for the default settings, all switches on, and a few
  combinations in between, on each lens (AVFoundation adds nothing beyond the replacement
  metadata, and keeps the required DNG tags);
- the reference RAW image data matches the saved DNG's (the two flattenings give identical
  sensor data);
- AVFoundation writes the lens correction opcodes and the maker note only when they are in the
  replacement dictionary;
- the developed HEIF (10-bit) and JPEG look right and pass the read-back;
- the processed fallback HEIF passes the read-back;
- the add-only prompt appears once, and a RAW plus HEIF shows as one photo in Photos with the RAW
  as the original;
- an exiftool dump of each saved file matches the tables above;
- with "Remove all optional details" on (the default) and with every switch on, a RAW is saved
  (issue #65), and the saved DNG's `DateTime`, `Make`, `Model` and `Software` are empty with the
  switches off: note which encoding AVFoundation uses (one NUL, a count of 0, or the tag left
  out), and that the read-back accepts it;
- on a lens without Bayer RAW, the processed fallback HEIF (and JPEG) is saved with "Remove all
  optional details" on: it is written through the same `fileDataRepresentation(with:)` call
  without the four TIFF fields, and whether AVFoundation needs them for a processed photo too
  wasn't measured (issue #65 measured RAW only). If it fails ("The photo wasn't taken. Try
  again."), the fallback needs the same empty fields;
- with Location on and access allowed, the saved DNG, HEIF and JPEG carry exactly the GPS tags
  in "Location" (note whether AVFoundation adds `GPSVersionID` to the DNG), the location is
  right in Photos, and with Location off no file has a GPS directory;
- a mirrored front camera photo (Mirror Front Camera on) shows mirrored, and an unmirrored one
  (the default) shows as others see you, in Photos and a RAW editor, for the DNG, HEIF, JPEG and
  the processed fallback, in portrait, both landscapes and upside down; and whether the system
  mirrored front camera photos before the app turned the photo output's mirroring off;
- a signed DNG, HEIF and JPEG are saved and open in Photos and a RAW editor, and validate with
  c2patool (issue #66); with maker notes on, an exiftool dump of the signed DNG's maker note
  matches the unsigned one's (the maker note moves 12 bytes, and its offsets are assumed to be
  relative to its own start).
