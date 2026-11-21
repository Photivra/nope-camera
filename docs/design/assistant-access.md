# Assistant Access

Design version: 1.0.0, direction B · Reach. Proposed 2026-11-18 for issue 82, which moved into release 1.0.0. **Accepted for 1.0.0 on 2026-11-18**, with all twenty decisions of section 19 as recommended; built in the same release (the new actions of 7.2 are not built in this change: decision 13). Not yet in the screen counts of [README.md](README.md). The drawings are in [assistant-access.html](assistant-access.html); each figure named below is `screens/<name>.html` with a PNG beside it. Every sentence of interface text here is a draft until the Honesty review. Nothing here was run on a device: section 14 lists what must be confirmed before it is built on or claimed (`AGENTS.md`, "Evidence-based").

Photivra Nope Camera already has Siri and Shortcuts actions. This design puts one setting in front of all of them, so a person decides whether Siri, Shortcuts and other assistants on the device may use the app, and whether the app asks first. It also fixes what an assistant can ever learn from the app: one sentence about what happened, never a photo, a location or a photo's details.

Contents: 1. What the code does today · 2. Principles · 3. The setting · 4. The check · 5. Asking first · 6. In the background or locked · 7. Actions · 8. What an assistant can and cannot read · 9. Assistant schemas and Apple Intelligence · 10. Indicators and records · 11. Finding the setting · 12. Devices · 13. Accessibility and Night Mode · 14. Assumptions and device checks · 15. The wording · 16. Alignment with issue 83 · 17. Tests · 18. When this is accepted · 19. Decisions for the owner

## 1. What the code does today

Read in the code on 2026-11-18 (branch `fix-review-100`).

