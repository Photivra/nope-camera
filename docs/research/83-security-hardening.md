# Research: security flaws and hardening for issue 83 (protection for high-risk use)

Status: research, 2026-11-21. No code, no builds, nothing run on a device or a simulator. Issue 83 is a specification; nothing in it is built. This page is not legal advice.

Scope: issue 83 as it stands for release 1.2.0 (the body, the decisions of 2026-11-18 and the fourteen of 2026-11-21), the build groups S1 to S6 and research step R4 of `docs/plans/1.1.0.md` at `c75e1b6`, and `docs/research/83-blind-spots.md` ("the review"). The review's 39 findings are not repeated. They are cited by their IDs (A1 to H2), and this page adds what a security review adds to them: known flaw classes and public incidents, platform and OWASP guidance, a ranked hardening checklist, security checks, and the limits on what may be said.

Photivra Nope Camera's rule is that copy describes only shipped, verified behavior (AGENTS.md, "Evidence-based" and "Honesty"). This page applies the same rule to itself, with the review's three labels and one more:

- **Verified (code):** read in this repository.
- **Verified (Apple):** stated in Apple's public documentation, cited in "Sources".
- **Reported:** stated by a named public source (a paper, a standard, a vendor or press report), cited in "Sources". Press reports of leaked documents are marked as such; nothing here depends on them being accurate.
- **To confirm on a device:** consistent with the documentation, not stated by Apple, not run.

This page describes flaw classes and defenses. It gives no procedure for defeating any product.

Numbering: flaw classes are FC1 to FC27, hardening items HD1 to HD38, security checks SC1 to SC18. The review's own device checks are cited as "review check N".

## 1. Threat model summary

### 1.1 What is protected

| Asset | Where it lives under issue 83 | Note |
|---|---|---|
| Capture files (DNG, HEIF, JPEG) | The app's store under Application Support | The only copy when "nope only" is chosen |
| Thumbnails and previews | In the store (plan decision 16), and in memory | The classic leak in vault-style apps (FC1, FC9) |
| The manifest and index | In the store | Holds capture times (review E5), counts and order |
| That captures exist, how many, and when | The store, settings, system records | Cannot be hidden (issue 83, "Limits to state plainly"; review B4, E6) |
| The protection settings | App Group `UserDefaults` | Default protection class; always backed up (review B4) |
| Exported and shared copies | Outside the app | Outside every control in this issue |

### 1.2 Who is considered, and what issue 83 can do about each

The one cryptographic protection in issue 83 is iOS Data Protection class Complete, whose key is derived from the device passcode and the device's hardware key [A1]. Lock Captures is access control inside the app's own process. Every row below follows from those two facts.

| # | Adversary | Capability | What protects captures | Honest result |
|---|---|---|---|---|
| T1 | A recipient of a shared file | Reads every byte | The metadata allowlist, "Share Without Optional Details", file names | Metadata can be removed; the sensor pattern cannot (FC13) |
| T2 | Someone who lives with the person | Brief use of the unlocked phone; may know the passcode | Lock Captures | Stops a person without the passcode. Does not stop deletion of the app (review D5) or a person who knows the passcode |
| T3 | Seizure of a locked phone that has been unlocked since restart (AFU) | Forensic tools, no passcode | Class Complete, if every file really has it | Strongest case for the design, and the one a class mistake silently breaks (FC6) |
| T4 | Seizure of a phone that is off or restarted (BFU) | Forensic tools, no passcode | All Data Protection classes except No Protection | Best state the phone can be in; reached by a restart or by iOS's inactivity restart (FC7) |
| T5 | Seizure while the phone is in the hand, unlocked | Uses the app directly | Lock Captures, the re-lock rules, the neutral marker | Only if the library has locked again (review D1, D3) |
| T6 | Forced unlock: a face held to the phone, or a demanded passcode | The person's biometrics or passcode | Passcode Only against a forced face; nothing against a demanded passcode | State plainly (FC4) |
| T7 | A thief who watched the passcode being typed | The phone and its passcode | Nothing in the app: the passcode opens the lock | The system's Stolen Device Protection addresses this, not the app (FC4) |
| T8 | Someone with a paired computer, a backup, or the backup password | Copies of the container | Leave Out of Backups (a request to iOS), backup encryption | Review B1 to B3 |
| T9 | A cloud provider under legal process | iCloud Backup without Advanced Data Protection | Leave Out of Backups; Advanced Data Protection | Review B1 |
| T10 | Code running with the app's privileges, or a jailbroken or instrumented phone | Reads the app's memory and files, changes its behavior | Nothing in the app | Out of scope and said so (FC2, FC26) |
| T11 | A dependency or build-chain attacker | Changes what ships | `docs/SECURITY_AUDIT.md`, check 1 | Issue 83 should add no dependency (FC25) |
| T12 | A mistake in a pull request | A log line, a temporary file, a wrong class | The static checks and tests in section 5 | The most likely adversary |

### 1.3 Three conclusions that shape the rest

1. **Class Complete carries the feature.** If one file, thumbnail, manifest or temporary copy has the default class instead, an AFU extraction (T3) reads it without the passcode. The Simulator does not enforce Data Protection, so no CI test can see this. HD1 and SC1 are ranked first for that reason.
2. **Lock Captures protects against people, not tools.** It is worth building well, because T2, T5 and T6 are the common cases for this audience. It must never be described in words that suggest it protects files (FC1, FC2, section 6).
3. **Most real incidents in this class are state and residue bugs, not broken cryptography:** a timer reset by a second entry point, a thumbnail in a cache, a notification kept by the system, a deleted file that comes back. The checklist is weighted accordingly.

## 2. Flaw classes and how each applies

Severity is the harm to a person in the review's audience if the flaw is present. Likelihood is the chance it is present or met in practice for this app, given the specification as written. Each entry says how it relates to the review.

### Vault apps and local authentication

**FC1. The store is protected by a screen, not by its own encryption.**
- *Evidence (Reported).* A 2015 review of three iOS photo vault apps found lock screens that could be bypassed on a jailbroken phone, PINs and album passwords stored in plaintext, and photos stored unencrypted [I1]. A 2017 study of 18 Android vault apps recovered hidden files from 16 without logging in [I2]. A 2022 comparison of five iOS vault apps found each left photos or evidence recoverable by forensic toolkits [I3]. A 2020 forensic advisory says the same of earlier vault apps and that newer ones are stronger [I4].
- *Applies to issue 83.* By design: "Nothing in this issue encrypts captures or stores keys." The issue says so plainly, which the apps in those studies did not.
- *Severity* High if any wording implies more; *likelihood* of the technical condition is certain, of a wording slip Medium.
- *Relation.* The review confirms nothing is called encryption. New here: the banned-words list in section 6 and decisions 1 and 2.

**FC2. Local authentication used as an event, not bound to a key.**
- *Evidence (Reported).* OWASP lists this as weakness MASWE-0044, "Biometric Authentication Can Be Bypassed", with tests MASTG-TEST-0266 and 0267 and the best practice "Use Cryptographic Binding for Biometric Authentication" [O3][O2]. A public instrumentation tool documents that overriding the result of `evaluatePolicy` works against apps that branch on its Boolean and "will not work in cases where keychain items are protected with access control flags" [O4]. Apple: keychain access control lists "are evaluated inside the Secure Enclave" [A2].
- *Applies to issue 83.* Yes: Lock Captures is `LAContext.evaluatePolicy` and `evaluateAccessControl` with no keychain item. It needs T10.
- *What binding would and would not add.* An attacker who can change the app's behavior at run time can also read the store's files directly, because the files are protected by the device's unlock state, not by the app. A keychain item with `.userPresence` or `.biometryCurrentSet` used only as an "unlock oracle" would stop the Boolean override and nothing else. Binding becomes meaningful only when the bound key encrypts the files, which is issue 84.
- *Severity* Medium; *likelihood* Low (needs a jailbroken or instrumented phone, which is out of scope in `docs/SECURITY_AUDIT.md`).
- *Relation.* New. Decision 1.

**FC3. Lock state-machine bypass: timers, second entry points, rapid sequences.**
- *Evidence (Reported).* In February 2019 an iOS messaging app's new Face ID lock could be skipped when its delay was anything other than "immediately": entering through the share sheet reset the timer [I5]. CVE-2018-9840 records another messaging app's screen lock bypassed "via certain rapid sequences of actions" [I6].
- *Applies to issue 83.* Directly. The issue's security review item 1 names routes and the clock; the review adds D2 (a phone lock inside the delay) and D3 (no re-lock in the foreground). Not yet stated: the lock's *initial* and *error* states; a prompt that is canceled and retried; two prompts in flight; a route that arrives while a prompt is showing; a scene created by the system (a second window on iPad, state restoration) that starts unlocked.
- *Severity* High; *likelihood* Medium. Both incidents shipped in mature apps.
- *Relation.* Builds on D2, D3 and owner decisions 4 and 5 of 2026-11-21. New: HD2 and SC3.

