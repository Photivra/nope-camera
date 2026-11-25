# Releasing

What the maintainer does to release Photivra Nope Camera. Every action that reaches users is the
maintainer's (AGENTS.md, rule 5): an App Store submission, a release tag, a change to signing, and
each publication of the website. None of these steps needs a coding agent.

## Before a release

- The release requirements in AGENTS.md, "Pull requests and releases": the full security audit
  (`docs/SECURITY_AUDIT.md`), the on-device checks (`docs/TESTING.md`), a `CHANGELOG.md` entry, and
  `MARKETING_VERSION` in `Config/Base.xcconfig` equal to that entry (`scripts/check-repo.sh`).
- The privacy policy (`docs/store/privacy-policy-draft.md`) is final: no `[bracketed]` item and no
  "draft" in any case, with its effective date, "Last updated" date and app version filled in. The
  site's build refuses to publish it otherwise.
- Every release changes the policy's "App version" to the new `MARKETING_VERSION`, and so its
  "Last updated" date too, in the release pull request.
- Before tagging, run the publishing build on the release commit, without `--preview`:
  `(cd site && npm ci --ignore-scripts) && scripts/check-site.sh`. The tag's run is the same
  build, so a failure here would otherwise first show after the tag exists.
- The tag is `vMAJOR.MINOR.PATCH`. Pushing it also republishes the website.

