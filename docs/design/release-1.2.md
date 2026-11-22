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

Evidence note: everything about today's behavior was read from the code on branch `n100-H` at `9cef00d`. Nothing here was measured on a device or run on a simulator. Each statement that needs a device is a device check in the plan, sections 3 and 6, with the outcome that follows from it in the plan, section 2.5.

Q, the quick menu, is not changed by anything here: no tile is added, removed, moved or made editable, and Q still opens only from its button. The new settings are in Settings; the Captures library opens from the Last Photo spot and from Settings.

Names: the interface says "nope."; documents and the About screen say "Photivra Nope Camera" (AGENTS.md, "Name and wordmark").

Figures: [release-1.2/save-photos-to.svg](release-1.2/save-photos-to.svg), [release-1.2/captures-library.svg](release-1.2/captures-library.svg), [release-1.2/export-share-clean.svg](release-1.2/export-share-clean.svg).

Issue 83 is the specification, with its ten owner decisions of 2026-11-18, the five recorded for the 1.1.0 plan, and the fourteen of 2026-11-21 that followed the blind-spot review ([docs/research/83-blind-spots.md](../research/83-blind-spots.md)). This section adds the screens, the entry points and the wording, and does not repeat the issue. Where the issue's text and a later decision differ, the later decision is right; the plan, section 2.1, lists each difference. The owner moved issue 83 from release 1.1.0 to its own release, 1.2.0, on 2026-11-21; where the issue says 1.1.0, read 1.2.0. "Review decision N" below is one of the fourteen; a letter and number such as "A2" is a finding of the review.

Anything that depends on a device check is marked. If the check fails, the fallback named with it is built and the sentence is not written.

## 1. Settings › Privacy

The group gets the two rows `SETTINGS-PLAN.md` reserved, above Assistant Access: **Save Photos To** (value: Photos, or nope only) and **Lock Captures** (value: Off, or On). Five rows in the group.

**In the Lock Screen camera's Settings, neither row is shown** (review decision 13; this replaces "read only"). The group has three rows there. Nothing in the Lock Screen camera states whether captures are kept in the app or locked.

**Save Photos To** (a page; figure, panel B):

1. The choice: Photos, nope only. The footer says what the choice covers and does not, and for nope only it states where the captures stand with backups (strings 20a, 20b, 21).
2. **The backup question** (review decision 2; figure, panel D). The first time nope only is chosen, the app asks once whether captures kept in the app stay in this iPhone's backups (strings 43 to 45). The two answers are drawn alike: neither is preselected, bold or the default action, and neither is marked destructive. Cancel leaves Save Photos To on Photos and the question is asked again next time. The answer sets Leave Out of Backups, which can be changed later on this page. The question is not asked again after it has been answered, including after Factory Defaults.
3. "Kept in nope.": a **Captures** row with the count and size, which opens the library. Shown whenever the app holds captures, whichever choice is selected. With Lock Captures on, the row shows no count or size.
4. **Leave Out of Backups** and **Neutral File Names**, each with its explanation (strings 23, 25).
   - Leave Out of Backups keeps its name (review decision 3). Its explanation says that the app asks iOS, that iOS treats this as a request, and that it does not cover a copy of the phone's storage made another way. It names a kind of backup (iCloud Backup, an encrypted or an unencrypted backup to a computer, a direct transfer to a new iPhone) only where research step R4 confirmed that kind honors the request; a kind that was not checked or did not honor it is not named. If no kind is confirmed, the option goes back to the owner before it is built.
   - Neutral File Names is an option on top of the file-name rule of section 3, not the only protection.
5. **Delete All Captures…**, shown when the app holds captures.
6. When the device has no passcode: a notice at the top (string 24).
7. While a burst, a series or a bracket is running, the choice cannot be changed and the page says why (string 50). The destination of a capture is fixed when the shutter is pressed and travels with it (G1).

