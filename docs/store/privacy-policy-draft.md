# Privacy policy: Photivra Nope Camera (DRAFT)

> **DRAFT, needs human review. Not published.** The maintainer reviews, completes and publishes
> this policy at `https://nope.photivra.com/privacy/`, the address the app's About screen and the
> store listing link to. It describes the planned 1.0 app; before publishing,
> check every statement against the release build and `docs/SECURITY_AUDIT.md`, and remove any
> that the release doesn't support. Wording follows `docs/PRIVACY.md` and
> `docs/research/privacy-claims.md`. Items in [brackets] are for the maintainer to fill in.
> Translations, if any, need fluent human review. This draft is not legal advice.

---

# Photivra Nope Camera privacy policy

Effective date: [date]. Last updated: [date]. App version: [1.0.0].

This policy covers the Photivra Nope Camera app for iPhone and iPad, and its Apple Watch app, published by
[LLC legal name]. It doesn't cover photivra.com or other Photivra products, which have their own policies.

## The short version

The app doesn't collect any data. It has no accounts, no analytics, no ads and no crash reporting,
and it makes no network connections. Your photos and settings stay on your device, in places you
control.

## What we collect

Nothing. The app doesn't send any information to us or to anyone else. We can't see your photos,
your settings, how you use the app, or that you use it at all. The App Store privacy label for
the app says "Data Not Collected".

## No network connections

The app contains no networking code and makes no network connections. To check, turn on App
Privacy Report (Settings › Privacy & Security). It lists every domain an app contacts during the
last 7 days, starting from when you turn it on. The app should list none. iOS itself, for example
iCloud Photos, makes its own connections.

The links in the app, on the About screen, leave the app only when you tap them. The source
code and this policy open in your web browser. Rate or Review opens the App Store's page for
rating or reviewing the app. The app doesn't fetch any of them; your browser or the App Store
does, under its own privacy settings. The app never asks you for a rating and doesn't record
whether you tapped a link. Ratings and reviews you write in the App Store are public.

The Apple Watch app sends only your commands, such as the shutter and the delay, to the app on
your iPhone, and gets back only short status, such as "Saved and signed". No photos or photo
details go to the watch. watchOS and iOS carry these messages between your paired devices in
their own way; neither app opens a network connection.

## What stays on your device

- **Your photos.** The app saves each photo straight to your photo library and stores no copy.
  While it is open it keeps small previews of your recent photos in memory, to show them to you;
  they are released when the app goes to the background. Saving a RAW together with a HEIF or
  JPEG copy as one photo needs a short-lived file; Photos takes it, and the app deletes anything
  left.
- **Details of your last photo.** To show you what's in the photo you just took, the app keeps a
  list of its details in memory. The list is gone when the app quits.
- **Your settings and presets.** Your choices (formats, privacy switches, signing and other
  options) and any presets you save are stored on your device in the app's own storage. The app
  doesn't sync or send them. Like other app data, they are included in your device backups. A
  preset name you type goes through the keyboard you use, as any typing does.
- **Logs.** The app writes no photo data or photo details to the system log.

## Permissions

- **Camera:** to take the photos you ask for.
- **Photos, add only:** to save your photos. The app can only add photos to your library. iOS
  doesn't let it see your existing photos.
- **Location, only if you turn it on:** location is off by default. If you turn it on, iOS asks
  your permission and shows the location arrow while the app uses it, and the location is written
  into the photos you take. The app never sends it anywhere.

You can change each permission at any time in Settings.

## What's written into your photos

By default the app removes every optional detail and adds no signature. A file keeps only what
it needs to open and display correctly (such as its size, color data and orientation). You choose
which other details to add, one switch at a time, for example the date and time, the camera and
lens model, or your location. The app explains each one, and `docs/PRIVACY.md` in the public
source code lists every item.

