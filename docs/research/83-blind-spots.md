# Review: blind spots in issue 83 (protection for high-risk use)

Status: review, 2026-11-21; the owner's decisions and where each finding went were added the same day under "Outcome". The findings below are as first written. No code. This is a review of a specification and a plan, not of an implementation: nothing in issue 83 is built. It is not legal advice.

Reviewed: issue 83 with its ten decisions of 2026-11-18 and the five recorded 2026-11-21; `docs/plans/1.1.0.md` (section 3.6, research step R4, groups S1 to S6, section 7, decisions 13 to 17) and `docs/design/release-1.1.md` (section 4, strings 13 to 40, three figures) at `c75e1b6`; the 1.0 code on the same base.

Photivra Nope Camera's rule is that copy describes only shipped, verified behavior (AGENTS.md, "Evidence-based" and "Honesty"). This review applies the same rule to itself. Each finding carries one of three confidence labels:

- **Verified (code):** read in this repository; the file and line are cited.
- **Verified (Apple):** stated in Apple's public documentation; the page is cited in "Sources".
- **To confirm on a device:** consistent with the documentation or with how the platform is known to behave, but not stated by Apple and not run. These are proposed as device checks, not as facts.

Nothing here was run on a device or a simulator.

The people this feature is for: reporters, activists, people leaving an abusive relationship, people photographing evidence, and parents sharing photos of children. The situations considered: the phone is seized locked; seized unlocked or while in use; unlocked under pressure (a face held to the phone, a passcode demanded); examined with forensic tools; backed up or synced; used briefly by someone else who lives with the person.

## Summary

39 findings: 2 critical, 11 high, 17 medium, 9 low.

| Severity | Findings |
| --- | --- |
| Critical | A1, B1 |
| High | A2, B2, B3, C1, D1, D2, D3, E1, F1, F2, H1 |
| Medium | A3, B5, C2, C3, C4, D4, D5, D6, E2, E3, E4, E5, F3, F4, G1, G2, H2 |
| Low | A4, B4, D7, D8, E6, E7, F5, F6, G3 |

What the specification already gets right, so it is not repeated below: the lock is enforced where data is read, not in screens; nothing is called encryption; exports are copies started by the person; no clipboard, drag, File Provider or intent returns a capture; the sensor pattern, screenshots and "cannot hide that it is installed" are stated as limits; every platform assumption the issue knew about is marked as a device check.

The two critical findings are both cases where a person who chose "nope only" can have captures leave the phone for Apple's servers without being told.

## A. Lock Screen camera and the settings hand-off

### A1. A stale or failed settings hand-off sends Lock Screen captures to Photos (critical)

- **What is missed.** The issue covers the Lock Screen camera having *no* settings snapshot. It does not cover a snapshot that is *out of date*. Today the hand-off can fail without the person knowing: `SharedSettings.publishToLockScreenCamera` logs a failure and returns, "the Lock Screen camera then opens with the copy it had", and a snapshot larger than 4096 bytes is not sent at all (`App/Shared/SharedSettings.swift`, lines 50 to 70). The extension applies whatever copy it finds (`App/NopeCaptureExtension/NopeCaptureExtension.swift`, line 60). The snapshot grows with each release's new settings, including this one's.
- **Why it matters.** A person switches Save Photos To to "nope only" before a demonstration. The hand-off fails or is over the limit. From the Lock Screen, the fastest way to shoot, every capture is added to Photos, and with iCloud Photos on it is uploaded. The only signal is that the saved sentence reads "Saved." instead of "Saved in nope."
- **Confidence.** Verified (code) for the silent failure paths. How often `updateAppContext` fails on a device: to confirm on a device.
- **Proposed change.** Do not let the destination depend on a copy that cannot be confirmed. Options are owner decision 1. Whichever is chosen: read the snapshot back after every change to Save Photos To and treat a mismatch as a failed change that the page shows; add a unit test for "snapshot says Photos, setting says nope only"; add a size test that fails the build when a full snapshot (every setting at its longest value) exceeds the limit; add the stale-snapshot case to security review item 5.

### A2. The session content folder is described by Apple as temporary, and the app would call a capture there "saved" (high)

- **What is missed.** With "nope only" the extension writes to `sessionContentURL` and the app moves the files later. Apple describes that URL as "a temporary directory that's created when the app extension launches" and documents no protection class, no size limit and no retention period for it. The issue lists the class, the limit and an interrupted write as device checks, but not: how long content is kept if the app is never opened unlocked; whether the folder is in device and iCloud backups; whether "Leave Out of Backups" (set on the store directory) has any effect on it; and what class a file has after it is moved into the store. A moved file keeps the class it was created with; the store directory's class applies only to files created in it.
- **Why it matters.** A person photographs an arrest from the Lock Screen, sees "Saved in nope.", and the phone is taken before the app is next opened unlocked. Whether those captures are protected like the store, appear in a backup, or still exist a month later is not known. The sentence promised a place the files had not reached.
- **Confidence.** Verified (Apple) for "temporary directory" and for the absence of documented guarantees. Everything else: to confirm on a device.
- **Proposed change.** Add to R4: the folder's path, its files' protection class as created and after the move, whether it appears in an encrypted computer backup, and whether content survives a restart, a week without opening the app, and low storage. The hand-off sets the class on each file explicitly after the move and a device check reads it back. The extension's sentence for a capture that is in the session folder is not "Saved in nope."; a separate string says it is kept until the phone is unlocked and the app is opened (draft: "Kept. Open nope. after unlocking to finish saving."), marked H. If R4 cannot show the folder is durable and protected, "nope only" from the Lock Screen is not offered and the control says why.

### A3. A full disk at the Lock Screen (medium)

- **What is missed.** The Lock Screen camera has no storage warning: the extension leaves out "the storage and battery warnings, whose system reader uses app-only UIKit API" (`NopeCaptureExtension.swift`, line 38). With Photos as the destination the library absorbed that. With "nope only" the extension itself writes each RAW, tens of megabytes, into a folder with an unknown limit.
- **Why it matters.** A long event shot from the Lock Screen fills the phone or the folder. Later captures fail. If any failure is quiet, the person leaves believing they have photos they do not.
- **Confidence.** Verified (code) for the missing warning. The limit: to confirm on a device.
- **Proposed change.** A failed write in the extension always shows the existing "Not saved" state with a storage reason, and a partial file is removed. Add to device check 7: fill the device, shoot from the Lock Screen, confirm each failure is shown and nothing partial is later filed as complete.

### A4. Read-only rows show the protection mode to anyone holding the locked phone (low)

- **What is missed.** The Lock Screen camera's Settings shows Save Photos To and Lock Captures as read only (issue 83, "Lock Screen camera"). Anyone can open that camera on a locked phone.
- **Why it matters.** A person who searches a locked phone learns that it holds captures kept out of Photos and that they are locked. The issue states that the app cannot hide that captures exist, but that statement is about an unlocked phone.
- **Confidence.** Verified against the specification.
- **Proposed change.** Owner decision 13: leave both rows out of the Lock Screen camera's Settings.

## B. Backups and extraction