**Lock Captures** (a page; figure, panel C): the switch and its explanation (string 26); Passcode Only with its own explanation (string 46); the limits in the footer (string 27). The switch is unavailable, with the reason, when the device has no passcode.

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

## 8. Accessibility

- VoiceOver: each capture is one element, "Photo, 21 November, 2:14 PM, RAW, signed", with actions Share, Save to Files, Save to Photos, Delete. Selecting is a trait, not a color. The locked screen reads its title, sentence and Unlock, nothing else.
- The neutral marker is a button labeled "Captures, locked"; while a photo saves it is not a button and reads "Last photo, saving" (string 8).
- The backup question reads its title, its message and three buttons of equal weight. It has no default action, so Return on a keyboard and the VoiceOver magic tap choose nothing.
- Dynamic Type to the largest sizes: the list layout above; export and delete actions wrap, never truncate; the option name "Share Without Optional Details" wraps to two lines.
- Night Mode: thumbnails drawn red like the viewer; settings rows `#1C0000` on black as elsewhere.
- Voice Control names match the visible labels. Switch Control and Full Keyboard Access reach every action; Escape closes the library, which locks it when Lock Captures is on.
- Authentication prompts are the system's. A device check completes the prompt with VoiceOver and with Switch Control, with and without Passcode Only (D8).

## 9. Draft strings

For the Honesty review. "H" marks a sentence that states what is or is not protected, saved or processed; it goes in `Honesty.xcstrings`. English (U.S.) only in 1.2.0; Spanish follows with issue 87 in 1.3.0. **The numbers continue from the 1.1.0 design and are not changed:** strings 1 to 12 are in [release-1.1.md](release-1.1.md), section 6; 13 to 40 were first drafted there for this issue; 41 to 56 were added with the review decisions.

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

Notes on the issue 83 strings:

- **Two reviews** (review decision 14, which amends the plan's decision 26 for issue 83). The owner reviews strings 20 to 24, 26 to 28, 30 to 33 and 36 from this table, as rewritten here with their lettered forms, before group S1 starts. The numbers are the ones these strings had in the 1.1.0 design, so the review list on the issue points to the same sentences; the design is built on them. The new strings marked H (31b, 31c, 41, 42, 44, 46 to 49, 51, 54, 55) came from the same decisions and are in the table for that pass. Every string is reviewed again in the built app before the release run.
- **Rewritten on 2026-11-21:** 20 (now 20a and 20b), 23, 24, 25, 26, 27, 28 (now 28a and 28b), 30, 31, 32 (its condition), 33, 34 (its name), 36. New: 31b, 31c, 41 to 56. Unchanged: 21, 22, 29, 35, 37 to 40.
- **Backup kinds.** Strings 20a, 20b, 23 and 44 name a kind of backup only as far as R4 confirmed it. "Including iCloud Backup" in 20a rests on Apple's documentation and is confirmed on a device before it is final. Where R4 confirms which kinds honor the request, 20b and 23 name those kinds in place of "this iPhone's backups".
- **String 27** follows the iPhone Mirroring check: if the prompt can be answered from a Mac with something other than the iPhone's passcode, the sentence names it.
- **String 33.** "And possibly to the individual phone" stays unless a comparison of the locked values across two phones of one model shows they do not differ; with no second phone, it stays. The sensor sentences are the wording of `docs/research/privacy-claims.md`, claim 9, as on the Honesty screen.
- **Face ID** in strings 26, 29, 46 stands for the device's own method (Face ID, Touch ID or Optic ID), as in the system's wording.
- **The name "Share Without Optional Details"** is a draft. "Share Clean" is not used in the interface; the issue and older notes call this part "Share clean".

The limits issue 83 lists under "Limits to state plainly" (what stays in a file, the sensor pattern, screenshots, that the app cannot hide that it is installed), and those the review adds (section 7), are Honesty screen entries and `docs/PRIVACY.md` text, written with part 6 of the issue once the device checks are in; they are not drafted here.
