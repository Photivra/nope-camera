# App Store product page plan for 1.0.0

Status: **accepted by the maintainer on 2026-11-19, with every decision as recommended (section
16).** Written 2026-11-19 for release 1.0.0. Nothing here is submitted, and no file in
`store/metadata/` is changed by this plan: each piece of copy below goes into those files in its
own pull request, when the checks named for it are recorded. This page plans how Photivra Nope
Camera uses each part of an App Store product page, which assets to make and how, and what the
maintainer does in App Store Connect. The layout mockups of every screenshot are in
[`docs/design/store.html`](../design/store.html).

It builds on the other pages in this folder: the claim table and field limits in
[`README.md`](README.md), the [App Privacy answers](app-privacy-label.md), the
[Accessibility Nutrition Label answers](accessibility-label.md) and the
[privacy policy draft](privacy-policy-draft.md).

## 1. Rules this plan follows

1. **The page describes only what is shipped and checked.** Each screenshot, caption, preview
   scene, keyword and sentence is tied to a claim (C1 to C12 in [`README.md`](README.md)) or to a
   feature's device check in `docs/TESTING.md`. An item whose check isn't done is left out of the
   submission, not softened.
2. **No "tested" or "verified" on the page**, in text, captions or video.
3. **No quality claims.** No "better", "sharper", "true to life", "professional" or "best". The
   page says what the app does and doesn't do; it never says how good a photo looks.
4. **Pictures are what they appear to be.** A viewfinder or a photo shown on the page is either
   a real capture made with the app on a named device, or it is plainly not a photo (section 5.2).
   No stock photos, no generated images, no retouching.
5. **Names** follow AGENTS.md, "Name and wordmark": "Photivra Nope Camera" in text; "nope." only
   as the wordmark and in quoted interface text. The tagline "Processing? Nope. Tracking? Nope.
   Network? Nope." may be used whole.
6. **Fonts** in captions and artwork: Inter (SIL OFL), never an Apple system font. The app's own
   screens, captured as they are, keep the system font.
7. **Colors** follow `docs/design/README.md`: black ground, white text, teal (`#40C8E0`) only for
   the wordmark's period and for facts the app itself marks in teal, amber only where the app
   shows a warning, red only for Night Mode.
8. **English (U.S.) only** for 1.0.0, US spelling.

### What Apple's pages said on 2026-11-19

Read on 2026-11-19. Limits change; confirm each in App Store Connect when uploading. Items marked
**unverified** were not confirmed on an Apple page that day.

