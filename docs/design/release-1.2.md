# Designs for 1.2.0

Status: proposed 2026-11-21 for release 1.2.0, which is one issue: 83, protection for high-risk use. Not built, not yet accepted, and not in the screen counts of [README.md](README.md). This design was first written as section 4 of [release-1.1.md](release-1.1.md); it was revised for the fourteen owner decisions that followed the review of issue 83, and moved here when the owner gave the issue its own release, all on 2026-11-21. Decisions already recorded on the issue are taken as fixed and marked "decided"; the open choices are in [docs/plans/1.2.0.md](../plans/1.2.0.md), section 7. All wording is a draft until the Honesty review. The figures are SVG files in [release-1.2/](release-1.2/); they are sketches of layout, states and wording, not pixel-exact screens. The full screen set (`screens/`) is redrawn when the design is accepted and built.

| Section | What |
| --- | --- |
| 1 | Settings › Privacy: Save Photos To, Lock Captures, the backup question |
| 2 | The Captures library, and what the camera screen shows |
| 3 | Getting captures out, Share Without Optional Details, file names |
| 4 | Delete |
| 5 | Saved wording |
| 6 | The Lock Screen camera |
| 7 | Limits the wording must cover |
| 8 | Accessibility |
| 9 | Every draft string, for the Honesty review |
| 10 | The High-Risk Checklist, with ways to get captures off the phone and the ways others may try to get photos (added 2026-11-21 and 2026-11-22) |

Evidence note: everything about today's behavior was read from the code on branch `n100-H` at `9cef00d`. Nothing here was measured on a device or run on a simulator. Each statement that needs a device is a device check in the plan, sections 3 and 6, with the outcome that follows from it in the plan, section 2.5.

Q, the quick menu, is not changed by anything here: no tile is added, removed, moved or made editable, and Q still opens only from its button. The new settings are in Settings; the Captures library opens from the Last Photo spot and from Settings.

Names: the interface says "nope."; documents and the About screen say "Photivra Nope Camera" (AGENTS.md, "Name and wordmark").

Figures: [release-1.2/save-photos-to.svg](release-1.2/save-photos-to.svg), [release-1.2/captures-library.svg](release-1.2/captures-library.svg), [release-1.2/export-share-clean.svg](release-1.2/export-share-clean.svg), [release-1.2/high-risk-checklist.svg](release-1.2/high-risk-checklist.svg).

Issue 83 is the specification, with its ten owner decisions of 2026-11-18, the five recorded for the 1.1.0 plan, and the fourteen of 2026-11-21 that followed the blind-spot review ([docs/research/83-blind-spots.md](../research/83-blind-spots.md)). This section adds the screens, the entry points and the wording, and does not repeat the issue. Where the issue's text and a later decision differ, the later decision is right; the plan, section 2.1, lists each difference. The owner moved issue 83 from release 1.1.0 to its own release, 1.2.0, on 2026-11-21; where the issue says 1.1.0, read 1.2.0. "Review decision N" below is one of the fourteen; a letter and number such as "A2" is a finding of the review.

Anything that depends on a device check is marked. If the check fails, the fallback named with it is built and the sentence is not written.

## 1. Settings › Privacy

The group gets the two rows `SETTINGS-PLAN.md` reserved, above Assistant Access: **Save Photos To** (value: Photos, or nope only) and **Lock Captures** (value: Off, or On). Five rows in the group. A sixth, **High-Risk Checklist**, is added by section 10; its place and who sees it are the plan's decisions 30 and 31.

**In the Lock Screen camera's Settings, neither row is shown** (review decision 13; this replaces "read only"). The group has three rows there (the High-Risk Checklist row is not shown there either; section 10.2). Nothing in the Lock Screen camera states whether captures are kept in the app or locked.

**Save Photos To** (a page; figure, panel B):

1. The choice: Photos, nope only. The footer says what the choice covers and does not, and for nope only it states where the captures stand with backups (strings 20a, 20b, 21).
2. **The backup question** (review decision 2; figure, panel D). The first time nope only is chosen, the app asks once whether captures kept in the app stay in this iPhone's backups (strings 43 to 45). The two answers are drawn alike: neither is preselected, bold or the default action, and neither is marked destructive. Cancel leaves Save Photos To on Photos and the question is asked again next time. The answer sets Leave Out of Backups, which can be changed later on this page. The question is not asked again after it has been answered, including after Factory Defaults.

   **Advanced Data Protection (owner, 2026-11-21; limits added the same day).** The backup question's second paragraph (string 44a) and the Honesty limits (section 7) suggest Apple's Advanced Data Protection for iCloud, and say what it does not cover. Each part is stated only as far as Apple's pages support it (sources H9 to H11 in section 10.9):
   - what it does for this app's data: iCloud Backup is end-to-end encrypted, so only the person's trusted devices hold the keys;
   - what Apple can still read: some details of each backup stay under standard protection, with keys Apple holds. Apple lists the date, time and size of each backup snapshot, the name, model, color and serial number of the device, and the list of apps and file formats in the backup. The question names the first group and the apps; the limits list and the checklist name them all;
   - that it does not cover a backup to a computer, which is a different kind of backup with its own encryption switch (string 69);
   - that it needs a recovery contact or a recovery key, and that it is turned on in the Settings app, not in the app;
   - that it is not available everywhere, without naming places;
   - that the app cannot tell whether it is on. There is no public interface for it, so the paragraph is shown the same way to everyone and never says it is on or off.

   The question itself carries no link. It ends with a pointer in words to the High-Risk Checklist (string 44b), where the item on Advanced Data Protection has the link to Apple's page; a link inside a one-time question would lead out of it before it is answered. Whether the question keeps a link of its own is the plan's decision 32. No other place in the app shows the suggestion apart from the checklist and the Honesty limits.
3. "Kept in nope.": a **Captures** row with the count and size, which opens the library. Shown whenever the app holds captures, whichever choice is selected. With Lock Captures on, the row shows no count or size.
4. **Leave Out of Backups** and **Neutral File Names**, each with its explanation (strings 23, 25).
   - Leave Out of Backups keeps its name (review decision 3). Its explanation says that the app asks iOS, that iOS treats this as a request, and that it does not cover a copy of the phone's storage made another way. It names a kind of backup (iCloud Backup, an encrypted or an unencrypted backup to a computer, a direct transfer to a new iPhone) only where research step R4 confirmed that kind honors the request; a kind that was not checked or did not honor it is not named. If no kind is confirmed, the option goes back to the owner before it is built.
   - Neutral File Names is an option on top of the file-name rule of section 3, not the only protection.
5. **Delete All Captures…**, shown when the app holds captures.
6. When the device has no passcode: a notice at the top (string 24).
7. While a burst, a series or a bracket is running, the choice cannot be changed and the page says why (string 50). The destination of a capture is fixed when the shutter is pressed and travels with it (G1).

**Lock Captures** (a page; figure, panel C): the switch and its explanation (string 26); Passcode Only with its own explanation (string 46); the limits in the footer (string 27), followed by the link to the High-Risk Checklist (string 81; section 10.3). The switch is unavailable, with the reason, when the device has no passcode.

- **Lock Again** (Immediately, After 1 Minute, After 5 Minutes) is built only if a device check in R4 shows that the app can tell, on returning, that the iPhone was locked inside the delay (review decision 4). If the check passes, the section is as drawn, with string 28b. If it fails or cannot be run, the section is left out, captures always lock at once, and the page uses string 28a.
- The delay, where built, counts only time away from the app. It never keeps the library open inside the app (section 2, "Locking again").

**Details in Each Photo** gains one footer sentence (string 48; review decision 9): for a photo kept in the app, the time it was taken stays inside the app to keep the library in order, even with Date and Time off.

**Factory Defaults**, applied in the app, leaves Save Photos To, Lock Captures (with Lock Again and Passcode Only) and Leave Out of Backups as they are, as the assistant route already does (review decision 10). Its confirmation says so (string 49). It needs no authentication for them, because it does not change them. Whether it also leaves Neutral File Names alone is the plan's decision 28.

## 2. The Captures library

