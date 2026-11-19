# The public site: nope.photivra.com

Status: **proposal, 2026-11-19, for release 1.0.0. Needs the maintainer's decisions (section 16).** This page designs a small public site for Photivra Nope Camera, served by GitHub Pages at `https://nope.photivra.com/`. It is a design and a build specification. No site code is part of this change, nothing is published, and no repository setting is changed by it.

The figures are in [nope-site.html](nope-site.html) and `screens/site-*`. Every piece of copy below is a **draft for the maintainer's wording review**; the privacy page is [the policy draft](../store/privacy-policy-draft.md) as it will be published.

Contents: 1. Summary · 2. Rules the site follows · 3. Structure and addresses · 4. The landing page · 5. The privacy page · 6. The support page · 7. Not found · 8. Visual design · 9. Accessibility · 10. Search and sharing · 11. Performance · 12. Security and privacy of the site · 13. Keeping the site true · 14. Build, checks and publishing · 15. What the maintainer does · 16. Decisions for the maintainer · 17. Sources and what is unverified

## 1. Summary

- **Three pages and a not-found page:** `/` (what the app does, screenshots, the App Store link), `/privacy/` (the privacy policy, the address the app's About screen already opens) and `/support/` (how to get help; the store's support URL). `/accessibility/` and `/press/` are left for later (section 3).
- **The site keeps the app's rules.** No cookies, no analytics, no JavaScript, no third-party fonts, scripts or content delivery networks, and no request to any other site. Every file is served from `nope.photivra.com`. A Content-Security-Policy in each page enforces it, and a check fails the build if it stops being true.
- **The site says nothing the app's own text doesn't.** The landing page's statements are the App Store description, word for word, taken from `store/metadata/en-US/description.txt` at build time. The privacy page is built from the one policy file. The screenshots are the store's captures with the store's captions.
- **It is built from the repository and published by a workflow** on each release tag and on demand: static files in `site/`, Tailwind CSS compiled at build time, checks before every deploy.
- **It must be live before the app is submitted**, because App Review opens the privacy and support addresses. Until the app is on the App Store, the landing page shows no badge and says so (figure `site-home-before`).

## 2. Rules the site follows

1. **No tracking of any kind.** No cookies, no local storage, no analytics, no beacons, no fingerprinting, no embedded third-party content.
2. **No external requests.** A page load asks `nope.photivra.com` for files and nothing else. Links to other sites are plain links that a person chooses to follow.
3. **No JavaScript.** Not "works without": there is none. The one `<script>` element allowed is the `application/ld+json` data block of section 10, which browsers don't run.
4. **Only shipped, checked features are described** ([`docs/store/README.md`](../store/README.md), claims C1 to C12). A sentence whose claim is not recorded as checked is not on the site. No "tested" or "verified" on the landing page, and no quality claims.
5. **Names** follow AGENTS.md, "Name and wordmark": "Photivra Nope Camera" in text, "nope." only as the wordmark and in quoted interface text. The tagline is used whole and always with the scoped sentence under it (section 4).
6. **Fonts:** Inter (SIL OFL 1.1), self-hosted. No Apple system font in the wordmark, the social image or any artwork.
7. **English (U.S.) only** for 1.0.0, US spelling, `lang="en-US"`.
8. **Apple's marketing rules** for the badge, product names and screenshots (section 4.3).
9. **The README stays the contributors' front door.** The site is for people who use the app; it links to the repository for the source, and the README links to the site.

## 3. Structure and addresses

| Address | Page | In the sitemap | Needed by |
|---|---|---|---|
| `https://nope.photivra.com/` | Landing page | Yes | The store's marketing URL (optional field) |
| `https://nope.photivra.com/privacy/` | Privacy policy | Yes | The app's About screen; the store's privacy policy URL |
| `https://nope.photivra.com/support/` | Support | Yes | The store's support URL |
| `https://nope.photivra.com/404.html` | Not found | No (`noindex`) | GitHub Pages serves it for unknown addresses |
| `/sitemap.xml`, `/robots.txt` | Generated at build | | Search engines |
| `/.well-known/security.txt` | Points to private vulnerability reporting (RFC 9116) | | Optional (decision 21) |

Every page address ends in a slash and is the page's one canonical address. The two legal and support addresses are already written into the app and its tests; they never move.

**Not built for 1.0.0, with the reason:**

- **`/accessibility/`.** The store plan (`docs/store/STORE-PAGE-PLAN.md`, section 10, on branch `design-store-page`) proposes this page as the optional Accessibility URL, published when the manual pass is done and the Accessibility Nutrition Labels are declared. Until then a page would describe what isn't yet checked. The support page carries the "report a barrier" paragraph meanwhile.
- **`/press/`.** The wordmark file isn't in the repository yet ([TRADEMARKS.md](../../TRADEMARKS.md)), and the brand files aren't under the GPL. A press page waits for a decision on what may be downloaded and on what terms.
- **Pages for custom product pages** (store plan, section 8). Added with those pages, each from the same claim table.

## 4. The landing page

Figures: `site-home` (dark), `site-home-light`, `site-home-phone`, `site-home-large-text`, `site-home-before`.

### 4.1 Outline, top to bottom