**FC4. The fallback is the weak point: a forced face, a demanded or observed passcode.**
- *Evidence.* NIST: "Biometric comparison is probabilistic" and "Biometric characteristics do not constitute secrets" [N1] (Reported). A digital-rights guide advises turning biometric unlock off before a protest [G1] (Reported). Apple lists when iOS itself demands the passcode, including after the power-off or Emergency SOS screen is shown and canceled [A4] (Verified, Apple). Apple's Stolen Device Protection exists because thieves learn passcodes; with it on, away from familiar places, a system-locked app opens only with Face ID or Touch ID, with no passcode fallback [A6][A7] (Verified, Apple). OWASP treats passcode fallback for sensitive actions as weakness MASWE-0045 [O3].
- *Applies to issue 83.* T6 and T7 pull in opposite directions. Passcode Only resists a forced face and gives a thief with the passcode everything. A biometrics-only mode would resist the thief and give a forced face everything. The issue offers the first; the review (D4) asks that it be explained.
- *Severity* High; *likelihood* High for T6 in this audience.
- *Relation.* Builds on D4. New: the T7 case and whether the app's own lock should offer a biometrics-only choice (decision 3). Whether Stolen Device Protection changes what an app's own `deviceOwnerAuthentication` prompt accepts is not stated by Apple: to confirm on a device (SC4).

**FC5. Biometric enrollment changes.**
- *Evidence (Reported, Verified Apple).* OWASP tests MASTG-TEST-0270 and 0271 check that an app detects enrollment changes [O2]. A keychain item can be restricted so it is unusable if enrollment changed since it was stored [A2].
- *Applies to issue 83.* The issue compares `LAContext.domainState.biometry.stateHash` with a value kept in settings. With `deviceOwnerAuthentication`, adding a face already needs the passcode, and the passcode opens the lock, so the check adds little against anyone it could stop. It is worth keeping as hygiene, not worth claiming.
- *Severity* Low; *likelihood* Low.
- *Relation.* New assessment; no change proposed beyond wording (section 6).

### Data Protection, extraction and backups

**FC6. A file with the wrong protection class.**
- *Evidence (Verified, Apple).* Class C, available after first unlock, "is the default class for all third-party app data not otherwise assigned to a Data Protection class"; with class C "the decrypted class key isn't removed from memory when the device is locked"; class A's key is discarded "shortly after the user locks a device (10 seconds, if the Require Password setting is Immediately)" [A1]. OWASP test MASTG-TEST-0299 checks the classes of files in private storage [O2].
- *Evidence (Reported).* Public reporting on leaked vendor support tables and on later product announcements describes extraction capability concentrated on phones in the AFU state [F1][F2][F3]. None of that reporting is needed for the conclusion, which follows from Apple's description of class C.
- *Applies to issue 83.* The class is set by whoever creates the file. Paths that create files the store did not explicitly class: a system image writer; an atomic replace through a system replacement directory (FC19); a move from the Lock Screen session folder (review A2); a restored backup (review B5); a thumbnail or preview made by a system service; a temporary export. The review covers the capture path (C1, C2, A2, B5). Not yet covered: sidecar and temporary files as a class, a single write path, and a static rule that fails the build on any other.
- *Severity* Critical; *likelihood* Medium.
- *Relation.* Builds on issue item 4 and review A2, B5, C1, C2. New: HD1, HD3, SC1, and decision 7 (the app-wide default-class entitlement).

**FC7. Forensic extraction depends on device state and passcode strength, which the app does not control.**
- *Evidence (Verified, Apple).* One passcode attempt is calibrated to about 80 milliseconds; a six-character alphanumeric passcode "would take more than five and one-half years" to exhaust; delays escalate after failed attempts; Erase Data removes everything after ten [A3].
- *Evidence (Reported).* From iOS 18.1 an iPhone that stays locked for 72 hours restarts itself and returns to the BFU state [F4]. Apple has not documented it in the pages read here.
- *Applies to issue 83.* As guidance and as wording limits only. A phone that was restarted and not unlocked protects the store with every class, not only class Complete; a short numeric passcode is the whole of the protection (review C3).
- *Severity* High; *likelihood* Medium.
- *Relation.* Builds on C3 and B3. New: decision 9 (how much device-level guidance `docs/PRIVACY.md` carries).

**FC8. Backup extraction.**
- *Evidence.* Review B1 to B3 with Apple's pages. OWASP tests MASTG-TEST-0058, 0215 and 0298 check sensitive data in backups and backup exclusion [O2]. Keychain items in a "this device only" class are protected with the device's hardware key when copied in a backup, and "when passcode set" items "aren't backed up" [A2] (Verified, Apple).
- *Applies to issue 83.* Covered by the review. Two additions: the app-switcher snapshot folder and saved scene state are in the app's container, and whether they are in each kind of backup is not documented (SC2, SC9); and the last sentence above is what would make issue 84's key non-restorable, which is a consequence to state there, not here.
- *Severity* Critical (already B1); *likelihood* High.
- *Relation.* No new finding; SC2 extends review check 4 with open tools.

### Copies and residue

**FC9. Copies the system keeps outside the app's control.**
- *Evidence (Reported).* In 2026 investigators recovered a messaging app's deleted messages from iOS's notification store; Apple fixed a bug in which "notifications marked for deletion" could be kept (iOS 26.4.2) [I7]. iOS records app use in system stores that forensic tools read (knowledgeC and, from iOS 16, Biome) [F5]. OWASP tests MASTG-TEST-0059 and 0290 cover the snapshot iOS takes when an app leaves the foreground [O2].
- *Applies to issue 83.* The app posts no capture content in notifications, Live Activities or widgets (issue, "Lock screen"). Places not yet named: thumbnails or previews made by a system service on the app's behalf (Quick Look, the share sheet's header and its preview), which run outside the app and may cache; system records of when the app and the camera were used (review E6); crash reports and diagnostics archives (FC18).
- *Severity* High; *likelihood* Medium.
- *Relation.* Builds on E2, E6. New: HD6, SC8, SC9.

**FC10. Deleting is not erasing, and a recovery rule can bring deleted captures back.**
- *Evidence (Reported).* iOS 17.5 made photos deleted long before reappear; Apple's fix note for 17.5.1 describes "photos that experienced database corruption" reappearing "even if they were deleted", and reporting describes files that had stayed on storage after their database entries were removed [I8]. SQLite keeps deleted content in free pages and journals unless `secure_delete` is on, and its full-text tables "might leave forensic traces" even then [S1]. NIST's media sanitization guidance (SP 800-88 Rev. 2, September 2025) treats cryptographic erase as the technique for encrypted media, under stated preconditions [N2]. Apple gives every file its own key [A5] (Verified, Apple); Apple's pages read here do not say what happens to that key when one file is deleted, so no claim is made.
- *Applies to issue 83.* Review E4 covers the index format and the word "now". The 17.5 incident maps onto a rule the review itself proposes: "a file that cannot be matched to the index is never deleted automatically" (C1) and "a file without a manifest is listed as a recoverable item" (G2). If a delete removes the index entry first and is interrupted before the file is removed (a crash, a full disk, the phone locking), the next launch finds an unmatched file and offers it back. For this audience a deleted capture reappearing is a serious failure.
- *Severity* High; *likelihood* Medium without an ordering rule.
- *Relation.* Builds on C1, E4, G2 and exposes a conflict between them. New: HD4, HD5, decision 8.

**FC11. Leftover bytes in a rewritten file.**
- *Evidence (Reported).* CVE-2023-21036 ("aCropalypse"): an image editor wrote a smaller file over a larger one without truncating it, so cropped-out content stayed recoverable in files people had already shared [I9].
- *Applies to issue 83.* "Share Without Optional Details" rewrites metadata without re-encoding the image, and the DNG path is byte-level code. Review F6 asks that every byte of the output be accounted for. Additions: the output is always a new file, never written over an existing one; a removed item's bytes are removed, not only its reference (in HEIF, an item dropped from the item table while its data stays in the media data box; in JPEG, data after the end marker or in a second image; in DNG, an unreferenced directory or strip); auxiliary images are covered by the allowlist.
- *Severity* High; *likelihood* Medium for the DNG writer, Low for formats rewritten by a system API.
- *Relation.* Builds on F6 and issue item 8. New: HD7, SC12, SC13.

**FC12. Metadata that identifies a device or person.**
- *Evidence (Reported).* C2PA's own harms modelling lists loss of control over personal information among the harms it considers [M1]; a 2025 report reviews how identity can be attached to provenance data [M2].
- *Applies to issue 83.* The existing allowlist, fail-closed read-back and per-photo anonymous signing already address this (`docs/PRIVACY.md`; the certificate validity is the same fixed range for every photo, line 334). Issue 83 adds one new place for metadata to hide: the store's manifest (review E5).
- *Severity* Medium; *likelihood* Low.
- *Relation.* No new finding. HD8 restates E5's manifest rule as a test.

