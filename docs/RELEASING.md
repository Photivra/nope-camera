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
5. **Repository settings, Code security:** the dependency graph and Dependabot alerts on, so the
   `site dependency review` job and the monthly grouped updates for `site/` work.

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
that names VoiceOver, Voice Control or text sizes before an iPhone manual pass is recorded in
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
merged later needs its date changed first. A date after today (UTC) is refused. The error names
the date to write.