| # | Section | Content | Source of the words |
|---|---|---|---|
| 1 | Header | The app icon's mark, "Photivra Nope Camera", and three links: Privacy, Support, Source code | |
| 2 | Hero, on black in both themes | The wordmark lockup ("nope." with "Photivra Nope Camera" beneath, the page's one `h1`); the tagline; one scoped sentence; the App Store badge, or the "not yet" note; screenshot 1 | The lockup and tagline: AGENTS.md. The sentence: the first line of `description.txt` |
| 3 | What it does, and what it doesn't | Five groups of statements | `description.txt`, word for word (section 13) |
| 4 | What it looks like | Four screenshots with captions, and one line saying where they were captured | The store's captures and caption strings |
| 5 | This site keeps the same rules | No cookies, analytics or JavaScript; who hosts it and what the host receives; how to check | Draft below |
| 6 | What you need | Devices in short, with a link to the full list on Support; open source, with the link | README, "Requirements" and "Languages"; the last line of `description.txt` |
| 7 | Footer | Links; the app version and the commit the site was built from; copyright and trademarks; Apple's credit lines; the DNG notice | `NOTICE`, `TRADEMARKS.md`; Apple's guidelines |

### 4.2 Draft copy

> **nope.**
> Photivra Nope Camera
>
> Processing? Nope. Tracking? Nope. Network? Nope.
>
> Photivra Nope Camera takes photos with as little processing as the camera allows, can sign each one, and keeps nothing that tracks you. Open it and shoot: there's nothing to set up.
>
> *(badge)* For iPhone and iPad. Free and open source.

The tagline's "Processing? Nope." alone reads as "no processing", which the app never claims. On this page it is always followed at once by "as little processing as the camera allows", the same rule the store plan sets for the promotional text.

Before the app is on the App Store (figure `site-home-before`):

> **Not on the App Store yet.** This page will link to the App Store when Photivra Nope Camera is available there. The source code is public now.

Section 3 shows the description's groups under sentence-case headings ("As little processing as the camera allows", "Nothing tracks you", "Signed, if you choose", "Honest about the limits", "For everyone"), with the line "The same statements as the App Store description, word for word." A group is shown only while its sentences are in `description.txt`; if the "For everyone" sentence is removed from the listing (store plan, decision 11), it leaves this page in the same build.

Section 5:

> **This site keeps the same rules**
>
> No cookies. No analytics. No JavaScript. Every file on these pages comes from nope.photivra.com, and nothing is loaded from another site.
>
> The site is hosted on GitHub Pages. Like any web host, GitHub receives your IP address when you load a page, and it logs that address for security. GitHub's privacy statement covers it.
>
> Check it yourself: your browser's network inspector shows every request a page makes, and the site's files are in the public repository.

Section 6, devices in short: "iPhone 11 or later, or iPhone SE (2nd generation) or later, with iOS 26 or later. iPad models that run iPadOS 26 or later. The Apple Watch app is a remote shutter. It takes no photos itself. English only in version 1.0.0." The Apple Watch line stays only if the watch app ships in 1.0.0 (store plan, decision 9).

Footer:

> Photivra Nope Camera 1.0.0. This site was built from the public source at commit *(short commit, linked)*. It sets no cookies, runs no JavaScript and loads nothing from other sites.
>
> An app from Photivra *(link to photivra.com)*. © 2026 Shackelford Creative, LLC. Photivra, Nope Camera, "nope." and the app icon are trademarks of Shackelford Creative, LLC. The source code is free software under the GNU General Public License, version 3.
>
> Apple, the Apple logo, iPhone, iPad and Apple Watch are trademarks of Apple Inc., registered in the U.S. and other countries and regions. App Store is a service mark of Apple Inc. This product includes DNG technology under license by Adobe.

The Apple credit line lists only the Apple names the built pages use, appears once on each page, and its exact form is re-read against Apple's guidelines when the page is built. "Apple Watch" leaves the line if the watch sentence leaves the page.

### 4.3 The App Store badge

From Apple's App Store Marketing Guidelines, read 2026-11-19 (section 17):

- Use Apple's own artwork, unchanged: not redrawn, recolored, angled or animated. The figures show a dashed placeholder because the artwork isn't drawn here.
- The preferred black badge. The hero is black, so the badge's gray outline separates it from the ground, as Apple's artwork intends.
- One badge on the page. It sits under the wordmark and the sentence, never larger than them.
- At least 40 px high on screen; clear space of one quarter of its height on every side.
- The U.S. English badge. It links to the app's App Store page.
- The page credits "Apple" and "the Apple logo" when the badge is shown (the footer line above).
- The badge file is Apple's. It is self-hosted (no request to Apple), kept as Apple supplies it, and listed in `THIRD_PARTY.md` and `TRADEMARKS.md` as Apple's artwork under Apple's terms, not under the GPL. The maintainer downloads it from Apple's marketing resources; an agent doesn't fetch or recreate it.
- **The badge and its link appear only when the app can be downloaded.** A value in `site/site.json` (`appStoreId`, and `available: true`) turns it on; with either missing the page shows the "not yet" note. The id exists once the app's record is created, before the app is available, so the id alone doesn't turn the badge on. The same id is the one `AboutScreen.appStoreID` would hold (store plan, section 12.2); the build checks the two agree when both exist.
- No Smart App Banner (`apple-itunes-app` meta tag) for 1.0.0: it is drawn by Safari with data Safari fetches from Apple, so it would be the one thing on the page that causes a request the page didn't serve (decision 9).

Other rules from the same guidelines that the copy follows: "Photivra Nope Camera for iPhone and iPad", never "iPhone app"; product names are singular and never translated; "on the App Store"; list only the Apple products the app runs on. Apple asks marketing copy to avoid "iOS"; the landing page uses it only in the requirement line, where the version number needs it, as the listing does by the maintainer's decision of 2026-11-12.

### 4.4 Screenshots

The site uses **the store's screenshot set**, not a second one: the same captures, the same captions, the same gates (`docs/store/STORE-PAGE-PLAN.md`, sections 4 to 6).

- **Which:** image 1 (the camera, default state) in the hero; images 2 (Honesty), 3 (What's in This Photo), 4 (Details in Each Photo) and 8 (Sign Each Photo) below. Images whose gates are open at submission are not on the site either.
- **Form:** the captured screen alone, unedited, with rounded corners and no device frame. No Apple product image, so Apple's bezel rules don't come into play. The caption is real text under the image (`figcaption`), not drawn into it, taken from the store's caption strings (`store/screenshots/captions/en-US.json` in the store plan).
- **Source and labeling:** camera screens are captures from the maintainer's iPhone in the release build (the store plan's source A); screens without a viewfinder are Simulator captures (source C). One line under the row says so: "Screens of Photivra Nope Camera 1.0.0, unedited. The camera screens were captured on an iPhone 16 Pro Max. The others were captured in Apple's Simulator, which has no camera." If the store plan's source B is used for any image shown here (a still shown in the Simulator's viewfinder), the line names it the same way the listing does.
- **No photos as results.** The site shows screens of the app, never a gallery of "photos taken with the app", so it makes no claim about how a photo looks.
- **Alternative text** for each image states the same fact as its caption and names the screen, for example: "The camera screen of Photivra Nope Camera. The status line reads RAW." The alt text never says more than the caption's claim allows.
- **Until captures exist,** the page is published without the screenshot sections rather than with drawings from `docs/design/screens/`: those are mockups, not the app.

## 5. The privacy page

Figures: `site-privacy`, `site-privacy-dark`, `site-privacy-print`.