| Fact | Where |
| --- | --- |
| Fourteen actions are offered to Siri and Shortcuts: Take Photo, Take Bracket, Open the Camera, Switch Lens, Turn On the Light, Turn Off the Light, Start Interval Shooting, Stop Interval Shooting, Set Night Mode, Set Focus Range, Set Photo Size, Set Fast Shutter, Set Focus on Faces, Apply Preset. Ten have a Siri phrase (the system's limit) | `App/NopeApp/Intents/`, `App/Shared/OpenCameraIntent.swift`, `NopeShortcuts.swift` |
| Two more intents are not listed in Shortcuts (`isDiscoverable = false`): the Control Center Night Mode toggle and the Live Activity's Stop button | `App/NopeControls/NightModeControl.swift`, `App/Shared/SeriesActivity.swift` |
| No action checks any setting before it runs. Each one runs for any caller | every `perform()` |
| Actions that need the camera open the app first (`openAppWhenRun = true`), hand a request to the camera screen and wait up to 10 seconds for it | `TakePhotoIntent`, `ShortcutInbox.startTimeoutSeconds` |
| An action answers with one sentence. No action returns a file, a thumbnail or metadata | `ShortcutDialog`, `ShortcutOutcome` |
| Apply Preset offers the saved presets by name, so the names a person typed are visible to Shortcuts and Siri | `PresetEntity`, `PresetQuery` |
| A preset stores privacy settings too (Details in Each Photo, Sign Each Photo), so Apply Preset can change them | `SettingsPresets.swift`; SETTINGS-PLAN.md 1.2 |
| The Apple Watch app sends commands over WatchConnectivity. It has no App Intents | `App/NopeWatch/`, `WatchCommandServer.swift` |
| The app declares no URL scheme, indexes nothing for system search, donates no activity and describes no on-screen content to the system | `App/NopeApp-Info.plist`; no `NSUserActivity`, Core Spotlight or donation call in `App/` or `Sources/` |
| Open the Camera is a `CameraCaptureIntent` with an empty `perform()`; the system opens the app, or the Lock Screen camera on a locked phone | `OpenCameraIntent.swift` |

## 2. Principles

1. **Off until the person turns it on.** A fresh install refuses every assistant request.
2. **One check, in one place, at run time.** Every action asks the same check inside `perform()`. An action the system already lists cannot skip it.
3. **Ask by default.** When access is on, each action is named and confirmed before it runs, unless the person chose otherwise.
4. **Status out, nothing else.** An assistant gets a sentence about what happened. It never gets a photo, a thumbnail, a file, a location, a photo's details or a count of what was taken earlier.
5. **Privacy settings are changed by hand only.** No assistant action changes a setting of the Privacy group, including this one.
6. **The app says what it did.** An action that ran through an assistant is shown on the camera, and a refused one is shown the next time the camera is on screen.
7. **Claims stop where the app's control stops.** The setting covers the app's own actions. What iOS, Siri or other apps do outside the app is stated as outside it.
8. **Q does not change.** Q's tiles stay fixed and button-opened, with no editing in place. No assistant action opens Q, edits it or reorders it, and Assistant Access gets no tile.

## 3. The setting

### 3.1 Place and name

Settings › Privacy › **Assistant Access**, a row that opens a page, after Sign Each Photo. This is the place SETTINGS-PLAN.md reserved (section 3, Privacy). In 1.1.0, Save Photos To and Lock Captures arrive above it, and it stays last in the group, as planned.

The row (figure `assistant-root`):

- Title: Assistant Access.
- Value: Off, Ask Every Action, Ask Before a Photo, or Never Ask.
- Note, under the title and value, always the same: "For Siri, Shortcuts and other assistants." This is the note pattern of [SETTING-SCOPE.md](SETTING-SCOPE.md), section 6: plain secondary text, no symbol, no color.

The name stays Assistant Access (issue 82; SETTINGS-PLAN.md). "Siri and Shortcuts" as a name would leave out other assistants that reach the same actions; the note names all three.

Search keywords, not shown on screen: siri, shortcuts, assistant, voice, automation, AI, intelligence, ask, confirm.

### 3.2 The page

Figures `assistant-page-off` (the default), `assistant-page-on`, `assistant-page-light`, `assistant-page-night`, `assistant-page-rtl`, `assistant-page-largest`. One page, one level deep, in this order:

1. **While access is off, one line at the top**, with the information symbol: "Assistant Access is off, so Ask First is not used now." The same manner as Fast Shutter and HEIF and JPEG Copies.
2. **Assistant Access** (switch), with its explanation.
3. **Ask First**: Every Action, Only Before a Photo, Never. One is selected (a checkmark). Each has its sentence under its name. The three choices are always shown and always enabled: the choice is stored while access is off and used when it is turned on. No row appears or disappears when the switch changes (decision 3).
4. **What Assistants Get**: three short paragraphs, as rows, so they follow the text size.
5. **This Session**: the requests since the app opened (section 10), or "No requests since nope. opened."

Defaults, for fresh installs and for people updating from an earlier build: Assistant Access **off**, Ask First **Every Action**. Issue 82's text of 2026-11-17 says on; this follows the later decision and the issue text needs the same change (decision 1).

### 3.3 What the two controls do

| Assistant Access | Ask First | A request to change something | A request that takes photos |
| --- | --- | --- | --- |
| Off | (any) | Refused. Nothing changes | Refused. No photo |
| On | Every Action | Asks, then runs | Asks, then runs |
| On | Only Before a Photo | Runs | Asks, then runs |
| On | Never | Runs | Runs |

"Takes photos" means Take Photo, Take Bracket and Start Interval Shooting (and Start Astro if it is added). Everything else is a change. Open the Camera and Open Assistant Access only open a screen and are not gated (section 7.3).

### 3.4 What the setting does not cover

Said on the page, because the row's note cannot hold it:

- The shutter button, the volume buttons, Camera Control and a headphone remote's buttons. A person presses these.
- The Apple Watch app, the Control Center controls ("Open nope.", Night Mode) and the Live Activity's Stop button. A person presses these too (decision 6).
- VoiceOver, Voice Control, Switch Control and Full Keyboard Access. They operate the app's own controls and are never refused.
- Anything outside the app: the system camera, other apps' camera or Photos access, screenshots, and what a person lets Siri or another assistant see or do on the screen.

### 3.5 Storage

- Two values in `NopeSettings`: `assistantAccess` (Bool, default false) and `assistantAsk` (every action, before a photo, never; default every action).
- Not stored in presets; applying a preset never changes them. The same rule issue 83 sets for Save Photos To and Lock Captures.
- Factory Defaults, applied in the app, returns both to their defaults. Factory Defaults applied through an assistant leaves both as they are (principle 5).
- A saved choice is kept on update.
- No action, control or link changes either value. They change on this page only.

## 4. The check

One type in `NopeCore`, used by every entry point, so the rules are not in the intents (`AGENTS.md`, "Siri and Shortcuts"):

```swift
/// What an entry point is, for the Assistant Access check.
public enum AssistantActionKind { case takesPhotos, changes, opensScreen, pressedByPerson }

/// What the check decided.
public enum AssistantDecision { case refuse, ask, run }

public struct AssistantAccess {
    public func decision(for kind: AssistantActionKind) -> AssistantDecision
}
```

- `.opensScreen` and `.pressedByPerson` always run. They are declared, not skipped, so the entry-point test (section 17) sees every entry point with a kind.
- Each discoverable intent calls one helper in the app target that does, in order: read the decision; refuse with the off answer, or ask (section 5), or go on; record the request for the session (section 10); run the existing code.
- The check is read when `perform()` starts and again after a confirmation returns. If access was turned off while the question was showing, the action is refused.
- Entity queries are behind the same check: with access off, `PresetQuery` returns no saved presets, only Factory Defaults (a fixed name). With access on it returns the names (section 8).
- The app cannot tell which assistant is asking. Siri, the Shortcuts app, an automation, Siri through headphones or a car, and an on-device assistant that uses App Intents all arrive the same way, so one setting covers all of them and no wording names the caller.

## 5. Asking first

### 5.1 What the person sees

Figure `assistant-confirm`. The question is asked by the system, with App Intents' `requestConfirmation`, so it looks and behaves the same in Siri, in Shortcuts and wherever else the action is run:

- **The question**: one whole sentence that names the action and its values. Siri speaks it.
- **One line under it, on screen only**: "You can change this in nope. › Settings › Privacy."
- **Two buttons**: the action's verb (Take Photo, Switch Lens, Apply Preset) and Cancel. Never Yes, OK or Continue alone: the button names what will happen.

The question shows the values the action will run with. They are fixed before the question is shown; a confirmation covers that one run with those values. It is never remembered, there is no "always allow" answer, and each step of a longer shortcut asks for itself.

### 5.2 The questions

| Action | Question (draft) | Button |
| --- | --- | --- |
| Take Photo | Take a photo? | Take Photo |
| Take Photo, with a delay | Take a photo in 10 seconds? | Take Photo |
| Take Photo, with a lens | Take a photo with the telephoto camera? | Take Photo |
| Take Photo, several | Take a burst of 10 photos? | Take Photos |
| Take Bracket | Take a bracket of 3 photos? | Take Bracket |
| Start Interval Shooting | Start interval shooting? A photo every 10 seconds for 5 minutes. | Start |
| Stop Interval Shooting | Stop interval shooting? | Stop |
| Switch Lens | Switch to the telephoto camera? | Switch Lens |
| Turn On the Light | Turn on the light? | Turn On |
| Turn Off the Light | Turn off the light? | Turn Off |
| Set Night Mode | Turn on night mode? / Turn off night mode? | Turn On / Turn Off |
| Set Focus Range | Set the focus range to Close-Up? | Set |
| Set Photo Size | Set the photo size to Largest? | Set |
| Set Fast Shutter | Set Fast Shutter to Freeze Motion (1/500 s)? | Set |
| Set Focus on Faces | Turn on Focus on Faces? / Turn off Focus on Faces? | Turn On / Turn Off |
| Apply Preset | Apply the preset “Street”? Its privacy settings are not applied. | Apply Preset |
| Apply Preset, Factory Defaults | Apply Factory Defaults? Privacy settings stay as they are. | Apply |

Each is a whole sentence with placeholders, formatted by the system (numbers, durations, plurals). None is built from fragments.

### 5.3 After the answer

- **Confirmed.** The action runs as it does today and answers with today's sentence ("Photo saved. It isn't signed."). An action that needs the camera opens the app at this point, not before.
- **Cancelled, or the question was dismissed or timed out.** Nothing changes and the app is not opened. The app adds no answer of its own: the question's error passes to the system, which answers (issue #126, owner decision of 2026-11-21; section 14, check 4).
- **No one there.** An automation that runs unattended cannot answer, so it stops at the question. The page says so. A person who wants unattended automations chooses Never, knowing what that allows.

### 5.4 Timing

| Wait | Length | Who sets it | If it runs out |
| --- | --- | --- | --- |
| Unlocking the phone | The system's | iOS | The action does not start |
| The question | The system's. The app sets no timer and cannot extend it | iOS | Treated as Cancel. Nothing changes |
| After Confirm, for the camera screen and the camera | 10 seconds, as today (`ShortcutInbox.startTimeoutSeconds`) | The app | "The camera isn't available right now." Nothing was taken |
| Behind an earlier request | As today | The app | "nope. is still doing an earlier request. Nothing changed." |
| A self-timer the person asked for | The delay named in the question | The person | Cancel on the camera ends it: "The timer was cancelled. No photo was taken." |

The rule "nothing leaves on a timer" (ACCESSIBILITY.md) is kept for everything the app draws. The question is the system's, and an unanswered question fails safe: nothing happens.

### 5.5 Why the system's question and not one drawn by the app

The system's confirmation is the documented way for an App Intent to ask, it is spoken and operable by voice, and it appears before the app is opened, so a refused or cancelled request never brings the camera up. A card drawn by the app on the camera would be red in Night Mode and fully under the app's control, but it would need the app on screen first and would not be spoken by Siri. It is the fallback if device check 2 fails (section 14).

## 6. In the background or locked

| State when the request arrives | Access off | Access on, asking | Access on, not asking |
| --- | --- | --- | --- |
| The app is on screen | The off answer. Nothing changes | The question; then the action | The action |
| The app is in the background or not running | The off answer. The app is not opened | The question, over whatever is on screen; on Confirm the app opens and the action runs once the camera is ready | The app opens and the action runs once the camera is ready. An action that needs no camera screen (Night Mode, Fast Shutter, Focus on Faces, Turn Off the Light, Stop Interval Shooting) runs without opening the app, as today |
| The phone is locked | The system asks for an unlock first; then as above | The same | The same |
| The Lock Screen camera is open | No assistant action runs there: the capture extension serves no requests. Siri asks for an unlock and the app handles it | The same | The same |
| A photo, countdown or series is running | The off answer | The question; then today's busy answers ("nope. is already taking a photo.") | Today's busy answers |

Rules behind the table:

- **Every gated action requires an unlocked device** (`authenticationPolicy = .requiresAuthentication`). A person holding a locked phone cannot start an action or answer a question for the owner. This includes Turn Off the Light and Stop Interval Shooting; the Live Activity's Stop button still works from the Lock Screen because a person presses it.
- **No photo is taken while the app is not on screen.** The camera runs only while the camera screen is shown (the app has no background mode), so the system's camera indicator is lit whenever a photo can be taken. An assistant request does not change this: it opens the app first.
- **Refusing does not open the app.** With `openAppWhenRun = true`, as today, iOS opens the app before `perform()` runs. The gated actions change to run in the background first and move to the foreground only after the check and the question (iOS 26's `supportedModes` and `continueInForeground`; section 14, check 1).

## 7. Actions

### 7.1 Offered in 1.0.0

The fourteen that exist, thirteen of them behind the check, plus one new action that opens the setting.

| Action | Kind | Siri phrase | Change in 1.0.0 |
| --- | --- | --- | --- |
| Take Photo | Takes photos | Yes | The check; the question |
| Take Bracket | Takes photos | Yes | The same |
| Start Interval Shooting | Takes photos | Yes | The same |
| Stop Interval Shooting | Changes | Yes | The same |
| Switch Lens | Changes | Yes | The same |
| Turn On the Light, Turn Off the Light | Changes | Yes | The same |
| Set Night Mode (On, Off) | Changes | Yes | The same |
| Set Focus Range, Set Photo Size, Set Fast Shutter, Set Focus on Faces | Changes | No | The same |
| Apply Preset | Changes | No | The check; the question; privacy settings are not applied (7.4); preset names are offered only while access is on |
| Open the Camera | Opens a screen | Yes | None. Not gated (7.3) |
| Open Assistant Access (new) | Opens a screen | No | Opens Settings at this page. Changes nothing. Not gated, so the off answer can offer it |

Each gated action's description in the Shortcuts app gains one closing sentence: "Needs Assistant Access, in nope. › Settings › Privacy."

All ten Siri phrase places stay as they are. The system lists the actions and phrases whether access is on or off; the app cannot hide them, so with access off they answer that access is off.

### 7.2 Designed here, built after the check has passed its device checks

Issue 82 asks for actions for the controls that already exist. They are all changes, all behind the same check, and none needs anything else in this document. They can ship in 1.0.0 once 7.1 is confirmed on a device, or in 1.1.0 (decision 13).

| Action | Values | Question (draft) |
| --- | --- | --- |
| Set Shooting Mode | Single, Timer, Burst, Interval, Astro, Bracket. Selects the word on the drive strip; takes no photo | Switch to Astro? |
| Set Manual Controls | On, Off | Turn on Manual Controls? |
| Set Shutter | Auto, or a time the lens offers | Set the shutter to 1/250 s? |
| Set ISO | Auto, or a value the lens offers | Set ISO to 400? |
| Set Focus | Auto, or a position from near to far | Set focus to Auto? |
| Set Formats | RAW, HEIF, JPEG, in the combinations Formats offers | Save RAW and HEIF? |
| Set Astro Frames | Frame count and delay, within Astro Settings' limits | Set Astro to 30 frames, 2 seconds apart? |
| Start Astro | (none) | Start Astro? 30 frames. (Takes photos) |

Lenses, formats and modes are `AppEnum` types, so steps can be chained in the Shortcuts editor. With Every Action each step asks; a person who chains steps will choose Only Before a Photo.

### 7.3 Not gated, and why

- **Open the Camera.** It opens the app and nothing else. The system can open any app for an assistant without the app's help, so refusing here would protect nothing and the page would claim something untrue. The same intent is the "Open nope." control, which a person presses, and on a locked phone it opens the Lock Screen camera.
- **Open Assistant Access.** It must work while access is off.
- **The Control Center Night Mode toggle and the Live Activity's Stop button.** Pressed by a person, not listed in Shortcuts. They are declared `.pressedByPerson` (decision 6).
- **The Apple Watch app.** A person presses its button on their own paired watch. It is a remote shutter like the volume buttons, not an assistant (decision 6).

### 7.4 Never offered

No action, entity, query, link or control exists for any of these, in 1.0.0 or later, unless this document is changed first:

| Never | Why |
| --- | --- |
| Reading a photo, a thumbnail, a preview or a file; "the last photo"; opening the Last Photo viewer or What's in This Photo | Principle 4. Issue 83, decision 5 |
| Reading any detail of a photo: location, time, lens, exposure, format, signature, tags | The same |
| Reading how many photos were taken, or when | It describes what the person did |
| Reading the camera's state on request (a "Get Camera Status" action), or describing what is on screen to the system | Section 8. Decision 8 |
| Changing a Privacy setting: Details in Each Photo, Location, Sign Each Photo, Assistant Access; and in 1.1.0 Save Photos To, Lock Captures, backup exclusion | Principle 5. Issue 83 |
| Applying a preset's privacy settings | The same. Through an assistant, Apply Preset applies everything else in the preset and answers: "“Street” applied, except its privacy settings. You can undo it in Presets." Applied by hand in the app, a preset applies in full, as today (decision 7) |
| Saving, renaming or deleting a preset | A preset's name is the person's text, and a saved preset can carry privacy settings |
| Deleting anything; Delete All Captures in 1.1.0 | Issue 83 |
| Opening, editing or reordering Q; adding a tile | The Q rule (principle 8) |
| Answering the app's permission prompts or first-run choices | The person's decisions |
| A `nope://` link that acts | The app has no URL scheme (`AGENTS.md`, "Prevention first"), and 1.0.0 adds none (decision 10) |

## 8. What an assistant can and cannot read

**Can, with access on:**

1. **The answer to an action it ran**: one sentence from `ShortcutDialog`, for example "Photo saved. It isn't signed.", "Now using the telephoto camera.", "This lens has no light." The sentence can reveal a little about the device and the moment: that a lens exists, that the camera was busy, that a photo was or was not saved and signed.
2. **The names of saved presets**, so Apply Preset can offer them. A name is the person's own text. The page says so.
3. **The fixed lists**: lenses, delays, focus ranges, sizes, Fast Shutter choices. These are the same on every device of a model.

**Can, with access off:** that the app is installed and which actions it declares (the system lists them), the fixed lists above, and the off answer. Nothing else.

**Cannot, in any state:** a photo, thumbnail, preview or file; where or when a photo was taken; any tag or detail of a photo; whether photos were taken earlier, or how many; the Privacy settings' values; the picture in the viewfinder.

How that is kept true:

- No intent's result carries a value besides its sentence, except a plain "Photos Saved" number (0 or the count of this request) for the photo actions, so a shortcut can branch on it (decision 9).
- No `AppEntity` exists for a photo, a file or a session. `PresetEntity` holds an identifier and a name.
- No snippet view shows a picture.
- Nothing is indexed for system search (no Core Spotlight, no `IndexedEntity`), nothing is donated (`IntentDonationManager`, `NSUserActivity`), and no on-screen content is described to the system. The optional search indexing of issue 82 is not part of 1.0.0.
- Logs mark every value private, as today; the request record of section 10 is in memory only.

**What the app does not control,** said on the page and on the Honesty screen: photos saved to Photos are in the Photos library, where the system and any app with Photos access can read them; a screenshot or a screen reading that a person asks an assistant for is the system's; opening the app is the system's.

## 9. Assistant schemas and Apple Intelligence

- **In 1.0.0 the actions stay plain App Intents.** An assistant that can run App Intents reaches them through `perform()`, so it meets the check and the question like any other caller.
- **Camera-domain assistant schemas** (open the camera, set the device, set the mode, start a capture; issue 82) are adopted only if device check 7 confirms, on the iOS versions the app supports, that a schema-conforming intent still runs the app's `perform()`, can ask for confirmation, and requires nothing the app does not offer. This is a go or no-go check, not a promise; until it passes, no schema is adopted and nothing in the app or its store text mentions Apple Intelligence.
- **Never adopted:** any schema of the photos domain or any other schema that represents a photo, an album, a file or a search of them as an entity, and any on-screen content annotation.
- **No wording names an assistant's capabilities.** The page says "Siri, Shortcuts and other assistants"; it does not say which assistant can do what, because that is the system's and changes between iOS versions.

## 10. Indicators and records

Three things show a person what assistants did. None is written to disk.

1. **On the camera, after an action that ran** (figure `assistant-camera-notice`): a hint in the bottom stack with a caption, "Siri or Shortcuts", and under it the same sentence the assistant got ("Now using the telephoto camera."). It stays until the next action on the camera or its Close button, and never leaves on a timer (ACCESSIBILITY.md), so VoiceOver, Switch Control and a slow reader at the largest text size all have as long as they need (owner decision on the third review of 1.0.0). A photo also gets its usual capture feedback. The caption says "Siri or Shortcuts" because the app cannot tell which.
2. **On the camera, after a refusal** (figure `assistant-camera-refused`): the next time the camera is on screen, a card: "Assistant Access is off. nope. refused 2 requests since it opened." with Settings and a close button. It stays until dismissed and is shown once per count; a new refusal brings it back. This is how a person learns that something tried, and how someone whose shortcut stopped working finds the setting.
3. **On the page, This Session** (figure `assistant-page-on`): up to 20 lines, newest first, each an action's name and what happened: Asked, allowed · Asked, cancelled · Ran without asking · Refused. No values, no times, no preset names. Under it: "Kept in memory only. Cleared when nope. closes." With none: "No requests since nope. opened."

Not kept: a log file, a history across launches, counts in the settings store. A lasting record of what a person asked their phone to photograph is itself something left behind, which issue 83 works to reduce. The one stored number is the tip's counter (section 11), which stops at five.

The system's own camera indicator is lit whenever the camera runs. The app does not draw a second one.

## 11. Finding the setting

Every place a person meets the check says where the setting is. Issue 82 lists five; with access off by default the order of importance changes, and the link becomes an action.

| # | Where | What it says | Figure |
| --- | --- | --- | --- |
| 1 | The off answer, in Siri and Shortcuts | "Assistant Access is off. You can turn it on in nope. › Settings › Privacy." with one button, Open Settings, which runs Open Assistant Access | `assistant-answers` |
| 2 | The refusal card on the camera | Section 10, item 2 | `assistant-camera-refused` |
| 3 | Each question | "You can change this in nope. › Settings › Privacy." | `assistant-confirm` |
| 4 | A tip, once, after five confirmed requests | "You've confirmed 5 assistant requests. You can change how nope. asks." with Settings and a close button, on the camera | `assistant-tip` |
| 5 | Settings search | The keywords of 3.1 | |
| 6 | The Shortcuts app | Each action's description ends "Needs Assistant Access, in nope. › Settings › Privacy." | |
| 7 | The Honesty screen and the Accessibility page | An entry each (section 15) | |
| 8 | The 1.0.0 release notes and CHANGELOG | That Siri and Shortcuts actions are off until Assistant Access is turned on, and where it is | |

Not used: a first-run question or any prompt that asks a person to turn access on. The app does not push toward the less private choice.

The tip uses TipKit, as issue 82 asks, drawn with the app's own card style so it is red in Night Mode. If TipKit cannot be styled that way, the app's card with one stored counter does the same (decision 12).

## 12. Devices

| Device | What differs |
| --- | --- |
| iPhone | As drawn. Settings is a sheet from Q › Settings; the page is one push |
| iPad | The page is a pushed page inside the Settings popover (as `ipad-settings-page`); no new layout. The hint and the cards sit in the picture's bottom stack in the column layout. On the Lock Screen the Live Activity's Stop is pressed by a person. No figure needed beyond the rule of [layouts.html](layouts.html) |
| iPhone Duo | Outer display: the stacked layout, as iPhone. Inner display: the column layout, as iPad. Folding or unfolding with the page open keeps it open. A question on screen while the phone is folded is the system's and stays the system's |
| Apple Watch | No setting on the watch and no assistant action: the watch app has no App Intents. Its Take Photo button is not gated (7.3). [watch.html](watch.html), "What the watch app does not have", gains one line: "No Assistant Access setting. The watch's button is a remote shutter you press, and is not affected by it." Whether Siri on the watch can reach the phone's actions is device check 9 |
| Lock Screen camera | No assistant action runs in it. Its Settings shows the Assistant Access row read only, with the value from the settings snapshot and the note "Unlock to change." (figure `assistant-lock-row`). Its Privacy changes do not last past the session today; this row is never changeable there, so a person holding a locked phone cannot turn access on. Two values are added to the snapshot |
| Headphones, a car, another speaker | Siri there sends the request to the phone, where it meets the same check and needs the phone unlocked. The headphone remote's volume press is a button, not an assistant (device check 9) |
| iPhone Mirroring | Device check 10, from issue 82 |

## 13. Accessibility and Night Mode

- **The row.** One element: "Assistant Access, Off, For Siri, Shortcuts and other assistants. Button." Title, value, note, trait: the order SETTING-SCOPE.md sets. Voice Control answers to "Assistant Access".
- **The page.** While access is off the top line is the first element, as static text. The switch reads "Assistant Access, off" and then its explanation, as every explained switch does. Each Ask First choice is one element with its sentence in its label and the selected trait on the chosen one; selection is a checkmark, never color alone. The paragraphs and the session list follow as static text. Each session line is one element: "Take Photo. Asked, allowed."
- **The question.** Drawn and spoken by the system, so VoiceOver, Voice Control, Switch Control and Type to Siri work as they do for any app's confirmation. The app's part is the sentence: whole, with the values, and buttons that name the action.
- **People who use Siri or Shortcuts as their main way to take a photo.** With access off, "Take a photo with nope." answers that access is off and offers Open Settings; with Every Action it asks each time. The Accessibility page gains an entry that says so and names Only Before a Photo and Never. VoiceOver, Voice Control, Switch Control, the volume buttons, Camera Control and the watch are never affected, and the entry says that too. `AGENTS.md` lists "Take a photo with nope." among the ways to shoot without seeing the screen; with access off by default that way needs one visit to Settings first (decision 1).
- **The hint and the cards.** The hint is announced, queued behind any capture result, as "Siri or Shortcuts. Now using the telephoto camera." The cards take VoiceOver focus only when the camera appears with them; their buttons, and the hint's Close, are 44 pt and are named Settings and Close.
- **Text size.** The page scrolls; every line wraps; nothing is truncated (`assistant-page-largest`). The hint and cards follow the scrolling layout's rules.
- **Right to left.** Mirrored (`assistant-page-rtl`); the path "nope. › Settings › Privacy" is one localized string, not joined fragments.
- **Contrast, transparency, motion.** The tokens of the other Settings pages and camera hints; the hint crossfades with Reduce Motion.
- **Night Mode.** The page, the hint and the cards are red on black (`assistant-page-night`, `assistant-camera-night`). The system's question, Siri's own screen and Shortcuts are drawn by iOS and are not red, like the search field that Settings leaves out in Night Mode. The app cannot change that; a person shooting in the dark who uses a voice or a shortcut can choose Only Before a Photo or Never, or use the shutter. The Night Mode entry on the Accessibility page says so.
- **Cognitive.** One switch and one choice. Each choice says what it allows in one sentence. The off answer and the question both say where to change it.

## 14. Assumptions and device checks

Each line is an assumption until confirmed in Apple's documentation for iOS 26 and 27 and on a device. Results go in `docs/TESTING.md`. A line that fails changes the design, not the claim.

| # | Assumption | If it does not hold |
| --- | --- | --- |
| 1 | A gated intent can start in the background and move to the foreground after the check (`supportedModes`, `continueInForeground`) | Keep `openAppWhenRun`; the app opens, then refuses or asks. The page's wording does not depend on this |
| 2 | `requestConfirmation` shows the question with a second line and custom button names in Siri and in Shortcuts, before the app opens, and throws on Cancel | The fallback of 5.5: the app's own card on the camera. Drop the second line if only it fails |
| 3 | An unattended automation stops at a confirmation and does not run the action | If it can run through, Every Action and Only Before a Photo must refuse when no person can answer |
| 4 | After Cancel the app can give an answer | No answer; nothing is claimed |
| 5 | `authenticationPolicy = .requiresAuthentication` makes Siri ask for an unlock for every gated action, on the Lock Screen, through headphones and in a car | The check refuses while the device is locked, by the app's own test |
| 6 | A result can carry one button that runs another intent (Open Settings in the off answer) | The sentence alone names the path |
| 7 | Camera-domain assistant schemas: what exists on iOS 26 and 27, and whether a conforming intent runs `perform()` and can ask for confirmation | No schema is adopted (section 9) |
| 8 | The system does not record or suggest the app's actions unless the app donates them | State what the system does on the Honesty screen; point to the system's Siri settings for the app |
| 9 | Siri on Apple Watch, headphones, a car or a speaker cannot run the phone's actions around the check | Any path found gets the same check before release |
| 10 | iPhone Mirroring: whether the camera runs, and whether any control can be operated from the Mac | State it as a limit |
| 11 | Siri on a locked phone: the photo action requires unlocking | Release blocker |
| 12 | The camera stops when the app leaves the screen, and the system's indicator shows whenever it runs | Release blocker |
| 13 | The names of the app's actions and phrases are listed by the system with access off, and nothing else about the app is | State what is listed |

## 15. The wording

US English. Drafts for the owner's Honesty review; none ships until reviewed. All go in `Honesty.xcstrings` except the questions and the action descriptions, which go in the app's catalog with the other Siri strings. Each translator comment says that Assistant Access, Ask First, Every Action, Only Before a Photo and Never are names in the app's Settings and "Must not claim more than the English."

| # | Where | Text |
| --- | --- | --- |
| 1 | Row note | For Siri, Shortcuts and other assistants. |
| 2 | Row values | Off · Ask Every Action · Ask Before a Photo · Never Ask |
| 3 | Page, top line while off | Assistant Access is off, so Ask First is not used now. |
| 4 | Switch explanation | Lets Siri, Shortcuts and other assistants on this device use nope.'s actions, such as taking a photo or switching lenses. While this is off, nope. refuses every one of them. |
| 5 | Ask First header and choices | Ask First · Every Action · Only Before a Photo · Never |
| 6 | Every Action | nope. names each action and asks before it runs. |
| 7 | Only Before a Photo | Changes run without asking. nope. asks before an action that takes photos. |
| 8 | Never | Actions run without asking. |
| 9 | Ask First footer | An automation that runs with no one there can't answer, so it stops at the question. |
| 10 | What Assistants Get, 1 | After an action, the assistant gets one sentence about what happened, such as "Photo saved." It never gets a photo, a location or a photo's details from nope. |
| 11 | What Assistants Get, 2 | While access is on, assistants can see the names of your presets. No action changes a Privacy setting, and a preset applied this way leaves your privacy settings as they are. |
| 12 | What Assistants Get, 3 | This covers nope.'s own actions. The shutter, the volume buttons, Camera Control, the Apple Watch app and the Control Center controls are not affected. Photos saved to Photos, and what Siri or other apps can see or do outside nope., are up to iOS. |
| 13 | Session header, empty text, footer | This Session · No requests since nope. opened. · Kept in memory only. Cleared when nope. closes. |
| 14 | Session results | Asked, allowed · Asked, cancelled · Ran without asking · Refused |
| 15 | The off answer | Assistant Access is off. You can turn it on in nope. › Settings › Privacy. |
| 16 | Its button | Open Settings |
| 17 | Under each question | You can change this in nope. › Settings › Privacy. |
| 18 | After Cancel | None: the app adds no answer, and the system answers (issue #126, owner decision of 2026-11-21) |
| 19 | Preset answer | "%@" applied, except its privacy settings. You can undo it in Presets. |
| 20 | Hint caption | Siri or Shortcuts |
| 21 | Refusal card | Assistant Access is off. nope. refused %lld requests since it opened. (with the singular form) |
| 22 | Tip | You've confirmed 5 assistant requests. You can change how nope. asks. |
| 23 | Action descriptions, closing sentence | Needs Assistant Access, in nope. › Settings › Privacy. |
| 24 | Lock Screen camera row note | Unlock to change. |
| 25 | Honesty entry, "Siri, Shortcuts and Assistants" | Siri, Shortcuts and other assistants can use nope. only if you turn on Assistant Access, and nope. asks before each action unless you choose otherwise. An assistant gets one sentence about what happened. It never gets a photo, a location or a photo's details from nope. This covers nope.'s own actions; photos you save to Photos, and what you let an assistant see on your screen, are up to iOS. |
| 26 | Accessibility page entry, "Siri and Shortcuts" | "Take a photo with nope." works after you turn on Assistant Access in Settings › Privacy. nope. then asks before each action; Only Before a Photo or Never asks less. VoiceOver, Voice Control, Switch Control, the volume buttons and Camera Control always work. |

What each claim rests on, and what would make it untrue:

- "refuses every one of them" (4): the check in every discoverable intent, held by the entry-point test. Open the Camera and Open Assistant Access open a screen and are not "actions such as taking a photo or switching lenses"; if the review reads "every" as including them, the sentence becomes "refuses every action that takes a photo or changes a setting."
- "never gets a photo, a location or a photo's details from nope." (10, 25): section 8, held by the result-type test. "from nope." is part of the claim: Photos is outside it.
- "No action changes a Privacy setting" (11): 7.4 and the preset rule. If decision 7 goes the other way, this sentence is removed.
- "asks before each action unless you choose otherwise" (25): the default, Every Action.
- Nothing says "no photo is taken while nope. is not on screen" until device check 12 is recorded; issue 82 asks for that sentence, and it is added to texts 12 and 25 then.
- Nothing says an assistant "cannot see" the screen or the photos in Photos. The app does not control either.

## 16. Alignment with issue 83

Issue 83 (protection for high-risk use) stays in 1.1.0. Nothing here blocks or contradicts it.

| Issue 83 | This design |
| --- | --- |
| Decision 5: captures held in the app are never indexed for system search; intents return status only, never files | Nothing is indexed at all in 1.0.0; results are a sentence and a count for every photo, wherever it is saved |
| Presets, Factory Defaults and assistants never change Save Photos To, Lock Captures or backup exclusion | The rule is already wider: no assistant action changes any Privacy setting (7.4), and the two new values are outside presets (3.5) |
| Decision 2: the lock guards the Save Photos To and Lock Captures pages only; Assistant Access stays open | Assistant Access needs no authentication in the app. It is read only in the Lock Screen camera, which issue 83 also does for its two rows |
| Describing on-screen content follows Assistant Access and never includes a capture's details while locked | Nothing on screen is described in 1.0.0 (decision 8), so there is nothing to restrict later |
| Delete All Captures is not an App Intent, a quick action, a link or a control | 7.4 |
| Security review item 2: the entry-point test also covers capture-returning intents, entity queries and the three settings | The test of section 17 already fails on any result type, entity or query that is not on its list, and on any intent that writes a Privacy setting |
| Less left behind | No request history on disk (section 10) |
| The Privacy group's order: Save Photos To, Lock Captures, Assistant Access | Assistant Access is added last in the group now and keeps that place |

One point for 1.1.0, not designed here: with Lock Captures on, the This Session list shows action names only, which already holds no capture details, so it needs no lock.

## 17. Tests

For the builder. Unit tests keep 100% line and branch coverage of non-UI code; the system's part is behind a protocol with a fake.

**Unit**

1. `AssistantAccess.decision(for:)`: every kind against off and each Ask First level (the table of 3.3), including `.opensScreen` and `.pressedByPerson`.
2. Each gated intent against each decision, with a fake confirmer: refused (nothing reaches `ShortcutInbox`, settings unchanged, the off answer), asked and confirmed (runs once), asked and cancelled (nothing reaches the inbox, nothing changes), run. Capture intents included.
3. Access turned off while a question is showing: refused after the answer.
4. The values in the question are the values the action runs with (delay, lens, count, interval and duration, preset name).
5. Defaults: off and Every Action on a fresh store; a stored choice survives a settings migration; Factory Defaults in the app resets both; presets neither store nor apply them; Factory Defaults through an assistant leaves them.
6. Apply Preset through an assistant: every Privacy-group value is unchanged, everything else applies, the answer is text 19, Undo restores as today. Applied in the app: unchanged from today.
7. `PresetQuery`: no saved names with access off; names with access on.
8. The session record: order, the cap of 20, each result, cleared with the process, never written to the settings store or a file; it holds no parameter values.
9. The refusal count and the tip counter (stops at five; shown once).
10. The settings snapshot for the Lock Screen camera carries the two values and stays under 4 KB.
11. Every question and answer string exists in the catalog with a comment; no string is built from fragments.

**Entry-point test** (issue 82, "No way around the setting"; issue 83, security review item 2). A repository check in the style of `scripts/check-security.sh`, with its own test script:

- It finds every `AppIntent`, `SetValueIntent`, `LiveActivityIntent`, `CameraCaptureIntent`, `AppShortcut`, `ControlWidget`, `AppEntity`, `EntityQuery`, assistant schema macro, `Transferable`, `NSUserActivity`, Core Spotlight use, donation call, `onOpenURL` and `CFBundleURLTypes` entry in the app and its extensions.
- Each must be listed in `security/assistant-entry-points.txt` with its kind. An unlisted one fails. A listed gated intent whose `perform()` does not call the helper fails.
- A result type other than a dialog (and the photo count) fails. An entity type other than `PresetEntity` fails. Any URL scheme, indexing, donation or user activity fails.
- A gated intent without `authenticationPolicy = .requiresAuthentication` fails.
- A unit test separately asserts that no intent path writes a Privacy-group setting, by applying every action with every parameter value against a settings fake that records writes.

**UI tests, each with `performAccessibilityAudit()`**

12. `testAssistantAccessRowAndNote`, `testAssistantAccessPageDefault` (off, Every Action selected, the top line), `testAssistantAccessPageOn`, `testAssistantAccessChoicesStayEnabledWhileOff`, `testSettingsRootRowsDoNotChange` updated for the new row.
13. The page in light, dark and Night Mode, at the largest text size and right to left (`auditSettingsScreens`).
14. `testSettingsSearchFindsAssistantAccessByKeyword` ("siri", "shortcuts").
15. With `SimulatedShortcut`: the hint after an action; the refusal card after a refused request, its count, Settings and Close; the tip after five confirmations and never again; each in Night Mode and at the largest text size.
16. The session list after an allowed, a cancelled and a refused request; VoiceOver labels of its lines.
17. The Lock Screen camera's Settings: the row is read only.
18. iPad popover and iPhone Duo inner display: the page inside the popover; fold and unfold with the page open.
19. `ShortcutUITests`: every existing test runs with access on and Never; one run of each action with access off expects the off answer and no change.

**Device checks:** the thirteen of section 14, recorded in `docs/TESTING.md`, plus the manual accessibility pass with VoiceOver, Voice Control and Switch Control over: the page, a refused request, a question answered by voice and by touch, and the hint.

**Documents, in the same change:** `docs/PRIVACY.md` (a section "Siri, Shortcuts and assistants": the setting, what an answer contains, preset names, what is not indexed or donated, the in-memory record), `docs/SECURITY_AUDIT.md` (the entry-point list), `docs/TESTING.md`, `AGENTS.md` ("Siri and Shortcuts": every action goes through the Assistant Access check; no action reads photos or changes a Privacy setting), the Honesty screen, the store claim table, CHANGELOG.

## 18. When this is accepted

- [SETTINGS-PLAN.md](SETTINGS-PLAN.md), section 3: Assistant Access is in the Privacy group in 1.0.0; the tree and [settings-tree.html](settings-tree.html) gain the row. The figures of the set that show the Privacy group are redrawn with the row (the list of SETTING-SCOPE.md, section 9), and the screen counts in README.md are updated.
- [BUILD-SPEC.md](BUILD-SPEC.md): a section 3.17 with the files (`SettingsScreen.swift`, a new `AssistantAccessSettingsView.swift`, `SettingsSearch.swift`, `CameraHints`, `App/NopeApp/Intents/*`, `NopeCore/AssistantAccess.swift`, `NopeSettings.swift`, `NopeSettingsSnapshot.swift`), the strings of section 15, and items in section 6 for the work outside `NopeUI`.
- [ACCESSIBILITY.md](ACCESSIBILITY.md), "Siri and Shortcuts": no longer "unchanged in 1.0.0"; the check, the questions and section 13.
- [navigation.md](navigation.md): Assistant Access, Q › Settings › Assistant Access, 3 taps.
- [system.html](system.html) and `screens/siri-results`: the off answer and a question.
- [watch.html](watch.html): the line of section 12.
- Issue 82: defaults (off), the link (an action, not `nope://`), the release named in "Release notes and Help" (1.0.0), and the decisions below.

## 19. Decisions for the owner

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 1 | The default of Assistant Access | **Off**, with Ask First on Every Action, for fresh installs and updates. Existing shortcuts and "Take a photo with nope." answer that access is off, with Open Settings, until it is turned on. Update issue 82's text, which says on | On with Every Action (issue 82 as written on 2026-11-17): existing shortcuts keep working with a question each time, and the voice shutter works without a visit to Settings |
| 2 | Name and place | "Assistant Access", Settings › Privacy, last in the group, with the note "For Siri, Shortcuts and other assistants." | "Siri and Shortcuts" as the name: more familiar, but leaves out other assistants |
| 3 | Ask First while access is off | Always shown and enabled, with the line "Assistant Access is off, so Ask First is not used now." No row appears or disappears, as on every other page | Shown only while access is on (issue 82 as written) |
| 4 | What Every Action covers | Every gated action, with no exceptions, including Stop Interval Shooting and Turn Off the Light. The name stays true | Stopping and turning off run without a question |
| 5 | Who draws the question | The system (`requestConfirmation`), before the app opens. Not red in Night Mode, which the docs state | A card drawn by the app on the camera: red in Night Mode, but the app must open first and Siri does not speak it. Kept as the fallback if device check 2 fails |
| 6 | The watch app, the Control Center controls and the Live Activity's Stop | Not gated: a person presses them, like the volume buttons. Declared as such in the entry-point list. The page says they are not affected | Gated, as issue 82's entry-point list reads: with access off, the watch remote, the Night Mode control and Stop are refused |
| 7 | Privacy settings and assistants | No assistant action changes a Privacy setting. Apply Preset through an assistant applies the rest of the preset and says so. One plain claim for the page and the Honesty screen | Apply Preset applies in full after its question, and asks even on Only Before a Photo; the claim is dropped |
| 8 | Reading the camera's state, and describing on-screen content to Siri | Neither in 1.0.0. An assistant learns only the answer to an action it ran | A "Get Camera Status" action (lens, mode, formats; never photos), behind the check and asked about like any action |
| 9 | Results for chaining in Shortcuts | The sentence, plus a "Photos Saved" number for the photo actions. No file, format, lens or settings values returned | The sentence only; or the structured values of issue 82 (format, lens, settings) without any file |
| 10 | The link to the setting | An action, Open Assistant Access, offered as the Open Settings button. No `nope://` scheme in 1.0.0: the app has none, and `AGENTS.md` rules it out | Add `nope://settings/assistant-access` and change the rule in `AGENTS.md`; links must then be proved never to act |
| 11 | What shows that an assistant acted | The camera hint with the caption "Siri or Shortcuts", the refusal card, and the in-memory list on the page. Nothing on disk | The hint only; or a history kept across launches |
| 12 | The tip after five confirmations | Keep it, once, as a card in the app's style (TipKit if it can be styled for Night Mode, else the app's card and one counter) | No tip: the line under each question is enough |
| 13 | New actions (7.2) | Build the check, the page and the fourteen existing actions first; add the new actions in 1.0.0 only after device checks 1 to 6 pass, otherwise 1.1.0. Each is independent | All of 7.2 in the first 1.0.0 build |
| 14 | Assistant schemas | None until device check 7 passes; never a photos-domain schema; no mention of Apple Intelligence in the app or the store text until then | Adopt the camera-domain schemas now |
| 15 | Locked phone | Every gated action requires an unlock, including stopping and turning off | Stop Interval Shooting and Turn Off the Light allowed while locked |
| 16 | The Lock Screen camera's Settings | The row is shown read only, "Unlock to change." | Leave the row out there |
| 17 | Preset names | Offered to Shortcuts and Siri only while access is on, and the page says assistants can see them | Never offered: Apply Preset takes a typed name and answers "can't be found" on a mismatch |
| 18 | A first-run question about assistants | None. The setting is found when it is needed (section 11) | One line at first run that names the setting |
| 19 | The sentence "No photo is taken while nope. is not on screen" | Added to the page and the Honesty screen only after device check 12 is recorded | In the first draft, before the check |
| 20 | Optional search indexing (issue 82) | Not in 1.0.0. If it returns, photos saved to Photos only (issue 83, decision 5), as its own design | Design it now |
