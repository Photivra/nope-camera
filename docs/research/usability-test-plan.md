# Usability test plan

For issue 127: a moderated usability test of Photivra Nope Camera with System Usability Scale (SUS) scores, including people who use VoiceOver and other assistive features. Proposed 2026-11-21; the maintainer runs it. The open choices (when, how many people, the targets, what is published) are decisions 22 to 25 of [docs/plans/1.1.0.md](../plans/1.1.0.md); this plan is written for the recommended answers and says where another answer changes it.

Nothing here adds code to the app. The app records nothing about a session: it has no analytics and no network code, and the test does not change that. Everything is observed and written down by the moderator.

## 1. Questions the test answers

1. Can a person who has never seen the app take a photo and tell whether, where and as what it was saved?
2. Can they find the controls the redesign moved (lenses, the drive strip, Q, Manual Controls, Settings), and get back from clean view?
3. Do they understand the app's own words: "RAW · Single frame", "Processed", "Saved and signed", "Not signed", the Honesty screen?
4. Is each task possible with VoiceOver, with the largest text size, and with Voice Control or Switch Control?
5. What is the SUS score, overall and for people using assistive features?

## 2. Build and timing

- The build under test is the 1.1.0 release candidate from TestFlight (decision 22), so the test also covers the quieter Show Controls button (issue 120), Shutter Sound (128) and the new save status (129). If the test is run on 1.0.0 instead, leave out tasks 12 and 13 and the last probe of task 1.
- One pilot session first, with someone outside the project. Fix the script, then run the rest. The pilot's numbers are not counted.
- Findings rated 3 or 4 (section 8) are fixed or filed before the release; the rest are filed.

## 3. Participants

Twelve people (decision 23), none of whom worked on the app:

| Group | People | Who |
| --- | --- | --- |
| A | 4 | Use only their phone's built-in camera; have not shot RAW |
| B | 4 | Use manual controls or shoot RAW, on a phone or a camera |
| C | 2 | Use VoiceOver every day |
| D | 1 | Use the largest text sizes, Zoom or Increase Contrast every day |
| E | 1 | Use Voice Control or Switch Control every day |

- Across the twelve: a spread of ages, at least one left-handed person, and at least four who do not work in software.
- People in C, D and E use their own iPhone with their own settings where they can; an assistive setup is personal, and a borrowed phone measures the phone. Others use their own iPhone (iOS 26 or 27) or the test phone.
- Twelve is the smallest group for which a SUS mean is reasonably stable; groups C to E are too small for a score of their own to mean much, so their results are reported as task outcomes and observations, with their SUS scores shown but not compared.

## 4. Consent and privacy

- Each person agrees in writing before the session to: what is observed, that notes are taken, whether audio or the screen is recorded (optional; the session works without), how long the notes are kept, and that they can stop at any time.
- Notes use a participant number, never a name. Recordings, if any, and the sheet that links numbers to people stay with the maintainer, outside the repository, and are deleted when the results are written up.
- Photos taken during a session stay on the participant's phone, or are deleted from the test phone in front of them.
- TestFlight is Apple's service: installing through it shares what Apple's TestFlight terms describe with Apple. Tell participants this before they install. The app itself still sends nothing.
- Only aggregates go in the repository (decision 25): scores, completion counts, times, and findings without anything that identifies a person.

## 5. Session