**FC13. The sensor's noise pattern.**
- *Applies to issue 83.* Unchanged by anything here. Stated as a limit in the issue, on the Honesty screen and in `docs/research/privacy-claims.md`, claim 9, with its sources. Review F2 puts it on the share summary.
- *Severity* High for a person relying on unlinkability; *likelihood* depends on the adversary. *Relation.* No new finding; section 6 keeps the wording limit.

**FC14. File names and ordering.**
- *Applies to issue 83.* Review F1 removes the date from names by default (owner decision 7 of 2026-11-21). Not yet stated: a neutral name built from a counter still tells a recipient how many photos came before and, by its gaps, that some were withheld or deleted; a collision suffix does the same; a name that is stable per capture lets two recipients match what each received without comparing pixels.
- *Severity* Medium; *likelihood* Medium (counters are the obvious implementation).
- *Relation.* Builds on F1. New: HD9.

**FC15. The share route identifies the sender or keeps a copy.**
- *Evidence (Reported).* In January 2024 a state forensic institute said it identified AirDrop senders from device logs by reversing hashed phone numbers and email addresses; researchers tied this to a weakness published in 2021 [I10]. OWASP tests MASTG-TEST-0276 to 0280 cover the general pasteboard, its expiry and its local-only option [O2].
- *Applies to issue 83.* Review F4 covers the AirDrop name and sender-side copies. The incident adds that the *receiving* device can hold a record that identifies the sender. Copy is removed from the share sheet and nothing in the app uses the pasteboard, so Universal Clipboard is not reached.
- *Severity* High; *likelihood* Medium.
- *Relation.* Builds on F4, E3. New: one sentence for `docs/PRIVACY.md` (HD10) and a static check that no pasteboard or drag API exists (SC5).

**FC16. Screenshots, screen recording and mirroring.**
- *Evidence (Verified, Apple).* The system reports when a scene is being captured (`isSceneCaptured`, `sceneCaptureState`); the signal "doesn't differentiate between capture types. Screen recording, AirPlay mirroring, and remote control all produce the same signal." Apple's own advice is to apply protections selectively and use neutral wording [A9]. Nothing in the pages read lets an app prevent a screenshot; a comparable open-source app says of iOS that it can block recordings inside the app and the recent-apps view but not screenshots [R2] (Reported).
- *Applies to issue 83.* The issue states the screenshot limit. Not considered: covering captures while the scene is being recorded, mirrored or remotely controlled. Whether iPhone Mirroring (review C4) raises this signal is not documented: to confirm on a device.
- *Severity* Medium; *likelihood* Medium.
- *Relation.* Builds on C4. New: HD11, SC10, decision 4.

**FC17. The app-switcher snapshot.**
- *Evidence.* MASTG-TEST-0059 and 0290 [O2]; a widely used messaging app ships a "hide screen in app switcher" cover for the same reason [R1] (Reported).
- *Applies to issue 83.* Covered by the issue and by review E2. Additions: the cover must be in place when the scene becomes *inactive* (the existing covers do this, `Sources/NopeUI/PhotoViewer.swift`, line 856); each scene has its own snapshot on iPad; the snapshot folder's protection class and backup status are unknown (SC9).
- *Severity* Medium; *likelihood* Medium. *Relation.* Extends E2 only.

**FC18. Logs and diagnostics.**
- *Evidence.* MASTG-TEST-0296 and 0297 [O2]; `docs/SECURITY_AUDIT.md`, check 13.
- *Applies to issue 83.* The issue's item 6 covers `Logger` values. Not covered: text that reaches diagnostics by other routes. A file-system error's description contains the full path; a message passed to `fatalError`, `precondition` or `assert` is written into the crash report, which stays on the phone and is sent to Apple and the developer if the person opted in; an error shown on screen can be captured in a screenshot. Store names are random, so the exposure is counts, structure and timing, not content.
- *Severity* Low to Medium; *likelihood* Medium.
- *Relation.* Builds on issue item 6. New: HD12, SC6.

**FC19. Temporary files and atomic-write residue.**
- *Applies to issue 83.* The issue's item 3 covers export copies. Not covered: where an atomic write or an item replacement puts its intermediate file (a sibling in the same folder, or a system replacement directory outside the store with the default class); intermediates left by a crash, a kill for memory, or the phone locking mid-write; and the conflict between "remove leftovers at launch" (item 3) and "delete nothing while protected data is unavailable" (review C1).
- *Severity* Medium; *likelihood* Medium.
- *Relation.* Builds on item 3, C1, G2. New: HD3.

**FC20. A database index.**
- *Evidence.* [S1] as in FC10: free pages, journals, write-ahead logs that are "not truncated following a checkpoint", and full-text shadow tables.
- *Applies to issue 83.* The issue describes "an index built from these files" without a format. Review E4 proposes a file rewritten whole. A database would also create journal and log files beside it, each needing the right class (FC6), and a store-encrypting library would be a new dependency (FC25).
- *Severity* Medium; *likelihood* Low if E4 is adopted. *Relation.* Supports E4. HD5 makes it a rule with a static check.

### Platform surfaces

**FC21. Search, Siri, Handoff and saved state.**
- *Applies to issue 83.* The issue's item 2 covers intents, entity queries and Spotlight. Not named: user activities advertised for Handoff or prediction, and saved scene state. A capture identifier kept in scene storage or a saved navigation path is written to disk outside the store, restores a viewer route at launch (FC3), and shows which capture was last open.
- *Severity* Low to Medium; *likelihood* Medium (scene storage is the convenient way to restore a screen). *Relation.* New: HD13.

**FC22. Third-party keyboards and the keyboard cache.**
- *Evidence (Verified, Apple).* A custom keyboard is used for every text field "except the passcode input and any secure text view" [A10]; an app can refuse custom keyboards for itself [A11]. MASTG-TEST-0055 and 0313 cover the keyboard cache [O2].
- *Applies to issue 83.* The specification adds no text field that holds capture data: no search, no rename, no caption. The authentication prompt is the system's. So this does not apply unless a later design adds a field.
- *Severity* Low; *likelihood* Low. *Relation.* New: HD14 is a rule, not a build item.

**FC23. Continuity.**
- *Evidence (Verified, Apple).* iPhone Mirroring needs the iPhone locked and nearby; the Mac authenticates with its login password, Touch ID or an Apple Watch; the iPhone's camera and microphone are not available, "including for Face ID" [A8].
- *Applies to issue 83.* Review C4. The quoted sentence makes one outcome more likely than the review could say: a Face ID prompt cannot be satisfied by the iPhone's camera during mirroring, so the app's lock would fall to whatever the system offers in its place. Which secret that is remains to confirm on a device (review check 8).
- *Severity* Medium; *likelihood* Low to Medium. *Relation.* Adds evidence to C4 only.

**FC24. An unlocked phone in someone else's hands.**
- *Applies to issue 83.* Review D1, D3, D5, D7 and E1 cover this. One addition from Apple's pages: the system's own app lock ("Require Face ID") gains a no-passcode-fallback behavior under Stolen Device Protection [A7], which the app's own lock does not have; the issue's footer for the system lock (a device check there) can say so once confirmed.
- *Severity* High; *likelihood* High. *Relation.* No new finding.

**FC25. Supply chain.**
- *Evidence.* MASVS-CODE-3; MASTG-TEST-0273 and 0275 [O1][O2]; `docs/SECURITY_AUDIT.md`, check 1.
- *Applies to issue 83.* The issue needs no new dependency: LocalAuthentication, Foundation file APIs and ImageIO are platform frameworks. The R4 probe is debug-only and not merged. The risk is a convenience dependency arriving with the store (a database wrapper, an image cache, a zip library for batch export).
- *Severity* High; *likelihood* Low. *Relation.* New: HD15.

**FC26. Jailbreak and instrumentation.**
- *Evidence.* MASVS-RESILIENCE-1 to 4 and tests MASTG-TEST-0088, 0240 and 0241 [O1][O2]; `docs/SECURITY_AUDIT.md`, check 20: "The source is public and the app holds no secrets, so anti-tampering, anti-debugging and obfuscation are not goals."
- *Applies to issue 83.* The app now holds something worth protecting, so the question is fair to reopen. Detection in an open-source app is advisory at best: the checks are public, they can be removed by the same means they detect, they produce false alarms on ordinary phones after system changes, and a result cannot be verified, which sits badly with the rule that copy describes only verified behavior.
- *Severity* Medium; *likelihood* Low. *Relation.* New: decision 5.