### B1. "nope only" keeps captures out of iCloud Photos and, by default, puts them in iCloud Backup (critical)

- **What is missed.** Leave Out of Backups is off by default (decision 3 of 2026-11-18), so captures kept in the app are in the device's iCloud Backup wherever that is on. Under standard data protection, Apple holds the keys to iCloud Backup, as it does for iCloud Photos. The footer shown when a person chooses "nope only" (string 20) says only that photos are "not added to Photos". The backup sentence (string 23) is under a different row, further down the page. The issue's own description of the mode ("do not sync through iCloud Photos") is accurate and easy to read as "do not go to iCloud".
- **Why it matters.** A reporter chooses "nope only" to keep source photos off a cloud account. That night the phone backs up. The captures are now held where the keys are Apple's, which is what the person was trying to avoid, and no sentence they read said so.
- **Confidence.** Verified (Apple) for who holds the keys with and without Advanced Data Protection. That Application Support is in iCloud Backup: verified (Apple), which says only `tmp` and `Library/Caches` are excluded by default.
- **Proposed change.** The choice is owner decision 2, because the default trades exposure against losing the only copy. In every option: the "nope only" footer itself says that captures kept in the app are in this iPhone's backups, including iCloud Backup, unless left out; `docs/PRIVACY.md` says the same next to its Advanced Data Protection recommendation; device check 7's backup test is run before string 20 is final.

### B2. "Leave Out of Backups" promises more than the API guarantees (high)

- **What is missed.** Apple: the flag "exists only to provide guidance to the system about which files and directories it can exclude; it's not a mechanism to guarantee those items never appear in a backup or on a restored device." Apple's page describes iCloud Backup only; it does not mention computer backups. The page for the property says some file operations reset it. The issue already plans a device check for device-to-device transfer and resets the flag at launch, but the row's name and string 23 ("unless left out") state a result, not a request.
- **Why it matters.** A person turns the switch on, later hands over the phone and passcode, and a computer backup is made. If the flag was reset, or that kind of backup does not honor it, the captures are in the backup after the app said they were left out. The switch also does nothing against a tool that copies the file system directly, which a person may not distinguish from "a backup".
- **Confidence.** Verified (Apple) for the guidance-not-guarantee wording and the iCloud-only scope. Behavior of encrypted and unencrypted computer backups and of direct transfer: to confirm on a device.
- **Proposed change.** Name and wording are owner decision 3. The explanation says the app *asks* iOS, lists only the backup kinds the device check confirmed, and says it does not apply to a copy of the phone's storage made with other tools. The app re-applies the flag after every write into the store, not only at launch, and a debug check reads it back. R4 covers an iCloud backup, an encrypted and an unencrypted computer backup, and a direct transfer; a kind that cannot be checked is "not claimed".

### B3. A computer the phone already trusts, and unencrypted computer backups (high)

- **What is missed.** The issue treats class Complete as "unreadable from shortly after the phone locks". Apple documents an escrow keybag kept on a computer the phone has synced with, which "allows the Finder or iTunes to back up and sync without requiring the user to enter a passcode", and that when a backup is not encrypted "the files aren't encrypted regardless of their Data Protection class". Neither is in the threat model (`docs/SECURITY_AUDIT.md`, "Who the adversaries are", mentions backups in one row without these cases) or in the planned limits text.
- **Why it matters.** A person's phone and laptop are taken together, or a partner has the person's laptop. If the laptop holds a pairing record, it may be able to back up the locked phone, captures included. Separately, a person who backs up to a computer without a backup password has every capture on that computer's disk in the clear.
- **Confidence.** Verified (Apple) for both statements. Whether current iOS asks for the passcode on the phone before each computer backup, which would narrow the first case: to confirm on a device.
- **Proposed change.** Add both to the threat model and to `docs/PRIVACY.md`'s high-risk guidance: encrypt computer backups, remove trusted computers that are not needed (the steps are taken from Apple's support page when the text is written, not from memory), and that Lockdown Mode requires the phone to be unlocked to connect to a computer or accessory (Apple). Add a device check: with the phone locked and paired, attempt a backup and record whether captures are in it, with and without Leave Out of Backups.

### B4. Settings outside the store show the mode and are in every backup (low)

- **What is missed.** Save Photos To, Lock Captures, Passcode Only, the re-lock time and the stored biometry state hash are settings, kept in the App Group's `UserDefaults`, which has the default protection class (available after the first unlock) and is always backed up.
- **Why it matters.** With Leave Out of Backups on, a backup still shows that the person kept captures in the app and locked them. This is within "cannot hide", but it is outside the phone.
- **Confidence.** Verified (code) that settings are in the App Group; verified (Apple) for the default class.
- **Proposed change.** State it in `docs/PRIVACY.md` with the limits. No design change.

### B5. Restore, transfer, offload and system updates are not in the device checks (medium)

