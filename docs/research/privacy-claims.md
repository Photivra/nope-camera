# Research: privacy claims and their sources

Status: research, 2026-11-11 (iOS/iPadOS 27, Android 17). No code. This is not legal advice. Every privacy statement nope. makes in the app, the store listings or the privacy policy must use the wording below (or stronger evidence) and cite these sources. **Confirmed** = an authoritative source states it. **Inferred** = consistent with the sources but not stated; verify on a device before shipping the wording.

## Claims, verdicts and wording

| # | Claim | Verdict | Wording to use |
|---|---|---|---|
| 1 | The app never connects to the internet | Confirmed for the app; the check has limits | "nope. contains no networking code and makes no network connections. To check, turn on App Privacy Report (Settings › Privacy & Security). It lists every domain an app contacts during the last 7 days, starting from when you turn it on. nope. should list none. iOS itself, for example iCloud Photos, makes its own connections." |
| 2 | Android: no `INTERNET` permission means no network access | Confirmed for the app's own process | "nope. doesn't request Android's internet permission, so it can't open network connections. You can see this in its permission list." |
| 3 | App Store label "Data Not Collected" | Correct | Declare "Data Not Collected". Apple's own opt-in analytics are Apple's collection, not the developer's. |
| 4 | Google Play: no data collected or shared | Correct; the Data safety form and a privacy policy are still required | Same |
| 5 | Privacy manifest | Required | `NSPrivacyTracking` false; no tracking domains; no collected data types; required-reason codes below |
| 6 | The app can't read the photo library | Confirmed (add-only access) | "nope. can only add photos to your library. iOS doesn't let it see your existing photos." |
| 7 | Location only when the switch is on | Confirmed for the prompt and indicator; GPS behavior inferred | "Location is off by default. If you turn it on, iOS asks your permission and shows the location arrow while nope. uses it." |
| 8 | Hidden metadata can link photos | Confirmed (tag definitions) | List the specific tags removed (see below) |
| 9 | A sensor noise fingerprint can't be removed | Confirmed (peer-reviewed) | "Every camera sensor leaves a faint, unique noise pattern. With enough of your photos, forensic tools can match them to the same camera. No app can fully remove it." |
| 10 | Enhanced Visual Search | Mechanism confirmed; whether it's on by default is not stated by Apple | "Photos may privately compare landmark regions with Apple's servers (Enhanced Visual Search). You can turn it off in Settings › Apps › Photos." Don't say "on by default" unless it's verified on a device. |
| 11 | iCloud encryption | Confirmed | "With standard protection, Apple holds the keys to iCloud Photos. With Advanced Data Protection, only your devices do. Some photo metadata and Shared Albums stay under standard protection." |
| 12 | Share with App Developers | Confirmed, with nuance | "If you opt in, Apple may share aggregated, non-identifying crash and usage statistics with developers. They never include your photos." |
| 13 | Photos' on-device analysis | Confirmed | Use Apple's wording: Photos uses on-device analysis to recognize people and pets and to classify scenes. Names you give people sync through iCloud. |
| 14 | Sharing from Photos | Confirmed: **location is included by default** | "When you share from Photos, location is included unless you turn it off under Options. Other details, such as the date and device model, may still be sent." |
| 15 | App Store build versus the source | Essentially accurate (inferred from App Store distribution) | "Apple encrypts and re-signs App Store apps, so there's no standard way to confirm a download was built from our public source. On Android, F-Droid verifies reproducible builds." |
| 16 | Face framing stays on the device | Inferred; Apple's Vision documentation doesn't say "on device" | "Face framing uses Apple's Vision framework on your iPhone, and nope. makes no network connections." Never quote Apple as saying "on device". |
| 17 | A privacy policy | Required by both stores, even for apps that collect no data | A privacy policy link in the App Store and Google Play listings, and inside the app |

## Notes