The app never writes serial numbers into your photos, and writes no unique image IDs unless you
turn on Maker Notes: Apple's maker notes hold IDs for each photo, which can link your photos.

## The signature (Content Credentials)

Signing is off by default. When you turn it on, each photo is signed so that anyone can check
whether the file has changed since it was signed. The signature names the app and its version as
the maker. It is not proof: anyone could make a file that says the same, and it doesn't show who
took the photo. An edit, or sharing in a way that converts the file, removes or breaks the
signature; to keep it, share the original file.

- A new signing key is made for every photo inside your device's Secure Enclave, used once and
  then discarded. The key never leaves the Secure Enclave. Because every photo has its own key,
  signatures can't link your photos to each other or to your device.
- The signature contains: the app name and version (the same for everyone), a random ID for that
  file, a description of the photo as a camera capture, and a certificate whose details are the
  same for every user (no name, email, device or location). The signature holds no date or
  time.
- You can turn signing off in Settings.

## What your device may still do outside the app's control

Once a photo is in your library, iOS and the Photos app handle it. The Honesty screen in the app
(Settings, then Honesty) explains each of these and names the setting where there is one:

- **iCloud Photos.** With standard protection, Apple holds the keys to iCloud Photos. With
  Advanced Data Protection, only your devices do. Some photo metadata and Shared Albums stay
  under standard protection.
- **Enhanced Visual Search.** Photos may privately compare landmark regions with Apple's servers.
  You can turn it off in Settings › Apps › Photos.
- **On-device analysis.** Photos uses on-device analysis to recognize people and pets and to
  classify scenes. Names you give people sync through iCloud.
- **Sharing.** When you share from Photos, location is included unless you turn it off under
  Options. Other details, such as the date and device model, may still be sent.
- **Share with App Developers.** If you opt in, Apple may share aggregated, non-identifying crash
  and usage statistics with developers. They never include your photos.
- **Siri.** If you use Siri with the app, Siri may send your spoken requests to Apple.
- **What Photos records.** Photos keeps its own record of when each photo was added and which app
  added it. That record isn't in the file, and the app can't change it.
- **Location.** With Location on, iOS works out where you are, and it may exchange data with
  Apple to do that. The app receives only the location iOS reports and never sends it anywhere.
- **Live Activities.** iOS may also show the app's Live Activity on a paired Apple Watch, in
  CarPlay or on a Mac. It shows the same counts.
- **App use.** iOS keeps its own record of when you use any app, for Screen Time and
  suggestions.

## What no app can remove

Every camera sensor leaves a faint, unique noise pattern. With enough of your photos, forensic
tools can match them to the same camera. No app can fully remove it. And anything visible in a
photo stays in it.

## This website

This policy is published at nope.photivra.com. The site uses no cookies, no analytics and no JavaScript, and loads nothing from other sites. It is hosted on GitHub Pages: when you load a page, GitHub receives your IP address and logs it for security, under [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Children

The app collects no data from anyone, including children.

## Changes to this policy

If this policy changes, the new version is published at this address with a new effective date,
and the change is noted in the app's release notes. Any change that would collect data is
against the project's rules, so we don't expect one.

## Open source

The app is free and open source under the GNU General Public License, version 3. Anyone can read
the code to check these statements: [https://github.com/Photivra/nope-camera](https://github.com/Photivra/nope-camera).

## Contact

Questions about this policy: write to [hello@photivra.com](mailto:hello@photivra.com), or open an issue in the GitHub repository, [github.com/Photivra/nope-camera/issues](https://github.com/Photivra/nope-camera/issues). Issues are public, so please don't include personal information. To report a security problem privately, use the repository's private vulnerability reporting (Security › Report a vulnerability).

The app never sends email, and it collects nothing. If you choose to write to us by email, your message and your email address are forwarded to us by Cloudflare Email Routing and stored by our email provider. We use them only to reply to you. We delete messages after 1 year, and you can ask us to delete yours sooner.