- In the release pull request's last push before merging, set the dates that must be the merge
  day: `CHANGELOG.md`'s release heading (`## [X.Y.Z] - YYYY-MM-DD`), and the "Last updated" dates
  of `site/content/support.json` and `site/content/accessibility.json` (and the policy's), in UTC
  (see "What can stop a publication" below). For 1.0.0 these were left at their earlier dates on
  the integration branch on purpose, for this step.

## When the GitHub UI runners are failing: a proof from the owner's Mac

If GitHub's macOS runners keep failing the UI shards for reasons outside the tests, a passing run
of the same UI suite on your Mac can stand in for the `ui-tests`, `ui-tests-ipad` and
`ui-tests-watch` checks of the release pull request. It is a fallback: the GitHub shards remain
the default, the ruleset doesn't change, and `repo-checks`, `unit-tests` and `docs` still have to
pass on GitHub. In a clean checkout of the pull request's head commit, pushed, with Xcode 27.2:

```sh
gh auth status                            # signed in as a login in .github/owner-mac-proof-allowed.txt
scripts/owner-mac-ui-proof.sh --dry-run
scripts/owner-mac-ui-proof.sh             # several hours; posts "ui-tests (owner Mac)" only when all passed
```

Then re-run each failed UI check's job with "Re-run job". The proof counts only for the commit it
was posted on and only while that commit's UI test inputs match; any push of a new commit needs
the GitHub shards or a new proof. Details, and how to withdraw a proof, are in `docs/TESTING.md`,
"When the GitHub UI runners are failing: a proof from the owner's Mac".

## The app build

The App Store build is made on your Mac with Xcode, from the release commit. No step needs a
coding agent.

1. **Bundle identifier.** The App Store app is `com.photivra.nope`. It can't be changed after the
   first upload. `Config/Base.xcconfig` keeps `com.photivra.nope.dev` for development builds, so a
   development build and the App Store app are separate apps with separate settings on a device.
   For the release build, add this line to your untracked `Config/Local.xcconfig`, beside
   `DEVELOPMENT_TEAM`:

   ```
   NOPE_BUNDLE_IDENTIFIER = com.photivra.nope
   ```

   The extensions, the Apple Watch app and the App Group follow it
   (`com.photivra.nope.capture`, `.controls`, `.watchkitapp` and `group.com.photivra.nope`), and
   Xcode's automatic signing registers them the first time. Never commit `Local.xcconfig`. Remove
   the line again for development builds.
2. **App Store record and App Store ID.** In App Store Connect, create the app with the bundle
   identifier `com.photivra.nope` (Apps, "+", New App). Its Apple ID (App Information, a number)
   is the App Store ID. Set `AboutScreen.appStoreID` in `Sources/NopeUI/AboutScreen.swift` to that
   number, in quotes, in a pull request, and run `scripts/check-app-store-id.sh`: it must print
   "app store id set". Without it the About screen has no Rate or Review row.
3. **Version and build number.** `MARKETING_VERSION` in `Config/Base.xcconfig` is the release
   version and matches the `CHANGELOG.md` entry (`scripts/check-repo.sh` checks this).
   `CURRENT_PROJECT_VERSION` is the build number: raise it by one, in a pull request, before every
   upload after the first one, since App Store Connect refuses a build number it already has for
   that version.
4. **Archive.** In Xcode, open `App/NopeCamera.xcodeproj`, choose the `NopeApp` scheme and the
   destination "Any iOS Device (arm64)", then Product › Archive. Or, in Terminal:

   ```sh
   xcodebuild archive -project App/NopeCamera.xcodeproj -scheme NopeApp -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/nope.xcarchive -allowProvisioningUpdates
   ```

5. **Check the archive.** The bundle identifier and versions:

   ```sh
   plutil -p build/nope.xcarchive/Products/Applications/nope.app/Info.plist \
     | grep -E 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion'
   scripts/check-launch-screen.sh build/nope.xcarchive/Products/Applications/nope.app
   scripts/check-app-store-id.sh
   ```

   The first command shows `com.photivra.nope`, the release version and the build number. Then
   run the security audit's checks on this archive (`docs/SECURITY_AUDIT.md`).
6. **Upload.** In Xcode's Organizer (Window › Organizer), select the archive, then Distribute App,
   App Store Connect, Upload. The build appears in App Store Connect, under TestFlight, after
   processing. Submitting it for review is a separate step, and yours (AGENTS.md, rule 5).

## The website, nope.photivra.com

The site is built from `site/` by `scripts/build-site.py` and published to GitHub Pages by the
`site` workflow (`.github/workflows/pages.yml`). The design is `docs/design/nope-site.md`. The App
Store's privacy policy and support addresses point at it, so it must be live before the app is
submitted for review.

### One-time setup

In this order (`docs/design/nope-site.md`, section 15):

1. **Verify the domain for the organization:** organization settings, Pages, "Add a domain" for
   `photivra.com`, then the TXT record GitHub names. This stops another account from claiming the
   name.
2. **DNS, at your DNS provider:** a `CNAME` record, name `nope`, target `photivra.github.io`, set to
   **DNS only** (not proxied). No wildcard record. If the domain has CAA records, they must allow
   Let's Encrypt.
3. **Repository settings, Pages:** source "GitHub Actions"; custom domain `nope.photivra.com`;
   wait for the DNS check and the certificate (up to 24 hours); then turn on **Enforce HTTPS**.
4. **Repository settings, Environments, `github-pages`, deployment branches and tags:** "Selected
   branches and tags", with the rules `v*` (tag), `main`, `release-*` and `release/*` (branches).
   The workflow allows the same refs: a run by hand from any other branch fails before it builds,
   and the deploy job runs only for a release tag or a run by hand from one of those branches.
   A release tag publishes only when its commit is on `main` or on its release branch
   (`release-X.Y.Z` or `release/X.Y.Z` for the tag `vX.Y.Z`). Also add a repository ruleset
   (Rules, Rulesets, branch ruleset for `release-*` and `release/*`, "Restrict creations") so only
   the maintainer can create release branches, since anyone with write access could otherwise
   create one and run the workflow from it.
5. **Repository settings, Code security:** the dependency graph and Dependabot alerts on, so the
   `site dependency review` job and the monthly grouped updates for `site/` work.
6. **The redirect domains, `nopecamera.com` and `nopecamera.org`, at your DNS provider.** Each
   sends every address to the site with a permanent (301) redirect that keeps the path:
   `https://nopecamera.com/privacy/` goes to `https://nope.photivra.com/privacy/`.
   `nope.photivra.com` stays the site's one address: it is the custom domain in GitHub Pages, the
   canonical address in every page (`site/site.json`, `domain`) and the address in App Store
   Connect, and its `CNAME` record of step 2 stays **DNS only**. Neither redirect domain is added
   to GitHub Pages. For each of the two domains:
   1. **Placeholder records, proxied:** an `A` record for the domain itself (name `@`) with the
      address `192.0.2.1`, and the same for `www`, both set to **proxied**. The address is a
      documentation address (RFC 5737) that is never reached: with the record proxied, your DNS
      provider answers the request and sends the redirect. No other records are needed for the
      redirect.
   2. **A redirect rule** for requests to the domain and to its `www` name: status 301, target
      `https://nope.photivra.com` followed by the request's path, so the path is kept. Let it match
      `http` and `https` requests alike; the target is always `https`.
   3. **Check it:** `curl -sI https://nopecamera.com/privacy/` answers `301` with
      `location: https://nope.photivra.com/privacy/`. Check `http://` and the `www` name too, and
      the same for `nopecamera.org`. `curl -sI https://nope.photivra.com/` still answers from
      GitHub Pages (`server: GitHub.com`), not through the provider's proxy.

### Publishing

- **First publication, before the app is submitted:** first, the claim table's device checks and
  the human review of `store/metadata/en-US/description.txt` (`docs/store/README.md`, "Claims and
  what they depend on") are done; any sentence whose check isn't done is removed from
  `description.txt` before publishing, since the landing page prints it word for word. Then fill
  the policy (above), and run Actions, the `site` workflow, "Run workflow" on the release branch
  (`release-X.Y.Z`; a run by hand publishes only from `main`, `release-*` or `release/*`). The landing page shows "Not on the App
  Store yet". Then open `https://nope.photivra.com/`, `/privacy/`, `/support/` and
  `/accessibility/`; check in the browser's network inspector that every request goes to
  `nope.photivra.com`; read a page with VoiceOver; print the privacy page.
- **In App Store Connect:** privacy policy URL `https://nope.photivra.com/privacy/`, support URL
  `https://nope.photivra.com/support/`, and, if wanted, marketing URL `https://nope.photivra.com/`.
  The accessibility URL `https://nope.photivra.com/accessibility/` only once Accessibility
  Nutrition Labels are declared.
- **Each release:** pushing the tag `vX.Y.Z` rebuilds and republishes the site. Pre-release tags
  don't publish.
- **Once the app can be downloaded:** download Apple's black U.S. English "Download on the App
  Store" badge (SVG) from Apple's marketing resources, add it unchanged as
  `site/assets/app-store-badge.svg`, list it in `THIRD_PARTY.md` and `TRADEMARKS.md` as Apple's
  artwork, set `appStoreId` and `"available": true` in `site/site.json`, and run the workflow by
  hand. The badge and the App Store link then appear.
- **On photivra.com:** link to the site, and add `Sitemap: https://nope.photivra.com/sitemap.xml`
  to its `robots.txt`.

If the deploy job stops with "The Pages address is …", the custom domain or Enforce HTTPS isn't
set yet (setup step 3). If it stops with "… is not allowed to deploy to github-pages due to
environment protection rules", the ref isn't in the environment's list (setup step 4). If the build
job stops with "A run by hand publishes only from main or a release branch", run it from one.

### What can stop a publication

The build and the checks run before every deploy (`scripts/check-site.sh`, the same on your
computer): an unfinished policy, a "Last updated" date older than the text it dates, a listing
that names an accessibility feature (VoiceOver, Voice Control, text sizes, screen readers and the like) before an iPhone manual pass is recorded in
`store/accessibility-status.json`, a page that
loads anything from another site, a broken link, an accessibility violation, a budget exceeded,
or a Lighthouse score under its floor. Each says what to fix. To see the pages locally before the
policy is final:

```sh
(cd site && npm ci --ignore-scripts)
scripts/check-site.sh --preview
python3 -m http.server --directory _site --bind 127.0.0.1 8000
```

`--preview` is for looking only: the publishing workflow never uses it. It skips only the policy's
draft markers, and its version and date rules while those markers remain; every other rule runs,
so a pull request shows what the publishing build would refuse.

"Last updated" dates (the policy, `site/content/support.json`, `site/content/accessibility.json`)
are UTC days. The build compares each with the newest change to its text in git, read in UTC; on
`main` that is the UTC day the pull request was merged. A date one day earlier than that is
accepted, so a pull request merged on the UTC day after its date was written still publishes; one
merged later needs its date changed first. So the dates in `site/content/support.json` and
`site/content/accessibility.json` (and the policy's) must be the merge day, UTC, or one day before
it: if not, the publishing build on `main` fails, and so does every later site pull request,
until a pull request rewrites the date. Set them to the merge day in the last push before merging.
A date after today (UTC) is refused. The error names
the date to write.