| Subject | What the page says | Source |
|---|---|---|
| Screenshots | 1 to 10 per device size; JPEG or PNG, no transparency. iPhone: the large Dynamic Island size (1320 × 2868, 1290 × 2796 or 1260 × 2736) is enough; the 6.5-inch size (1284 × 2778 or 1242 × 2688) is required only when the larger one isn't provided; smaller sizes are scaled from it. iPad: 13-inch (2064 × 2752 or 2048 × 2732) required if the app runs on iPad. Apple Watch: required for a watch app, one size, the same in every language (416 × 496 for Series 10 to 12, 422 × 514 for Ultra 3 and 4, and smaller sizes) | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) |
| App previews | Optional; up to 3 per device size and language; 15 to 30 seconds; up to 500 MB; at most 30 frames a second; iPhone 886 × 1920, iPad 1200 × 1600 (portrait). The page lists no Apple Watch previews. Previews are shown before screenshots | [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/) |
| Version fields | Promotional text 170 characters, editable without a new version; description 4,000; keywords 100 bytes; What's New isn't available for the first version; support URL required and must lead to contact information; marketing URL optional; copyright is the year and the owner's name | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information/) |
| Custom product pages | Up to 70 pages (earlier 35); each can change screenshots, previews, promotional text, keywords and a deep link; each is reviewed, without an app update | [Custom product pages](https://developer.apple.com/app-store/custom-product-pages/) |
| Accessibility Nutrition Labels | Voluntary for now, to become required later, with no date given; a feature is declared per device, only if every common task can be done with it; the Accessibility URL is optional | [Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels) |
| Featuring | Nominations are sent from App Store Connect, at least two weeks ahead and up to three months for wider consideration | [Getting featured](https://developer.apple.com/app-store/getting-featured/) |
| Age rating | 4+, 9+, 13+, 16+ and 18+, from a questionnaire | [Age ratings](https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/) |
| **Unverified** | That search results show the first three portrait screenshots, or a preview in the first place; which fields search indexes besides keywords; that screenshots have no alternative text; the names of the nomination types; the exact form of the App Store address that opens the write-review page; iPhone Duo screenshot sizes and whether they become required | From memory, or seen once and not confirmed |

## 2. Text fields

Current files are in `store/metadata/en-US/`. "Keep" means no change is proposed.

| Field | Limit | Proposal | Notes |
|---|---|---|---|
| Name | 30 | Keep: "Photivra Nope Camera" (20) | Never translated |
| Subtitle | 30 | Keep: "RAW photos. No tracking." (24) | Both halves rest on C1 and C4 (decision 2) |
| Promotional text | 170 | Keep for submission (167). After the device checks, option B below | The one field that can change without a new version: use it for what a release adds, never for news or seasons |
| Description | 4,000 | Keep the five sections; add the two sections in 2.2 when their checks pass | About 2,060 characters today, so there is room |
| Keywords | 100 | Proposal in 2.3 | |
| What's New | 4,000 | Not available for a first version | From 1.0.1 on: the user-facing lines of that version's CHANGELOG entry, in plain sentences, no "bug fixes and improvements" filler |
| Support URL | | `https://nope.photivra.com/support/` | Must be live, with a way to make contact, before submission |
| Marketing URL | optional | `https://nope.photivra.com/` | Optional; add when the site's first page is live. Leave empty rather than point at a page that isn't there |
| Privacy policy URL | | `https://nope.photivra.com/privacy/` | Must be live before submission; the app's About screen opens the same address |
| Copyright | | Keep: "2026 Shackelford Creative, LLC" | |
| Primary category | | Photo & Video | |
| Secondary category | optional | Utilities | Decision 3. The app has no editing, social or entertainment side, so no other category fits |
| Age rating | | Every answer "None" or "No"; expected result 4+ | No web access, no user-generated content shared by the app, no messaging, no advertising, no bundled content. Answer the questionnaire from scratch in App Store Connect |
| Price | | Free, no in-app purchases | |
| Seller name | | Comes from the developer account, not from this repository | |

### 2.1 Promotional text

Current (167), keep for the first submission:

> Single-frame RAW with as little processing as the camera allows. Signing if you want it. No network connections, no analytics, and optional details removed by default.

Option B (155), with the tagline, after checks C1, C4 and C6 are recorded on a device:

> Processing? Nope. Tracking? Nope. Network? Nope. Single-frame RAW, no network connections, and optional details removed by default. Signing if you want it.

The tagline's "Processing? Nope." is followed at once by what is actually true ("single-frame
RAW"), and the description's first line keeps "as little processing as the camera allows". If
the tagline is used alone anywhere on the page, it sits next to that scoped sentence.

### 2.2 Description: proposed additions

Add each paragraph only when the check named after it is done. Each bullet is one sentence that
can be removed alone.

After FOR EVERYONE's place in the order, before it:

> MORE CONTROL WHEN YOU WANT IT
> • Manual Controls: set focus, shutter, ISO and white balance yourself, or leave any of them on auto.
> • Timer, Burst, Interval, Astro and Bracket. Every frame is saved as its own photo. The app never merges frames.
> • Night Mode turns the whole screen red on black.
> • Pinch to switch lenses. There is no digital zoom: the picture is never enlarged or cropped.

Checks: the manual controls device check; the per-lens bracket checks and the tag check on
series frames ("never merges"); the all-red pixel check for Night Mode; pinch tuning (#95). The
list of manual controls must match the readout row of the release build on the test device.
Night Mode is described by what it does (red on black); the text makes no claim about night
vision.

> ON IPHONE, IPAD AND APPLE WATCH
> • Open the camera from the Lock Screen, Control Center or the Action button.
> • On iPad, the app works in both orientations and in a window beside other apps.
> • The Apple Watch app is a remote shutter for the iPhone. It takes no photos itself.
> • Siri and Shortcuts can use the app only if you turn on Assistant Access. It is off by default.

Checks: the Lock Screen camera and controls on a device; the iPad pass on the iPad Air; Assistant
Access device checks (#82). The Apple Watch sentence states what the watch app is; see decision 9
on listing a watch app that has run only in the Simulator.

Also open from the honesty audit: the FOR EVERYONE line ("Designed to work with VoiceOver, Voice
Control and the largest text sizes") stays a design aim until the manual pass
([`accessibility-label.md`](accessibility-label.md)). Recommendation: do the pass before
submission; if it isn't done, remove that sentence and keep "The volume buttons work as a
shutter." (decision 11).

### 2.3 Keywords

Current (87): `raw,dng,privacy,metadata,exif,c2pa,signed,photo,no tracking,offline,open source,natural`

Proposed (98): `raw,dng,manual,astro,interval,bracket,burst,privacy,private,metadata,exif,c2pa,offline,open source`

- A keyword is a claim: someone who searches "astro" and finds the app is told it has an Astro
  mode. `manual`, `astro`, `interval`, `bracket` and `burst` go in only with the section 2.2
  paragraph they belong to. Until then keep the current list.
- Dropped: `natural` (a quality word), `signed` (covered by `c2pa`; "signed" alone invites the
  reading that a photo is proven), `photo` and `no tracking` (the subtitle and category already
  carry "photo" and "tracking"; whether search indexes them is unverified, so this is a judgment).
- Never: other apps' or companies' names, "pro", "best", "ai", "proraw" (the app never uses
  ProRAW, and a keyword can't say "not").

## 3. Screenshots: sizes and what to upload

| Device class | Upload | Capture source |
|---|---|---|
| iPhone | One set at 1320 × 2868 (portrait). No separate 6.5-inch set: Apple scales the large set down | iPhone 16 Pro Max (real device, native 1320 × 2868), or an iPhone Pro Max Simulator of the same size |
| iPad | One set at 2064 × 2752 (portrait) | iPad Pro 13-inch Simulator. The test iPad (iPad Air, 5th generation) is a smaller size, which Apple doesn't accept for the 13-inch set |
| Apple Watch | One set at 416 × 496 | Apple Watch Series 12 (46mm) Simulator, the one CI uses, with `-NopeSimulatedPhone` |
| iPhone Duo | None for 1.0.0 | Optional today as far as known (unverified); revisit when Apple's page is confirmed |

Portrait for iPhone and iPad: the camera's stacked layout is the one most people will see, and
one orientation per set keeps the row even. The iPad's sideways layout appears inside one iPad
screenshot (section 6).

Every image uses a clean status bar (`xcrun simctl status_bar <device> override --time 9:41
--batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`; on the device, a
screen recording or capture with Do Not Disturb on). The status bar must not show a carrier name.
Wi-Fi or cellular bars are part of the system status bar and say nothing about the app, so the
images use the standard bar, not Airplane Mode (decision 6).

## 4. Screenshot layout

One layout for all three device classes:

- Black ground. A caption band at the top: one line, Inter Semi Bold, white, sentence case, with a
  period. An optional second line in Inter Regular at 70% white for the scope ("Off by default.").
- Under it the captured screen, unscaled in proportion, with the device's corner radius and no
  device frame. No hands, no bezels, no badges, no stars, no "new".
- The first image also carries the wordmark lockup: "nope." large with "Photivra Nope Camera"
  beneath it (AGENTS.md).
- The captured screen is never edited: no moved controls, no removed warnings, no composited
  pictures except as section 5.2 allows.

Accessibility of the images:

- Caption text at least 4.5:1 against its ground (white on black is 21:1), and large: about
  1/32 of the image height for the main line (90 px in the iPhone upload), so it reads in the small search-result size.
- No information by color alone: the Night Mode image says "Night Mode" in the caption.
- As far as known (unverified) the App Store gives screenshots no alternative text, so **every
  caption's fact must also be a sentence in the description**, where VoiceOver reads it. The
  tables below name that sentence.
- No flashing or fast cuts in previews; respect the same rule the app follows for Reduce Motion.

## 5. What the pictures may show

### 5.1 The limits

- **The Simulator has no camera.** The simulated camera's preview is a gray brightness ramp, and
  its "photos" are placeholders. A Simulator capture of the camera screen therefore shows no
  scene. It must never be dressed up as one.
- **A viewfinder is not the photo.** The live picture is the device's preview stream, not the
  RAW. A caption over a viewfinder never says "this is what you get".
- **The Last Photo viewer shows a screen-size preview**, not the file. A caption over it never
  speaks of detail or quality.
- **A RAW opened in Photos is drawn by Photos.** The page never shows Photos' rendering as the
  app's result.
- **Astro:** a night sky appears only if it is a frame the maintainer took with the app's Astro
  mode on the named device. No star fields from elsewhere.
- **People and places:** no recognizable people, no house numbers, license plates or screens with
  personal content; no location shown in What's in This Photo unless the screenshot is about the
  Location switch, and then a public landmark only.

### 5.2 Three ways to fill the viewfinder (decision 4)

| | A. Device captures | B. Simulator with a real still | C. Simulator as it is |
|---|---|---|---|
| How | The maintainer captures each iPhone screen on the iPhone 16 Pro Max, in the release build | A Debug-only launch argument shows one still as the simulated preview; the still is a photo the maintainer took with the app, developed by the app, unedited | Screens captured with the gray ramp |
| Honest? | Yes: real app, real camera, real device | Yes, if the still is the app's own output and a footnote says so; the composite is in the preview only, never in a "result" | Yes, but shows no picture |
| Covers | iPhone only (the device's size is the required size) | iPhone, iPad 13-inch and every state a scenario can reach, repeatable for later languages | Everything |
| Cost | A capture session by hand; states like "no RAW on this lens" depend on the device | A small test-tooling change (Debug builds only; Release ignores the argument, like `-NopeSimulatedCamera`) plus 3 to 5 stills | None |
| Weakness | Not repeatable by script; iPad still needs B or C | Needs the stills and the tooling; the footnote must be on the page | The first image of a camera app has no picture |

**Recommendation: A for the iPhone set's camera screens and for the previews; B for the iPad set
and for iPhone states the device can't reach; C for screens with no viewfinder** (Settings,
Honesty, What's in This Photo text, Apple Watch). With B, the description's last line gains:
"Screenshots on iPad show photos taken with the app on an iPhone." Wording to be settled with
the stills in hand; it must name where the pictures came from and claim nothing about them.

The stills: 3 to 5 photos by the maintainer, taken with the app, of plain daylight subjects (a
street, a plant, a building, a table), one dim interior for the manual controls image and, only
if one exists, one Astro frame. HEIF copies developed by the app in the Standard look, as saved.
They become public on the page; the maintainer chooses them and decides whether the source files
are committed under `store/screenshots/source/` (they contain no optional details when saved with
the defaults; check each with What's in This Photo or `scripts/dump-tags.swift` first).

## 6. Screenshot storyboards

"Gate" names what must be recorded before the image is uploaded. "Says it in text" names the
description sentence that carries the same fact.

### 6.1 iPhone (8 images at submission, up to 10)

The first three carry the whole message for someone who sees only the search result: what it is,
what it doesn't do, and that the files are in the person's hands.

| # | Screen | Caption (second line) | Source | Gate | Says it in text |
|---|---|---|---|---|---|
| 1 | Camera, default state, wide lens: status line with the teal seal and "RAW", shutter, lens row. Wordmark lockup in the band | "RAW photos. No tracking." | A | C1, C4 | Description, first line |
| 2 | Settings › Honesty, top of the page: No Network, No Data Collected, Check It Yourself | "No network connections. No analytics. No accounts." ("Check it in App Privacy Report.") | C | C4; C5 for the second line | NOTHING TRACKS YOU, bullets 1 and 2 |
| 3 | What's in This Photo for a RAW with default details: the summary and its four lines | "See what is in each file." | A or C | C10, C6 | HONEST ABOUT THE LIMITS |
| 4 | Settings › Privacy › Details in Each Photo, with Remove All Optional Details on and Location off | "You choose what each photo keeps." ("Location is off by default.") | C | C6, C7 | NOTHING TRACKS YOU, bullets 3 and 4 |
| 5 | Camera on a lens without RAW: the amber "Processed" marker, with the processing note open at medium height | "If a lens can't save RAW, it says so." | A if the device has such a lens, else B | C2 | AS LITTLE PROCESSING, bullet 2 |
| 6 | Camera with Manual Controls on: the readout row and one dial open | "Manual controls when you want them." | A | Manual controls device check; section 2.2 paragraph in the description | MORE CONTROL, bullet 1 |
| 7 | Camera with the drive strip and the Interval card ("Every 10 seconds, 10 photos") | "Timer, Burst, Interval, Astro, Bracket." ("Every frame is its own photo.") | A | Series tag check; section 2.2 | MORE CONTROL, bullet 2 |
| 8 | Sign Each Photo in Settings with its footer, or What's in This Photo for a signed photo | "Sign each photo, if you choose." ("Off by default. A signature is not proof of who took a photo.") | C | C9 | SIGNED, IF YOU CHOOSE |
| 9 | Camera in Night Mode, Astro idle card | "Night Mode: red on black." | A | All-red pixel check; section 2.2 | MORE CONTROL, bullet 3 |
| 10 | The Lock Screen with the app's control, or Control Center with "Open nope." and Night Mode controls | "Open it from the Lock Screen or Control Center." | A (device only; the Simulator can't show these faithfully) | Lock Screen camera and controls device checks; section 2.2 | ON IPHONE, IPAD AND APPLE WATCH, bullet 1 |

Images 6, 7, 9 and 10 are left out of the first submission if their gates are open; the set
still reads whole with images 1 to 5 and 8. Image 10 shows system screens: capture them as they
are, with a plain wallpaper, and crop nothing.

Not shown, on purpose: Compare (the app's photo beside the phone-processed one invites a quality
reading the page can't support), any "before and after", and the first-run screen (its three
statements are already images 1, 2 and 8).

### 6.2 iPad (6 images)

| # | Screen | Caption | Source | Gate |
|---|---|---|---|---|
| 1 | Camera, portrait, default state. Wordmark lockup | "RAW photos. No tracking." | B | C1, C4; iPad pass on the iPad Air |
| 2 | Honesty, as iPhone 2 | Same as iPhone 2 | C | C4, C5 |
| 3 | What's in This Photo as a popover over the camera | "See what is in each file." | B or C | C10 |
| 4 | Details in Each Photo | "You choose what each photo keeps." | C | C6, C7 |
| 5 | The camera in a window beside another app (Split View), column layout | "Works in a window beside other apps." | B | iPad pass; section 2.2 bullet |
| 6 | Sign Each Photo, as iPhone 8 | Same as iPhone 8 | C | C9 |

If the iPad Air has no camera without RAW, no iPad image shows the "Processed" marker as a real
state; the iPhone set carries it. No iPad image shows a feature the iPad build doesn't offer on
that device.

### 6.3 Apple Watch (4 images, 416 × 496, no caption band)

Watch screenshots are the bare screen: at this size a caption band would be unreadable. The
order tells the story.

| # | Screen (`-NopeSimulatedPhone` scenario) | What it shows |
|---|---|---|
| 1 | Ready: Take Photo | The remote shutter |
| 2 | Countdown running | The timer started from the wrist |
| 3 | Result: "Saved, not signed" as plain status (signing off, the default) | What the watch reports after a photo, in the default setup |
| 4 | Camera not open on the iPhone | What the watch says when it can't take a photo: it is a remote, not a camera |

Image 3 uses the default-setup result rather than "Saved and signed", so the row matches what a
new user sees. Gate: decision 9.

## 7. App previews

Previews play without sound in the row, before the screenshots, so a preview becomes the first
thing seen. Recommendation: **one iPhone preview at submission (P1), only if it is recorded on
the device from the release build; otherwise none.** P2 and P3 follow when their gates close. No
iPad preview for 1.0.0 (the Simulator has no camera, and a real 13-inch iPad isn't among the test
devices). Apple's page lists no Apple Watch previews.

Rules for all three:

- Screen recordings of the app on the iPhone 16 Pro Max, exported at 886 × 1920, 30 frames a
  second, H.264, 15 to 30 seconds.
- Real time. No speeding up of saving, focusing or switching lenses; a cut between scenes is a
  plain crossfade so it reads as a cut, never as speed.
- Text cards use the screenshot caption style. No voice. The sound track is silence or the
  recording's own sound; no music that needs a license.
- The poster frame is the frame that matches screenshot 1.
- No finger overlays that aren't the system's; no device frame.

### P1. "Open it and shoot" (about 20 s) — gates: C1, C4, C10

| Time | On screen | Text card |
|---|---|---|
| 0–3 s | The launch mark on black, then the camera appears: status line "RAW", a daylight scene | "RAW photos. No tracking." |
| 3–8 s | One press of the shutter. The capture feedback, then the result line as the app shows it with default settings | none |
| 8–13 s | Tap Last Photo: the viewer opens on the photo. Tap Photo Details: What's in This Photo, the summary | "See what is in each file." |
| 13–18 s | Scroll the sheet once, slowly, to the optional details group | "Optional details are removed by default." |
| 18–20 s | Close to the camera. Hold | Wordmark lockup |

### P2. "What each photo keeps" (about 25 s) — gates: C4 to C9

| Time | On screen | Text card |
|---|---|---|
| 0–4 s | Camera. Open Q, tap Settings | "You choose what each photo keeps." |
| 4–11 s | Privacy › Details in Each Photo: Remove All Optional Details on; turn it off, the items appear, turn it on again | none |
| 11–16 s | Location row: off | "Location is off by default." |
| 16–22 s | Honesty: No Network, No Data Collected, Check It Yourself | "No network connections. No analytics. No accounts." |
| 22–25 s | Sign Each Photo: off, with its footer in view | "Signing is your choice." |

### P3. "More control when you want it" (about 25 s) — gates: the section 2.2 checks

| Time | On screen | Text card |
|---|---|---|
| 0–5 s | Camera in full auto. Tap Manual Controls: the readout row appears | "Manual controls when you want them." |
| 5–11 s | Open one dial, turn it, close it | none |
| 11–17 s | Drive strip: Single to Interval; the card shows the plan; back to Single | "Timer, Burst, Interval, Astro, Bracket." |
| 17–22 s | Q › Night Mode: the screen turns red on black | "Night Mode: red on black." |
| 22–25 s | Hold on the red camera | Wordmark lockup |

P3 shows no series running to its end and no Astro result: a 20-second clip can't show one
without cutting time.

## 8. Custom product pages

Up to 70 are allowed; the useful number is small. A custom page is worth making only when there
is a link that leads to it (a page of the site, the README) or a keyword set it should answer,
and only if its promise is one the app keeps for that audience. None is needed for submission;
each can be added later without a new build.

| Page | Audience | What changes | Honest? | Recommendation |
|---|---|---|---|---|
| RAW and manual | Photographers who look for a RAW or manual camera | Screenshot order 1, 6, 7, 5, 9, 3; preview P3; promotional text about single-frame RAW and manual controls; keywords `raw,dng,manual` | Yes, when the section 2.2 gates are closed | **Make it second,** after those checks |
| Privacy | People who look for a camera without tracking | Order 2, 4, 3, 1, 8; preview P2; promotional text from C4 to C8; keywords `privacy,private,metadata,exif,offline` | Yes, on C4 to C8 | **Make it first,** once the site has a page that links to it |
| Open source | Developers who arrive from the repository | Same images as the default; promotional text "Free and open source under the GNU GPL, version 3." | Yes (C12) | Optional; the default page already says it |
| Astro | Night-sky photographers | Would need real Astro frames and a statement of what Astro mode does and doesn't do (single frames, never stacked) | Only with real frames from the device; a stacking audience may expect merged results the app never makes | **Not for 1.0.0** |
| Accessibility | People who use assistive technology | Images at the largest text size, VoiceOver named in captions | Only after the Nutrition Labels are declared with their evidence | **Not until the labels are declared** |
| Reporters, proof of authenticity | Newsrooms, fact-checkers | Would lead with signing | **No.** A self-signed Content Credential is not proof of who took a photo or that it is real; a page aimed at this audience would promise what the signature can't give | **Don't make it** |

A custom page's deep link is not used: the app registers no address that opens a given screen,
and adding one is a new feature, outside 1.0.0.

## 9. Not used for 1.0.0

- **Pre-order:** not used (maintainer's decision, 2026-11-19).
- **Product Page Optimization** (tests of the icon, screenshots or previews): not used for 1.0.0
  (maintainer's decision, 2026-11-19). No alternate icons or screenshot sets are planned. It can
  be looked at again once the page has had steady traffic for some months.
- **In-App Events:** not used (maintainer's decision, 2026-11-19).

## 10. Accessibility Nutrition Labels

The answers, the common tasks and the evidence each answer needs are in
[`accessibility-label.md`](accessibility-label.md). For the page:

- **Nothing is declared until its evidence column is complete on that device.** A device left
  unanswered shows as not yet indicated, which is true; a wrong "Yes" is not.
- **iPhone:** all seven applicable features (VoiceOver, Voice Control, Larger Text, Dark
  Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion) can be
  declared after one manual pass of tasks 1 to 5 on the iPhone 16 Pro Max with each setting on.
  Captions and Audio Descriptions don't apply.
- **iPad:** the same, after the same pass on the iPad Air. Until then, undeclared for iPad.
- **Apple Watch:** undeclared for 1.0.0. The watch app has UI tests with audits in the Simulator,
  but no manual pass on a watch is possible with the test devices.
- **Accessibility URL:** optional. When the pass is done, publish a short page
  (`https://nope.photivra.com/accessibility/`) with: what was checked on which device, how to use
  the volume buttons and Camera Control as a shutter, that pinch has a button equivalent, and
  what isn't declared yet (iPad or Apple Watch) and why. Until that page exists, leave the field
  empty.
- The description's FOR EVERYONE sentence and the labels must agree: see decision 11.

## 11. App Privacy and the privacy manifests

- **Label:** "Data Not Collected", as in [`app-privacy-label.md`](app-privacy-label.md), entered
  only after audit check 8 (no connection at run time) is recorded for the release build.
- **Four manifests must agree with it:** `App/NopeApp/PrivacyInfo.xcprivacy`,
  `App/NopeCaptureExtension/PrivacyInfo.xcprivacy`, `App/NopeControls/PrivacyInfo.xcprivacy` and
  `App/NopeWatch/PrivacyInfo.xcprivacy`: tracking false, no tracking domains, no collected data
  types, and only the required-reason API entries each target uses. The app's manifest declares
  three categories today (user defaults, system boot time, disk space); `docs/PRIVACY.md` lists
  the same three. Recheck all four against the archive's privacy report (Xcode, Organizer,
  "Generate Privacy Report") before upload.
- **The same facts in five places:** the label, the manifests, the privacy policy page, the
  description's NOTHING TRACKS YOU section and the Honesty screen. A change to one is a change to
  all five in the same pull request.
- **Privacy policy URL** must answer before submission; **Privacy Choices URL** stays empty.
- **The page itself:** screenshots and previews show no personal data (section 5.1).

## 12. Ratings and reviews

Decided (maintainer, 2026-11-19): **the app never shows a rating prompt or popup.** It doesn't
use StoreKit's review request at all. The About screen gets one plain row, "Rate or Review", that
opens the App Store's write-review page only when the person taps it.

Why no prompt: it interrupts a camera; it is drawn by the system and reaches the App Store over
the network, in an app whose page says it makes no network connections; and it would add
StoreKit to a build that is checked for networking code. The row has none of these costs: it is
a link, like the two the About screen has now.

### 12.1 The Rate or Review row

| | Design |
|---|---|
| Place | Settings › About, the last section, after Source Code. Last because it is the least needed row on the screen; it is never moved up, pinned or repeated elsewhere (not in Q, not on the camera, not on Honesty) |
| Section header | "App Store" |
| Row | "Rate or Review". A link row drawn like the Privacy Policy row, with the same link styling and no symbol, badge, stars, count or color of its own |
| Footer | "Opens the App Store. Ratings and reviews there are public." |
| Action | Hands `https://apps.apple.com/app/id<App Store ID>?action=write-review` to the system, which opens the App Store. The app fetches nothing and learns nothing about what the person does there, including whether they rate at all |
| Never | No prompt, alert, tip, banner, red dot or "new" marker; no reminder after a number of photos or days; no wording that asks ("Enjoying the app?", "Please", "Help us"); nothing stored about whether the row was tapped |
| VoiceOver | Label "Rate or Review"; hint "Opens the App Store."; the link trait. No value: the address tells a listener nothing the hint doesn't |
| Voice Control | "Tap Rate or Review" (the visible name) |
| Larger Text | The row wraps; the footer wraps; no truncation at the largest accessibility size |
| Night Mode | Red on black like the rest of About: the row's text takes the same red treatment as the other two link rows, with no system blue. The App Store itself is not red; the footer already says the row leaves the app |
| iPad | The same row in the same place, in Settings' sheet or column. The App Store opens as the system decides (full screen, or beside the app in a window); the app stays as it was |
| Lock Screen camera | Only where About is offered there. A link from the locked camera needs the device unlocked first, as for the other two links (to confirm on a device) |
| Settings search | Found by "rate", "review", "rating", "feedback", "App Store". Not "stars", which finds Astro (maintainer's decision, 2026-11-19) |
| Right to left | Leading and trailing as the other rows; nothing to mirror |
| Strings | "App Store" (header; a name, not translated), "Rate or Review", "Opens the App Store. Ratings and reviews there are public.", "Opens the App Store." (hint), in the string catalog with translator comments. US English |

The wording is a label, not a request. "Rate or Review" names both things the page offers;
"Reviews there are public" is the one fact a person should know before writing one.

### 12.2 The App Store ID

The address needs the app's numeric App Store ID, which exists once the app's record is created
in App Store Connect (App Information, "Apple ID"). It is not secret.

- `AboutScreen.appStoreID` holds it; `rateAddress` and `rateURL` are built from it, next to
  `privacyPolicyURL` and `sourceURL`.
- Until the id is set, the row and its section are not shown: no dead link ships. A release
  check fails if a Release build has no id.
- The form of the address (`?action=write-review`) is unverified here until it can be opened for
  a live app; confirm on the device after the first release, and on a TestFlight build note that
  the App Store doesn't take reviews for it.

### 12.3 Tests and documents that change with the row

In the pull request that builds it:

- Unit tests: the address is `https`, host `apps.apple.com`, path `/app/id` plus digits, query
  `action=write-review`; the row is hidden with no id. UI tests with audits: the row, its footer
  and hint, at the largest text size, in Night Mode (the all-red pixel check on About), right to
  left and on iPad. The Simulator has no App Store, so opening it is a device check.
- [`../SECURITY_AUDIT.md`](../SECURITY_AUDIT.md), check 7: the allowed hits become three links on
  the About screen (the privacy policy, the source code, and the App Store write-review page).
- `docs/PRIVACY.md` ("Links: two, on the About screen"), the privacy policy draft ("Two links in
  the app ... open in your web browser") and the App Review notes in [`README.md`](README.md)
  ("The two links in the app") become three, and say that the third opens the App Store.
- `docs/design/settings.html` and its About figure, `docs/design/ACCESSIBILITY.md`, and the
  common tasks in [`accessibility-label.md`](accessibility-label.md) (About is part of settings).
- Audit check 8 on a device: tapping the row must add no domain under the app in App Privacy
  Report (the App Store's own activity is the App Store's).

### 12.4 Outside the app

- The site's support page and the README may carry the same link.
- **Answer reviews** in App Store Connect: plainly, with the fix or the limit, never with a
  request to change a rating. A review that reports a false statement in the app is handled as a
  bug.

## 13. Apple Watch, iPad and system features on the page

| Subject | Where it shows | Condition |
|---|---|---|
| iPad | Its own 13-inch screenshot set (6.2); one description bullet; no "iPad" in the subtitle or keywords (the store already lists the device) | The iPad pass on the iPad Air |
| Apple Watch | Its own screenshot set (6.3); one description bullet that says it is a remote shutter and takes no photos | Decision 9 |
| Lock Screen camera, Control Center controls, Action button | iPhone screenshot 10; one description bullet | Device checks of the Lock Screen camera and both controls |
| Camera Control and volume buttons as a shutter | The FOR EVERYONE sentence already names the volume buttons; add "and Camera Control" after one press is recorded on the device | Device check |
| Siri and Shortcuts | One description bullet that leads with "only if you turn on Assistant Access" | #82 device checks. Never a screenshot of Siri: the page must not suggest an assistant is part of the default app |
| Live Activity and Dynamic Island for a running series | Not on the page for 1.0.0 | Could join screenshot 7's second line after the device check; low value |
| AirPods as a remote shutter | Not on the page | "Pending verification on a device" in the CHANGELOG |
| iPhone Duo | Not on the page for 1.0.0 | Tested in the Simulator only |

## 14. Featuring nomination and localization

### Featuring nomination

Sent by the maintainer from App Store Connect (Featuring › Nominations). Apple asks for at least
two weeks' notice.

- **What to send:** a nomination for the new app, with: one paragraph on what it is (the
  description's first line and the three section titles); what is unusual about it (no network
  connections; single-frame RAW with a clear label when a lens can't save one; open source;
  the Honesty screen, which states the app's own limits); the Apple technologies it uses
  (the Lock Screen camera, Control Center controls, App Intents with an off-by-default access
  switch, Live Activities, the Apple Watch remote, Camera Control); accessibility work, with the
  declared Nutrition Labels; the expected release date; the product page link.
- **What not to send:** anything the page itself can't say (section 1).
- **When:** the app is released as soon as the build is approved, and the nomination is sent the
  same day, accepting that the notice is shorter than Apple asks for (decision 12).
- A second nomination fits a later release that adds languages, since localization is one of the
  things Apple's editors name.
- If Apple asks for promotional artwork, it is made from the brand files in `docs/design/` and
  committed there.

### Localization

- 1.0.0 lists English (U.S.) only. Its text and images are what every storefront shows.
- Spanish (`es-ES`, `es-MX`) comes with the Spanish strings (#87). Every language added later
  needs, in the same pull request as its strings (AGENTS.md, "Localization"): the five text files
  in `store/metadata/<locale>/`, caption strings for every screenshot and preview card, and a
  native-speaker review of all of them. Translations claim no more than the English.
- To make that cheap: captions are never baked into a master image. Each caption is a string in
  `store/screenshots/captions/<locale>.json`, keyed by image number; captures are taken per
  language with `-AppleLanguages`; the layout step sets the caption over the capture. Caption
  bands leave room for text half again as long as the English.
- The Apple Watch size chosen now (416 × 496) is the size for every later language.
- A custom product page is localized only when its default-page language is.

## 15. Assets to produce, and the App Store Connect steps

### 15.1 Assets

| # | Asset | Count | Made by | How |
|---|---|---|---|---|
| 1 | Source stills for the viewfinder (5.2) | 3 to 5 | Maintainer, iPhone 16 Pro Max | Taken with the release build, default settings plus a HEIF copy; checked with What's in This Photo |
| 2 | iPhone camera-screen captures (6.1: 1, 5, 6, 7, 9, 10; 3 optional) | 6 to 7 | Maintainer, device | Release build; side button and volume up, or a screen recording frame; Do Not Disturb on. A written shot list with the exact state of each |
| 3 | iPhone settings and sheet captures (6.1: 2, 3, 4, 8) | 4 | Script, Simulator | A UI test class that only navigates and saves an attachment, launched with `-NopeSimulatedCamera allow` and the `-NopeSettings.*` arguments the existing UI tests use; `simctl status_bar` override; iPhone Pro Max Simulator at 1320 × 2868 |
| 4 | iPad captures (6.2) | 6 | Script, iPad Pro 13-inch Simulator | As 3; images 1, 3 and 5 need the still of option B |
| 5 | Apple Watch captures (6.3) | 4 | Script, Apple Watch Series 12 (46mm) Simulator | `-NopeSimulatedPhone` scenarios, through `scripts/run-watch-ui-tests.sh`'s setup |
| 6 | Caption strings | 1 file | Agent, reviewed by maintainer | `store/screenshots/captions/en-US.json` |
| 7 | Layout step: capture plus caption to the upload size | 1 script | Agent | A script that draws the band with Inter and writes PNGs without an alpha channel to `store/screenshots/en-US/<device>/NN.png`; checks size, no alpha, caption contrast |
| 8 | Layout mockups of every image, before any capture | 20 | Done 2026-11-19 | HTML and PNG in `docs/design/screens/store-*`, gathered in [`docs/design/store.html`](../design/store.html); every place for a real picture is marked as a placeholder |
| 9 | Preview P1 (P2, P3 later) | 1 to 3 | Maintainer records; agent edits | Screen recording on the device; cut list from section 7; export 886 × 1920 H.264 |
| 10 | Support page and privacy page on the site | 2 | Maintainer | Privacy from `privacy-policy-draft.md`; support with a contact |
| 11 | Accessibility page | 1 | Maintainer, after the pass | Section 10 |

Simulator captures come from Debug builds, because only Debug honors the simulated camera. The
screens they show (Settings, sheets, the watch) are the same views the release build draws; the
pull request that adds the script says so, and no Debug-only element (a debug menu, a test
banner) may be in frame.

Option B's still preview (5.2) is the only code change this plan asks for. It is test tooling in
`App/NopeApp/DebugTools/`, compiled in Debug only.

### 15.2 The maintainer, in App Store Connect

In order. Steps 1 to 9 can be done before the build is ready.

1. App Information: name, subtitle, primary and secondary category, content rights, age rating
   questionnaire.
2. App Privacy: the answers in `app-privacy-label.md`; the privacy policy URL.
3. Pricing and Availability: free; storefronts.
4. Version 1.0.0: promotional text, description, keywords, support URL, marketing URL, copyright
   (from `store/metadata/en-US/`, after the decisions below are applied to those files in a pull
   request).
5. Screenshots: iPhone (large Dynamic Island size), iPad 13-inch, Apple Watch. App preview P1 if
   recorded; choose its poster frame.
6. Accessibility: declare, per device, only the features whose evidence is complete; the
   Accessibility URL if the page exists.
7. App Review Information: the notes in `README.md`, "App Review notes"; contact details.
8. Export compliance: as in `README.md`.
9. Featuring › Nominations: section 14.
10. Add the build, choose release on approval (decision 12), submit.
11. After approval: read the live page on an iPhone, an iPad and the watch tab against this plan
    and the claim table; fix anything that differs before release.
12. After release: answer reviews; update the promotional text only when a release changes what
    the app does; add custom product pages (section 8) when their links exist.

## 16. Decisions

All seventeen were decided by the maintainer on 2026-11-19, each as recommended.

| # | Decision | Decided (2026-11-19) |
|---|---|---|
| 1 | This plan as the page plan for 1.0.0 | Accepted |
| 2 | Subtitle | Keep "RAW photos. No tracking." |
| 3 | Secondary category | Utilities |
| 4 | How the viewfinder is filled (5.2) | A (device captures) for iPhone camera screens and previews; B (a still taken with the app, in the Simulator) for iPad and for iPhone states the device can't reach; C (the Simulator as it is) where no viewfinder shows. The footnote sentence goes into the description with B |
| 5 | Source stills | Committed under `store/screenshots/source/`, after each file's details are checked |
| 6 | Status bar in images | The standard clean bar, not Airplane Mode |
| 7 | Promotional text | Keep the current text for submission; change to option B (2.1) after C1, C4 and C6 are recorded on a device |
| 8 | The Rate or Review row (section 12) | In 1.0.0 if the app's App Store ID exists before the release build is cut; otherwise in the next release. The row is hidden without an id |
| 9 | Apple Watch on the page | The watch screenshot set and one plain sentence ("remote shutter"); the watch's accessibility labels stay undeclared |
| 10 | App preview at submission | P1 only, and only if it is recorded on the device from the release build; otherwise none |
| 11 | The "Designed to work with VoiceOver, Voice Control and the largest text sizes" sentence | The manual pass is done on the iPhone before submission and the labels are declared; if the pass isn't done, the sentence is removed and nothing is declared |
| 12 | Featuring | Release on approval and nominate the same day |
| 13 | Description additions and keywords (2.2, 2.3) | Each paragraph and its keywords are added only as its checks are recorded; the submission doesn't wait for them |
| 14 | Custom product pages | None at submission. Privacy first, then RAW and manual, when the site has pages that link to them. Never the "proof" page |
| 15 | iPad Nutrition Labels | Declared only after the pass on the iPad Air |
| 16 | Marketing URL | Empty until the site's first page is live |
| 17 | Layout mockups before any capture | Yes; drawn 2026-11-19 ([`docs/design/store.html`](../design/store.html)) |

Also decided on 2026-11-19: no Product Page Optimization tests, no In-App Events and no
pre-order (section 9); no rating prompt or popup, and a Rate or Review row on the About screen
(section 12).