- **Entry points:** the Last Photo spot, and the Captures row on the Save Photos To page. Not Q.
  - While the app holds captures, the Last Photo spot opens the viewer for this session's photos as today; the viewer's Open in Photos becomes **Show in Captures** for a photo kept in the app.
  - Before the first photo of a session, where the spot today holds Open Photos, it holds **Captures** (a stack symbol) when the app holds captures.
  - With Lock Captures on: a neutral marker in the spot (the stack symbol, no thumbnail), which opens the library after authentication (decided).
- **Nothing outside the lock** (review decision 6). With Lock Captures on, the app makes and holds no thumbnail, preview or details of a capture kept in the app anywhere but in the store, behind the lock. There is no session record for such a capture: the Last Photo spot, the saving state that issue 129 adds in 1.1.0, the session viewer, Photo Details, the thumbnail's VoiceOver action and the comparison view have nothing to show and show the neutral marker or nothing. This holds from the moment the photo is taken, not only after the app has been in the background.
- **The saving state** (review decision 6; release 1.1.0's design, [release-1.1.md](release-1.1.md), 3.2). With Lock Captures on and Save Photos To set to nope only, no preview of the photo is made or held. The saving state is the ring on the neutral marker, the failed state is the amber mark on the same marker, and the saved state is the neutral marker. The labels and announcements are the same; nothing of the picture is on the camera screen at any moment.
- **Locking again** (review decision 5). With Lock Captures on, an unlocked library locks when the library is closed, and when a capture's viewer that was opened from the camera is closed back to the camera. Moving between the grid, a capture and Photo Details inside the library does not lock. So the camera screen never has an unlocked library behind it, however long the app stays in front.
- **Layout:** a grid of square thumbnails, newest first, in sections by day; an adaptive grid (three columns on an iPhone upright, more on wider windows). Each cell shows the format chip (RAW, HEIF, JPEG, or RAW + HEIF as one item) and the signed seal where it applies. At the largest text sizes the grid becomes a list: thumbnail, date, format, size.
- **The time of capture** is kept in the store for every capture, to order the library and make the day sections, including when the Date and Time detail is off and the file itself holds no time (review decision 9). Apart from this, the manifest holds nothing that the file's own detail switches removed. `docs/PRIVACY.md` says that a backup of the app carries these times.
- **One capture:** opens in the existing Last Photo viewer (paging, zoom, Photo Details), with Share, Save to Files, Save to Photos and Delete in its menu. What's in This Photo for a stored capture also lists "File name when exported" (string 52).
- **Select:** Select, Select All, and a section's "Select" for a whole day; then Share…, Save to Files…, Save to Photos, Delete. Progress and a summary for several ("9 exported. 1 could not be exported: …").
- **Empty:** "No Captures" with one sentence on what appears here.
- **Locked:** the lock symbol, "Captures Are Locked", Unlock. No thumbnails, counts, dates or sizes are drawn behind it. If the passcode has been removed, the screen says that setting one restores access and that nothing was deleted (string 47).
- **Unavailable:** if the app is running while the iPhone's protected data cannot be read (it was started while the phone was locked), the library shows the locked screen and the store reads, rebuilds, moves and deletes nothing (C1). This is a state of the store, not an error.
- **A file without its details** (a capture whose manifest could not be written or read) is listed with a plain label (string 53) and can be exported or deleted. It is never hidden and never deleted automatically (G2).
- **Privacy cover:** while the library, a capture or Photo Details is on screen and the scene becomes inactive, the cover replaces the content (the viewer's existing cover, extended). Whether the cover also hides the share sheet, the Files picker and a confirmation, which the system draws above the app's views, is a device check; if a picture shows, the share sheet gets a neutral header (the app's icon and a count, no image) and an open sheet is dismissed when the scene becomes inactive (E2).
- A session, for "export a whole session", is a day's section in 1.2.0. The manifest stores no session identifier.

## 3. Getting captures out

- **Share…** first asks As Saved or **Share Without Optional Details** (figure, panel A), then opens the system share sheet. The option was drafted as "Share Clean"; it was renamed because "clean" can be read as untraceable (review decision 8). The name is a draft for the owner's string review.
- **Removed from the share sheet** (review decision 12): Copy, Save Image, Assign to Contact and Print, and any other action that a device check shows writes to Photos or to a shared album. The app's own Save to Photos stays. If an action that writes to a shared album cannot be removed by type, the export note names it and the claim "cannot be added to a shared album by mistake" is not made for the share sheet.
- **Share Without Optional Details** shows its summary first (panel B), read back from the copy. Each row says "Removed" only when the stored file held that detail, and "Not in the file" otherwise. "What Stays in the File" includes the sensor-pattern sentence in the wording already used on the Honesty screen (string 33). If the read-back fails, nothing is shared and the screen says why.
- **As Saved** says when the file holds a location (string 31b).
- **File names** (review decision 7). A copy's name carries the date or time only when the Date and Time detail is in that copy. Otherwise the name is random. So a copy without optional details never has a dated name, and with the default details no exported name has one. Neutral File Names, when on, gives every copy a random name, for people who keep the date in the file but not in its name. The Share and Save to Files steps show the name the copy will have (string 51). Whether the same rule applies to photos saved straight to Photos, with Save Photos To set to Photos, is the plan's decision 29.
- **Save to Files…** opens the system's folder picker. A note before it, every time: the copy is outside the app's protection, and the place it goes keeps its own copy (string 30).
- **Save to Photos** makes a copy in Photos (add-only), keeping a RAW pair as one asset.
- **Space:** before several captures are exported, the app checks that there is room for the temporary copies and says how much is needed if there is not (string 54; E7).
- With Lock Captures on, an export from an unlocked library does not ask again; from anywhere else it asks first.
- If Share Without Optional Details is cut from the release, the share step says, for a file that holds optional details, that the copy includes them (string 31c).

## 4. Delete

- One capture or a selection: a confirmation that states the count and that there is no Recently Deleted (decided: a single delete always asks).
- **Delete All Captures…**: the confirmation states the count, that it cannot be undone, what it does not reach, and that restoring an earlier backup brings back the captures that were in it (string 36; figure, panel C). It does not say "now" or anything else about how fast or how completely storage is erased.
- While a burst or a series is running, or photos are still saving, Delete All stops it and discards the pending photos first, and its confirmation says so (string 55). No capture is saved after the delete (E4).
- Every delete also removes what the camera screen holds of the deleted captures: the Last Photo spot is reset and the session's records and previews for them are dropped. After Delete All the session viewer is empty (E1).

## 5. Saved wording

With nope only, the saved sentence names the place: "Saved in nope." and its signed and unsigned forms (strings 16 to 18; decided). The Photos sentences are unchanged.

## 6. The Lock Screen camera

- **It always keeps its captures in its own session folder**, whatever its copy of the settings says, and never writes to Photos (review decision 1). When the app is next opened with the iPhone unlocked, it files each capture by the setting at that moment: into Photos, or into the app's store. A stale or missing copy of the settings therefore cannot send a capture to the wrong place.
- **Its sentence is not "Saved."** A capture in the session folder has not reached either place, so the Lock Screen camera says it is kept and what finishes the save (string 41). This is also the sentence when Save Photos To is Photos: a photo taken from the Lock Screen camera reaches Photos when the app is next opened unlocked, which is later than in 1.0.0. The release notes say so.
- **A failed write is always shown.** The Lock Screen camera has no storage warning of its own, so every failed write shows the existing "Not saved" state with the reason, and a partial file is removed (A3).
- **Nothing of a capture with Lock Captures on:** as decided in 2026-11-18, the Lock Screen camera then shows no thumbnail or details. It learns that setting from its copy of the settings, which can be out of date; what it shows in that case is an open question for the owner (plan, decision 27).
- **This design is conditional on a device check.** It is built only if R4 shows that the session folder keeps its content (through a restart, a week without the app being opened, and low storage) and that its files, once written, cannot be read while the iPhone is locked. **If the check fails,** the review's fallback is built instead: nothing is kept in the session folder; a change of Save Photos To takes effect only once the app has read the Lock Screen camera's copy back, and a failed read-back is shown on the page as a change that was not made; with nope only in effect the Lock Screen camera does not take photos and says why (string 42); with Photos it saves as in 1.0.0.

## 7. Limits the wording must cover

The limits text itself is written with part 6 of the issue, after the device checks. The review adds these to what it must cover, each only as far as its check or source supports:

- Lock Captures and iOS protection start a few seconds after the iPhone locks, are as strong as the passcode, and do not exist while the iPhone is unlocked, including while Keep Screen On holds the screen on (C3). The Keep Screen On entry on the Honesty screen gains a sentence for captures kept in the app.
- A computer the iPhone already trusts, and a backup to a computer that is not encrypted (B3).
- Settings are kept outside the store and are in every backup, so a backup shows that captures were kept in the app and locked (B4).
- iPhone Mirroring, by the result of its device check (C4).
- Records iOS keeps: App Privacy Report, the app's storage size, and the system log's record that the app asked for authentication (E6).
- The app cannot erase storage; a deleted file is removed, not overwritten (E4).
- What a share route adds outside the file, per route checked (F4).
- Which export option suits which purpose: a copy without optional details has no date and no signature, so it is the wrong choice for a record (F5).
- A phone managed by an employer or school (G3).
- A hostile app update (owner, 2026-11-21; also the checklist item "Update nope. yourself", string 70): an update to nope. that runs on the phone can read everything the app can read, including captures kept in the app while it is unlocked, and could add a network connection the current app does not have. Lock Captures does not protect against the app itself. For high-risk use, automatic updates can be turned off and each release's notes and source read before updating. The text claims no protection against this.
- Advanced Data Protection (owner, 2026-11-21): the same suggestion as string 44a, with every limit in full, each as Apple's pages state it (section 10.9, H9 to H11):
  - it end-to-end encrypts iCloud Backup, iCloud Photos and iCloud Drive, among other categories;
  - Apple still holds the keys to some metadata. For a backup: the date, time and size of each snapshot, the device's name, model, color and serial number, and the list of apps and file formats in it. For a photo in iCloud Photos: a checksum of the file, when it was created, imported and modified, whether it is a favorite, hidden or deleted, and how often it was viewed. For a file in iCloud Drive: checksums of its content and of its name, its type, size and dates;
  - shared albums and items shared by a public link are not end-to-end encrypted, with it on or off;
  - it does not cover a backup to a computer;
  - it needs a recovery contact or recovery key, and Apple cannot recover the data for a person who has lost access;
  - it is not available everywhere;
  - the app does not know whether it is on, and says so.
- The High-Risk Checklist (section 10) is a list of iPhone settings and habits, not a statement about this phone: the app cannot see or change any of them. The Honesty screen links to it with string 81.

## 8. Accessibility

- VoiceOver: each capture is one element, "Photo, 21 November, 2:14 PM, RAW, signed", with actions Share, Save to Files, Save to Photos, Delete. Selecting is a trait, not a color. The locked screen reads its title, sentence and Unlock, nothing else.
- The neutral marker is a button labeled "Captures, locked"; while a photo saves it is not a button and reads "Last photo, saving" (string 8).
- The backup question reads its title, its message and three buttons of equal weight. It has no default action, so Return on a keyboard and the VoiceOver magic tap choose nothing.
- Dynamic Type to the largest sizes: the list layout above; export and delete actions wrap, never truncate; the option name "Share Without Optional Details" wraps to two lines.
- Night Mode: thumbnails drawn red like the viewer; settings rows `#1C0000` on black as elsewhere.
- Voice Control names match the visible labels. Switch Control and Full Keyboard Access reach every action; Escape closes the library, which locks it when Lock Captures is on.
- The High-Risk Checklist: section 10.5.
- Authentication prompts are the system's. A device check completes the prompt with VoiceOver and with Switch Control, with and without Passcode Only (D8).

## 9. Draft strings

For the Honesty review. "H" marks a sentence that states what is or is not protected, saved or processed; it goes in `Honesty.xcstrings`. English (U.S.) only in 1.2.0; Spanish follows with issue 87 in 1.3.0. **The numbers continue from the 1.1.0 design and are not changed:** strings 1 to 12 are in [release-1.1.md](release-1.1.md), section 6; 13 to 40 were first drafted there for this issue; 41 to 56 were added with the review decisions; 44a was rewritten and 44b and 57 to 100 added for section 10.

| # | Where | Text | H |
| --- | --- | --- | --- |
| 13 | Settings › Privacy, row | Save Photos To | |
| 14 | Its choices | Photos · nope only | |
| 15 | Settings › Privacy, row | Lock Captures | |
| 16 | Saved, nope only, signed | Saved in nope. and signed. | H |
| 17 | Saved, nope only, signing off | Saved in nope. Not signed: signing is off in Settings. | H |
| 18 | Saved, nope only, other unsigned reasons | Saved in nope. Not signed: (the existing reason) | H |
| 19 | Library title; Last Photo spot button | Captures | |
| 20a | Save Photos To footer, nope only, captures kept in backups | New photos are kept in nope. and are not added to Photos. They are in this iPhone's backups, including iCloud Backup. Photos already in Photos stay there: nope. can add photos but can't read or move them. | H |
| 20b | Save Photos To footer, nope only, captures left out | New photos are kept in nope. and are not added to Photos. nope. has asked iOS to leave them out of this iPhone's backups. Photos already in Photos stay there: nope. can add photos but can't read or move them. | H |
| 21 | Save Photos To footer, Photos, while captures are held | New photos go to Photos. The captures already in nope. stay here until you export or delete them. | H |
| 22 | Under the Captures row | Deleting the app deletes these. Export the ones you want to keep. | H |
| 23 | Leave Out of Backups, explanation | nope. asks iOS to leave these captures out of this iPhone's backups. iOS treats this as a request, not a guarantee, and it does not cover a copy of the phone's storage made another way. Left out, captures are lost if the phone is lost and do not move to a new phone. | H |
| 24 | Notice with no passcode | This iPhone has no passcode, so iOS does not protect the captures kept in nope. Anyone who has the phone can read them. | H |
| 25 | Neutral File Names, explanation | A copy's name includes the date and time only when the file itself holds them. With this on, every exported or shared copy, and every photo saved to Photos, gets a random name. | H |
| 26 | Lock Captures, explanation | Viewing, sharing and deleting captures kept in nope. asks for Face ID or the passcode. Taking photos never asks, and the camera screen shows no picture of a capture kept in nope. | H |
| 27 | Lock Captures footer | A gate inside the app, not encryption. Anyone with the iPhone's passcode can open it. It does not cover copies in Photos or already shared, and it does not stop someone with the unlocked iPhone from deleting nope. and every capture in it. | H |
| 28a | Lock Captures page, without Lock Again (the default outcome) | Captures lock again when you go back to the camera, leave nope. or lock the iPhone. | H |
| 28b | Lock Again footer (only if the device check passes) | The time counts from when you leave nope. Captures always lock again when you go back to the camera, when the iPhone locks, and when nope. is closed. | H |
| 29 | Locked library | Captures Are Locked · Use Face ID or the passcode to see them. · Unlock | |
| 30 | Before Save to Files and the share sheet | The copy leaves nope.'s protection. The app or place you send it to keeps its own copy. The capture in nope. is not changed. | H |
| 31 | Share choices | As Saved: every detail in the file, and its signature. · Share Without Optional Details: a copy with the optional details removed. | H |
| 31b | As Saved, when the file holds a location | As Saved: every detail in the file, including its location, and its signature. | H |
| 31c | Share step, only if Share Without Optional Details is cut | This copy includes the optional details in the file. | H |
| 32 | Summary, signature (when the stored file was signed) | The copy is not signed: a signature does not survive a change to the file. | H |
| 33 | Summary, What Stays in the File | Color and size data that the file needs to open can point to the phone model, and possibly to the individual phone. Every camera sensor also leaves a faint, unique noise pattern in the picture. With enough of your photos, forensic tools can match them to the same camera. No app can fully remove it. The picture itself is not changed. | H |
| 34 | Share Without Optional Details, check failed | Not shared: nope. couldn't confirm that the copy holds only the details listed. | H |
| 35 | Delete All, title and button | Delete %lld Captures? · Delete %lld Captures | |
| 36 | Delete All, message | This deletes every capture kept in nope. It can't be undone. It does not reach copies in Photos, in iCloud, in backups or already shared. Restoring an earlier backup brings back the captures that were in it. | H |
| 37 | Delete, one or several | There is no Recently Deleted. This can't be undone. | H |
| 38 | Empty library | No Captures · Photos you keep in nope. appear here. | |
| 39 | Face ID usage text (Info.plist) | nope. uses Face ID to unlock the captures you keep in the app. | H |
| 40 | Viewer, for a photo kept in the app | Show in Captures | |
| 41 | Lock Screen camera, after a photo | Kept. Open nope. after unlocking to finish saving. | H |
| 42 | Lock Screen camera, only if the session-folder check fails and nope only is chosen | Photos can't be kept in nope. while the iPhone is locked. Unlock and open nope. to take photos. | H |
| 43 | Backup question, title | Keep Captures in This iPhone's Backups? | |
| 44 | Backup question, message | Captures kept in nope. are not in Photos. In backups, they can be restored to a new phone, and anyone who can open the backup can read them. Left out, they are lost if the phone is lost or replaced. | H |
| 44a | Backup question, second paragraph | Apple's Advanced Data Protection end-to-end encrypts iCloud Backup, so only your trusted devices hold the keys. Apple can still read some details, such as each backup's date, time and size and which apps are in it. It does not cover backups to a computer, needs a recovery contact or key, and is not available everywhere. You turn it on in the Settings app. nope. can't tell whether it's on. | H |
| 44b | Backup question, last line | More in Settings › Privacy › High-Risk Checklist. | |
| 45 | Backup question, buttons | Keep in Backups · Leave Out of Backups · Cancel | |
| 46 | Passcode Only, explanation | Face ID can be used by someone holding the phone to your face. With this on, only the passcode opens your captures. | H |
| 47 | Locked library, the passcode was removed | This iPhone has no passcode. Set one in the Settings app to open your captures. Nothing was deleted. | H |
| 48 | Details in Each Photo footer, added sentence | For a photo kept in nope., the time it was taken stays inside nope. to keep your captures in order, even with Date and Time off. It is not written into the file. | H |
| 49 | Factory Defaults confirmation, added sentence | Save Photos To, Lock Captures and Leave Out of Backups stay as they are. | H |
| 50 | Save Photos To, while a burst, series or bracket runs | Stop the series to change where photos are saved. | |
| 51 | Share and Save to Files steps | File name · (the name the copy will have) · The name holds the date and time only when the file itself holds them. | H |
| 52 | What's in This Photo, for a stored capture | File name when exported | |
| 53 | Library, a file without its details | Photo, details not available | |
| 54 | Export of several, not enough space | Not exported: this needs about %@ of free space. | H |
| 55 | Delete All while a series runs or photos are saving, added sentence | The series stops, and photos still being saved are not kept. | H |
| 56 | Last Photo spot with Lock Captures on, VoiceOver | Captures, locked | |
| 57 | Settings › Privacy, row; page title | High-Risk Checklist | |
| 58 | The row's second line | iPhone settings and habits. nope. can't see or change them. | H |
| 59 | Checklist, opening | Most of what protects the photos on this iPhone comes from iOS and its passcode, not from nope. These are settings and habits that Apple documents. nope. can't see or change any of them, and doesn't know which you use. | H |
| 60 | Checklist, headings | This iPhone · If the iPhone May Be Taken · Backups · Getting Captures Off This iPhone · nope. | |
| 61 | Item, This iPhone | Use a longer passcode · iOS protection of a locked iPhone rests on the passcode. A longer one with letters and numbers takes longer to guess. · Settings app › Face ID & Passcode › Change Passcode › Passcode Options › Custom Alphanumeric Code | H |
| 62 | Item, This iPhone | Turn on Stolen Device Protection · Away from familiar places such as home or work, iOS asks for Face ID with no passcode fallback for some actions, and waits an hour before some changes. It needs Find My and Significant Locations, and it may already be on. · Settings app › Face ID & Passcode › Stolen Device Protection | H |
| 63 | Item, This iPhone | Set a short Auto-Lock · Auto-Lock sets how long the iPhone waits before it locks itself. iOS protection for captures kept in nope. starts a few seconds after the iPhone locks, not before. · Settings app › Display & Brightness › Auto-Lock | H |
| 64 | Item, This iPhone | Consider Erase Data · With Erase Data on, iOS erases the iPhone after 10 failed passcode attempts in a row. Captures kept in nope. that are not in a backup are then lost. · Settings app › Face ID & Passcode › Erase Data, at the bottom | H |
| 65 | Item, This iPhone | Consider Lockdown Mode · Apple describes Lockdown Mode as optional, extreme protection for the very few people who may be personally targeted by sophisticated digital threats. Some apps, websites and features are limited, and the iPhone must be unlocked to connect to a computer or an accessory. · Settings app › Privacy & Security › Lockdown Mode. The iPhone restarts. | H |
| 66 | Item, If the iPhone May Be Taken | Turn off Face ID quickly · Press and hold the side button and either volume button for 2 seconds. When the sliders appear, press the side button to lock the iPhone. Face ID stays off until the passcode is entered. · No setting: it works from the buttons. | H |
| 67 | Item, If the iPhone May Be Taken | Restart or turn off the iPhone · After an iPhone is turned on or restarted, Face ID does not work until the passcode is entered. To turn it off, hold the side button and either volume button until the slider appears, then drag the slider. | H |
| 68 | Item, Backups | Consider Advanced Data Protection · Apple's Advanced Data Protection for iCloud end-to-end encrypts iCloud Backup, iCloud Photos and iCloud Drive, so only your trusted devices hold the keys. Apple can still read some details. For a backup: its date, time and size, the device's name, model and serial number, and the list of apps in it. For a photo: a checksum of the file and when it was created. It does not cover backups to a computer or shared albums. It needs a recovery contact or recovery key; if you lose access, Apple can't recover this data for you. It is not available everywhere. nope. can't tell whether it's on. · Settings app › your name › iCloud › Advanced Data Protection | H |
| 69 | Item, Backups | Encrypt backups to a computer · A backup to a Mac or PC is not encrypted unless you select Encrypt local backup. Without it, anyone who can open the computer's files can read the backup. If you forget the backup password, you can't use that backup. · On the computer: Finder or the Apple Devices app › your iPhone › General › Encrypt local backup | H |
| 70 | Item, nope. | Update nope. yourself · An update to nope. can read everything nope. can read, including captures kept in the app. nope. can't protect against its own updates. With App Updates off, the App Store tells you about each update and does not install it, so you can read the release notes first. The switch is for every app: other apps also wait for you, including their security fixes. · Settings app › Apps › App Store › App Updates | H |
| 71 | Getting Captures Off This iPhone, opening | nope. sends nothing itself. Each way below uses Share… or Save to Files… in Captures. A copy that leaves nope. is outside nope.'s protection: whoever receives it controls it from then on. For a record, choose As Saved: the copy keeps its details and its signature. For publishing, choose Share Without Optional Details: the copy has no date and no signature. | H |
| 72 | Item, Getting Captures Off This iPhone | Send in an encrypted messaging app · Use Share… and pick a messaging app you already trust that is end-to-end encrypted, with disappearing messages if it has them. The person you send to then holds a copy and can keep, forward or screenshot it; disappearing messages don't prevent that. Some messaging apps shrink or change photos, which removes the signature. nope. can't tell what an app does with a file: check that app's own documentation. | H |
| 73 | Item, Getting Captures Off This iPhone | Save to storage you trust · Save to Files… copies to a folder you choose: iCloud Drive, a cloud storage service you trust with end-to-end encryption turned on, or a connected drive. Whoever runs that place then controls the copy. With Advanced Data Protection on, iCloud Drive is end-to-end encrypted, and Apple can still read some details, such as the file's type, size and dates. A folder under On My iPhone is still on this iPhone. | H |
| 74 | Item, Getting Captures Off This iPhone | AirDrop to your own device · AirDrop sends a copy to a nearby Apple device over Wi-Fi and Bluetooth. Send to a device you control. That device's passcode, settings and backups then decide who can read the copy. | H |
| 75 | Item, Getting Captures Off This iPhone | Back up to a computer, encrypted · An encrypted backup to a Mac or PC includes the captures kept in nope., unless you chose Leave Out of Backups. It is a copy for restoring an iPhone, not a folder of photos. The computer and the backup password then control it. | H |
| 76 | Item, Getting Captures Off This iPhone | Use your organization's documentation tool · If an organization you work with gave you a tool for sending in documentation, use it the way they told you. Some tools accept files shared from other apps; some accept only photos taken inside them. The organization then controls the copy. nope. doesn't check or recommend any tool. | H |
| 77 | Item, Getting Captures Off This iPhone | Then keep fewer captures in nope. · When you have opened the copy where you sent it and it is complete, delete the capture from nope. The fewer captures nope. holds, the fewer there are to find on this iPhone. A delete does not reach copies in Photos, in backups or already shared, and nope. can't erase storage. | H |
| 78 | Checklist, link labels | Apple: Set a passcode · Apple: Stolen Device Protection · Apple: Auto-Lock · Apple: Erase Data · Apple: Lockdown Mode · Apple: Face ID · Apple: Restart your iPhone · Apple: Advanced Data Protection · Apple: Encrypted backups · Apple: App updates · Apple: iCloud data security · Apple: AirDrop | |
| 79 | Checklist, closing | This list is not complete, and it is not advice for your situation. Apple can change these settings. Checked against Apple's support pages in %1$@, for iOS %2$@. | H |
| 80 | Checklist, closing, about the links | Links open Apple's website in your browser. nope. itself makes no network connection. | H |
| 81 | Link under the Save Photos To footer and the Lock Captures footer, and on the Honesty screen | Most protection comes from the iPhone's own settings. High-Risk Checklist | H |
| 82 | VoiceOver hint on each link | Opens Apple's website in your browser. | |
| 83 | Checklist, row under the opening; title of its page | Ways Others May Try to Get Your Photos | |
| 84 | That page, opening | The ways known today, in plain words. For each: what helps, and what nope. can't do. | H |
| 85 | Route | Someone holding the unlocked iPhone · Anyone holding the iPhone while it is unlocked can open Photos, and can open nope. unless Lock Captures is on. · What helps: Lock Captures; a short Auto-Lock; locking the iPhone before it leaves your hand. · nope. can't stop that person from deleting nope. and every capture in it. | H |
| 86 | Route | Being made to unlock · Someone can hold the iPhone up to your face, or demand the passcode. · What helps: Turn off Face ID quickly; Passcode Only in Lock Captures. · Once the passcode is given, it opens the iPhone and Lock Captures. nope. adds nothing against that. | H |
| 87 | Route | A passcode seen or guessed · A passcode that was watched while you typed it, or is short enough to guess, opens the iPhone and Lock Captures. · What helps: a longer passcode; Stolen Device Protection; Erase Data. · nope. has no passcode of its own. It relies on the iPhone's. | H |
| 88 | Route | Forensic tools, after the iPhone is taken · Some tools copy data from a locked iPhone. An iPhone that has been unlocked since it was last restarted keeps more of its data reachable than one that was restarted and not unlocked since. · What helps: Restart or turn off the iPhone; a longer passcode; a short Auto-Lock; Lockdown Mode. · nope. can't tell what such a tool can do and promises nothing against one. | H |
| 89 | Route | iCloud, from Apple · Without Advanced Data Protection, Apple holds the keys to iCloud Backup and iCloud Photos, and can be required by law to hand over what it holds. · What helps: Advanced Data Protection; Leave Out of Backups; Save Photos To set to nope only, which keeps new photos out of Photos. · nope. can't tell whether Advanced Data Protection is on. With it on, Apple can still read some details. | H |
| 90 | Route | A backup on a computer · A backup on a Mac or PC that is not encrypted can be read by anyone who can open that computer. A computer this iPhone already trusts may be able to make one. · What helps: Encrypt backups to a computer; Leave Out of Backups; Lockdown Mode. · Leave Out of Backups is a request to iOS, not a guarantee. | H |
| 91 | Route | Copies you already shared · A copy you sent is held by the person and the service that received it, and they can pass it on. · What helps: sharing less, and choosing who receives it; Getting Captures Off This iPhone. · nope. can't reach, change or delete a copy that has left it. | H |
| 92 | Route | Photos saved before nope only · Photos saved to Photos earlier are still there: in iCloud Photos if you use it, in any shared album they were added to, and in Recently Deleted for a time after you delete them. · What helps: deleting them in the Photos app, and then from Recently Deleted. · nope. can add photos to Photos but can't read, move or delete them. | H |
| 93 | Route | What a shared file says · A file can carry its date, place and phone model. Every camera sensor also leaves a faint noise pattern that can link photos to one phone. · What helps: Details in Each Photo; Share Without Optional Details. · No app can fully remove the sensor's pattern. | H |
| 94 | Route | The screen · Whatever is on the screen can be recorded, mirrored to another screen, viewed remotely, captured in a screenshot, or photographed. · What helps: opening captures only where the screen is yours alone. · nope. can't block screenshots or screen recording. | H |
| 95 | Route | A managed iPhone · An iPhone set up by an employer or school follows that organization's settings. · What helps: an iPhone that nobody else manages. · nope. can't see or change what the organization has set. | H |
| 96 | Route | Spyware or a compromised iPhone · Software that has taken over the iPhone can see what you see, including a capture while it is open. · What helps: Lockdown Mode, which Apple made for people who may be personally targeted. · nope. can't detect spyware or a modified iPhone, and doesn't claim to. | H |
| 97 | Route | An update to nope. itself · An update, whether made in bad faith or under compulsion, can read everything nope. can read and could add a network connection. · What helps: Update nope. yourself; reading each release's notes and source first. · nope. can't protect against its own updates. | H |
| 98 | Route | Deleted files · Deleting removes a file from nope. It does not overwrite the iPhone's storage, which can keep deleted data for a time, and earlier backups still hold the file. · What helps: keeping fewer captures; Leave Out of Backups. · nope. can't erase storage and has no feature that claims to. | H |
| 99 | That page, closing | These are the ways known today. Others likely exist that are not known yet: new tools, and flaws not yet found in iOS or in apps. No app and no phone can promise protection against those. | H |
| 100 | That page, link to the full text | The full text, with sources · Opens the Photivra Nope Camera privacy document in your browser. | |

Notes on the issue 83 strings:

- **Two reviews** (review decision 14, which amends the plan's decision 26 for issue 83). The owner reviews strings 20 to 24, 26 to 28, 30 to 33 and 36 from this table, as rewritten here with their lettered forms, before group S1 starts. The numbers are the ones these strings had in the 1.1.0 design, so the review list on the issue points to the same sentences; the design is built on them. The new strings marked H (31b, 31c, 41, 42, 44, 46 to 49, 51, 54, 55) came from the same decisions and are in the table for that pass. Every string is reviewed again in the built app before the release run.
- **Rewritten on 2026-11-21:** 20 (now 20a and 20b), 23, 24, 25, 26, 27, 28 (now 28a and 28b), 30, 31, 32 (its condition), 33, 34 (its name), 36. New: 31b, 31c, 41 to 56. Unchanged: 21, 22, 29, 35, 37 to 40.
- **Backup kinds.** Strings 20a, 20b, 23 and 44 name a kind of backup only as far as R4 confirmed it. "Including iCloud Backup" in 20a rests on Apple's documentation and is confirmed on a device before it is final. Where R4 confirms which kinds honor the request, 20b and 23 name those kinds in place of "this iPhone's backups".
- **String 27** follows the iPhone Mirroring check: if the prompt can be answered from a Mac with something other than the iPhone's passcode, the sentence names it.
- **String 33.** "And possibly to the individual phone" stays unless a comparison of the locked values across two phones of one model shows they do not differ; with no second phone, it stays. The sensor sentences are the wording of `docs/research/privacy-claims.md`, claim 9, as on the Honesty screen.
- **Face ID** in strings 26, 29, 46 stands for the device's own method (Face ID, Touch ID or Optic ID), as in the system's wording.
- **String 44a** was rewritten on 2026-11-21 to state the limits of Advanced Data Protection (section 1). It joins the owner's first review. If it is still too long for the question, the first cut is "You turn it on in the Settings app.", which the checklist item (string 68) also carries as its path.
- **Strings 57 to 82** are the High-Risk Checklist (section 10). Each item's cell is its title, its text and, where there is one, the place to go, separated by "·"; each is one localized string per part, never joined from fragments. Every sentence that states what iOS, Apple or the app does or does not do is marked H, including the paths. The source for each is in section 10.4 and 10.6.
- **No third-party app or service is named** in strings 57 to 82 or anywhere else in the checklist (owner, 2026-11-22). Kinds are described: "an end-to-end encrypted messaging app", "a cloud storage service you trust", "your organization's documentation tool". Apple's own features are named.
- **Strings 83 to 100** are the page "Ways Others May Try to Get Your Photos" (section 10.7). Each route's cell is its title, what happens, what helps and what the app cannot do; each part is one localized string. They name no tool, product or authority, and give no steps. Strings 88, 90 and 94 follow device checks: 88's second sentence rests on Apple's description of the protection classes (H16) and on R4; 90's second sentence is the review's check of a backup made by a trusted computer while the iPhone is locked, and is left out if that check does not show it; 94 gains a sentence about covering captures only if that is built and its check passed.
- **Strings that wait for a check:** 63 (its second sentence follows the same check as the first limit in section 7), 64 and 75 (what is in a backup, by R4's backup result and the answer to Leave Out of Backups), 71 (its last sentence is left out if Share Without Optional Details is cut). None of 57 to 82 says anything about Lock Captures under Stolen Device Protection, the app in Lockdown Mode, or what AirDrop shows the receiving device; a sentence on each is added only from its recorded device check.
- **String 79** takes the month and the iOS version from the review record (section 10.8), so the page never states a date that no review supports.
- **The name "Share Without Optional Details"** is a draft. "Share Clean" is not used in the interface; the issue and older notes call this part "Share clean".

The limits issue 83 lists under "Limits to state plainly" (what stays in a file, the sensor pattern, screenshots, that the app cannot hide that it is installed), and those the review adds (section 7), are Honesty screen entries and `docs/PRIVACY.md` text, written with part 6 of the issue once the device checks are in; they are not drafted here.

## 10. The High-Risk Checklist

Added at the owner's request on 2026-11-21, and extended on 2026-11-22 with the ways to get captures off the phone. Figure: [release-1.2/high-risk-checklist.svg](release-1.2/high-risk-checklist.svg). Nothing here is built.

Most of the protection that issue 83 relies on comes from the iPhone and its passcode, not from the app. The research on hardening (`docs/research/83-security-hardening.md`, on branch `research-83-hardening` until it is merged; its decision 9 and its addendum on a hostile update) put that guidance in `docs/PRIVACY.md`. The owner wants it inside the app as well. This section designs one static page for it.

### 10.1 What the page is, and is not

- **A static list.** Text, in five groups, with links to Apple's pages, and one row that opens a second static page (10.7). No checkmarks, no switches, no "done" state, no status, no count, no progress, no badge on the row.
- **The app cannot detect these settings and never implies that it can.** No public interface tells an app the passcode's length, the Auto-Lock time, or whether Erase Data, Stolen Device Protection, Lockdown Mode, Advanced Data Protection, automatic updates or backup encryption are on. The page says so in its first paragraph (string 59) and the row says so in its second line (string 58).
- **The page stores nothing.** It writes no setting, so no backup or settings hand-off shows that it was opened or which items were read. It is not in presets, has no assistant action, and Factory Defaults has nothing to reset.
- **It holds no capture data**, so it is not behind Lock Captures and opens without authentication.
- **It is called a checklist** because the owner named it so. The name is a draft for the string review; the page has nothing to check off.
- **It adds no feature for sending.** The part on getting captures off the phone (10.6) describes the export and share routes of section 3 and nothing else: no upload, no server, no new share target.

### 10.2 Entry point

Drawn as recommended; the choices are the plan's decisions 30 and 31.

- **A row, "High-Risk Checklist"** (string 57), as the last row of Settings › Privacy, below Assistant Access (figure, panel A). It has a second line (string 58) and no value, because the app has no state to show.
- **Shown to everyone,** whichever way Save Photos To and Lock Captures are set. Most of the list also applies to photos saved to Photos, and a row that appeared only with those settings on would itself show that they are on.
- **Not shown in the Lock Screen camera's Settings.** That screen shows neither of the two rows of issue 83 (review decision 13), and a link to a website is not expected to open while the iPhone is locked (an assumption, not checked). The page is reached after unlocking.
- **Settings search** finds the page by its title and by each item's title ("Lockdown Mode" gives "High-Risk Checklist, in Privacy").
- **Q, the quick menu, is unchanged.** The page is not reached from the camera screen.

### 10.3 Links to the page from elsewhere

- **The backup question** ends with a pointer in words (string 44b; figure, panel D). It is not a link and not a fourth button: the question keeps three buttons of equal weight and nothing that leads out of it. The plan's decision 32.
- **The Save Photos To footer** and **the Lock Captures footer** each end with a link to the page (string 81). On the Lock Captures page the link is outside the part that needs authentication to change.
- **The Honesty screen** links to it with the same string, under the limits of section 7.
- The Captures library, the share steps and the camera screen do not link to it.

### 10.4 The items about the iPhone

Eleven items were asked for. Ten are below; the eleventh, keeping fewer captures, is the last step of 10.6. For each: what Apple's page states (the only part the string may rest on), what the app adds, and where the person is sent. "H" numbers are the sources in 10.9.

| String | Item | Apple's page states | Added by the app, and its basis | Where |
| --- | --- | --- | --- | --- |
| 61 | A longer passcode with letters and numbers | The passcode options include Custom Alphanumeric Code (H1). A stronger passcode makes the key that protects the data stronger, and a longer alphanumeric passcode takes far longer to try (H2) | Nothing | Settings app, in words |
| 62 | Stolen Device Protection | Away from familiar locations, some actions need Face ID or Touch ID with no passcode fallback, and some changes wait an hour; it needs Find My and Significant Locations; it may already be on (H3) | Nothing. Whether it changes what the app's own Lock Captures prompt accepts is not stated by Apple and is a device check; the item is silent on it | Settings app, in words |
| 63 | A short Auto-Lock | Auto-Lock sets the time before the iPhone locks (H1, H4) | That iOS protection for captures kept in the app starts a few seconds after the lock: Apple's description of the Complete class (H16), and the same device check as the first limit of section 7 | Settings app, in words |
| 64 | Erase Data after 10 failed attempts | Erase Data removes all information, media and settings after 10 failed passcode attempts in a row; afterwards the iPhone is restored from a backup or set up as new (H1) | That captures kept in the app and left out of backups are lost: section 1 | Settings app, in words |
| 65 | Lockdown Mode | It is optional, extreme protection for the very few people who may be personally targeted; some apps, websites and features are limited; the device must be unlocked to connect to a computer or accessory; turning it on restarts the iPhone (H8) | Nothing. How the app behaves in Lockdown Mode is a device check of R4; a sentence is added only from its result | Settings app, in words |
| 66 | Turning Face ID off quickly | Holding the side button and either volume button for 2 seconds shows the sliders; pressing the side button then locks the iPhone; Face ID works again after the passcode is entered (H5) | Nothing | No setting; the buttons |
| 67 | Restarting before the iPhone may be taken | After an iPhone is turned on or restarted, the passcode is required before Face ID or Touch ID works (H1, H6); how to turn it off (H7) | The moment: the heading "If the iPhone May Be Taken". The text names no authority, place or tool | No setting; the buttons |
| 68 | Advanced Data Protection for iCloud | What it covers, what metadata Apple still holds, what it needs, that Apple cannot recover the data, and where it is not offered (H9, H10, H11); section 7 | That the app cannot tell whether it is on | Settings app, in words |
| 69 | Encrypted computer backups only | A backup to a computer is not encrypted by default; Encrypt local backup is in the Finder, the Apple Devices app or iTunes; a forgotten password makes earlier encrypted backups unusable (H13) | That an unencrypted backup can be read by anyone who can open the computer's files: review finding B3 | On the computer, in words |
| 70 | Automatic App Store updates off, for high-risk use | Apps update automatically by default; Settings › Apps › App Store › App Updates turns that off; the App Store then notifies of each update (H12) | The hostile-update limit of section 7, and that the switch is for every app, so other apps' fixes also wait | Settings app, in words |

Rules for these items:

- **Wording follows the page, not memory.** A sentence about iOS that the cited page does not state is removed, or becomes a device check.
- **Each item has one link,** to the Apple page it rests on (string 78). Item 68 has two (H9 and H10).
- **Face ID** in strings 61 to 67 stands for the device's own method, as in section 9. On a device with Touch ID the path reads "Touch ID & Passcode". Items 66 and 67 name buttons that differ by model; their text for models without Face ID is written from Apple's page for that model when S1 builds the page, or the item is not shown on that model.
- **"Consider"** is used where the setting can lock the person out or erase data (Erase Data, Lockdown Mode, Advanced Data Protection). The page states the cost in the same item.
- **Not on the page:** anything the review or the hardening research lists that has no Apple page to rest on. A managed phone (G3) and trusted computers (B3) stay in `docs/PRIVACY.md`'s section, outside the table.

**Opening the Settings app.** Apple documents three URL strings that open the Settings app: the app's own settings page, the app's notification settings, and the default-apps page (H15). None opens Face ID & Passcode, Display & Brightness, Privacy & Security, iCloud or App Store. So no item has a button that opens Settings; every item says where to go in words. The `prefs:` and `App-prefs:` schemes are not documented and are not used. If Apple documents a URL for one of these screens later, that item gains a button at the next review.

### 10.5 Accessibility

- **VoiceOver order:** the title; the opening paragraph; then, group by group, the heading, and for each item its text followed by its link. Headings have the heading trait, so the rotor moves by group. An item's title, text and place are one element, read in that order; the link is the next element, a link with the hint of string 82. Nothing on the page has the selected, checked or toggled trait.
- **Paths** are read as written, with "›" spoken as a pause, not as "greater than". Each path is one localized string, so its order can follow the language in right-to-left layouts.
- **Largest text:** one column at every size. Titles, text, paths and link labels wrap and never truncate. No two things sit side by side, so nothing has to reflow.
- **Night Mode:** rows `#1C0000` on black and red text as on other settings pages, with the contrast values of release 1.1's design, section 3. A link is marked by its underline and the arrow symbol, not by color, so it is still a link when everything is red.
- **Differentiate Without Color, Increase Contrast, Bold Text, Button Shapes:** nothing on the page uses color for meaning.
- **Voice Control:** every link label is different ("Apple: Lockdown Mode"), so each can be spoken. Switch Control and Full Keyboard Access reach every link; Escape goes back.
- **Reduce Motion:** the page has no animation.
- **Cognitive:** short sentences, one idea per item, the same three parts in the same order in every item. The opening and the closing say what the page is not.
- **The backup question** with string 44a is longer than before. At large text sizes its message scrolls above the three buttons, which stay visible and equal.

### 10.6 Getting captures off the phone

Added 2026-11-22. A group on the same page, "Getting Captures Off This iPhone" (strings 71 to 77), in the same source of truth. It uses only what section 3 already has: Share… (As Saved, or Share Without Optional Details), Save to Files… and the backups of section 1. Nothing is sent by the app.

The group opens with three statements that hold for every way (string 71): the app sends nothing itself; a copy that leaves the app is outside its protection and under the control of whoever receives it; and which export option fits which purpose. **A signed copy with its details (As Saved) suits a record. Share Without Optional Details suits publishing:** it has no date and no signature (section 7, F5).

| String | Way | Route in the app | Who controls the copy afterwards | Trade-off the item states | Basis |
| --- | --- | --- | --- | --- | --- |
| 72 | An end-to-end encrypted messaging app, with disappearing messages | Share… | The person it is sent to, and that app | The recipient can keep, forward or screenshot it; disappearing messages do not prevent that. Some messaging apps shrink or change a photo, which removes the signature. The app cannot tell what another app does | No product is named and nothing is promised about any. The person is sent to that app's own documentation |
| 73 | Storage the person trusts: iCloud Drive, a cloud storage service with end-to-end encryption turned on, or a connected drive | Save to Files… | Whoever runs that place | With Advanced Data Protection, iCloud Drive is end-to-end encrypted and Apple can still read the file's type, size and dates and checksums of its content and name (H10). "On My iPhone" is still on this phone | H10; section 3 |
| 74 | AirDrop to a device of the person's own | Share… | That device: its passcode, settings and backups | It goes to a nearby Apple device over Wi-Fi and Bluetooth (H14), so only to a device the person controls. What the receiving device records about the sender is device check 9; a sentence is added only from its result | H14; review finding F4 |
| 75 | An encrypted backup to a computer | The backup of section 1; no step in the app | The computer and the backup password | It is a copy for restoring an iPhone, not a folder of photos; captures left out of backups are not in it | H13; R4's backup result |
| 76 | The documentation tool of an organization the person already works with | Share… or Save to Files…, if the tool accepts files | That organization | Some tools take shared files and some take only photos made inside them. The app checks and recommends none | No product is named |
| 77 | Then keeping fewer captures in the app | Delete, section 4 | Not applicable | Delete only after the copy has been opened where it went. A delete does not reach other copies or earlier backups, and the app cannot erase storage (string 36) | Section 4 |

Rules for this group:

- **No third-party app or service is named** (owner, 2026-11-22), here or anywhere in the checklist, in the app or in `docs/PRIVACY.md`'s section. Kinds are described. Apple's own features (AirDrop, Files, iCloud Drive, Advanced Data Protection, encrypted computer backups) are named, because they are part of the platform.
- **The words "safe", "safer" and "secure" are not used.** The group says "storage you trust" and states who controls each copy.
- **Save to Photos is not listed** as a way off the phone: the copy stays on this iPhone, and reaches iCloud only if the person uses iCloud Photos.
- **File sharing with a computer through the Finder stays off** (issue 83, security review item 4); the group does not suggest it.
- A copy made with a connected drive follows the Save to Files… note (string 30).

### 10.7 Ways others may try to get your photos

Added 2026-11-22. A plain-language list of the known routes to a person's photos, written defensively: what happens, what helps, and what the app cannot do. One or two lines each. No steps, no tool names, no named product or authority; kinds only.

**Where it is shown.**

- **In the app: a second static page,** opened from a row under the checklist's opening paragraph (string 83; figure, panel B). It is a short version: fourteen routes, each with its three parts (strings 85 to 98), an opening line (84) and the closing statement (99). Like the checklist it has no status, stores nothing, and is not behind Lock Captures. It is a separate page so that the checklist stays a list of things to do and this stays a list of things to know.
- **The full text is in `docs/PRIVACY.md`,** in the same "High-risk use" section that is the source of truth (10.8). The app's sentences are that section's sentences, word for word, checked by the same repository check. The document adds what does not fit a phone screen: the finding or flaw class behind each route, the Apple page or research source, and the device check that a sentence waits for. The page ends with a link to that document (string 100), which opens in the browser like the link on the About screen.
- **Each "what helps" names a checklist item or a setting by its exact title,** so that Settings search and Voice Control find it. They are text, not links, on this page; the checklist is one step back.

**The routes.** "Source" cites the blind-spot review's findings (letters and numbers) and the hardening research's adversaries (T) and flaw classes (FC).

| String | Route | What helps | What the app cannot do | Source |
| --- | --- | --- | --- | --- |
| 85 | Someone holding the iPhone while it is unlocked | Lock Captures; a short Auto-Lock (63) | Stop the deletion of the app and its captures; protect a library that is open | T2, T5; D1, D3, D5 |
| 86 | Being made to unlock with Face ID or the passcode | Turn off Face ID quickly (66); Passcode Only | Anything once the passcode is given | T6; FC4; D4 |
| 87 | A passcode seen or guessed | A longer passcode (61); Stolen Device Protection (62); Erase Data (64) | Add a passcode of its own: the lock uses the iPhone's | T7; FC4, FC7; C3 |
| 88 | Forensic tools on an iPhone that was taken; unlocked since restart, or not | Restart or turn off (67); a longer passcode (61); a short Auto-Lock (63); Lockdown Mode (65) | Know or promise anything about such a tool | T3, T4; FC6, FC7; H16 |
| 89 | iCloud Backup or iCloud Photos obtained from Apple, without Advanced Data Protection | Advanced Data Protection (68); Leave Out of Backups; nope only | Tell whether Advanced Data Protection is on; hide the metadata Apple still holds | T9; B1; H10 |
| 90 | A backup on a computer, above all an unencrypted one; a computer the iPhone already trusts | Encrypt backups to a computer (69); Leave Out of Backups; Lockdown Mode (65) | Make iOS honor the request to leave captures out | T8; B2, B3; H13 |
| 91 | Copies already shared or sent, and the recipient's side | Sharing less; 10.6 | Reach a copy that has left the app | T1; FC15; F4 |
| 92 | Photos saved to Photos before nope only was chosen: iCloud Photos, shared albums, Recently Deleted | Deleting them in the Photos app | Read, move or delete anything in Photos (the app is add-only) | String 20a; B1 |
| 93 | Details in a shared file, and the sensor's noise pattern | Details in Each Photo; Share Without Optional Details; the file-name rule | Remove the sensor's pattern | T1; FC12, FC13; F1, F2 |
| 94 | Screen recording, mirroring, remote viewing, screenshots | Choosing where captures are opened | Block a screenshot or a recording | FC16; C4 |
| 95 | An iPhone managed by an employer or school | An iPhone nobody else manages | See or change what the organization set | G3 |
| 96 | Spyware, or a compromised iPhone | Lockdown Mode (65), as Apple describes it | Detect spyware or a modified iPhone; no claim is made in either direction | T10; FC26 |
| 97 | A hostile or compelled update to the app itself | Update nope. yourself (70) | Protect against its own updates; show that the App Store build matches the source | The hardening research's addendum; section 7 |
| 98 | Deleted files that are removed, not erased, on flash storage | Keeping fewer captures (77); Leave Out of Backups | Erase storage; the app has no "erase" feature and claims none | FC10; E4 |

**The closing statement** (string 99; owner, 2026-11-22). The page and the document both end by saying that the list covers only the ways known today, that others likely exist that are not known yet (new tools, and flaws not yet found in iOS or in apps), and that no app and no phone can promise protection against those. It is the last thing read on the page, before the link.

**Wording rules for this page.**

- **Defensive only.** Each line says that a route exists and what limits it. None says how it is done.
- **Kinds, not names:** "forensic tools", "spyware", "a messaging app", "the service that received it". Apple and its features are named.
- **The hardening research's rule against wording about seizure and tools** (its section 6.2) was written for claims of protection, and still holds for them: no sentence says the app protects against any of these. This page names the routes because the owner asked for them to be named, and each line that names one also says what the app cannot do.
- **"Can", not "will".** A route is something that can happen, stated without a likelihood.
- **Route 92's "for a time"** is replaced by the period Apple's page on deleting photos gives, when that page is read for the final text.
- **Accessibility** is as in 10.5: one column, each route one VoiceOver element read in the order title, what happens, what helps, what the app can't do; the route titles have the heading trait; nothing truncates; no color carries meaning.

### 10.8 One source of truth, and how it stays current

- **The source of truth is the "High-risk use" section of `docs/PRIVACY.md`.** It holds two tables, the checklist and the routes of 10.7. The first has each item's text exactly as the app shows it (quoted interface text, so "nope." stays), the place to go, the Apple page it rests on, and the date that page was last read. The guidance the hardening research's decision 9 put in `docs/PRIVACY.md` and this page are therefore the same text, not two. What the section says beyond the table (a managed phone, trusted computers, how to read release notes before updating) is marked as not shown in the app.
- **The app's two pages are copies of those tables.** A repository check (`scripts/check-high-risk-checklist.sh`, with a passing and a failing case as AGENTS.md requires) fails when a checklist string in `Honesty.xcstrings` differs from the table, when a link in the app is not in the table, when a link is neither `https://support.apple.com/…` without a query nor the privacy document's address that the About screen already uses, or when the month and iOS version of string 79 differ from the table's review line.
- **Until S1 writes that section,** the table in section 9 here (strings 57 to 100) and the tables in 10.4, 10.6 and 10.7 are the draft of it.
- **Review record.** The section ends with one line: the date of the last review, the iOS version it was made for, and who made it.
- **Cadence** (the plan's decision 34; the recommended option is described). The review is a step in `docs/RELEASING.md`, written so that the maintainer can do it without help: open each link in the table, compare the page with the item's sentence and path, correct or remove what no longer holds, update the dates and the review line; then read the routes of 10.7 against what has become known since the last review, and add, correct or remove. It is done before every release of the app, and when a new major version of iOS is released. A script (`scripts/check-checklist-links.sh`, run by hand at the review, not in CI, so that CI does not depend on a website) reports any link that no longer answers.
- **Who.** The person preparing the release makes the review; the maintainer approves the result with the release, as for every string. An item whose Apple page no longer supports it is corrected or removed before the release goes out, never left with a note.
- **Paths change between iOS versions.** The supported systems are iOS 26 and 27. An item whose path differs between them names the path for each, or names the screen without the full path.

### 10.9 Sources

Apple's pages, read on 2026-11-21 and 2026-11-22. Dates are as each page shows them. "Search summary" means the page was found and summarized through a search and not read in full; such a page supports only the statement it is cited for, and is read in full before the string is final.

- [H1] iPhone User Guide, "Set a passcode on iPhone" (the iOS 27 guide): https://support.apple.com/guide/iphone/set-a-passcode-iph14a867ae/ios
- [H2] Apple Platform Security, "Passcodes and passwords", published 2024-12-19: https://support.apple.com/guide/security/passcodes-and-passwords-sec20230a10d/web
- [H3] "About Stolen Device Protection for iPhone", published 2026-10-22: https://support.apple.com/en-us/120340
- [H4] iPhone User Guide, "Keep the iPhone display on longer" (search summary; the Auto-Lock path is also in H1): https://support.apple.com/guide/iphone/keep-the-iphone-display-on-longer-iph7117338a8/ios
- [H5] iPhone User Guide, "Set up Face ID on iPhone", section "Temporarily disable Face ID": https://support.apple.com/guide/iphone/set-up-face-id-iph6d162927a/ios
- [H6] Apple Platform Security, "Optic ID, Face ID, Touch ID, passcodes, and passwords", published 2024-12-19: https://support.apple.com/guide/security/face-id-touch-id-passcodes-and-passwords-sec9479035f1/web
- [H7] "Restart your iPhone", published 2026-11-11: https://support.apple.com/en-us/118259
- [H8] "About Lockdown Mode", published 2026-09-14: https://support.apple.com/en-us/105120
- [H9] "How to turn on Advanced Data Protection for iCloud", published 2026-04-17: https://support.apple.com/en-us/108756
- [H10] "iCloud data security overview", published 2026-01-05: https://support.apple.com/en-us/102651
- [H11] "Apple can no longer offer Advanced Data Protection in the United Kingdom to new users", published 2025-09-22: https://support.apple.com/en-us/122234
- [H12] "How to manually update apps from the App Store", published 2026-09-14: https://support.apple.com/en-us/102629
- [H13] "About encrypted backups on your iPhone, iPad, or iPod touch", published 2026-09-21: https://support.apple.com/en-us/108353
- [H14] "How to use AirDrop on your iPhone or iPad", published 2026-10-05: https://support.apple.com/en-us/119857
- [H15] `UIApplication.openSettingsURLString`, with `openNotificationSettingsURLString` and `openDefaultApplicationsSettingsURLString` under "See Also": https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring
- [H16] Apple Platform Security, "Data Protection classes", published 2024-12-19: https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web

Limits of this section: nothing was run on a device. Apple's pages for iPad and for iPhone models without Face ID were not read. No page of any third-party app was used, and nothing is stated about any.
