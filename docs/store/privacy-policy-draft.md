# Privacy policy: nope. (DRAFT)

> **DRAFT, needs human review. Not published.** The maintainer reviews, completes and publishes
> this policy on the Photivra website. It describes the planned 1.0 app; before publishing,
> check every statement against the release build and `docs/SECURITY_AUDIT.md`, and remove any
> that the release doesn't support. Wording follows `docs/PRIVACY.md` and
> `docs/research/privacy-claims.md`. Items in [brackets] are for the maintainer to fill in.
> Translations, if any, need fluent human review. This draft is not legal advice.

---

# Photivra Nope Camera privacy policy

Effective date: [date]. App version: [1.0.0].

This policy covers the Photivra Nope Camera app ("nope.") for iPhone and iPad, published by
[LLC legal name]. It doesn't cover the Photivra website or other Photivra products,
which have their own policies.

## The short version

nope. doesn't collect any data. It has no accounts, no analytics, no ads and no crash reporting,
and it makes no network connections. Your photos and settings stay on your device, in places you
control.

## What we collect

Nothing. nope. doesn't send any information to us or to anyone else. We can't see your photos,
your settings, how you use the app, or that you use it at all. The App Store privacy label for
nope. says "Data Not Collected".

## No network connections

nope. contains no networking code and makes no network connections. To check, turn on App
Privacy Report (Settings › Privacy & Security). It lists every domain an app contacts during the
last 7 days, starting from when you turn it on. nope. should list none. iOS itself, for example
iCloud Photos, makes its own connections.

A few links in the app (this policy, a Content Credentials checker and the source code) open in
your web browser. nope. doesn't fetch them; your browser does, under its own privacy settings.

## What stays on your device

- **Your photos.** nope. takes each photo into memory and saves it straight to your photo
  library. It keeps no copy of its own. If it ever needs a temporary file while saving, the file
  is protected and deleted immediately.
- **Details of your last photo.** To show you what's in the photo you just took, nope. keeps a
  list of its details in memory. The list is gone when the app quits.
- **Your settings.** Your choices (formats, privacy switches, signing and other options) are
  stored on your device in nope.'s own storage. Like other app data, they may be included in your
  device backups.
- **Logs.** nope. writes no photo data or photo details to the system log.

## Permissions

- **Camera:** to take the photos you ask for.
- **Photos, add only:** to save your photos. nope. can only add photos to your library. iOS
  doesn't let it see your existing photos.
- **Location, only if you turn it on:** location is off by default. If you turn it on, iOS asks
  your permission and shows the location arrow while nope. uses it, and the location is written
  into the photos you take. nope. never sends it anywhere.

You can change each permission at any time in Settings.

## What's written into your photos

By default, nope. removes every optional detail from your photos. A file keeps only what it
needs to open and display correctly (such as its size, color data and orientation), plus the
Content Credentials signature. You choose which other details to add, one switch at a time, for
example the date and time, the camera and lens model, or your location. The app explains each
one, and `docs/PRIVACY.md` in the public source code lists every item.

nope. never writes serial numbers or unique image IDs into your photos.

## The signature (Content Credentials)

Each photo is signed so that anyone can check whether the file has changed since nope. saved it.
The signature doesn't prove who took the photo.

- A new signing key is made for every photo inside your device's Secure Enclave, used once and
  then discarded. The key never leaves the Secure Enclave. Because every photo has its own key,
  signatures can't link your photos to each other or to your device.
- The signature contains: the app name and version (the same for everyone), a random ID for that
  file, a description of the photo as a camera capture, and a certificate whose details are the
  same for every user (no name, email, device or location). It contains the capture time only if
  the date switch is on.
- You can turn signing off in Settings.

## What your phone may still do outside nope.'s control

Once a photo is in your library, iOS and the Photos app handle it. The Honesty screen in nope.
(the ⓘ button) explains each of these, with a link to its setting:

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
- **Siri.** If you use Siri with nope., Siri may send your spoken requests to Apple.

## What no app can remove

Every camera sensor leaves a faint, unique noise pattern. With enough of your photos, forensic
tools can match them to the same camera. No app can fully remove it. And anything visible in a
photo stays in it.

## Children

nope. collects no data from anyone, including children.

## Changes to this policy

If this policy changes, the new version is published at this address with a new effective date,
and the change is noted in the app's release notes. Any change that would collect data is
against the project's rules, so we don't expect one.

## Open source

nope. is free and open source under the GNU General Public License, version 3. Anyone can read
the code to check these statements: [https://github.com/Photivra/nope-camera](https://github.com/Photivra/nope-camera).

## Contact

Questions about this policy: open an issue in the GitHub repository,
[github.com/Photivra/nope-camera/issues](https://github.com/Photivra/nope-camera/issues). Issues
are public, so please don't include personal information. To report a security problem
privately, use the repository's private vulnerability reporting (Security › Report a
vulnerability). There is no contact email.