About 45 minutes, one person at a time, in person where possible (a remote session works for groups A and B over a video call with the phone's screen shared).

| Minutes | Part |
| --- | --- |
| 5 | Welcome, consent, "we are testing the app, not you", think aloud |
| 2 | Background questions: which camera app they use, RAW or manual experience, assistive features |
| 25 | Tasks (section 6), in order, each read aloud from a card and handed over |
| 5 | The SUS questionnaire (section 7), filled in alone |
| 8 | Debrief: what was hardest, what surprised them, what they would change, what the app's name and promises mean to them |

Moderator rules: read the task as written; do not name a control; wait before helping; when a person is stuck for a minute or asks, give one hint and record it; after two hints, show the way and record the task as not completed.

## 6. Tasks

The app starts freshly installed, with the camera and Photos prompts not yet answered, in a room with something to photograph near and far. For each task record: the outcome (completed unaided, completed with a hint, not completed), the time from the end of the reading to the end of the task, wrong turns, what was said, and the answer to one question, "Overall, how easy or difficult was that?" on a scale from 1 (very difficult) to 7 (very easy).

| # | Task card | Done when | What it tests |
| --- | --- | --- | --- |
| 1 | Open the app and take a photo of the object on the table. Then tell me: was it saved, and what kind of file is it? | A photo is taken and the person states saved or not and the format, from the screen | First run, permissions, the shutter, the status line, the saved sentence. Probe: "How do you know it was saved?" |
| 2 | Look at the photo you just took, and find out what information is stored inside the file. | Photo Details is open and the person names two details | Last Photo, the viewer, What's in This Photo |
| 3 | Take a photo that shows as much of the room as possible. | A photo with the widest lens | The lens row |
| 4 | Take a photo of yourself. | A photo with the front camera | Switch Camera |
| 5 | Set the camera so you have three seconds to get ready, and take a photo. | A timer photo | The drive strip, Timer |
| 6 | Take several photos quickly, one after another, of something moving. | A burst of three or more | Burst, hold or Start Burst |
| 7 | Take a photo with the shutter speed set to 1/60 of a second. Then put everything back to automatic. | A photo at 1/60 s, then all controls on auto | Manual Controls, a dial, All Auto. Groups A and D may skip after one hint; record it |
| 8 | Hide everything on the screen except the picture and the shutter. Take a photo. Then bring the controls back. | Clean view on, a photo, clean view off | Q, Hide Controls, Show Controls (issue 120) |
| 9 | Make the screen easier on your eyes in the dark. | Night Mode is on | Q or Settings, Night Mode |
| 10 | Find out whether your photos include where they were taken, and make sure they do not. | The person finds Location under Details in Each Photo and states it is off | Settings, Privacy, search |
| 11 | Turn on signing, take a photo, and tell me whether that photo was signed. | Sign Each Photo on, a photo, a correct answer | Privacy, the seal, the saved sentence. Probe: "What does signed mean here?" |
| 12 | Make the camera play a sound when it takes a photo. (1.1.0) | Shutter Sound is on, or the person finds why it cannot be changed | Settings, search (issue 128) |
| 13 | Keep your next photo out of the Photos app, take it, and then send it to me. (1.1.0, if issue 83 is in the build) | nope only is on, a photo, the share sheet is open for it | Save Photos To, Captures, export |
| 14 | Find out, in the app, what it does and does not do to your photos. | The Honesty screen or the guide is open and the person restates one point | Honesty, the guide. Probe: "What does RAW · Single frame mean to you?" |

Order: 1 and 2 first for everyone; 3 to 14 in the same order for everyone, so later tasks do not teach earlier ones differently from person to person. If time runs out, tasks 7 and 13 are dropped first, and the drop is recorded.

For groups C and E every task is attempted with the person's own way of using the phone; the outcome also records whether anything was unreachable, unlabeled or announced wrongly.

## 7. System Usability Scale

Given on paper or read aloud, straight after the tasks and before the debrief. Each statement is answered from 1 (strongly disagree) to 5 (strongly agree). The wording is the standard scale (J. Brooke, 1986), with "app" for "system"; do not reword, reorder or explain the statements beyond saying that "cumbersome" means awkward to use.

1. I think that I would like to use this app frequently.
2. I found the app unnecessarily complex.
3. I thought the app was easy to use.
4. I think that I would need the support of a technical person to be able to use this app.
5. I found the various functions in this app were well integrated.
6. I thought there was too much inconsistency in this app.
7. I would imagine that most people would learn to use this app very quickly.
8. I found the app very cumbersome to use.
9. I felt very confident using the app.
10. I needed to learn a lot of things before I could get going with this app.

Scoring, for each person: for statements 1, 3, 5, 7 and 9 take the answer minus 1; for statements 2, 4, 6, 8 and 10 take 5 minus the answer; add the ten numbers and multiply by 2.5. The result is from 0 to 100. A form with a missing answer is scored with 3 for that statement, and that is noted. The score is not a percentage.

Report: the mean, the median, the lowest and the highest, the standard deviation and a 95% confidence interval for all twelve; the same mean for groups A and B separately; each score of groups C to E listed without a mean. For reference, the published average across many products is about 68; decision 24 sets this test's target.

## 8. Findings

Each problem seen is written as one sentence, with how many people met it, and a severity:

| Severity | Meaning |
| --- | --- |
| 4 | A task could not be completed, or a person believed something false about a photo (saved, signed, where it went, what it contains) |
| 3 | Completed only with a hint, or a long wrong turn, for two or more people |
| 2 | A delay or a wrong turn the person recovered from |
| 1 | A remark or a preference |

A severity 4 about a false belief is an Honesty problem and is fixed before release whatever else is decided. Anything a person using assistive features could not reach, or that was announced wrongly, is at least severity 3.

## 9. Targets

With the recommended answer to decision 24:

- mean SUS of 75 or more across the twelve;
- tasks 1, 2, 3, 5, 8 and 10 completed unaided by at least ten of twelve;
- every task possible, with or without a hint, for each person in groups C, D and E;
- no open severity 4 finding at release.

Missing a target does not block the release by itself; it means the findings behind it are fixed or the maintainer decides, in the release checklist, to ship with them filed.

## 10. What goes in the repository

When the test is done, one file, `docs/research/usability-test-results.md`: the date range, the build, the number of people in each group, the SUS figures of section 7, a table of tasks with outcomes and median times, the findings with severity and the issue filed for each, and what was changed. Issue 127 closes with a link to it. No names, recordings, quotes that identify a person, or raw notes.

## 11. Materials to prepare

- The consent form and the background questions.
- Fourteen task cards, one task each, in large print, and in braille or as a text file for group C if asked.
- The SUS form, in large print and as a text file.
- The observer sheet: one row per task with outcome, time, hints, ease (1 to 7) and notes.
- A stopwatch that is not the test phone, a spare charged iPhone with the build installed, and objects to photograph near and far, one of them moving.