- **What is missed.** Device check 8 covers an app update. Not covered: restoring an iCloud or computer backup to the same and to a new phone (are captures present, and what protection class do restored files have); a direct device-to-device transfer; "Offload App" followed by reinstalling (the system is expected to keep an offloaded app's data; not checked); an iOS update between captures.
- **Why it matters.** The captures are the person's only copy. A restored file with the default class, or a store that is empty after offload, is found at the worst time. A restore also brings back captures the person deleted after that backup was made.
- **Confidence.** To confirm on a device.
- **Proposed change.** Add these to device check 8. Add to string 36 or the limits text that restoring an earlier backup restores captures deleted since. The store re-applies its protection class to every file at each unlocked launch (a verification pass, not only "raise CompleteUnlessOpen").

## C. Data Protection behavior

### C1. The app can run while protected data is unavailable, and the rebuild rule can then misread the store (high)

- **What is missed.** "If the index is missing or damaged, the app rebuilds it from the files", migrations, the launch-time cleanup of leftover exports, and the hand-off all assume the store can be read. The app can be started or resumed while the phone is locked: by the watch remote, a Live Activity button, a Shortcuts automation, or by the system before first use. The app already checks for this in one place (`App/NopeApp/NopeApp.swift`, line 63, for assistants). With class Complete, every read of the store then fails. The Simulator does not enforce Data Protection, so the unit tests, the UI tests and the upgrade fixtures cannot see this.
- **Why it matters.** A code path that treats "cannot read" as "damaged" rebuilds an empty index, or a cleanup removes files it could not match to an index entry. The person unlocks and the library is empty. For someone holding evidence in the app only, that is total loss with no backup if Leave Out of Backups is on.
- **Confidence.** Verified (Apple) that class Complete files are inaccessible while locked and that the app is told through the protected-data callbacks. The exact errors and which launch routes occur while locked: to confirm on a device.
- **Proposed change.** A rule in the specification and in security review item 9: the store has three states (available, unavailable, damaged); while protected data is unavailable it reads nothing, rebuilds nothing, migrates nothing and deletes nothing, and a permission error is never treated as damage. A file that cannot be matched to the index is never deleted automatically. The file-system fake gains a "locked" mode that fails reads as the device does, used by every store, migration, delete and hand-off test. Device check: start the app from the watch and from a Shortcuts automation while locked, then unlock; every capture is present.

### C2. Choosing the class at the moment of locking (medium)

- **What is missed.** The design writes class Complete when unlocked and CompleteUnlessOpen "while locked". The class key is discarded about 10 seconds after locking (Apple), and `isProtectedDataAvailable` follows that, not the lock button. A save that starts in that window, a long burst still writing when the screen locks, and the per-capture manifest and thumbnail written with it, are edge cases the text does not settle. A wrong guess fails the save.
- **Why it matters.** The person presses the side button right after the last shot of a burst. If the remaining writes fail, the last photos are lost.
- **Confidence.** Verified (Apple) for the 10 seconds and for CompleteUnlessOpen allowing creation while locked. The failure mode of a Complete write at the boundary: to confirm on a device.
- **Proposed change.** Consider always creating capture files, manifests and thumbnails as CompleteUnlessOpen and raising them to Complete in the verification pass (B5); a closed CompleteUnlessOpen file is not readable while locked either. If the two-class design stays, a failed Complete write is retried once as CompleteUnlessOpen before the capture is reported as not saved. Device check: a 20-photo burst with the side button pressed during the save.

### C3. When class Complete gives no protection, and what string 24 implies (medium)

- **What is missed.** String 24 says that with no passcode, captures "are not protected when it is locked". Its plain converse is that with a passcode they are. That holds only once the phone has actually locked and the class key is gone. It does not hold while the phone is unlocked or in use; while Keep Screen On holds the screen on during a series (Honesty entry "Keep Screen On"); with Auto-Lock set to Never; for a trusted computer (B3); or against someone who has or guesses the passcode. A short numeric passcode is the whole of the protection.
- **Why it matters.** At a protest the phone is usually taken while it is in the person's hand with the camera open. The person believed "locked" was a property of the app.
- **Confidence.** Verified (Apple) for the class behavior; verified (code) that Keep Screen On exists.
- **Proposed change.** The limits text for part 6 lists these conditions in one place, in plain words: the protection starts a few seconds after the screen locks, is exactly as strong as the passcode, and does not exist while the phone is unlocked. `docs/PRIVACY.md`'s guidance names a longer passcode, a short Auto-Lock time and how to disable Face ID quickly from the side buttons. The Keep Screen On entry gains one sentence when captures are kept in the app.

### C4. iPhone Mirroring (medium)

- **What is missed.** A Mac signed in to the same Apple Account can show and control the iPhone while the iPhone's own screen is locked. Neither the issue nor the plan mentions it. Not known from documentation read for this review: whether an app's `LocalAuthentication` prompt can be satisfied from the Mac, and with which secret.
- **Why it matters.** A partner who knows the person's Mac password opens the app through the Mac. If the prompt accepts the Mac's own authentication, string 27 ("Anyone with the iPhone's passcode can open it") names the wrong secret. If the prompt cannot be answered there, that is worth knowing and saying.
- **Confidence.** To confirm on a device.
- **Proposed change.** Add to device check 7: with iPhone Mirroring, open the library with Lock Captures on, with and without Passcode Only; record what the prompt accepts. String 27 follows the result. `docs/PRIVACY.md` names iPhone Mirroring among the ways into an unlocked phone.

## D. Lock Captures

### D1. This session's photos are held in memory, outside the store's lock (high)

- **What is missed.** Security review item 1 puts the lock where "a capture's file, thumbnail or details" is read from the store. The camera also keeps every photo of the session in memory: up to 100 records with a thumbnail and full details, and screen-size previews for the newest 20 (`Sources/NopeCore/SessionPhotos.swift`, lines 92 to 113; `PhotoSaver` makes the thumbnail and preview from the saved files). The Last Photo viewer, Photo Details, the thumbnail's VoiceOver action and the comparison view read from there. Issue 129's early preview puts the new photo's picture in the Last Photo spot before the save. The design says the spot shows a neutral marker with Lock Captures on, but nothing says these in-memory copies are not made, or that every reader of them asks the lock. The plan gives `CaptureFeedback.swift` to S1, then S3, and issue 129's group D edits the same spot earlier.
- **Why it matters.** A person takes photos with Lock Captures on and the phone is taken from their hand with the camera open. If any route still shows the session viewer or the early preview, the most recent photos, the ones most likely to matter, are on screen with no authentication.
- **Confidence.** Verified (code) for what is held in memory. That a route stays open depends on the build; it is a gap in the specification.
- **Proposed change.** State the rule in the issue; the choice is owner decision 6. The route test of item 1 adds: the Last Photo spot during and after a save, the session viewer, Photo Details from the spot's accessibility action, the comparison view, and issue 129's saving state, each with Lock Captures on. Issue 129's design (3.2) gains a line for the locked case.

### D2. "Always locked after the iPhone locks" may not be observable by a suspended app (high)

- **What is missed.** With "After 1 Minute" or "After 5 Minutes", the app is normally suspended in the background. A suspended app receives no notification when the device locks. If the phone is locked and unlocked again inside the delay, the app may have no way, on resuming, to know that it happened. String 28 states the behavior as fact; the issue does not mark it as a device check.
- **Why it matters.** A person sets five minutes so that switching apps is not a nuisance, and locks the phone when approached. Someone who gets the phone unlocked within five minutes opens the app and the library is open, against what the page said.
- **Confidence.** To confirm on a device. Verified (Apple) only that the protected-data callbacks exist; their delivery to a suspended app, and their timing against the 10-second key discard, is not documented.
- **Proposed change.** Add to R4: with each delay, unlock the library, background the app, lock and unlock the phone at 5, 15 and 45 seconds, reopen; record whether the app can tell. The outcome decides owner decision 4. String 28 is not used until then.

### D3. Nothing re-locks the library while the app stays in the foreground (high)

- **What is missed.** Every re-lock rule is about the background. A person who unlocks the library, looks, and returns to the camera has an unlocked library for as long as the app stays in front, which during a series with Keep Screen On can be hours. The issue says the Last Photo button's routes ask the lock but not when an unlocked state ends inside the app.
- **Why it matters.** Same scene as D1: the phone is taken while the camera is open. One tap on the Last Photo spot opens every capture kept in the app.
- **Confidence.** Verified against the specification (no rule exists).
- **Proposed change.** Owner decision 5. The lock's state machine tests gain "library closed" and "idle in the foreground" events.

### D4. Face ID is the default, and Face ID is the weak point under pressure (medium)

- **What is missed.** With the default policy, a phone held to the person's face opens the library. Passcode Only is the setting that resists that, but the page presents it as a third row with no explanation in the figure, and string 27 names only the passcode.
- **Why it matters.** A person told to unlock "just the phone" has their face used a second time for the library.
- **Confidence.** Verified (Apple) for the policy's behavior: biometry first, then the passcode.
- **Proposed change.** Passcode Only gets its own explanation, marked H (draft: "Face ID can be used by someone holding the phone to your face. With this on, only the passcode opens your captures."). Unit test: the authentication context never allows reuse of an earlier device unlock (`touchIDAuthenticationAllowableReuseDuration` stays 0).

### D5. The lock does not stop someone deleting the app (medium)

- **What is missed.** Deleting the app from the Home Screen needs no authentication and removes every capture. String 22 says deleting the app deletes them, as a warning to the owner. The Lock Captures page does not say that the lock does not prevent it, and Photos, by comparison, keeps deleted items for a time.
- **Why it matters.** A person keeps photos of injuries in the app, locked, so a partner cannot see them. The partner cannot see them, and can destroy all of them in two taps. For evidence, "nope only" is less durable than Photos against this person.
- **Confidence.** Verified against the specification. That deleting an app asks for no authentication is ordinary system behavior, not read from Apple's documentation for this review.
- **Proposed change.** The Lock Captures footer adds that it does not stop someone with the unlocked phone from deleting the app and its captures. `docs/PRIVACY.md`'s guidance for evidence: export a copy to a place the other person cannot reach, soon.

### D6. Factory Defaults in the app silently changes where photos go (medium)

- **What is missed.** The issue lets Factory Defaults, applied in the app, reset Save Photos To, Lock Captures and backup exclusion (after authentication when the lock is on). The assistant route already keeps Privacy settings ("Apply Factory Defaults? Privacy settings stay as they are.", `App/NopeApp/Intents/AssistantQuestions.swift`, line 258); the in-app route does not (`Sources/NopeCore/SettingsPresets.swift`, line 315).
- **Why it matters.** A person resets settings to fix an exposure problem. Save Photos To returns to Photos and Leave Out of Backups to off. The next photos go to Photos and to iCloud Photos; the only signal is the saved sentence.
- **Confidence.** Verified (code) for the two routes' existing difference.
- **Proposed change.** Owner decision 10.

### D7. Settings left open under the lock can change what future files hold (low)

- **What is missed.** By decision 2 of 2026-11-18, Details in Each Photo, Sign Each Photo and Assistant Access stay open with Lock Captures on. Someone with brief use of the unlocked phone can turn Location and every detail on. Later captures then carry them, and "As Saved" shares them.
- **Why it matters.** A person who lives with the user turns Location on; the user later sends a photo, as saved, to someone who should not learn where they are.
- **Confidence.** Verified against the specification.
- **Proposed change.** No change to the decision is proposed. The share choice screen (string 31) states, for "As Saved", when the file holds a location; the summary in What's in This Photo already can. Add a UI test that the As Saved choice names a location when present.

### D8. Passcode removed, and assistive access to the prompt (low)

- **What is missed.** If the passcode is removed, "captures stay locked" until one is set again. That is recoverable, but nothing says so on the locked screen, and export and delete are blocked meanwhile. The authentication prompt is the system's; no device check runs it with VoiceOver, Switch Control or Voice Control.
- **Why it matters.** A person who cannot use Face ID, with Passcode Only on, must be able to complete the prompt with their input method or they cannot reach their own photos.
- **Confidence.** To confirm on a device.
- **Proposed change.** The locked screen's no-passcode state says that setting a passcode restores access and that nothing was deleted. Add to device check 7: complete the prompt with VoiceOver and with Switch Control, with and without Passcode Only.

## E. Residue outside the store

### E1. Deleting a capture leaves its picture in memory and possibly on screen (high)

- **What is missed.** Security review item 7 lists files, thumbnails, index entries, temporary exports and pending Lock Screen captures. It does not list the session's in-memory records (D1): the Last Photo thumbnail, the previews, the details.
- **Why it matters.** A person taps Delete All Captures as an officer approaches and returns to the camera. The Last Photo spot still shows the last photo, and the viewer still pages through the session's photos, until the app is quit.
- **Confidence.** Verified (code) that the records live until the app quits (`SessionPhotos.swift`, line 92).
- **Proposed change.** Every delete removes the matching session records and resets the Last Photo spot; Delete All clears the session entirely and releases the previews. Item 7's test adds a UI check that after each kind of delete no picture of a deleted capture can be reached, and a unit test on `SessionPhotos`.

### E2. The privacy cover does not cover what the system presents over the app (medium)

- **What is missed.** The existing cover is drawn in the app's own views when the scene is not active. The share sheet, the Files picker, a confirmation dialog and the authentication prompt are presented above those views. The share sheet's header normally shows a thumbnail and the file name; the delete dialog shows the count.
- **Why it matters.** A person opens the share sheet, is interrupted and switches away. The app-switcher card, and the snapshot iOS stores for it, may show the photo.
- **Confidence.** To confirm on a device.
- **Proposed change.** The device check of the app-switcher snapshot is run with the share sheet open, the Files picker open and each dialog open, and the stored snapshot is inspected in a downloaded container (`docs/SECURITY_AUDIT.md`, check 11, already describes how). If the picture shows: give the share sheet a neutral header (link metadata with the app's icon and a count, no image), and place the cover in a window above presented content or dismiss the sheet when the scene deactivates.

### E3. The share sheet offers more than Copy (medium)

- **What is missed.** Only Copy is removed. For an image file the system sheet can also offer Save Image, Assign to Contact, Print and, depending on the system, adding to a shared album. Apple's list of activity types has no constant for shared albums, so that one may not be removable by type. Save Image writes to Photos outside the app's own Save to Photos, so without its pairing or its file name rule. Also unspecified: what the sheet's own preview caches, and what happens to a multi-file share when the phone locks and the class Complete temporary files become unreadable part-way.
- **Why it matters.** The issue's first promise for "nope only" is that a capture "cannot be added to a shared album by mistake". The share sheet is one tap from doing that.
- **Confidence.** Verified (Apple) for the list of activity types. Which activities appear for DNG, HEIF and JPEG files, and the lock-during-share behavior: to confirm on a device.
- **Proposed change.** Owner decision 12. Device check 9 adds: list every action the sheet offers for each format; share ten RAW files by AirDrop and lock the phone during the transfer; run the container scan and inspect `Library/Caches` and `tmp` after each.

### E4. What a delete leaves, and a save that lands after Delete All (medium)

- **What is missed.** Three things. (1) The index format is not specified; a database file keeps deleted rows in free pages and journals, so file identifiers, sizes and times of deleted captures could remain in the store. (2) Flash storage and file-system snapshots mean deletion is not erasure; the issue says it makes no claim, but string 36 says "now". (3) Delete All during a burst, a series or a pending save: a capture can finish saving after the delete.
- **Why it matters.** The person deletes everything during a series; the series' next photo is saved a second later and is found on the phone.
- **Confidence.** (1) and (3): verified against the specification (not addressed). (2): general platform behavior, not app-specific.
- **Proposed change.** (1) The index is a file rewritten whole, or after any delete it is rebuilt from scratch; Delete All removes and recreates the store directory. (2) Keep "It can't be undone" and drop "now" unless a check supports it; the limits text says the app cannot erase storage and iOS does not offer apps a way to. (3) Delete All stops any running series or burst and discards pending saves first, and says so in the confirmation when one is running; unit test with a save in flight.

### E5. The time of capture stays in the store when Date and Time is off (medium)

- **What is missed.** With the date detail off (the default is every optional detail removed), the file holds no capture time. The library is sectioned by day, VoiceOver reads "21 November, 2:14 PM", and the stored file's own file-system dates are the capture time. So the manifest or the file system keeps what the switch removed, and a backup carries it. The issue covers the dates of *exported* copies only.
- **Why it matters.** A person who turned the date off so that a photo cannot be placed in time hands over the phone; the library and a backup both show when each was taken.
- **Confidence.** Verified against the design (4.2, 4.6).
- **Proposed change.** Owner decision 9. In either option the rule for the manifest is written down: it holds nothing that the file's own detail switches removed, apart from what that decision allows.

### E6. Records iOS keeps that the limits text should name (low)

- **What is missed.** The Honesty entry "App Use Records" exists. For this audience it should also name: App Privacy Report lists when the camera was used by the app (seven days, when on); Settings shows the app's storage size (already in the issue); the system log records that the app asked for authentication.
- **Why it matters.** After Delete All, these still show that photos were taken and roughly when.
- **Confidence.** Verified (Apple) for App Privacy Report (`docs/research/privacy-claims.md`, note 1). The log entry: to confirm on a device.
- **Proposed change.** One sentence added to that entry and to `docs/PRIVACY.md` in part 6.

### E7. Temporary export copies double the space needed (low)

- **What is missed.** A batch export writes a copy of each file to `tmp` first. Exporting a large library on a nearly full phone fails part-way.
- **Why it matters.** The person exporting before travel gets a partial export; the summary reports it, so this is a nuisance, not a hazard.
- **Confidence.** Verified against the specification.
- **Proposed change.** Export one file at a time (write, hand over, delete), or check free space first and say how much is needed. Share clean copies need real copies; As Saved copies can be file-system clones, to confirm on a device that a clone keeps class Complete.

## F. Share clean and file names

### F1. Default file names carry the date and time that the default details remove (high)

- **What is missed.** Neutral File Names is off by default and is described as names "that do not encode the date and time", so the ordinary export name does encode them. The default for Details in Each Photo is every optional detail removed, including the date. In the default configuration, then, an exported file has no date inside it and the date in its name. Neutral File Names is also second in the cut order.
- **Why it matters.** A parent posts a photo believing it carries no date; a source sends a reporter a file whose name is the minute it was taken. What's in This Photo, which lists what is in the file, does not list the name.
- **Confidence.** Verified against the specification and the design (string 25; figure A shows "All Optional Removed"). What name Photos assigns is already a device check.
- **Proposed change.** Owner decision 7. In every option, the Share and Save to Files steps show the name the copy will have, and What's in This Photo for a stored capture lists "File name when exported".

### F2. The name "Share Clean" and its summary leave out the one thing that still links photos (high)

- **What is missed.** The summary's "What Stays in the File" (string 33) says color and size data "can point to the phone model". It does not say that the sensor's pattern in the pixels can link photos to one phone, which the issue itself lists as a limit to state, and which the Honesty screen already states ("The Sensor's Noise Pattern"). The word "clean" suggests a file that cannot be traced. With the default details, Share Clean also removes nothing, yet the figure's rows read "Removed".
- **Why it matters.** An activist shares "clean" photos under a pseudonym and, separately, ordinary photos from the same phone under their own name. The two sets can be matched. The summary screen is the last thing they read before sending.
- **Confidence.** Verified against strings 31 to 33 and `docs/research/privacy-claims.md`, claim 9 (peer-reviewed sources cited there).
- **Proposed change.** Owner decision 8. In every option: the summary gains the sensor sentence in the wording claim 9 already approved; each row says "Removed" only when the original held it and "Not in the file" otherwise (the figure already does this for Location).

### F3. Whether the locked values identify the model or the individual phone is not checked (medium)

- **What is missed.** The issue says the color matrices, noise profile and levels are "specific to the phone model and lens". Phones are calibrated individually at the factory; whether any locked DNG value, or a lens-correction opcode when that switch is on, differs between two phones of the same model has not been compared.
- **Why it matters.** If a value is per unit, it is a serial number in all but name, present in every RAW with every detail off, and "can point to the phone model" understates it.
- **Confidence.** To confirm on devices: it needs two phones of one model.
- **Proposed change.** A device check: the same scene and settings on two phones of the same model; compare every locked tag and opcode list byte for byte. Until it is done, the wording says "the phone model, and possibly the individual phone". If two units are not available the claim "model only" is not made.

### F4. What sharing adds outside the file (medium)

- **What is missed.** String 30 says the copy "leaves nope.'s protection". It does not say that the route itself identifies the sender or keeps a copy: AirDrop shows the sending device's name, which usually contains the owner's name; Messages and Mail keep the sent file on the sender's phone and, where enabled, in the sender's cloud account; a receiving app may add its own details or re-encode. `docs/research/privacy-claims.md` already lists "what metadata survives AirDrop, Messages and Mail" as an open device check (item 6).
- **Why it matters.** A person deletes a capture from the app after sending it and believes it is gone from the phone; the copy in the Messages thread remains, unlocked and backed up.
- **Confidence.** To confirm on a device for each route; the AirDrop name is standard system behavior.
- **Proposed change.** String 30 gains one clause: the app you share with keeps its own copy. `docs/PRIVACY.md` lists the routes checked and what each showed. Device check 10 records, per route, the received file's name, dates and tag set.

### F5. Share Clean and evidence (low)

- **What is missed.** Share Clean removes the date and the signature, the two things that help a photo serve as a record. The choice screen says what each option does, not when each is the wrong choice.
- **Why it matters.** A person documenting abuse sends "clean" copies to an advocate and later finds they carry no date and no signature.
- **Confidence.** Verified against strings 31 and 32.
- **Proposed change.** `docs/PRIVACY.md` and the how-to-use guide say which option suits which purpose. No interface change proposed.

### F6. What a rewritten copy can still carry (low)

- **What is missed.** "Exactly the tag set of Remove All Optional Details" is checked by the app's own reader. The reader's coverage of containers, not only tags, matters for a rewritten file: an embedded EXIF thumbnail in a JPEG, a preview image in a DNG's sub-IFD, an XMP packet, an ICC profile's description and date fields, and bytes left between or after structures by a byte-level rewrite.
- **Why it matters.** A stale embedded thumbnail or leftover bytes can hold what the visible tags no longer do.
- **Confidence.** To confirm in the S4 tests.
- **Proposed change.** Security review item 8's test asserts, per format, that the clean copy has no bytes outside the structures the reader accounts for (every byte of the file is attributed to image data, an allowlisted tag or required structure), and device check 10 compares the copy with `exiftool -a -G1 -u` output as `docs/research/privacy-claims.md` already prescribes.

## G. Switching, storage and managed devices

### G1. Captures in flight when Save Photos To changes (medium)

- **What is missed.** "The choice applies to captures taken from then on" does not say what "taken" means for a burst, an interval series, a bracket or a pending save (issue 129, step 3) that straddles the change.
- **Why it matters.** A person switches to "nope only" while a save is pending; that photo goes to Photos.
- **Confidence.** Verified against the specification.
- **Proposed change.** The destination is fixed when the shutter is pressed and travels with the capture. The Save Photos To page cannot be changed while a series is running (or the change applies to the next series), and says so. Unit tests for each drive mode.

### G2. A full or failing store (medium)

- **What is missed.** Low storage for the store itself: the capture file is written but the manifest, thumbnail or index is not; an atomic replace leaves a temporary file; delete is needed precisely when the disk is full.
- **Why it matters.** A capture with no manifest that the library does not list is lost in practice even though its bytes exist.
- **Confidence.** Verified against the specification.
- **Proposed change.** A capture is reported saved only after its file and manifest are both written and read back; a file without a manifest is listed as a recoverable item, not hidden and not deleted (C1). The existing low-storage warning counts the store's needs (file plus manifest plus thumbnail). Test: every write in a save failing in turn.

### G3. Managed and supervised devices (low)

- **What is missed.** A phone managed by an employer or school is under that organization's control in ways the app cannot see.
- **Why it matters.** A reporter using a work phone.
- **Confidence.** General platform behavior; not checked.
- **Proposed change.** One sentence in `docs/PRIVACY.md`'s high-risk guidance: use a phone that is not managed by anyone else.

## H. Scope and cut order

### H1. Cutting Lock Captures leaves an ungated library and designs that depend on it (high)

- **What is missed.** The recorded cut order ends with Lock Captures. If it is cut and the store ships, every capture kept in the app is one tap from the camera screen (the Last Photo spot) for anyone holding the unlocked phone. Photos, by comparison, has the Hidden album and can be locked by the system. Several other rules also lean on the lock: the neutral marker, "nothing at all" in the Lock Screen camera, the gate before export and before Delete All, and D1.
- **Why it matters.** A person asked to "open your camera" shows every protected capture. The feature named for high-risk use would, in that one situation, protect less than Photos.
- **Confidence.** Verified against the plan (decision 13) and the design (4.2).
- **Proposed change.** Owner decision 11.

### H2. Cutting Neutral File Names or Share clean (medium)

- **What is missed.** If Neutral File Names is cut, F1's leak ships with no remedy. If Share clean is cut, a person who turned details on has no way to send a copy without them except changing settings before shooting, and strings 31 to 34 and the figure's panels A and B go with it.
- **Why it matters.** Each cut should leave the remaining wording true.
- **Confidence.** Verified against the plan.
- **Proposed change.** Resolve F1 by decision 7 so that a cut of the option leaves nothing leaking. If Share clean is cut, the share step states, for a file that holds optional details, that the copy includes them.

## New or extended device checks

For R4 and section 7 of the plan. A check that cannot be run ends as "not claimed".

1. Stale settings snapshot: change Save Photos To, force a failed hand-off, shoot from the Lock Screen; where did the capture go (A1).
2. Session content folder: path, class as created and after the move, in or out of each kind of backup, survival of a restart, a week unopened and low storage (A2).
3. Full disk from the Lock Screen camera (A3).
4. Backups: iCloud, encrypted computer, unencrypted computer, direct transfer; each with and without Leave Out of Backups; and a backup attempted with the phone locked and already paired (B2, B3).
5. Restore to the same and a new phone; offload and reinstall; an iOS update; the class of every stored file afterwards (B5).
6. Launch while locked from the watch remote and a Shortcuts automation, then unlock; all captures present (C1).
7. A burst with the side button pressed during the save (C2).
8. iPhone Mirroring with Lock Captures on, with and without Passcode Only (C4).
9. Each re-lock delay with the phone locked and unlocked inside it (D2).
10. The authentication prompt with VoiceOver and Switch Control (D8).
11. The app-switcher snapshot with the share sheet, the Files picker and each dialog open (E2).
12. Every action the share sheet offers per format; a ten-file AirDrop with the phone locked part-way; the container scan after each (E3).
13. Locked DNG values compared across two phones of one model (F3).
14. Per share route: the received file's name, dates and tags (F4).

## Owner decisions

Each lists its options with the recommendation first and one line of reason. All fourteen were decided by the owner on 2026-11-21, each as option (a); see "Outcome".

1. **Where Lock Screen captures go, given that the settings copy can be stale (A1).** (a) **Recommended, if R4 shows the session folder is durable and protected:** the Lock Screen camera always writes to its session folder, whatever its copy says, and the app files each capture by the current setting when it is next opened unlocked. (b) Keep the copy-driven design; after each change the app reads the copy back, and the Save Photos To page shows a warning and offers Try Again until the Lock Screen camera has it. (c) With "nope only" chosen and the copy unconfirmed, the Lock Screen camera does not take photos and says why. *Reason: (a) removes the failure instead of reporting it, but it delays Lock Screen photos reaching Photos for everyone, so it needs the R4 result first.* **Decided 2026-11-21: (a).**
2. **Backups when "nope only" is chosen (B1).** (a) **Recommended:** the first time "nope only" is chosen, ask once, with neither answer preselected: keep captures in this iPhone's backups, or leave them out; the footer states the current answer. (b) Keep Leave Out of Backups off by default and add the backup sentence to the "nope only" footer. (c) Turn Leave Out of Backups on by default when "nope only" is chosen, with the loss warning. *Reason: the default trades exposure in a backup against losing the only copy, and only the person knows which matters more for them.* **Decided 2026-11-21: (a).**
3. **The name and wording of Leave Out of Backups (B2).** (a) **Recommended:** keep the row name; the explanation says the app asks iOS to leave captures out, names only the backup kinds a device check confirmed, and says it does not cover other ways of copying the phone. (b) Rename the row to "Ask iOS to Leave Out of Backups". (c) Hold the option until the checks are done for every backup kind. *Reason: Apple describes the flag as guidance, not a guarantee.* **Decided 2026-11-21: (a).**
4. **Re-lock delays (D2).** (a) **Recommended:** if the device check cannot show that a lock of the phone inside the delay is detected, 1.1.0 ships "Immediately" only. (b) Keep the delays and drop the sentence about the iPhone locking. (c) Keep both as drafted if the check passes. *Reason: a delay is a convenience; a sentence that is sometimes false is not acceptable on this page.* **Decided 2026-11-21: (a).**
5. **When an unlocked library locks again inside the app (D3).** (a) **Recommended:** when the library or a capture's viewer is closed back to the camera. (b) Only on the background rules, as specified. (c) After a short idle time in the foreground. *Reason: the camera is the part of the app that is open in public; returning to it should close the library behind the person.* **Decided 2026-11-21: (a).**
6. **This session's photos with Lock Captures on (D1).** (a) **Recommended:** no thumbnail, preview or details of a capture kept in the app is held in memory outside the store's lock; the Last Photo spot and issue 129's saving state show the neutral marker. (b) Keep them in memory but make every reader ask the lock. (c) Show this session's photos without authentication until the app next leaves the foreground. *Reason: the most recent photos are the ones most likely to be on screen when the phone is taken.* **Decided 2026-11-21: (a).**
7. **File names (F1).** (a) **Recommended:** an exported name never carries the date or time unless the Date and Time detail is in that file; Neutral File Names remains for people who keep the date in the file but not in the name. (b) Neutral File Names on by default. (c) As planned: dated names unless the option is turned on. *Reason: the name should not put back what the detail switch removed, and (a) stays true if the option is cut.* **Decided 2026-11-21: (a).**
8. **The name "Share Clean" (F2).** (a) **Recommended:** a descriptive name, such as "Share Without Optional Details", and the sensor-pattern sentence in the summary. (b) Keep "Share Clean" and add the sentence. (c) Keep the name and summary as drafted. *Reason: "clean" can be read as untraceable, which no camera app can deliver.* **Decided 2026-11-21: (a).**
9. **The capture time in the library when Date and Time is off (E5).** (a) **Recommended:** keep the time in the store for ordering and day sections, and say so in the Details in Each Photo footer and `docs/PRIVACY.md`. (b) For such captures keep only an order number: no day sections, no time in the label, and store file dates set to a fixed value. *Reason: (a) keeps the library usable and is honest if stated; (b) is the stricter reading of the switch and costs more to build.* **Decided 2026-11-21: (a).**
10. **Factory Defaults applied in the app (D6).** (a) **Recommended:** it leaves Save Photos To, Lock Captures and Leave Out of Backups as they are, like the assistant route. (b) It resets them after authentication, and its confirmation names each change. (c) As specified: reset after authentication when the lock is on. *Reason: a reset meant to fix the camera should not change where photos are kept.* **Decided 2026-11-21: (a).**
11. **The cut order (H1).** (a) **Recommended:** the store does not ship without Lock Captures; if the lock must be cut, parts 1, 2 and 5 move with it. (b) Keep the recorded order; if the lock is cut, the Save Photos To footer says captures are not locked and points to the system's Require Face ID for the whole app. (c) Keep the recorded order with no change. *Reason: without the lock, anyone holding the unlocked phone reaches every capture from the camera screen.* **Decided 2026-11-21: (a).**
12. **Which share sheet actions are removed (E3).** (a) **Recommended:** Copy, Save Image, Assign to Contact and Print, plus any action the device check shows writes to Photos or a shared album; Save to Photos stays as the app's own action. (b) Copy only, as specified, with the others named in the export note. *Reason: each of these leaves a copy in a system place the note does not name, and one of them contradicts the mode's first promise.* **Decided 2026-11-21: (a).**
13. **Save Photos To and Lock Captures in the Lock Screen camera's Settings (A4).** (a) **Recommended:** not shown there. (b) Read only, as decided. *Reason: the Lock Screen camera can be opened by anyone holding the locked phone.* **Decided 2026-11-21: (a).**
14. **When the sentences that shape this design are reviewed (plan decision 26).** (a) **Recommended:** strings 20 to 24, 26 to 28, 30 to 33 and 36 are reviewed from the table before S1 starts, and all strings again in the built app before the release run (the plan's option c). (b) In the built app only, as the plan recommends. *Reason: findings B1, B2, C3, D2 and F2 are wording that would be built on.* **Decided 2026-11-21: (a).**

## Outcome

Added 2026-11-21, after the owner answered the fourteen decisions on issue 83. Nothing was built or run for this section. The same day the owner moved issue 83 out of release 1.1.0 into its own release, 1.2.0. The plan is now `docs/plans/1.2.0.md` and the design is `docs/design/release-1.2.md`, both written with the decisions folded in; "plan" and "design" below mean those two. The findings above cite the 1.1.0 plan and design as they stood at `c75e1b6`. Decision numbers 13 to 17 and 26, device check numbers 6 to 12 and string numbers 13 to 40 are unchanged in the new documents, so those citations still point to the right items; the design's sections 4.1 to 4.6 are now sections 1 to 5 and 8 of the 1.2.0 design.

### The fourteen decisions

Every decision is the recommended option, (a).

| # | Decision | Outcome | Where it is specified |
| --- | --- | --- | --- |
| 1 | Where Lock Screen captures go | The Lock Screen camera always writes to its session folder; the app files each capture by the current setting when next opened unlocked. Conditional on R4 showing the folder is durable and protected. If R4 does not show that, the fallback from A1 and A2 is built: nothing is kept in the folder, a change of Save Photos To takes effect only after the Lock Screen camera's copy is read back, and with nope only the Lock Screen camera does not take photos and says why | Plan 2.1 and 2.5; design 6; strings 41, 42 |
| 2 | Backups when nope only is chosen | Asked once, the first time nope only is chosen, with neither answer preselected; the footer states the current answer | Design 1; strings 20a, 20b, 43 to 45; figure `save-photos-to.svg`, panel D |
| 3 | Leave Out of Backups | The name stays. The text says the app asks iOS, names only the backup kinds a device check confirmed, and says it does not cover other ways of copying the phone | Design 1; string 23 |
| 4 | Re-lock delays | Built only if a device check shows a lock of the phone inside the delay is detected; otherwise Immediately only | Plan 2.5; design 1; strings 28a, 28b |
| 5 | Locking again inside the app | When the library, or a capture's viewer opened from the camera, is closed back to the camera | Design 2, "Locking again" |
| 6 | This session's photos with Lock Captures on | Nothing of a capture kept in the app is held outside the store's lock; the Last Photo spot and issue 129's saving state show the neutral marker | Design 2, "Nothing outside the lock" and "The saving state"; plan 2.1 |
| 7 | File names | No date or time in an exported name unless the Date and Time detail is in that file; Neutral File Names stays as an option | Design 3; strings 25, 51 |
| 8 | The name "Share Clean" | Renamed; the draft is "Share Without Optional Details". The summary carries the sensor-pattern sentence | Design 3; strings 31, 33; figure `export-share-clean.svg` |
| 9 | The capture time when Date and Time is off | Kept in the store for ordering and day sections; stated in the Details in Each Photo footer and, when group S6 writes it, in `docs/PRIVACY.md` | Design 1 and 2; string 48 |
| 10 | Factory Defaults | Leaves Save Photos To, Lock Captures and Leave Out of Backups unchanged | Design 1; string 49 |
| 11 | The cut order | The store does not ship without Lock Captures; if the lock is cut, parts 1, 2 and 5 move with it. Replaces the cut rule of the plan's decision 13. With issue 83 now a release of its own, a cut of the lock means that release waits | Plan 2.1, 4.6 and decision 13 |
| 12 | Share sheet actions | Copy, Save Image, Assign to Contact and Print are removed, plus any action a device check shows writes to Photos or a shared album; the app's own Save to Photos stays | Design 3; plan, R4 and device check 9 |
| 13 | The Lock Screen camera's Settings | Save Photos To and Lock Captures are not shown there. Replaces read only | Design 1; figure `save-photos-to.svg`, panel A |
| 14 | When the strings are reviewed | Strings 20 to 24, 26 to 28, 30 to 33 and 36 from the design table before S1 starts; all strings again in the built app before the release run. Amends the plan's decision 26 for issue 83 | Plan 4.2, 4.6 and decision 26; design 9 |

### Where each finding went

"Decision N" is the table above. "Plan" is section 2 of the 1.2.0 plan unless another section is named. Wording for the Honesty screen and `docs/PRIVACY.md` is written by group S6 after the device checks; until then it is a listed requirement (design 7), not text.

| Finding | Severity | Outcome |
| --- | --- | --- |
| A1 | Critical | Decision 1. The destination no longer depends on the settings copy. Kept from the proposal: a test that the extension writes to the folder whatever the copy says, and a build-failing test of the copy's size limit. The read-back of the copy is part of the fallback only |
| A2 | High | Decision 1's gate. R4 gains the folder checks; the class is set on each file after the move and checked at each unlocked launch; the Lock Screen camera says "Kept…", not "Saved" |
| A3 | Medium | Folded in: every failed write in the Lock Screen camera is shown and a partial file removed; device check 7 fills the device |
| A4 | Low | Decision 13 |
| B1 | Critical | Decision 2. The nope only footer states the backup answer; the iCloud Backup wording waits for the device check; `docs/PRIVACY.md` in S6 |
| B2 | High | Decision 3. The flag is set after every write and read back in debug builds; R4 checks each kind of backup |
| B3 | High | Folded in: R4 attempts a backup with the phone locked and paired; the threat model and `docs/PRIVACY.md` guidance in S6 (design 7) |
| B4 | Low | Folded in as a limit for S6 to state (design 7). No design change |
| B5 | Medium | Folded in: device check 8 gains restore, transfer, offload and an iOS update; string 36 says a restore brings captures back; the class of every file is checked at each unlocked launch |
| C1 | High | Folded in: three store states, the rule against treating a permission error as damage, the fake's locked mode for every store test, R4 and device check 7 |
| C2 | Medium | Folded in part. The two-class design stays, with one retry as CompleteUnlessOpen and the launch check. The alternative, always creating files as CompleteUnlessOpen, is adopted only if R4's burst check shows class Complete writes failing at the moment of locking |
| C3 | Medium | Folded in: string 24 no longer implies that a passcode alone protects; the conditions are listed for S6 (design 7), with the Keep Screen On sentence |
| C4 | Medium | Folded in: an R4 check and device check 7; string 27 follows the result |
| D1 | High | Decision 6. The route test gains the Last Photo spot during and after a save, the session viewer, Photo Details, the comparison view and the saving state |
| D2 | High | Decision 4. R4 gains the check; string 28b is used only if it passes |
| D3 | High | Decision 5. The lock's tests gain the "library closed", "viewer closed" and "idle in the foreground" events |
| D4 | Medium | Folded in: Passcode Only has its own explanation (string 46); a unit test that an earlier device unlock is never reused |
| D5 | Medium | Folded in: string 27 says the lock does not stop someone deleting the app; evidence guidance in S6 |
| D6 | Medium | Decision 10 |
| D7 | Low | Folded in: As Saved names a location when the file holds one (string 31b), with a UI test. The 2026-11-18 decision on which settings the lock guards is unchanged |
| D8 | Low | Folded in: the locked screen's no-passcode sentence (string 47); device check 7 completes the prompt with VoiceOver and Switch Control |
| E1 | High | Folded in: every delete removes the session's records and resets the Last Photo spot; a UI test and a unit test |
| E2 | Medium | Folded in: R4 and device check 7 inspect the snapshot with the share sheet, the Files picker and each dialog open; the remedy (a neutral share-sheet header, sheets dismissed when the scene becomes inactive) is built only if a picture shows |
| E3 | Medium | Decision 12. R4 and device check 9 list the sheet's actions per format and lock the phone during a ten-file AirDrop |
| E4 | Medium | Folded in: the index is rewritten whole and Delete All recreates the store directory; "now" is removed from string 36; Delete All stops a series and discards pending saves, and says so (string 55) |
| E5 | Medium | Decision 9, with the rule that the manifest holds nothing else the detail switches removed |
| E6 | Low | Folded in as a limit for S6 to state (design 7) |
| E7 | Low | Folded in part: a free-space check before several captures are exported (string 54). Exporting one file at a time is not adopted, because the share sheet and the folder picker take all the files at once. Clones for As Saved copies are used only if R4 shows a clone keeps its protection class |
| F1 | High | Decision 7. The rule is built with export (group S2), and the name is shown before sharing and in What's in This Photo |
| F2 | High | Decision 8. Summary rows say "Removed" only when the stored file held the detail |
| F3 | Medium | Folded in: an R4 comparison across two phones of one model; until it is done the wording says "and possibly to the individual phone" |
| F4 | Medium | Folded in: string 30 says the receiving app or place keeps its own copy; device check 9 records each route's received name, dates and tags; the list of routes in S6 |
| F5 | Low | Folded in as guidance for S6 (`docs/PRIVACY.md` and the how-to guide). No interface change |
| F6 | Low | Folded in: the per-format test accounts for every byte of the copy; device check 10 compares with `exiftool` output |
| G1 | Medium | Folded in: the destination is fixed at the press; Save Photos To cannot be changed while a series runs (string 50); unit tests per drive mode |
| G2 | Medium | Folded in: saved means file and manifest written and read back; a file without a manifest is listed (string 53), never hidden or deleted; the storage warning counts the store's needs; a test fails each write in turn |
| G3 | Low | Folded in as guidance for S6 |
| H1 | High | Decision 11 |
| H2 | Medium | Folded in: decision 7 keeps the name rule if the Neutral File Names option is cut; if Share Without Optional Details is cut, the share step says the copy includes the optional details (string 31c) |

No finding was left out. Three were folded in only in part, for the reasons given in their rows: C2, E2 and E7.

### Questions raised while folding the decisions in

Not decided. They are in the 1.2.0 plan, section 7.2, as decisions 27 to 29:

- The Lock Screen camera learns whether Lock Captures is on from the same settings copy that A1 showed can be out of date. What it shows when that copy cannot be confirmed is open.
- Decision 10 names three settings. Whether Factory Defaults also leaves Neutral File Names unchanged is open.
- Decision 7 covers exported copies. Whether the same rule applies to the name the app gives a photo saved straight to Photos is open.

## Sources

Apple documentation read for this review, 2026-11-21:

- "Creating a camera experience for the Lock Screen" (LockedCameraCapture): https://developer.apple.com/documentation/lockedcameracapture/creating-a-camera-experience-for-the-lock-screen
- `URLResourceValues.isExcludedFromBackup`: https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup
- "Optimizing your app's data for iCloud Backup": https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup
- "Encrypting your app's files": https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files
- Apple Platform Security, "Data Protection classes": https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web
- Apple Platform Security, "Keybags for Data Protection": https://support.apple.com/guide/security/keybags-for-data-protection-sec6483d5760/web
- "iCloud data security overview": https://support.apple.com/en-us/102651
- "About Lockdown Mode": https://support.apple.com/en-us/105120
- `LAPolicy.deviceOwnerAuthentication`: https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication
- `UIActivity.ActivityType`: https://developer.apple.com/documentation/uikit/uiactivity/activitytype-swift.struct

In this repository: `docs/research/privacy-claims.md` (claims 9, 11, 21, 22; device checks 6, 10, 11), `docs/SECURITY_AUDIT.md` (threat model; check 11), `docs/PRIVACY.md` ("What the app does today").