**FC27. Captures in memory.**
- *Evidence.* MASTG-TEST-0060 [O2]; `docs/SECURITY_AUDIT.md`, check 15.
- *Applies to issue 83.* Review D1 and E1 cover the session's records. Additions: decoded thumbnails and full images held by the library and viewer after the lock engages; images held by a system image cache. Overwriting buffers is not dependable in Swift: `Data` and decoded images are copied and backed by system-managed memory the app cannot scrub. The honest control is to drop every reference at re-lock and make no claim about memory.
- *Severity* Medium; *likelihood* Medium. *Relation.* Builds on D1, E1. New: HD16.

## 3. Platform guidance, standards and reference designs

### 3.1 Apple

- **Data Protection classes [A1].** Class A (Complete), class B (Complete Unless Open: a file can be created and written while locked; "as soon as the file is closed, the per-file key is wiped from memory"), class C (the default), class D. Issue 83's use of A, with B for writes while locked, matches the documented purpose of each. Review C2's suggestion to create every capture as class B and raise it later is consistent with this page.
- **Keychain [A2].** Access control lists are evaluated in the Secure Enclave. "When passcode set, this device only" items are not backed up and are discarded if the passcode is removed. This is the natural home for a key in issue 84 and is the reason a forgotten or removed passcode there means loss. Issue 83 keeps "no Keychain items" unless decision 1 changes it.
- **Passcodes [A3], biometrics [A4].** Quoted in FC4 and FC7.
- **Stolen Device Protection [A6][A7].** A system feature; covers system-locked apps. The app cannot turn it on or detect it through any API read here.
- **Lockdown Mode, Advanced Data Protection.** As in the review's sources. Advanced Data Protection puts iCloud Backup under end-to-end encryption [A12].
- **Screen capture [A9].** Quoted in FC16.
- **CryptoKit and the Secure Enclave.** Already used for per-photo signing keys (`Sources/NopeSigning/SecureEnclaveSigningKey.swift`). Nothing in issue 83 needs them.

### 3.2 OWASP MASVS v2, mapped to issue 83

`docs/SECURITY_AUDIT.md` maps its checks to MASVS and lists "AUTH: Not applicable: no accounts or sign-in". With issue 83 that line stops being true: MASVS-AUTH-2 and AUTH-3 concern local authentication. HD17 updates it. Control statements are paraphrased from [O1]; tests are from [O2], several of which OWASP marks as beta.

| Control | What it asks | Where issue 83 meets it | Tests to draw on | State |
|---|---|---|---|---|
| MASVS-STORAGE-1 | Sensitive data is stored securely | Class Complete on every store file; nothing in the App Group, Caches or tmp | MASTG-TEST-0299, 0300 to 0302, 0388 | In the spec; HD1, HD3 add the single write path |
| MASVS-STORAGE-2 | Sensitive data does not leak | Logs, backups, memory, system-held copies, keyboard cache | 0296, 0297, 0058, 0215, 0298, 0060, 0055 | Partly in the spec; HD6, HD12, HD16 are new |
| MASVS-CRYPTO-1, -2 | Strong cryptography; sound key management | Nothing new in issue 83. Applies in full to issue 84 | 0061, 0062, 0063 | Not applicable to 83; random names use the system generator (HD9) |
| MASVS-AUTH-1 | Secure authentication protocols | No accounts or servers | none | Not applicable |
| MASVS-AUTH-2 | Local authentication follows platform best practice | Lock Captures | 0064, 0266, 0267, 0270, 0271 | Event-bound by design: a known gap against T10, stated (FC2; decision 1) |
| MASVS-AUTH-3 | Sensitive operations need additional authentication | Export, delete, Delete All, the protection settings | 0268, 0269 | In the spec; passcode fallback is deliberate (FC4; decision 3) |
| MASVS-NETWORK-1, -2 | Secure network traffic | No network | audit checks 7, 8 | Unchanged |
| MASVS-PLATFORM-1 | Inter-process mechanisms used securely | Share sheet, Files export, intents, extensions, pasteboard, user activities | 0072, 0073, 0276 to 0280, 0075 | In the spec and review E3; HD13 and SC5 are new |
| MASVS-PLATFORM-2 | WebViews used securely | None | none | Not applicable |
| MASVS-PLATFORM-3 | The user interface does not leak | App-switcher cover, capture state, the neutral marker | 0059, 0290 | In the spec and review E2; HD11 is new |
| MASVS-CODE-3 | No components with known vulnerabilities | No new dependency | 0273, 0275 | HD15 |
| MASVS-CODE-4 | Untrusted input is validated | The reader, the rewrite, the session-folder hand-off, manifests | fuzz tests (issue item 9) | In the spec; HD7, HD18 extend |
| MASVS-RESILIENCE-1 to -4 | Platform integrity, anti-tampering, anti-analysis | Not goals (audit check 20) | 0088, 0240, 0241 | Decision 5 |
| MASVS-PRIVACY-1 | Minimal access to data and resources | No new permission beyond the Face ID usage text | audit check 16 | In the spec |
| MASVS-PRIVACY-2 | The person cannot be identified | Metadata, names, the manifest | audit check 9 | In the spec; HD8, HD9 |
| MASVS-PRIVACY-3 | Transparency | The limits text, the Honesty screen | audit check 19 | S6; section 6 |
| MASVS-PRIVACY-4 | Control over one's data | Export, delete one, Delete All, backup choice | none | In the spec; HD4 makes delete dependable |

### 3.3 NIST

- **SP 800-63B-4 (July 2025), section 3.2.3 [N1].** Biometrics are not secrets and are to be used only together with a physical authenticator. On a phone the device is that authenticator; the point for issue 83 is the wording: Face ID is a convenience in front of the passcode, never the protection itself.
- **SP 800-88 Rev. 2 (September 2025) [N2].** As summarized by NIST and by secondary sources (the full text was not read for this page), it warns about relying on overwriting for flash storage and keeps cryptographic erase as the technique for encrypted media, under preconditions. For the app this supports "no claim about recovery of deleted files" and argues against any "secure delete" or "shred" wording or feature.

### 3.4 Reference designs

Cited as designs to learn from, not as endorsements, and each as its publisher describes it.

- **A messaging app's Screen Lock and app-switcher cover [R1].** The lock uses the phone's own passcode or biometrics and is separate from that app's PIN; the cover is a separate setting. Its history supplies two of the incidents above (FC3, FC9): a lock built on device authentication is a state machine that needs adversarial tests, and content handed to the system can outlive the app's own deletion.
- **A documentation app for human-rights work [R2].** It encrypts its files inside the app under its own lock, which is the model of issue 84, not of issue 83. Its public notes are useful for wording: "There is no such thing as an app that is 100% 'secure'"; exported files "are no longer encrypted"; and "Due to iOS restrictions, it is not possible to camouflage" the app on iOS. It offers a quick-delete control with a visible countdown that can be canceled. It publishes independent audits.
- **A proof-of-capture camera tool [R3].** It keeps proof data in a separate file and does not modify the media, and its maintainers state plainly what has not been audited or tested. The second point is the practice issue 83 already follows.
- **A protest-safety guide [G1].** The device-level advice people in this audience are given: a long passcode, biometric unlock off, the Lock Screen camera so the phone stays locked, metadata removed before posting.

## 4. Hardening checklist

Ranked. **P1** closes a route to captures or to their reappearance. **P2** reduces residue or strengthens a test. **P3** is hygiene or a rule for later designs. "State" says where the item already stands: **Spec** (in issue 83), **Review** (in the blind-spot review, with its ID), or **New**. "Owner" is the build group that would carry it; nothing here is assigned or decided.

