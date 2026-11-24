# iOS parity column

The iOS column for `core/shared/PARITY.md` (Android build 170). Kept here so status changes don't need the Android
chat to merge them. `done`, `part: <what is missing>`, `todo`, or `skip: <why>`.

## Feature sections

Every row in these sections of PARITY.md is **todo**. They are the shared screens and engine, which come from the
Kotlin Multiplatform move in `hubbub0/Mess-Machine`, not from code written here:

Layouts and looks, Top bar, Tabs, Play page, Bottom dock and More, Settings tray and Edit tray, FannyPack strips,
Perform row and side dock, Hold chords and scales and note repeat, Mute and drop, Loop strip, Synth page,
Seq page (Steps and Roll), Perform page, Sheets, Recording, Undo.

| Row | iOS |
|---|---|
| MIDI in | part: CoreMIDI over USB and Bluetooth (Apple's pairing screen behind the Bluetooth key), every source, parser ported line for line (running status, program change and pressure skipped, bend); events reach the stand-in tone. Pad and key mapping waits on the shared screens. |
| MIDI map | todo |
| MIDI file out | todo (engine) |
| Mic onto a pad, Workbench | part: Record (tap start, tap keep) saves mic takes as 16-bit WAV with silent edges cut; Import brings in any audio file iOS reads, mixed to mono; both get `bn:<id>` keys, play through the stand-in engine, and a mess naming them loads. Chops, resampling (Bottle it), saved edits and key and tempo measuring wait on the shared engine. |

## Android-only pieces

| Android piece | iOS |
|---|---|
| Low-latency output, lock-free ring, grow on clicks, shrink after 10 clean s | part: RemoteIO render callback reading the same ring design (`ios/Audio`), grows up to 3 blocks on clicks and shrinks after 10 clean s, 5 ms IO buffer asked for, interruptions, route changes (headphones out stops) and media reset handled. Test tone instead of the engine. Not yet measured on a real iPhone. |
| MIDI (android.media.midi) | part: see MIDI in |
| Background play with Stop | done: audio background mode, Now Playing entry with Stop and Pause |
| Notifications permission, reopen notice | skip: not needed on iOS |
| In-app update from GitHub releases | todo: TestFlight, needs Tyler's Apple Developer Program membership |
| Bug notes as GitHub issues | part: same title, body, marker and labels plus `ios`; with a key posts directly, else opens the filled-in page; Replies reads Claude's comments and the issue status back (same status words as Android). Send all as one bundle and the full Notes screen come with the shared screens. |
| Quick note speech | done: Say it in the note sheet (SFSpeechRecognizer, on the phone when it can), one tap to start, one to stop |
| Mic for mouth control and takes | part: takes done (see Workbench); mouth control waits on the shared engine's MouthTracker, which plugs into MicIn.onSamples |
| Pad buzz | done: UIImpactFeedbackGenerator on every pad hit (rigid for hard MIDI hits) |
| Lock pins the screen | skip: Guided Access is the user's own setting; no API |
| 60 Hz or Smooth screen | todo |
| Back button closes the top panel | skip: no back key; panels close with their X |
| Light status bar icons on light skins | todo (with skins) |
| Share sheet, open a mess file, import sounds | part: opens .json messes from Files and "Open in", shares the re-saved mess, imports sounds to the Workbench. WAV, stems and MIDI sharing wait on the engine's bounce. |
| Test tags, big test, phone test | part: accessibilityIdentifier uses Android's tags where a control exists (`pad-0`, `bar-play`, `bar-notes`); XCUITest drives the day-one screen with screenshots |

## Mess format

| Part | iOS |
|---|---|
| Top-level keys, clamps, kit loading, missing count, sel fallback | done |
| Loops: len, steps, notes, offs (a tick on a step becomes a hit) | done |
| motion, acc, chance, locks, edits, synths, padOpts | part: carried through unchanged for sounds on a pad; not interpreted until the shared engine reads them |
| v1 top-level steps, v2 `inst` notes, site files, qb: aliases | done |
| Pre-106 LFO filter move in padOpts | todo: lands with the shared engine's PadOpts |
| Missing sounds keep their pads, unknown top-level and per-loop keys carried, `v` above 3 flagged (build 172) | done (the pad's Missing label waits on the shared screens) |
| Writes `app: "ios"` | done |