- **The text is `docs/store/privacy-policy-draft.md`,** everything under its draft notice, converted to HTML by the build. There is no second copy to edit (section 13). When the maintainer publishes it, the file drops "draft" from its name and notice in the same change, and the bracketed items are filled. **The build fails while any `[bracketed]` item or the word "DRAFT" remains,** so an unfinished policy can't be published.
- **Top of the page:** the title (`h1`), then a small table: **Effective date**, **Last updated**, **App version**. The effective date and app version are the ones the policy file states. "Last updated" is a date written in the policy file, and the build fails if the file's text changed after that date without the date changing.
- **"On this page"**: a list of links to each heading. Headings have stable anchors (`#what-we-collect`), so the app, the store notes and support answers can point at a section.
- **Layout:** one column, at most 44rem wide (about 70 characters a line), body text 17 px, headings two steps larger, lists as lists. No decoration.
- **Print:** black on white, the header links, the contents list and the footer links removed, the page address and the three dates in a line under the title, link addresses printed after the link text, headings kept with the paragraph that follows. Checked in the browser's print preview at Letter and A4.
- **One addition the policy needs** before the site is live: today it says it "doesn't cover the Photivra website". This site is where the policy is read, and its host logs IP addresses, so the policy should say so itself. Draft for the maintainer, as a section before "Children":

> ## This website
>
> This policy is published at nope.photivra.com. The site uses no cookies, no analytics and no JavaScript, and loads nothing from other sites. It is hosted on GitHub Pages: when you load a page, GitHub receives your IP address and logs it for security, under GitHub's privacy statement.

  And "It doesn't cover the Photivra website" becomes "It doesn't cover photivra.com", so the two sites aren't confused. If an email address is added (section 6), the "Contact" section changes with it.

## 6. The support page

Figures: `site-support`, `site-support-dark`.

### 6.1 How a person gets help: the options

| | A. GitHub issues only | B. Issues and an email address | C. A form |
|---|---|---|---|
| What the person needs | A GitHub account | Nothing for email | Nothing |
| What becomes known, and to whom | Their GitHub name and what they write, to everyone | Their email address and message, to the maintainer and both mail providers | Whatever the form asks, to the maintainer and the form's service |
| Effect on the site's rules | None: a plain link | None: a plain `mailto:` link | Breaks them: a form needs a server or a third-party service, and usually JavaScript |
| Effect on the app's statements | None | The policy's "There is no contact email" changes; the policy says what is received by email and what it is used for. The app still collects nothing | The policy would have to describe the form's service |
| Risk | App Review asks that the support address lead to an easy way to make contact; an account wall may not count as easy, and it shuts out people who won't make an account | Unwanted mail; an address to keep answered | Not acceptable under section 2 |

**Recommendation: B.** GitHub issues stay the first way for bugs, and an email address at the project's domain is offered beside it, as a plain `mailto:` link with no script around it. The page says plainly what each way reveals. The address is an alias chosen by the maintainer; it is not written in this repository until the maintainer adds it. If the maintainer prefers A, the page ships without the email block and the policy's contact section stays as it is.

### 6.2 Outline and draft copy

> # Support
>
> Photivra Nope Camera has no accounts and makes no network connections, so it can't send us a report, and we can't see what happened on your device. To get help, write to us in one of these ways.
>
> ## Get help
>
> **Report a problem or ask a question.** Open an issue on GitHub. You need a free GitHub account. Issues are public. Don't include personal information, and attach a photo only if you're willing to make it public: a photo can carry its location and other details.
>
> **Write by email.** *(address)* If you write, we receive your email address and whatever you send. We use them only to answer you. Email is not private in transit the way the app is: your mail provider and ours handle the message.
>
> **Report a security problem privately.** Use private vulnerability reporting on GitHub. Please don't open a public issue for a security problem.
>
> ## What helps us help you
>
> The app version, from Settings, then About. Your device model and its iOS or iPadOS version. What you did, what you expected, and what happened instead.

**Common questions.** Each answer is taken from text that is already reviewed; none adds a claim.

| Question | Draft answer | Taken from |
|---|---|---|
| Where do my photos go? | Into your photo library. The app saves each photo straight to Photos and stores no copy of its own. | Policy, "What stays on your device" |
| Why can't the app show my older photos? | The app can only add photos to your library. iOS doesn't let it see your existing photos. | Listing, C8 |
| Why does a lens say "Processed"? | That lens can't save unprocessed RAW. The app tells you before you shoot, unless you turn that marker off, and labels the photo. | Listing, C2 |
| How can I check that the app makes no network connections? | Turn on App Privacy Report in Settings, under Privacy & Security. It lists every domain an app contacts. The app should list none. | Policy, "No network connections"; C5 |
| What does a signature show? | Whether the file has changed since it was signed. It is not proof of who took the photo. Signing is off by default. | Listing, C9 |
| How do I remove the app's data? | Delete the app. Its settings and presets are removed with it. Your photos stay in Photos. | Policy, "What stays on your device"; that deleting an app removes its stored settings is iOS behavior, to cite from Apple's documentation before publishing |

**Devices.** The full list from the README's "Requirements", then the README's "What was tested" paragraph, worded as a limit rather than a claim:

> For version 1.0.0 the app was run on real hardware on an iPhone 16 Pro Max and an iPad Air (5th generation). On other models, and on Apple Watch, it was run only in Apple's Simulator, which has no real camera. If something on these pages isn't true on your device, tell us: it's handled as a bug.

**Accessibility.**

> If something in the app or on this site doesn't work with VoiceOver, Voice Control, Switch Control, a keyboard or large text, report it in the same way. It's handled as a bug.

The page ends with **Last updated** and **App version**. It has no rating request. The store plan allows the App Store's write-review link here; it is left out for 1.0.0 so the support page asks nothing of the reader (decision 20).

## 7. Not found

Figure: `site-404`. "Page not found. There is no page at this address. The site has three pages:" and the three links. `noindex`, not in the sitemap, same header and footer.

## 8. Visual design

### 8.1 The look

The site looks like the app's first frame: the camera's black, the icon's mark, the teal period, white type. The hero is black in both themes, as the launch screen is black in every appearance ([LAUNCH-SCREEN.md](LAUNCH-SCREEN.md)); under it the page follows the reader's light or dark setting. There is no other color, no gradient, no illustration, no animation.

### 8.2 Tokens

One set of names, defined once in the site's Tailwind theme (section 14.2) and used by every class.

