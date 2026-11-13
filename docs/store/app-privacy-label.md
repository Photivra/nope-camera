# App Store privacy label answers

Status: **draft, needs human review.** The maintainer enters these answers in App Store Connect
(App Privacy). They are true only if the release build passes the checks named below in
[`../SECURITY_AUDIT.md`](../SECURITY_AUDIT.md).

## Answers

| App Store Connect question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** |
| Resulting label | **Data Not Collected** |
| Data used to track you | None (the question isn't asked once "No" is chosen) |
| Data linked to you | None |
| Data not linked to you | None |
| Privacy policy URL | The published page from [`privacy-policy-draft.md`](privacy-policy-draft.md) (required even with no data collected) |
| Privacy choices URL (optional) | Leave empty |

## Why "Data Not Collected" is correct

Apple defines "collect" as transmitting data off the device in a way that lets the developer or
its third-party partners access it for longer than needed to service the request in real time.
Data processed only on the device isn't collected, and developers don't disclose data Apple
collects ([App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/);
`docs/research/privacy-claims.md`, claim 3 and note 3).

- nope. contains no networking code and makes no network connections (audit checks 3, 7, 8).
- No analytics, crash-reporting or advertising SDK (audit check 14).
- The only non-platform dependency, the C2PA library, signs files on the device and sends
  nothing (audit checks 3 and 8 must confirm this for the prebuilt framework).
- Photos go to the user's own library through add-only access; that is the user's storage, not
  collection.
- Crash and usage data a user chooses to share with developers through Apple's "Share with App
  Developers" is collected by Apple, not by the developer.

## Privacy manifest

`App/NopeApp/PrivacyInfo.xcprivacy` must agree with these answers: `NSPrivacyTracking` false, no
tracking domains, no collected data types (audit check 6).

## Export compliance

Not part of App Privacy, but answered at the same time: **No** non-exempt encryption. The app
uses cryptography only to sign photos, and Info.plist should set `ITSAppUsesNonExemptEncryption`
to `NO` (see [`README.md`](README.md), "Other App Store Connect fields").

## Recheck before every release

Answer again from scratch if any release adds a dependency, a network feature (none is
allowed), a support or feedback form inside the app, or anything that sends data off the
device.