| ID | Rank | Item | State | MASVS | Owner |
|---|---|---|---|---|---|
| HD1 | P1 | **One write path for the store.** Every file the store creates (capture, manifest, index, thumbnail, export copy, intermediate) goes through one function that takes the protection class as a required argument and reads the class back after the write. A static check fails the build on any other file-writing call in the storage and export modules. | Spec item 4 and Review A2, B5, C2 for the class; the single path and static rule are New | STORAGE-1 | S1; check in S6 |
| HD2 | P1 | **The lock is a fail-closed state machine, and reading needs proof of unlock.** Locked is the initial state, the state after any error, cancel, timeout or unknown event, and the state of every newly created scene. The store's read functions take a value that only the lock can create and that stops working when the lock engages, so a route that forgot to ask cannot compile. One prompt at a time; a result that arrives after a re-lock is discarded. | Spec item 1 and Review D2, D3 for the rules; the type-level proof and the race rules are New | AUTH-2, AUTH-3 | S3 (the empty gate file S1 creates is where the type lives) |
| HD3 | P1 | **Intermediates stay inside the store.** Atomic writes and replacements use a directory inside the store, created with the store's class and backup rule, never a system replacement or temporary directory. Leftovers are removed at the next *unlocked* launch only, and only from that directory (Review C1 stands for everything else). | Spec item 3 in part; New | STORAGE-1, STORAGE-2 | S1, S2 |
| HD4 | P1 | **Delete in an order that cannot bring a capture back.** A delete first records the capture's identifier as deleted, then removes files, thumbnails and export copies, then removes the index entry, then clears the record. A rebuild or recovery scan never lists a file whose identifier is recorded as deleted. How this meets Review C1 and G2 is decision 8. | New (conflict between Review C1/G2 and the delete rule) | PRIVACY-4, STORAGE-2 | S1, S5 |
| HD5 | P1 | **No database for the index.** A file rewritten whole (Review E4). A static check bans SQLite and Core Data imports in the storage module. If a later design needs one: `secure_delete` on, a rollback journal that is deleted, no write-ahead log, no full-text tables, a `VACUUM` after Delete All, every database and journal file through HD1. | Review E4; the static check and fallback settings are New | STORAGE-2 | S1 |
| HD6 | P1 | **No system-made pictures of a capture.** Thumbnails and previews are decoded in the app's process from the store, with system image caching off; no Quick Look preview or thumbnail service is given a store file. The share sheet gets neutral metadata (the app icon and a count), not a preview image (Review E2). No notification, Live Activity or widget carries capture content, a file name or a time. | Spec ("Lock screen") and Review E2 in part; the in-process rule is New | STORAGE-2, PLATFORM-3 | S1, S2 |
| HD7 | P1 | **A clean copy is a new file with every byte accounted for.** Written from scratch to a new file, never over an existing one. Removed items' data is removed, not only unreferenced. Auxiliary and embedded images are on the allowlist or absent. The output is checked by the app's reader and, in CI, by a second independent parser (ExifTool is already pinned for `file-compat`). | Review F6 and Spec item 8; new-file rule, removed-data rule and second parser are New | CODE-4, PRIVACY-2 | S4 |
| HD8 | P2 | **The manifest holds nothing the detail switches removed.** A test builds captures with each switch off and asserts the manifest and index contain no field beyond the documented set (Review E5, with the capture time as the one decided exception). | Review E5; the test is New | PRIVACY-2 | S1 |
| HD9 | P1 | **Export names are random, per export.** Drawn from the system random generator for each export; no counter, no collision suffix that counts, no reuse of the store's internal name, no name stable across exports. | Review F1 for dates; New for counters and stability | PRIVACY-2 | S4 (S2 if S4 is cut) |
| HD10 | P2 | **Say what the route records.** `docs/PRIVACY.md` and the share note: the receiving device and the app shared with may keep a record that identifies the sender, not only a copy (adds to Review F4). | Review F4; the receiving-side sentence is New | PRIVACY-3 | S6 |
| HD11 | P2 | **Cover captures while the scene is being captured.** With Lock Captures on, the library and viewer show the cover while `isSceneCaptured` is true, with a neutral notice. Subject to SC10 and to decision 4. | New | PLATFORM-3 | S3 |
| HD12 | P2 | **Diagnostics carry no paths.** No path, file name, count or time in a message passed to `fatalError`, `precondition` or `assert`, in an error's description shown on screen, or in a signpost. File-system errors are mapped to the app's own constant messages before they reach a log or a view. | Spec item 6 for `Logger`; the rest is New | STORAGE-2 | S1, S2 |
| HD13 | P2 | **No capture identifier in saved state or user activities.** Scene storage and saved navigation hold no capture identifier; the library always opens at its top, locked. Any user activity is ineligible for Handoff, search and prediction. | Spec item 2 for intents and Spotlight; New for saved state and Handoff | PLATFORM-1, STORAGE-2 | S1, S3 |
| HD14 | P3 | **No text fields over capture data.** A rule for later designs: a search, rename or caption field in the library is a new review (keyboard cache, third-party keyboards). | New | STORAGE-2 | S6 (rule in `docs/ARCHITECTURE.md`) |
| HD15 | P1 | **No new dependency for issue 83.** The S groups add nothing to `security/allowed-dependencies.txt`; a pull request that does is a separate reviewed decision. | New as a stated rule; the allowlist mechanism exists | CODE-3 | All S groups |
| HD16 | P1 | **Drop every picture when the lock engages.** At re-lock, at background, and when protected data becomes unavailable: release decoded thumbnails, viewer images and session records, and empty any image cache the app controls. No claim about memory is made. | Review D1, E1 for session records; library and viewer images are New | STORAGE-2 | S3 |
| HD17 | P2 | **Update the audit plan.** `docs/SECURITY_AUDIT.md`: the MASVS-AUTH row, the threat model's assets and adversaries (section 1 here), check 11's pass rule (the container now holds captures by design), and new checks from section 5. | New | all | S6 |
| HD18 | P2 | **Treat the session folder as input.** Files from the Lock Screen session folder are given new random names, checked with the fail-closed reader before they are listed, and never trusted for their names, dates or extensions. | Spec item 5 in part; New | CODE-4 | S1 |
| HD19 | P1 | Verify the class of every stored file at each unlocked launch and re-apply it. | Review B5 | STORAGE-1 | S1 |
| HD20 | P1 | Three store states; read, rebuild, migrate and delete nothing while protected data is unavailable. | Review C1 | STORAGE-1 | S1 |
| HD21 | P1 | Re-lock when the library or viewer closes; delays only if a phone lock inside the delay is detected. | Review D2, D3; decided 2026-11-21 | AUTH-2 | S3 |
| HD22 | P1 | No thumbnail, preview or detail outside the lock; the neutral marker. | Review D1; decided | STORAGE-2, PLATFORM-3 | S3 |
| HD23 | P1 | Lock Screen captures always go to the session folder; the app files them. | Review A1; decided | STORAGE-1 | S1 |
| HD24 | P1 | Backup choice asked once; the footer states it; the flag re-applied after every write. | Review B1, B2; decided | STORAGE-2 | S5 |
| HD25 | P2 | Remove Copy, Save Image, Assign to Contact and Print from the share sheet. | Review E3; decided | PLATFORM-1 | S2 |
| HD26 | P2 | The privacy cover over system-presented sheets and dialogs. | Review E2 | PLATFORM-3 | S3 |
| HD27 | P2 | Delete All stops a running series and discards pending saves first. | Review E4 | PRIVACY-4 | S5 |
| HD28 | P2 | A fresh authentication context for every unlock; no reuse of an earlier device unlock. | Review D4 | AUTH-2 | S3 |
| HD29 | P2 | Passcode Only explained in its own words. | Review D4 | PRIVACY-3 | S3 |
| HD30 | P2 | Temporary export copies in class Complete, removed when the share ends. | Spec item 3 | STORAGE-2 | S2 |
| HD31 | P2 | File sharing, open-in-place and document browser keys off; no File Provider; checked in the built app. | Spec item 4 | PLATFORM-1 | S2 |
| HD32 | P2 | No intent, entity query or Spotlight item returns a capture. | Spec item 2 | PLATFORM-1 | S1 (with #82) |
| HD33 | P3 | **A written threat model for the store**, in `docs/SECURITY_AUDIT.md`: section 1.2's table, kept current, with what is out of scope. | New | PRIVACY-3 | S6 |
| HD34 | P3 | **Device-level guidance in `docs/PRIVACY.md`**, sourced from Apple's pages when written. Scope is decision 9. | Review C3, B3 in part; New items in decision 9 | PRIVACY-3 | S6 |
| HD35 | P3 | **A seam for issue 84.** Whether the manifest reserves a versioned per-file field so encryption can be added later without rewriting originals. Decision 2. | New | CRYPTO-2 | S1 |
| HD36 | P3 | **Enrollment check kept, not claimed.** The `stateHash` comparison stays as specified; no sentence presents it as protection (FC5). | Spec; the wording limit is New | AUTH-2 | S3, S6 |
| HD37 | P3 | **No "secure delete", overwrite or shred feature**, and no wording that suggests one (FC10; NIST). | Spec ("no claim about recovery"); the rule against the feature is New | PRIVACY-3 | S5, S6 |
| HD38 | P3 | **The security test plan in section 5** becomes part of the 1.2.0 audit. Whether it gates the release is decision 10. | New | all | S6 |

### What belongs in issue 84, not in issue 83

- Any key that protects capture data: per-file or per-store encryption with CryptoKit, a keychain item with an access control (`.userPresence`, `.biometryCurrentSet`, `.devicePasscode`), "this device only" key storage, and the consequences that follow (no restore to a new phone; loss if the passcode is removed, because "when passcode set" items are discarded [A2]).
- Cryptographic binding of Lock Captures (MASTG's best practice for FC2). It is meaningful only with those keys.
- Any statement that a copy of the app's files cannot be read without the unlock.

What issue 83 can do for issue 84 without building it: the single write path (HD1) is where encryption would later sit; the manifest's version field and HD35 decide whether originals would need rewriting; the delete ordering (HD4) is the same either way.

## 5. New device and security checks

These add to the review's fourteen device checks and to R4. Free, open-source or Apple tools only, as in `docs/SECURITY_AUDIT.md`. A check that cannot be run ends as "not claimed". Checks marked **Static** need no build and can run in `repo-checks`; **Test** runs in CI on the Simulator; **Device** needs the test phone when it is free.

| ID | Kind | Check | Guards |
|---|---|---|---|
| SC1 | Device | **Protection class of every file, read on the phone.** A debug-only screen (not in Release) lists each file under the app's container, the App Group and the session folder with its protection class and backup flag, after: a capture unlocked, a capture from the Lock Screen and its hand-off, a burst with the side button pressed, an export, a canceled export, "Share Without Optional Details", a delete, an app update, and a restore. Pass: every store file and intermediate is class Complete (or Complete Unless Open only while awaiting the raise); nothing capture-related has the default class. | FC6, HD1, HD3; MASTG-TEST-0299 |
| SC2 | Device | **Backup self-check with open tools.** Make an unencrypted and an encrypted computer backup with libimobiledevice [T1], with Leave Out of Backups off and on. Search the backup's file list and contents for the app's domain, image signatures (TIFF/DNG, HEIF, JPEG), thumbnails, the manifest, the app-switcher snapshots and saved state. Record what is present in each case. | FC8, review B1 to B3; MASTG-TEST-0058, 0215 |
| SC3 | Test | **Lock state machine under adversarial sequences.** Model-based tests drive the lock with every event in every order: prompt canceled then retried, two prompts requested, result arriving after re-lock, a route arriving during a prompt, a new scene created while unlocked, background and foreground inside and outside the delay, the clock stepping, protected data becoming unavailable. Pass: no sequence reaches an unlocked read without a success after the last lock event. UI test: every route the issue lists, plus cold launch into a restored route. | FC3, HD2; MASTG-TEST-0064, 0267 |
| SC4 | Device | **What the prompt accepts.** With Stolen Device Protection off and on, at and away from a familiar place if that can be arranged: what the app's prompt accepts with the default policy and with Passcode Only; after five failed Face ID matches; after the power-off screen is shown and canceled. | FC4; wording of the Lock Captures footer |
| SC5 | Static | **Banned APIs in the app's code.** Fail on: general pasteboard use; drag sources and transferable file representations of captures; Quick Look preview and thumbnail generation; SQLite and Core Data in the storage module; scene storage keyed by a capture; user activities without the three eligibility flags off; any file write in the storage and export modules outside HD1's function. Each rule gets a passing and a failing case in `scripts/test-check-security.sh`, as AGENTS.md requires. | FC9, FC15, FC20, FC21, HD1, HD5, HD6, HD13 |
| SC6 | Static and Test | **Diagnostics free of paths.** Static: no interpolation in `fatalError`, `precondition` or `assert` messages in the storage, export and lock code. Test: every store error surfaced to a view or log is one of the app's constant messages. | FC18, HD12; MASTG-TEST-0297 |
| SC7 | Test | **Delete cannot resurrect.** With the file-system fake failing at each step of a delete in turn, and with a simulated crash between steps, relaunch and rebuild: the deleted capture is never listed, never offered as recoverable, and its files are gone once the store is next available. Same for Delete All with a save in flight (review E4). | FC10, HD4 |
| SC8 | Device | **Container and group scan after each flow.** Extends the issue's item 3 scan to the whole downloaded container and the App Group: after capture, library browsing, viewing, each export route, a canceled share, "Share Without Optional Details", delete and Delete All, list every file and search for image signatures outside the store. Includes `Library/Caches`, `tmp`, `Library/SplashBoard`, saved state and any system-created folder. | FC9, FC19; MASTG-TEST-0052, 0302 |
| SC9 | Device | **System-held locations that can be inspected.** On a stock phone only three views exist: the downloaded container, a backup, and a diagnostics archive (sysdiagnose). For each, after the flows in SC8: search for capture file names, thumbnails and paths, using open parsers where they exist [T2]. State in the report that system stores outside these views (the notification store, usage records, system thumbnail caches) cannot be inspected on a stock phone and are **not claimed**. | FC9, FC17, FC18 |
| SC10 | Device | **Scene capture signal.** Does `isSceneCaptured` become true, and promptly, during: Control Center screen recording, AirPlay mirroring, a wired display, iPhone Mirroring, a screen-sharing call. Is one frame of a capture visible in a recording that starts while the viewer is open. Does the cover interfere with VoiceOver or Switch Control. | FC16, HD11; decision 4 |
| SC11 | Test | **Manifest allowlist.** HD8's test. | FC12, review E5 |
| SC12 | Test | **Clean-copy differential check.** For each format and each fixture: the clean copy's tag set from the app's reader equals the allowlist; ExifTool's full dump (`-a -G1 -u`, as `docs/research/privacy-claims.md` prescribes) shows nothing else; the image data is byte-identical to the original's; the file has no bytes outside accounted structures; no auxiliary or embedded image is present that the allowlist does not name. | FC11, HD7; review F6 |
| SC13 | Test | **Fuzz the rewrite, not only the reader.** Mutated and truncated inputs to the clean-copy writer, including the store's own fixtures with damaged headers: the writer either produces a file that passes SC12 or refuses. It never crashes, never writes outside its output file, and never emits input bytes it did not account for. A sentinel-bytes test plants a marker in every removable structure of a fixture and asserts the marker is absent from the output. | FC11, HD7; issue items 8, 9 |
| SC14 | Test | **Export names.** Over many exports of the same captures: no name repeats, no name contains a counter, date, time, the store's internal name, or anything that orders the files; names differ between two exports of one capture. | FC14, HD9 |
| SC15 | Test | **Memory release at re-lock.** After the lock engages, the lock model, library model and viewer hold no image, thumbnail or details object (checked through the models' own state; the Instruments pass of audit check 15 is repeated on a device with the store in use). | FC27, HD16; MASTG-TEST-0060 |
| SC16 | Static | **Dependencies unchanged.** `Package.resolved` and `security/allowed-dependencies.txt` at the end of each S group equal those at its start. | FC25, HD15; MASTG-TEST-0273 |
| SC17 | Device | **MASTG pass on the release candidate.** Run the iOS tests named in section 3.2's table against the archive and the test phone, recording each as pass, fail or not applicable in the audit report, with OWASP's beta status noted where it applies. | section 3.2 |
| SC18 | Device | **Keyboard and text.** Confirm the built library, viewer, export and lock screens contain no text field; if one exists, HD14's review has not happened. | FC22, HD14 |

What these checks cannot show, and the report must say so: the contents of system stores outside the container; behavior on iOS versions and devices not tested; anything about a jailbroken phone; anything about commercial forensic tools.

## 6. Residual risks and wording limits

### 6.1 Risks that remain after everything above

1. Anyone with the device passcode reaches every capture, in the app or through a backup (T2, T6, T7).
2. A phone taken while unlocked and in the library, before a re-lock (T5).
3. A locked phone whose passcode is short enough to be found, or a tool that defeats the lock itself (T3, T4). The app adds nothing beyond iOS here.
4. Code running inside the app or a modified system (T10).
5. Copies that left the app, and records the route or the recipient keeps (FC15).
6. The sensor pattern in the pixels (FC13).
7. System records that the app and camera were used, how much storage the app holds, and that it is installed (FC9, review E6).
8. Deleted data that the storage hardware or a system snapshot still holds, and earlier backups (FC10).
9. Screenshots, and a camera pointed at the screen (FC16).
10. Loss: the app deleted, the phone lost, with captures left out of backups (review D5).
11. Platform behavior this project has not checked on a given iOS version.

### 6.2 What must never be promised

The store claim table, the Honesty screen, `docs/PRIVACY.md`, the site and every string follow these. Each line is a claim the evidence above does not support.

- **Never "encrypted", "encrypted vault", "secure vault", "military-grade", or "protected by Face ID"** for the store or for Lock Captures. The files are protected by iOS and the device passcode; the lock controls viewing in the app. Nothing more is said until issue 84 ships and is verified.
- **Never "secure", "safe", "private" or "protected" without the object and the limit** in the same sentence (protected from what, by what).
- **Never "cannot be accessed", "nobody can see", "even if your phone is seized", "forensic-proof", or anything about police, courts, borders or named tools.**
- **Never "permanently deleted", "securely deleted", "erased", "wiped", "unrecoverable" or "gone"** for Delete or Delete All. "Deleted from the app. It can't be undone." is the ceiling (review E4).
- **Never "not in backups" or "never leaves this iPhone".** Leave Out of Backups is a request to iOS, and only the backup kinds a device check confirmed are named (review B2).
- **Never "anonymous", "untraceable", "unlinkable" or "clean"** for a shared file (review F2; owner decision 8 of 2026-11-21).
- **Never "blocks screenshots" or "blocks screen recording".** At most: the app covers captures while it is told the screen is being recorded or mirrored, if HD11 ships and SC10 passed.
- **Never "hidden", "disguised", "stealth" or "decoy".** The app cannot hide that it is installed or that it holds captures.
- **Never a claim about jailbroken or modified phones**, in either direction.
- **Never "detects new faces or fingerprints" as a protection** (FC5).
- **Never "audited" or "independently reviewed"** unless an independent review exists and is linked. "The project runs the audit itself" is the accurate sentence today (`docs/SECURITY_AUDIT.md`).
- **Never "meets OWASP MASVS" or "NIST-compliant".** The audit *maps* its checks to MASVS controls; that is all that may be said.
- **Uncertain platform behavior is a device check, not a sentence.** Stolen Device Protection, iPhone Mirroring, Lockdown Mode and "Require Face ID" are described only as Apple's pages describe them, or as a recorded check found them, with the iOS version.

## 7. Owner decisions

Each lists its options with the recommendation first and one line of reason. None is decided here.

1. **Whether Lock Captures is bound to a keychain item in 1.2.0 (FC2).** (a) **Recommended:** no; the lock stays a gate as specified, the issue keeps "no Keychain items", and cryptographic binding arrives with issue 84 where it protects a key that encrypts the files. (b) Add a keychain item with an access control, used only to prove the unlock, as defense in depth. (c) Bring issue 84's "encryption tied to the lock" into 1.2.0. *Reason: without encryption, binding stops one instrumentation technique on a phone where the same attacker can already read the files, and it adds a keychain item whose presence after the app is deleted is not documented by Apple.*
2. **What 1.2.0 does to prepare for issue 84 (HD35).** (a) **Recommended:** issue 84 stays on hold; the 1.2.0 manifest reserves a versioned per-file field and the store keeps the single write path, so encryption could be added later without rewriting originals. (b) No preparation; issue 84 designs its own migration when it is scheduled. (c) Schedule issue 84's local encryption for the release after 1.2.0 now. *Reason: the seam costs little and commits to nothing; what encryption would add over iOS's own is mainly for copies in backups, at the price of captures that cannot be restored or that are lost with the passcode.*
3. **A biometrics-only choice for Lock Captures (FC4).** (a) **Recommended:** not in 1.2.0; the page says that anyone with the passcode can open captures and points to the system's Stolen Device Protection and "Require Face ID", described as Apple describes them. (b) Add a "Face ID Only" choice beside Passcode Only, with its lockout explained. (c) No change and no pointer. *Reason: the system already offers this behavior for a whole app; a biometrics-only lock on the only copy of a capture can lock the owner out.*
4. **Captures while the screen is being recorded, mirrored or remotely controlled (FC16, HD11).** (a) **Recommended:** with Lock Captures on, cover the library and viewer and show a neutral notice, if SC10 shows the signal is prompt and the cover does not harm assistive use. (b) Show the notice only. (c) Do nothing and keep the stated limit. *Reason: Apple provides the signal for this purpose and advises applying it selectively; tying it to Lock Captures leaves ordinary use unchanged.*
5. **Jailbreak or tampering detection (FC26).** (a) **Recommended:** none; `docs/SECURITY_AUDIT.md`, check 20, stays as written and the limit is stated. (b) An advisory notice with no change in behavior. (c) Refuse to open the store when a check trips. *Reason: in an open-source app the checks are public and removable, they misfire on ordinary phones, and their result cannot be verified, so any sentence about them would be a claim the project cannot support.*
6. **A decoy, hidden library or duress feature.** (a) **Recommended:** none: no decoy passcode, no second library, no disguised icon or name, no automatic deletion on failed attempts. (b) Record it as a research note for a later release, with no commitment. (c) Design one. *Reason: the app cannot hide its storage size, system records or backups, a comparable app states that camouflage is not possible on iOS, and a feature that looks deniable but is not gives a false sense of safety to the people least able to afford it; it would also be a hidden feature in an app whose rule is honesty.*
7. **The app-wide default protection class entitlement (FC6).** (a) **Recommended:** decide after R4: add `com.apple.developer.default-data-protection` with the Complete value only if a device check shows the app, its controls, the watch remote and the Lock Screen camera still work when started while the phone is locked; explicit per-file classes remain the primary control either way. (b) Do not add it; rely on HD1 and HD19. (c) Add it now. *Reason: it would catch files a system framework creates on the app's behalf, but it changes an entitlement allowlist and may break starts while locked (review C1), which only a device can show.*
8. **A delete that was interrupted (FC10, HD4).** (a) **Recommended:** a delete records the capture as deleted before removing anything; a leftover file recorded as deleted is removed at the next unlocked launch and never shown; a leftover file *not* recorded as deleted is listed as recoverable, as review G2 proposes. (b) Never remove a file automatically (review C1 as written); an interrupted delete shows the capture again, and the library says the delete did not finish. (c) Remove every unmatched file automatically. *Reason: (a) keeps the review's protection against losing captures while making sure a capture the person deleted cannot come back; it is a behavior promise, so it is the owner's.*
9. **Device-level guidance in `docs/PRIVACY.md` (FC7, HD34).** (a) **Recommended:** a short section for high-risk use, each line taken from an Apple support page when written: a longer passcode, a short Auto-Lock, turning biometrics off from the side buttons, restarting the phone before a foreseeable seizure, Erase Data, encrypted computer backups, Advanced Data Protection, Lockdown Mode, Stolen Device Protection. (b) Link to Apple's safety guide and to an independent guide, and write none of it here. (c) Only the items the review already lists (C3, B3). *Reason: most of the protection in section 1 comes from the phone, not the app, and the people this is for need to be told so in one place; the cost is text that must be kept current.*
10. **Whether the security checks gate the 1.2.0 release (HD38).** (a) **Recommended:** SC1, SC2, SC3, SC7, SC8 and SC12 are release gates recorded in the audit report with device and iOS version; the rest are run and recorded, and a failure is ranked by the audit's existing rules. (b) All eighteen gate the release. (c) All are best effort. *Reason: the six named checks cover the routes to a capture or to its reappearance; gating on all eighteen ties the release to checks that depend on hardware and system features that may not be available.*

## Sources

Read or searched for this page on 2026-11-21. Publication dates are as shown by each source. "Search summary" means the page was located and summarized through a web search and not read in full; such sources support only the general statement they are cited for.

**Apple**

- [A1] Apple Platform Security, "Data Protection classes", published 2024-12-19: https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web
- [A2] Apple Platform Security, "Keychain data protection", published 2024-12-19: https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web
- [A3] Apple Platform Security, "Passcodes and passwords", published 2024-12-19: https://support.apple.com/guide/security/passcodes-and-passwords-sec20230a10d/web
- [A4] Apple Platform Security, "Face ID, Touch ID, passcodes, and passwords", published 2024-12-19: https://support.apple.com/guide/security/face-id-touch-id-passcodes-and-passwords-sec9479035f1/web
- [A5] Apple Platform Security, "Data Protection overview", published 2026-08-03: https://support.apple.com/guide/security/data-protection-overview-secf6276da8a/web
- [A6] "About Stolen Device Protection for iPhone", published 2026-10-22: https://support.apple.com/en-us/120340
- [A7] "Use locked apps with Stolen Device Protection" (search summary): https://support.apple.com/125690
- [A8] "iPhone Mirroring: Use your iPhone from your Mac", published 2026-10-14: https://support.apple.com/en-us/120421
- [A9] "Protecting sensitive content when screen sharing and remote control are active" (SwiftUI documentation, copyright 2026): https://developer.apple.com/documentation/swiftui/protecting-sensitive-content-when-screen-sharing
- [A10] Apple Platform Security, "Supporting extensions" (search summary): https://support.apple.com/guide/security/supporting-extensions-secabd3504cd/web
- [A11] `application(_:shouldAllowExtensionPointIdentifier:)` (search summary): https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:shouldallowextensionpointidentifier:)
- [A12] Apple Platform Security, "Advanced Data Protection for iCloud" (search summary): https://support.apple.com/guide/security/sec973254c5f
- The review's Apple sources (LockedCameraCapture, `isExcludedFromBackup`, iCloud Backup, keybags, Lockdown Mode, `LAPolicy`, `UIActivity.ActivityType`) are listed in `docs/research/83-blind-spots.md`, "Sources".

**OWASP**

- [O1] OWASP MASVS v2, control list: https://mas.owasp.org/MASVS/
- [O2] OWASP MASTG, test index (iOS tests named by ID in this page; several marked beta by OWASP): https://mas.owasp.org/MASTG/tests/
- [O3] OWASP MASWE-0044, "Biometric Authentication Can Be Bypassed", and MASWE-0045, "Fallback to Non-biometric Credentials Allowed for Sensitive Transactions" (search summary; beta): https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0044/ and https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0045/
- [O4] objection wiki, "Understanding the iOS Biometrics Bypass", last edited 2019-11-06: https://github.com/sensepost/objection/wiki/Understanding-the-iOS-Biometrics-Bypass

**NIST**

- [N1] NIST SP 800-63B-4, "Digital Identity Guidelines: Authentication and Authenticator Management", July 2025, section 3.2.3: https://pages.nist.gov/800-63-4/sp800-63b.html
- [N2] NIST SP 800-88 Rev. 2, "Guidelines for Media Sanitization", 2025-09-26 (search summary): https://csrc.nist.gov/pubs/sp/800/88/r2/final

**Incidents and studies**

- [I1] M. Allen, "Breaking into and Reverse Engineering iOS Photo Vaults", IOActive, 2015-11-19: https://ioactive.com/breaking-into-and-reverse-engineering/
- [I2] X. Zhang, I. Baggili, F. Breitinger, "Breaking into the vault: Privacy, security and forensic analysis of Android vault applications", Computers & Security, 2017 (search summary): https://serval.unil.ch/notice/serval:BIB_80F8762F548E
- [I3] Gilbert and Seigfried-Spellar, forensic comparison of five iOS photo vault apps, Journal of Digital Forensics, Security and Law, 2022 (search summary): https://core.ac.uk/download/519805626.pdf
- [I4] DoD Cyber Crime Center advisory on photo vault apps, 2020 (search summary): https://content.govdelivery.com/accounts/USDODDC3/bulletins/2e03b69
- [I5] "WhatsApp security bug lets anyone bypass Face ID and Touch ID", 9to5Mac, 2019-02-21: https://9to5mac.com/2019/02/21/whatsapp-security-vulnerability/ ; SecurityWeek, same week: https://www.securityweek.com/bug-allows-bypass-whatsapp-face-id-touch-id-protection/ (search summaries)
- [I6] CVE-2018-9840 (search summary): https://nvd.nist.gov/vuln/detail/CVE-2018-9840
- [I7] "iOS 26.4.2 Patches Flaw That Let FBI Extract Deleted Signal Messages", MacRumors, 2026-04-22: https://macrumors.com/2026/04/22/ios-26-4-2-notification-database-security-fix ; Privacy Guides, 2026-04-23: https://www.privacyguides.org/news/2026/04/23/apple-releases-patch-for-the-signal-notification-issue-that-allowed-recovery-of-deleted-messages/ (search summaries)
- [I8] "Apple Releases iOS 17.5.1 With Fix for Reappearing Photos Bug", MacRumors, 2024-05-20: https://www.macrumors.com/2024/05/20/apple-releases-ios-17-5-1-photos-bug/ ; TidBITS, 2024-05-20: https://tidbits.com/2024/05/20/ios-17-5-1-and-ipados-17-5-1-fix-photo-reappearance-bug (search summaries)
- [I9] CVE-2023-21036: The Register, 2023-03-20: https://www.theregister.com/2023/03/20/google_pixel_acropalypse/ ; Cloudflare: https://blog.cloudflare.com/how-cloudflare-images-addressed-the-acropalypse-vulnerability (search summaries)
- [I10] M. Green, "Attack of the week: Airdrop tracing", 2024-01-11: https://blog.cryptographyengineering.com/2024/01/11/attack-of-the-week-airdrop-tracing/ ; MacRumors, 2024-01-09: https://www.macrumors.com/2024/01/09/airdrop-cracked-chinese-authorities/ (search summaries; the originating claim was not independently verified)

**Forensics (public reporting; none of it verified by this project)**

- [F1] "Leaked Docs Show What Phones Cellebrite Can (and Can't) Unlock", 404 Media, July 2024: https://www.404media.co/leaked-docs-show-what-phones-cellebrite-can-and-cant-unlock/ ; 9to5Mac, 2024-07-18: https://9to5mac.com/2024/07/18/cellebrite-cant-unlock-many-iphones (search summaries)
- [F2] "Leaked Document Suggests Cellebrite Can Wirelessly Exploit iPhones", Privacy Guides, 2026-10-19 (the article itself says the document is unconfirmed): https://www.privacyguides.org/news/2026/10/19/leaked-document-suggests-cellebrite-can-wirelessly-exploit-iphones/
- [F3] "BFU Extraction: Forensic Analysis of Locked and Disabled iPhones", Elcomsoft, December 2019 (search summary): https://blog.elcomsoft.com/2019/12/bfu-extraction-forensic-analysis-of-locked-and-disabled-iphones/
- [F4] J. Classen, "Reverse Engineering iOS 18 Inactivity Reboot", November 2024: https://naehrdine.blogspot.com/2024/11/reverse-engineering-ios-18-inactivity.html ; TechCrunch, 2024-11-14: https://techcrunch.com/2024/11/14/new-apple-security-feature-reboots-iphones-after-3-days-researchers-confirm (search summaries)
- [F5] SANS, "FOR518 Mac and iOS Forensic Analysis poster update" (knowledgeC and Biome) (search summary): https://www.sans.org/blog/new-for518-mac-and-ios-forensic-analysis-poster-update

**Metadata and provenance**

- [M1] C2PA, "Harms Modelling", specification 2.2 (search summary): https://spec.c2pa.org/specifications/specifications/2.2/security/Harms_Modelling.html
- [M2] K. Kaye, P. Dixon, "Privacy, Identity and Trust in C2PA", World Privacy Forum, September 2025 (search summary): https://worldprivacyforum.org/posts/privacy-identity-and-trust-in-c2pa
- The sensor pattern: `docs/research/privacy-claims.md`, claim 9, with its peer-reviewed sources.

**Reference designs and guidance**

- [R1] Signal Support, "Screen Lock" and "Screen Security" (search summary): https://support.signal.org/hc/en-us/articles/360007059572 and https://support.signal.org/hc/en-us/articles/360043469312-Screen-Security
- [R2] Tella, "Security and privacy" (read 2026-11-21) and FAQ (search summary): https://tella.app/security-and-privacy
- [R3] Guardian Project and WITNESS, ProofMode (search summary): https://gitlab.com/guardianproject/proofmode
- [G1] Electronic Frontier Foundation, Surveillance Self-Defense, "Attending a Protest", last reviewed 2026-06-26: https://ssd.eff.org/module/attending-protest

**Other**

- [S1] SQLite, "PRAGMA statements" (`secure_delete`, `journal_mode`, `auto_vacuum`): https://www.sqlite.org/pragma.html
- [T1] libimobiledevice (open-source tools for device backups): https://libimobiledevice.org
- [T2] iLEAPP (open-source parser for iOS backups and diagnostics archives): https://github.com/abrignoni/iLEAPP

In this repository: issue 83 and its comments; `docs/research/83-blind-spots.md`; `docs/plans/1.1.0.md` (groups S1 to S6, R4); AGENTS.md; `docs/PRIVACY.md`; `docs/SECURITY_AUDIT.md` (threat model; checks 1, 11, 13, 15, 20; MASVS coverage); `SECURITY.md`; `security/allowed-entitlements.txt`; issue 84.

## Addendum (2026-11-21): a hostile or compelled app update

Added at the owner's request.

- **Threat.** The app's publishing accounts are taken over, or the maintainer is compelled, and an update is published that collects a person's captures. Once installed and opened, the update runs with everything the app can reach: captures kept in the app (while the phone is unlocked, and through Lock Captures, which the app itself controls), Photos if full access was granted, settings and signing material, and it could add networking that the app does not have today.
- **What limits it.** It must be installed and opened; App Review applies; iOS permissions still gate Photos and other apps' data; changes to an open-source app are visible in the repository, though the App Store build cannot be checked against the source byte for byte (no reproducible builds on iOS); a network connection would also require a changed privacy label.
- **What the project does.**
  - Accounts: protect the Apple developer account and GitHub with passkeys or hardware security keys, and give App Store Connect access only to the people who need it, each with the narrowest role.
  - Releases: only the maintainer submits builds; each release has a public tag, changelog and source.
  - Networking is never added without a public, reviewable change and an updated privacy label.
- **What users are told.** In the limits text (design 1.2, section 7) and docs/PRIVACY.md's high-risk section: the app cannot protect against an update from its own publisher; for high-risk use, turn off automatic updates and read each release's notes before updating.
- **Never claimed.** That the app protects against its maker, or that the App Store build is verified to match the source.
- **Severity.** High impact, low likelihood. It is a residual risk shared by every installed app; no build group can remove it.


## Owner decisions (2026-11-21)

All ten decisions in this document were answered with the recommended option, with one change made afterwards by the owner:

- **No app-level encryption.** The project does not implement its own encryption of captures. It relies on iOS Data Protection on the device, and suggests Apple's Advanced Data Protection for iCloud backups. Issue #84 is closed as not planned. Decision 2's reserved per-file field (HD35) is dropped: 1.2.0 adds no encryption seam. Decision 1 stands without its reference to #84: Lock Captures is a gate, not encryption, and is not bound to a keychain item.