| Token | Dark | Light | Use | From |
|---|---|---|---|---|
| `ground` | `#000000` | `#FFFFFF` | Page background | `NopeColor.launchBackground` (dark) |
| `surface` | `#1C1C1E` | `#F2F2F7` | Cards, the dates table | The design pages' card colors |
| `ink` | `#F2F2F7` | `#1C1C1E` | Text, links, icons | The design pages' ink |
| `muted` | `#AEAEB2` | `#5F5F64` | Secondary text | `NopeColor.labelSecondary` (dark) |
| `rule` | `#3A3A3C` | `#D1D1D6` | Hairlines between sections (decoration only) | The design pages' rule |
| `focus` | `#40C8E0` | `#1C1C1E` | Focus outline | `NopeColor.fact` value (dark) |
| `mark` | `#EDEDEE` | `#EDEDEE` | The wordmark and the mark, always on black | `NopeColor.mark` |
| `period` | `#40C8E0` | `#40C8E0` | The wordmark's period, always on black | `NopeColor.markPeriod` |
| `band` | `#000000` | `#000000` | The hero's ground | `NopeColor.launchBackground` |

- **Teal has one use on the site: the period of the wordmark and the mark** (and the dark theme's focus outline). In the app teal marks verified facts; the site makes no such marks, so there are no teal check marks, links or headings.
- Amber and Night Mode red are not site colors. They appear only inside a screenshot that shows them, and they are not defined in the theme.
- Links are the text color, underlined; they never depend on color.
- The mark is drawn from the icon's three paths with the period as sRGB `#40C8E0`. [`launch-mark.svg`](launch-mark.svg) must not be copied as is: its period is `#6AC5DD`, a value that only suits Xcode's asset compiler.

### 8.3 Type

Inter, weights 400, 600 and 700, on a `rem` scale so the reader's text size is respected.

| Role | Size | Weight | Notes |
|---|---|---|---|
| Wordmark | The smaller of 8.5rem and 26% of the window's width | Outlines | An image, not text: it scales with the window, so it never causes sideways scrolling at large text sizes |
| Full name under it | 1.25rem | 600 | |
| Tagline | 1.25 to 1.625rem | 600 | |
| `h1` on the privacy and support pages | 2 to 2.75rem | 700 | |
| `h2` | 1.625 to 2.125rem (1.5rem in documents) | 700 | |
| `h3` | 1.25rem | 600 | |
| Body | 1.0625rem, line height 1.55 | 400 | Lines at most about 70 characters |
| Small | 0.9375rem; the footer 0.875rem | 400 | Never smaller |

The wordmark on the site is the Inter outline file, once that brand file is added to the repository (it is not there yet; [TRADEMARKS.md](../../TRADEMARKS.md)). The figures set "nope." as live Inter Bold text as a stand-in; the build doesn't.

### 8.4 Space, shape and layout

- Spacing on the app's scale (4, 8, 12, 16, 24, 32, 48 px; `NopeSpace`), which is Tailwind's default scale at steps 1, 2, 3, 4, 6, 8 and 12. Section padding 64 px, 48 px on a phone.
- Radii from `NopeRadius`: 12 px (small) and 24 px (large); screenshots take the capture's own corner radius.
- Content column 66rem at most; documents 44rem. Side margins 24 px, 16 px on a phone.
- One breakpoint at 48rem: two columns become one; the four screenshots become two by two, and one column under 22rem.
- The header is not sticky, so it never covers a focused element.
- Every link in the header and footer has a target at least 44 px high.

### 8.5 Figures

| Figure | Shows |
|---|---|
| `site-home` | The landing page, dark, 1280 px wide, with the badge |
| `site-home-light` | The same in the light theme; the hero stays black |
| `site-home-phone` | The landing page at 390 px, dark (drawn from `site-home.html`) |
| `site-home-large-text` | The top of the landing page at 320 px with text at 200%: no sideways scrolling, nothing clipped |
| `site-home-before` | The hero before the app is on the App Store: no badge |
| `site-privacy` | The privacy page, light |
| `site-privacy-dark` | The privacy page at 390 px, dark |
| `site-privacy-print` | The first printed sheet of the privacy page |
| `site-support` | The support page, light, with the email block of option B |
| `site-support-dark` | The support page at 390 px, dark |
| `site-404` | The not-found page |

The figures are self-contained HTML with a PNG, like the rest of this folder, with one difference: their text is set in Inter, embedded as a Latin subset, because site artwork may not use an Apple system font. Screenshots and the badge are labeled placeholders. Bracketed items in the policy text appear as they are in the draft.

## 9. Accessibility

The baseline is WCAG 2.2 AA, the same as the app's. The site states no accessibility claim of its own; this section is what the build must meet and what the checks look for.

- **Structure:** one `h1` on each page; headings in order with none skipped; `header`, `nav` (labeled "Site"), `main`, `footer` landmarks; the contents list on the privacy page is a labeled `nav`. Lists are lists, the dates are a description list.
- **Skip link:** the first focusable element, "Skip to content", visible when focused.
- **Keyboard:** everything is a link, in reading order. No keyboard traps are possible without scripts. The current page's link has `aria-current="page"` and a heavier underline.
- **Visible focus:** a 3 px outline, offset 3 px, in the `focus` token, on `:focus-visible`; never removed. It has at least 3:1 against the ground in both themes (10.6:1 and 17.0:1).
- **Contrast,** computed from the tokens:

  | Pair | Dark | Light | Needs |
  |---|---|---|---|
  | `ink` on `ground` | 18.8:1 | 17.0:1 | 4.5:1 |
  | `muted` on `ground` | 9.5:1 | 6.4:1 | 4.5:1 |
  | `ink` on `surface` | 15.3:1 | 15.3:1 | 4.5:1 |
  | `muted` on `surface` | 7.7:1 | 5.7:1 | 4.5:1 |
  | `mark` on `band` | 18.0:1 | 18.0:1 | 3:1 |
  | `period` on `band` | 10.6:1 | 10.6:1 | 3:1 |

  The `rule` hairlines are decoration and carry no information. The teal period never sits on white (2.0:1), which is one reason the hero stays black.
- **Images:** every screenshot has alternative text tied to its caption's fact (section 4.4). The mark in the header is decorative (`aria-hidden`), next to the name in text. The wordmark's accessible name is "Photivra Nope Camera"; "nope." is hidden from assistive technology so the heading is read once.
- **Text size and reflow:** sizes in `rem`; no fixed heights on text; no sideways scrolling at 320 px wide or at 200% and 400% zoom (figure `site-home-large-text`); text spacing may be overridden without loss.
- **Motion:** none. No transitions, no smooth scrolling, no animated images. Any motion added later must sit behind `motion-safe:` and have a still equivalent.
- **Themes:** `prefers-color-scheme` decides; `<meta name="color-scheme" content="dark light">`. Windows High Contrast (`forced-colors`) is honored: system colors replace the tokens, and the focus outline stays.
- **Language:** `lang="en-US"` on every page.
- **Link text** says where the link goes ("Open an issue on GitHub", "privacy statement"); no "click here". Links that leave the site are plain links in the same tab.
- **Checks:** the automated pass of section 14.3 on every page in both themes, and a manual pass before the first publication and after any layout change: VoiceOver in Safari on iPhone and on a Mac, keyboard only, 200% and 400% zoom, 320 px wide, both themes, and print preview. The result is recorded in `docs/TESTING.md`.

## 10. Search and sharing

- **Titles and descriptions,** unique for each page (drafts; the descriptions use only listing sentences):

  | Page | `<title>` | Meta description |
  |---|---|---|
  | `/` | Photivra Nope Camera: RAW photos, no tracking | Photivra Nope Camera takes photos with as little processing as the camera allows, can sign each one, and keeps nothing that tracks you. For iPhone and iPad. Free and open source. |
  | `/privacy/` | Privacy policy · Photivra Nope Camera | The app doesn't collect any data. It has no accounts, no analytics, no ads and no crash reporting, and it makes no network connections. |
  | `/support/` | Support · Photivra Nope Camera | How to get help with Photivra Nope Camera, report a problem, and check which devices it runs on. |
  | `/404.html` | Page not found · Photivra Nope Camera | (none; `noindex`) |

- **Canonical:** `<link rel="canonical">` on each page, `https`, with the trailing slash. Enforce HTTPS redirects `http`.
- **Sitemap:** `sitemap.xml` in the sitemaps.org 0.9 format with the three pages, each with `lastmod` set to the date of the release the site was built from; `robots.txt` with `User-agent: *`, `Allow: /` and `Sitemap: https://nope.photivra.com/sitemap.xml`; `<link rel="sitemap" type="application/xml" href="/sitemap.xml">` in each page. All three are generated by the build from the list of pages, so they can't disagree with it.
- **Open Graph and the large-image card:** `og:type` (`website`), `og:site_name`, `og:title`, `og:description`, `og:url`, `og:image` with its width, height and alternative text, `og:locale` (`en_US`), and `twitter:card` set to `summary_large_image`. These are read by a service when someone shares a link; they cause no request from a reader's browser.
- **The social image:** one self-hosted PNG, 1200 × 630, the wordmark lockup on black with the tagline and the scoped sentence in Inter. No screenshot in it, no badge, no Apple artwork. Its alternative text: "nope. Photivra Nope Camera".
- **Structured data** (JSON-LD), on the landing page only:
  - `WebSite`: the name and the address.
  - `MobileApplication`: `name` "Photivra Nope Camera", `operatingSystem` "iOS", `applicationCategory` "PhotographyApplication", `softwareVersion` from the build, `description` from the listing's first sentence, `url`, `license` (the GPL-3.0 address), `isAccessibleForFree`, `inLanguage` "en-US", and `publisher` as an `Organization` with the name from `NOTICE` and `url` `https://photivra.com/`.
  - Only when the app is available: `downloadUrl` (the App Store page) and `offers` with price 0 in USD.
  - **Never:** `aggregateRating`, `review`, award or feature lists, or screenshots that aren't on the page.
- **Icons:** `favicon.ico` (32 px), an SVG icon, `apple-touch-icon.png` (180 px) and a minimal `manifest.webmanifest` (name, icons, black theme and background color, `display: browser`). All are the app icon, a brand asset, self-hosted.
- **The Photivra site:** the footer links to `https://photivra.com/` ("An app from Photivra"). photivra.com links back and lists this site's sitemap in its `robots.txt`; that change is made in that site, not here.
- **`llms.txt`** in the repository gains the site's address; the site itself doesn't need one for three pages.

## 11. Performance

**Budgets** (transferred bytes, compressed as served; the build fails over them):

| Item | Budget |
|---|---|
| HTML, each page | 12 KB (the privacy page 16 KB) |
| CSS, the one file | 10 KB |
| Font files | 2 files, 45 KB together |
| Icons and the inline mark | 8 KB |
| Hero screenshot, the size a phone loads | 45 KB |
| **Landing page, first view** (HTML, CSS, fonts, icon, hero image) | **150 KB** |
| Each screenshot below the fold | 60 KB |
| **Landing page, everything** | **400 KB** |
| Privacy page; support page | 80 KB each |
| JavaScript | 0 |
| Requests to other hosts | 0 |
| The social image (not loaded by pages) | 120 KB |

**Targets** on a mid-range phone on a slow 4G profile: Largest Contentful Paint under 2.5 s, Cumulative Layout Shift under 0.1, Interaction to Next Paint under 200 ms (with no scripts there is nothing to delay input).

**How:**

- No JavaScript, so nothing blocks rendering but one small stylesheet.
- One CSS file, minified, holding only the classes the pages use, with a content hash in its name.
- **Fonts:** Inter subset to the characters the pages use (Basic Latin and the punctuation in the copy), as WOFF2, weights 400 and 600–700, `font-display: swap`, the regular weight preloaded. The fallback font is given `size-adjust`, `ascent-override` and `descent-override` so the swap moves nothing. The OFL text ships beside the files.
- **Images:** each screenshot as AVIF and WebP with a PNG fallback in a `picture` element, in two or three widths with `srcset` and `sizes`; `width` and `height` always set, so nothing shifts; the hero image loads eagerly with `fetchpriority="high"`, the rest `loading="lazy"` and `decoding="async"`. Image files are written by the build from the store's captures and carry no metadata.
- The wordmark and the mark are inline SVG: no request, no font needed for the largest element.
- Every asset name carries a content hash, so a page never mixes old and new files.
- **A limit of the host:** GitHub Pages sets the cache lifetime itself and a site can't change response headers. The hashes are still right, but a long cache lifetime isn't ours to set, and a tool's "cache policy" note is expected (section 17).

## 12. Security and privacy of the site

- **Content-Security-Policy,** by `<meta http-equiv>` as the first element after the character set on every page:

  `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'`

  No `script-src` entry means scripts fall under `default-src 'none'`. No `'unsafe-inline'`: the pages have no `style` attributes and no inline `<style>`; inline SVG uses presentation attributes only.
- **`<meta name="referrer" content="no-referrer">`,** so a site the reader goes to isn't told which page they came from.
- **What a meta tag can't do:** `frame-ancestors`, reporting and `sandbox` only work as response headers, and GitHub Pages doesn't let a site set headers (no HSTS header of its own either). The pages have no forms and no actions, so framing gains an attacker nothing; the limit is stated here rather than hidden.
- **External links** are limited to a short list the check enforces: the repository on `github.com`, GitHub's privacy statement, `apps.apple.com` (when available), `photivra.com`, and the GPL text. Nothing else can be linked without changing the list in a reviewed pull request.
- **No forms, no embedded media, no iframes, no `mailto:` with a prefilled body.**
- **DNS only, no proxy.** The domain's record points straight at GitHub. A proxy in front of the site would be a second party that sees every reader, and some proxies add scripts or rewrite pages; either would make the site's statements false (section 15).
- **What the host does** is said on the landing page and in the policy: GitHub logs the reader's IP address for security.

## 13. Keeping the site true

| What the site says | Single source | How it gets to the site | What stops a drift |
|---|---|---|---|
| The privacy policy | `docs/store/privacy-policy-draft.md` (renamed when published) | Converted to HTML by the build | No hand-kept HTML copy exists; the build fails on a `[bracket]`, on "DRAFT", on Markdown it doesn't know, and on a "Last updated" date older than the file's last text change |
| The statements on the landing page | `store/metadata/en-US/description.txt` | The first line, the groups and the last line are read from the file | The build fails on a heading it has no sentence-case name for; one human review of the listing covers both |
| Titles, descriptions and other site-only sentences | `site/content/` (one file per page) | Templates | Each sentence that states a fact about the app carries a claim id (C1 to C12) in a comment; the check fails on a fact sentence without one, and [`docs/store/README.md`](../store/README.md)'s claim table gains a "Site" column |
| Screenshots and captions | The store's captures and caption strings | Resized by the build | A screenshot whose gate is open isn't in the store set, so it isn't on the site |
| Devices and languages | README, "Requirements" and "Languages" | Kept by hand in `site/content/`, with a check that the device lines match the README's | The check |
| App version | `MARKETING_VERSION` in `Config/Base.xcconfig` | Read by the build | `scripts/check-repo.sh` already ties it to the changelog; the build fails if the policy's app version differs |
| The App Store link | `site/site.json` | Template | Shown only with an id and `available: true`; checked against `AboutScreen.appStoreID` when that exists |
| "Built from commit …" | The commit being built | Written by the build | |

**With each app release** the tag's workflow rebuilds and republishes the site, so the site always describes the released version. A pull request that changes the policy, the listing or the README's requirements runs the site's build and checks too, so a change that would break the site is seen before the release.

The site's own statements ("no cookies", "no JavaScript", "nothing is loaded from another site") are enforced by the checks of section 14.3, the same way `scripts/check-no-networking.sh` stands behind the app's.

## 14. Build, checks and publishing

### 14.1 Files

```
site/
  site.json            the domain, appStoreId, available
  content/             one file per page: site-only sentences, titles, descriptions, alt text
  templates/           page templates (header, footer, each page)
  styles/site.css      Tailwind input: the theme (tokens) and a few base rules
  assets/              fonts (with OFL.txt), icons, the social image, the badge (Apple's file)
  package.json         Tailwind CLI and the check tools, exact versions
  package-lock.json
scripts/build-site.py  builds _site/ (Python standard library only)
scripts/check-site.sh  the checks of 14.3; scripts/test-check-site.sh tests them
.github/workflows/site.yml
```

`_site/` and `site/node_modules/` are not committed. The build script follows the repository's existing Python scripts and adds no Python dependency: it converts the policy's small set of Markdown (headings, paragraphs, lists, bold, links, code), fills the templates, writes the sitemap, `robots.txt` and the manifest, resizes images, hashes asset names and runs the Tailwind CLI.

### 14.2 Tailwind CSS

Maintainer's decision, 2026-11-19: the site's CSS is Tailwind CSS, compiled at build time.

- **The Tailwind CLI, an exact version, as a development dependency of a site-only package** (`site/package.json` with its lockfile). It runs in the build and writes one minified CSS file containing only the classes found in the templates and the generated HTML. **Never the CDN or Play script:** no runtime, no external request.
- **The theme is the token table of section 8.2.** The colors are CSS variables that change with `prefers-color-scheme`, exposed to Tailwind as theme colors (`bg-ground`, `text-ink`, `text-muted`, `border-rule`, `bg-surface`, `outline-focus`, `fill-mark`, `fill-period`, `bg-band`), so pages rarely need a `dark:` class. Radii `small` (12 px) and `large` (24 px), the font family, and the type sizes of 8.3 are theme values; spacing is Tailwind's default scale, which already holds the app's steps.
- **One token source, where practical.** The app's tokens live in Swift (`DesignTokens.swift`, listed in [tokens.md](tokens.md)). The site's theme repeats six of those values. `check-site.sh` reads the values from `tokens.md` and fails if the site's `mark`, `period`, `band`, dark `ground`, dark `muted` or the two radii differ. Generating both from one file is possible later; for nine tokens a check is smaller than a generator.
- **Variants kept:** `focus-visible:` for the outline, `motion-safe:` for any motion ever added, `print:` for the print layout, `forced-colors:` where a border must survive, and the one `md:` breakpoint.
- **Preflight** (Tailwind's base reset) is kept; its bytes are inside the 10 KB budget. The output keeps Tailwind's license banner.
- **Dependencies in a public repository:** the lockfile is committed; installs use `npm ci --ignore-scripts` and nothing else; versions are exact, never ranges; a pull request that changes `site/package-lock.json` states each package's license and is reviewed like any dependency change (AGENTS.md, "Third-party licenses"). `THIRD_PARTY.md` gains rows for Tailwind CSS (MIT) and each check tool, marked "site build only; not part of the app; nothing but the generated CSS is served". The app's `security/allowed-dependencies.txt` is about app code and doesn't change. GitHub's dependency review on pull requests and update alerts for the `site/` package are repository settings for the maintainer (decision 18).

### 14.3 Checks before every deploy

All run on the built `_site/`, on the runner, against a local server on `127.0.0.1`. None calls an outside service; the only network use is installing the pinned tools.

| Check | What fails it | Tool |
|---|---|---|
| The site's promises | Any `<script>` other than one `application/ld+json` block; any `on…` attribute; any `style` attribute or inline `<style>`; any `src`, `srcset`, `href` on `link`, `url()` or `@import` that leaves the site; an external `<a>` not on the allowed list; a missing or different Content-Security-Policy; a form, iframe, `object` or `embed` | `check-site.sh` (standard library) |
| A real page load | Any request to another host, any cookie set, any storage written, any console error or CSP violation, in a headless browser | The browser the audit below drives |
| HTML | Validation errors | The Nu HTML Checker, run locally |
| Links | A broken internal link or anchor; a missing file; `http:` anywhere. External links are checked for form only, not fetched | `check-site.sh` |
| Search | A page without exactly one `h1`, a unique title, a description, a canonical address that is `https` with a trailing slash, `lang="en-US"`, the sitemap link; a sitemap that doesn't list exactly the public pages; `robots.txt` without the sitemap line; `404.html` in the sitemap or without `noindex`; JSON-LD that doesn't parse, or that holds a rating, a review, or an offer while the app isn't available | `check-site.sh` |
| Truth | A `[bracket]` or "DRAFT" in the policy page; the policy's version differing from the app's; a stale "Last updated"; a fact sentence without a claim id; device lines differing from the README; token values differing from `tokens.md`; the badge shown without `available`; a host name banned by AGENTS.md rule 6 | `check-site.sh` |
| Accessibility | Any violation at WCAG 2.2 A or AA, on every page, in both themes and at 320 px | axe-core in a headless browser |
| Size | Any budget of section 11 exceeded | `check-site.sh` |
| Lighthouse | Scores under the floor on any page: performance 95, accessibility 100, best practices 95, search 100 (mobile profile, three runs, the median) | Lighthouse, run locally |

`scripts/test-check-site.sh` gives each rule of `check-site.sh` a passing and a failing page, as the repository's other checks have. The automated accessibility check doesn't replace the manual pass of section 9.

### 14.4 The workflow

`.github/workflows/site.yml`, GitHub-hosted runners, every action pinned by commit SHA, as the repository's other workflows are.

- **Runs on:** a pushed release tag (`v` and three numbers, so pre-release tags don't publish); by hand (`workflow_dispatch`, with the ref to build); and on pull requests that touch `site/`, the policy, the listing text, the README or the site scripts, where it builds and checks but doesn't deploy.
- **Build job** (`contents: read` only): check out; install Node at a pinned version; `npm ci --ignore-scripts` in `site/`; `scripts/build-site.py`; `scripts/test-check-site.sh`; `scripts/check-site.sh` and the other checks of 14.3; upload `_site/` as the Pages artifact.
- **Deploy job** (needs the build job; `pages: write` and `id-token: write`; environment `github-pages`): deploy the artifact. It first checks that the Pages address is `https://nope.photivra.com/`, and stops if it isn't.
- One deployment at a time (a concurrency group); a running deployment is not cancelled.
- **No preview deployment.** A pull request is reviewed from the build's uploaded artifact, opened locally. Nothing unreleased is published anywhere.
- **No `CNAME` file.** With a workflow as the Pages source, GitHub ignores a `CNAME` file; the custom domain is the repository's Pages setting. The domain is written once in `site/site.json`, where the build and the deploy check read it.

### 14.5 The order for 1.0.0

1. The site is built and merged with its checks. The policy is final (no brackets), and captures exist or the screenshot sections are left out.
2. The maintainer does the one-time setup of section 15.
3. **First publication, by hand, before the app is submitted,** from the release branch, in the "not yet" state. The privacy and support addresses are then live for App Review, and the store's marketing URL may be filled (store plan, decision 16).
4. The app is approved and released; the release is tagged; the tag's workflow republishes the site.
5. The maintainer sets `appStoreId` and `available` in `site/site.json` and runs the workflow by hand; the badge appears. From then on each release tag republishes by itself.

Publishing the site reaches users, so each publication is the maintainer's act (AGENTS.md, rule 5): a tag, or a run started by hand.

## 15. What the maintainer does

One time, in this order. None of it is done by an agent.

1. **Verify the domain for the organization** (organization settings, Pages, "Add a domain": a TXT record that GitHub names). GitHub recommends this before adding a custom domain; it stops another account from claiming the name if the record is ever left dangling.
2. **DNS at the domain's provider:** a `CNAME` record, name `nope`, target `photivra.github.io` (the organization's Pages host, without the repository name), **DNS only, not proxied**. No wildcard record for the domain: GitHub warns that a wildcard lets others claim subdomains. If the domain has CAA records, they must allow Let's Encrypt, which issues the certificate.
3. **Repository settings, Pages:** source "GitHub Actions"; custom domain `nope.photivra.com`; wait for the DNS check and the certificate (GitHub says up to 24 hours); then turn on **Enforce HTTPS**.
4. **Repository settings, Environments, `github-pages`:** allow deployments from release tags (`v*`) and from the branch used for runs by hand. Optionally require the maintainer's approval for each deployment (decision 17).
5. **Download the App Store badge** from Apple's marketing resources and add it to `site/assets/`, unchanged.
6. **Choose the support address** (if option B) and add it; fill the policy's bracketed items and its dates.
7. **Run the workflow by hand** for the first publication; open the three addresses; check them with a browser's network inspector (only `nope.photivra.com` in the list) and with VoiceOver; print the privacy page.
8. In App Store Connect, the privacy policy URL, the support URL and, if wanted, the marketing URL are the three addresses.
9. On photivra.com: link to the site and list its sitemap in `robots.txt`.

After that a release needs nothing more than its tag. The repository's release instructions gain these steps in the pull request that builds the site, so a release never depends on an agent.

## 16. Decisions for the maintainer

| # | Decision | Recommendation |
|---|---|---|
| 1 | Accept this design as the site for 1.0.0 | Yes |
| 2 | Pages: `/`, `/privacy/`, `/support/` and a not-found page; `/accessibility/` after the manual pass and the Nutrition Labels; `/press/` later | Yes, three pages now |
| 3 | No JavaScript at all, with the JSON-LD data block as the one allowed `<script>` element | Yes. If any `<script>` element is unwanted, drop JSON-LD; the rest of section 10 stands |
| 4 | The hero is black in both themes, with the lockup, the tagline and the scoped sentence | Yes. It keeps the teal period on black and matches the launch screen |
| 5 | The tagline on the landing page | Use it, always directly above "as little processing as the camera allows". Without that sentence it would read as "no processing" |
| 6 | Landing page statements are taken word for word from `description.txt` | Yes: one text, one review. The page then changes whenever the listing does |
| 7 | Body font: self-hosted Inter, or the reader's system font | Inter. It matches the wordmark and the store images, and no page or picture of the site then shows an Apple system font. Cost: about 45 KB |
| 8 | Screenshots: the store's set (images 1, 2, 3, 4 and 8), no device frames, with one line saying where they were captured; none until captures exist | Yes |
| 9 | App Store badge: Apple's black badge, self-hosted, shown only once the app can be downloaded; no Smart App Banner | Yes. The banner would cause a request to Apple that the page didn't serve |
| 10 | Support contact: (A) GitHub issues only, or (B) issues and an email address | B. An account wall may not meet App Review's "easy way to contact", and it shuts some people out. It changes the policy's "There is no contact email" |
| 11 | If B: the address, and how long messages are kept | An alias at the project's domain; say on the page that messages are used only to answer, and state the retention once decided |
| 12 | Add a "This website" section to the privacy policy, and change "the Photivra website" to "photivra.com" | Yes. The site is where the policy is read, and its host logs IP addresses |
| 13 | The "what was run on real hardware" paragraph on the support page | Yes, worded as a limit, as in the README. It isn't on the landing page |
| 14 | "Last updated" comes from a date written in the policy file, with a check that it isn't stale | Yes. A legal date should be a person's decision, not a build time |
| 15 | The build refuses to publish a policy with a bracketed item or "DRAFT" | Yes |
| 16 | Publish by hand before submission in the "not yet" state, then on each release tag; no preview deployments | Yes. App Review needs the two addresses live first |
| 17 | Require the maintainer's approval on the `github-pages` environment for every deployment | No for 1.0.0: a tag or a run by hand is already the maintainer's act. Turn it on if anyone else gains write access |
| 18 | Site build dependencies: Tailwind CLI (decided), and Node-based check tools (axe-core, Lighthouse, a headless browser driver) plus the Nu HTML Checker, all pinned, CI only; dependency review and update alerts for `site/` turned on in the repository settings | Yes. They are the first npm dependencies in the repository; none is served or bundled. If fewer are wanted, keep Tailwind, `check-site.sh` and axe-core, and run Lighthouse by hand before a release |
| 19 | Lighthouse floors: performance 95, accessibility 100, best practices 95, search 100; budgets as in section 11 | Yes. Budgets and floors are raised or lowered only by the maintainer |
| 20 | The App Store write-review link on the support page | Not for 1.0.0 |
| 21 | `/.well-known/security.txt` pointing to private vulnerability reporting | Yes; it is one static file. It needs an expiry date renewed at least yearly, which the build can set from the release date |
| 22 | DNS only (no proxy) for `nope`, and domain verification for the organization | Yes to both |
| 23 | Commit the App Store badge (Apple's file) and the wordmark outlines (a brand file) under `site/assets/`, listed in `THIRD_PARTY.md` and `TRADEMARKS.md` as not under the GPL | Yes. The site can't be built from the repository otherwise. The wordmark file is needed before the build starts |
| 24 | The footer line "An app from Photivra" linking to photivra.com, and the publisher named in the structured data as in `NOTICE` | Yes |
| 25 | The Apple Watch line on the landing page | Follows the store plan's decision 9: shown only if the watch app ships in 1.0.0 |

## 17. Sources and what is unverified

Read on 2026-11-19:

| Subject | What the page says | Source |
|---|---|---|
| App Store badge | Preferred black badge; one per layout; subordinate to the main message; clear space one quarter of its height; at least 40 px on screen; don't modify, angle or animate; credit Apple and the Apple logo when it is used; credit lines once per site | [App Store Marketing Guidelines](https://developer.apple.com/app-store/marketing/guidelines/) |
| Product names and images | "App name for iPhone"; singular names; "on the App Store"; avoid "iOS" in marketing copy; Apple product images only from Apple's bezels, unmodified; show the app as it runs | The same page |
| Custom domain | A `CNAME` DNS record to `<organization>.github.io`; with a custom workflow no `CNAME` file is created and an existing one is ignored; verifying the domain is recommended; wildcard records are warned against; DNS changes and the HTTPS option can take up to 24 hours | [Managing a custom domain](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site) |
| HTTPS | Certificates come from Let's Encrypt after the DNS check; Enforce HTTPS is a repository setting | [Securing your site with HTTPS](https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https) |
| What the host logs | "The visitor's IP address is logged and stored for security purposes", signed in or not | [What is GitHub Pages?](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages) |
| Publishing with a workflow | `configure-pages`, `upload-pages-artifact`, `deploy-pages`; `pages: write` and `id-token: write`; the `github-pages` environment | [Using custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) |

**Unverified**, to confirm when the site is built or first published; none is stated on the site as fact until then:

- That the `github-pages` environment needs a rule added before a tag can deploy (it is the default behavior as recalled, not read on a GitHub page that day).
- The cache lifetime GitHub Pages sends, and that it can't be changed.
- That a CAA record without Let's Encrypt blocks the certificate, and that a proxied record does (both recalled; the GitHub pages read don't mention them). DNS only is recommended for the reasons in section 12 either way.
- That a browser doesn't apply `script-src` to an `application/ld+json` block: the page-load check of 14.3 shows it, since a CSP violation fails the build.
- That `frame-ancestors`, reporting and `sandbox` are ignored in a meta Content-Security-Policy (from the CSP specification, not re-read that day).
- Whether GitHub gives a Pages site's owner any access logs. The draft copy says only what GitHub's page says.
- That deleting an app removes its stored settings (the support answer); cite Apple's documentation first.
- The exact form of Apple's credit line for a site read worldwide, and the current badge file; re-read the guidelines when building.
- Tailwind's and the check tools' current versions and licenses; read each license when pinning.
- The font and image sizes in the budgets are estimates until the first build measures them.