1. **App Privacy Report** (iOS 15.2+) shows:
   - data and sensor access (camera, photos, location and others);
   - network activity and the domains contacted.

   It covers the last 7 days, and only from when it's turned on. It's stored on the device, encrypted. Apple doesn't say whether system services acting on an app's behalf are attributed to that app (inferred: they aren't). nope. will appear for Camera, Photos and, when switched on, Location. That is access, not collection.
2. **Android:** `INTERNET` is a normal permission, granted at install, and users can't toggle it.
   - **Other apps can still go online:** an intent can hand a task to another app that does, for example opening a link in the browser. That's expected.
   - **Audit the merged manifest:** a library can add `INTERNET` to the build.
   - **Without the permission,** web views and the download manager can't fetch content.
3. **"Collect"** (Apple): transmitting data off the device in a way the developer or partners can access beyond real-time servicing. Data processed only on the device isn't collected. "You are not responsible for disclosing data collected by Apple."
4. **Google Play:**
   - "Collection" means transmitting data off the device, and "sharing" means transferring it to a third party.
   - Data handled only on the device is exempt.
   - Every app must complete the Data safety form and link a privacy policy.
5. **Required-reason codes:** these are from third-party copies of Apple's list. Recheck them against Apple's page before submission.
   - `UserDefaults`: CA92.1.
   - File timestamps: C617.1. Use DDA9.1 only if timestamps are shown to the user.
   - Disk space: E174.1, for the check before writing and the out-of-storage message.
   - System boot time: 35F9.1, for elapsed-time measurement.

   The C2PA library ships its own manifest if it uses any of these.
6. **Add-only access** (`PHAccessLevel.addOnly`, iOS 14+): the app can add assets but can't read or fetch the library, inferred to include **its own saved photos**. So:
   - "What's in your last photo" and the thumbnail must come from data kept in memory when the photo was saved, never from the library.
   - After the app quits, that data is gone.
7. **Location:**
   - **The prompt:** Allow Once, Allow While Using App or Don't Allow, plus Precise Location. iOS shows the location arrow during use.
   - **GPS in files:** the capture APIs are believed to write GPS only when the app supplies it. Verify on a device.
8. **Tags that can identify a device or link photos** (from the ExifTool tag tables):
   - **Apple maker notes:** RunTime (uptime since restart), AccelerationVector, BurstUUID, ContentIdentifier (pairs a Live Photo), ImageUniqueID, ImageCaptureRequestID, PhotoIdentifier, plus camera details.
   - **Standard EXIF and DNG:** Make, Model, LensMake, LensModel, Software, HostComputer, OffsetTime\*, ImageUniqueID (0xA420), BodySerialNumber, LensSerialNumber, CameraSerialNumber, RawDataUniqueID, UniqueCameraModel.
   - **XMP:** DocumentID and InstanceID.

   Verify what nope.'s output actually contains with `exiftool -a -G1 -u`.
9. **The noise fingerprint (PRNU):**
   - Lukáš, Fridrich and Goljan, "Digital Camera Identification from Sensor Pattern Noise", IEEE TIFS 1(2), 2006, doi:10.1109/TIFS.2006.873602.
   - Chen et al., "Determining Image Origin and Integrity Using Sensor Noise", IEEE TIFS 3(1), 2008, doi:10.1109/TIFS.2007.916285.
   - Shullani et al., "VISION" smartphone dataset, EURASIP JIS 2017:15.
   - Inferred: a minimally processed RAW keeps the fingerprint more strongly than a processed photo.
10. **Enhanced Visual Search:**
    - **Apple's description:** an on-device model finds a region that may be a landmark and computes an embedding. The embedding is quantized and homomorphically encrypted, and sent through a third-party relay that hides the IP address, with decoy queries. The server works only on ciphertext.
    - **The default:** Apple's privacy page doesn't state it, so verify on a reset device.
11. **iCloud:** under standard protection, keys are held in Apple data centers. Under Advanced Data Protection, Photos is end-to-end encrypted. Some Photos metadata and Shared Albums aren't.
12. **Share with App Developers:** set in Settings › Privacy & Security › Analytics & Improvements. It's off when iPhone Analytics is off. Developers get aggregated or non-identifying crash and usage data.
14. **Sharing:** sharing from Photos includes metadata such as date, location and device. Location can be turned off under Options. "All Photos Data" (the original file) is a separate switch. What else is stripped isn't documented, so verify on a device.
15. **Reproducible builds:** F-Droid publishes a developer-signed APK only when its own build from source matches. App Store binaries are encrypted and re-signed by Apple.

## Changes this makes to the design

- **The "last photo" details and the thumbnail** come from memory at save time, not from Photos. The empty state means "no photo saved since nope. opened".
- **Wording:** the Honesty screen's App Privacy Report line says "from when you turn it on, for the last 7 days". The Enhanced Visual Search line says "may", not "on by default". The sharing line says location is included unless turned off under Options.
- **A privacy policy link** is added to Settings and to the store listings. It opens in the browser.
- **Face framing** is described without attributing "on device" to Apple.

## Must verify on a device

1. App Privacy Report: no domains for nope. after a week of use, while camera, photos and location accesses are recorded.
2. ExifTool on DNG, HEIF and JPEG output, before and after stripping, for every switch combination.
3. With location off there's no GPS block in any output. With it on, the prompt and the arrow appear.
4. With add-only access, a library fetch returns nothing, including nope.'s own photos.
5. Whether Enhanced Visual Search is on by default on a freshly reset device.
6. The share sheet's Options defaults, and what metadata survives AirDrop, Messages and Mail.
7. Android: the merged manifest has no `INTERNET`, and the permission views show none.
8. The Xcode privacy report shows no missing required-reason warnings on upload.

## Sources

- **Apple support and legal pages:**
  - [App Privacy Report](https://support.apple.com/en-us/102188)
  - [Location Services](https://support.apple.com/en-us/102515)
  - [iCloud data security overview](https://support.apple.com/en-us/102651)
  - [Photos and privacy](https://www.apple.com/legal/privacy/data/en/photos/)
  - [App analytics and privacy](https://www.apple.com/legal/privacy/data/en/app-analytics/)
  - [Sharing photos on iPhone](https://support.apple.com/guide/iphone/share-photos-and-videos-iphf28f17237/ios)
  - [Location metadata in Photos](https://support.apple.com/guide/personal-safety/manage-location-metadata-in-photos-ips0d7a5df82/web)
- **Apple developer pages:**
  - [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
  - [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (5.1.1)
  - [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
  - [PHAccessLevel.addOnly](https://developer.apple.com/documentation/photokit/phaccesslevel/addonly)
  - [Apple ML research: homomorphic encryption](https://machinelearning.apple.com/research/homomorphic-encryption)
- **Android and Google Play:**
  - [Android INTERNET permission](https://developer.android.com/reference/android/Manifest.permission#INTERNET)
  - [Google Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- **Metadata tags:** [ExifTool Apple tags](https://exiftool.org/TagNames/Apple.html), [ExifTool EXIF tags](https://exiftool.org/TagNames/EXIF.html)
- **Builds:** [F-Droid reproducible builds](https://f-droid.org/docs/Reproducible_Builds/)
- **Papers:** Lukáš et al. 2006; Chen et al. 2008; Shullani et al. 2017 (see note 9)
