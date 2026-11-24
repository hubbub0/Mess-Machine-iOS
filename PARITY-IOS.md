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
| MIDI in | part: CoreMIDI over USB, every source, parser ported line for line (running status, program change and pressure skipped, bend); events reach the stand-in tone. Pad and key mapping waits on the shared screens. No Bluetooth pairing screen yet. |
| MIDI map | todo |
| MIDI file out | todo (engine) |
| Mic onto a pad, Workbench | part: mic opens with play-and-record, level meter, samples handed on. No recording to file yet. |

## Android-only pieces

| Android piece | iOS |
|---|---|
| Low-latency output, lock-free ring, grow on clicks, shrink after 10 clean s | part: RemoteIO render callback reading the same ring design (`ios/Audio`), grows up to 3 blocks on clicks and shrinks after 10 clean s, 5 ms IO buffer asked for, interruptions, route changes (headphones out stops) and media reset handled. Test tone instead of the engine. Not yet measured on a real iPhone. |
| MIDI (android.media.midi) | part: see MIDI in |
| Background play with Stop | done: audio background mode, Now Playing entry with Stop and Pause |
| Notifications permission, reopen notice | skip: not needed on iOS |
| In-app update from GitHub releases | todo: TestFlight, needs Tyler's Apple Developer Program membership |
| Bug notes as GitHub issues | part: same title, body, marker and labels plus `ios`; with a key posts directly, else opens the filled-in page. Reply checking and the note list screen come with the shared Notes screen. |
| Quick note speech | todo: SFSpeechRecognizer |
| Mic for mouth control and takes | part: see Mic onto a pad |
| Pad buzz | done: UIImpactFeedbackGenerator on every pad hit (rigid for hard MIDI hits) |
| Lock pins the screen | skip: Guided Access is the user's own setting; no API |
| 60 Hz or Smooth screen | todo |
| Back button closes the top panel | skip: no back key; panels close with their X |
| Light status bar icons on light skins | todo (with skins) |
| Share sheet, open a mess file, import sounds | part: opens .json messes from Files and "Open in", shares the re-saved mess. Sounds import waits on the engine. |
| Test tags, big test, phone test | part: accessibilityIdentifier uses Android's tags where a control exists (`pad-0`, `bar-play`, `bar-notes`); XCUITest drives the day-one screen with screenshots |

## Mess format

| Part | iOS |
|---|---|
| Top-level keys, clamps, kit loading, missing count, sel fallback | done |
| Loops: len, steps, notes, offs (a tick on a step becomes a hit) | done |
| motion, acc, chance, locks, edits, synths, padOpts | part: carried through unchanged for sounds on a pad; not interpreted until the shared engine reads them |
| v1 top-level steps, v2 `inst` notes, site files, qb: aliases | done |
| Pre-106 LFO filter move in padOpts | todo: lands with the shared engine's PadOpts |
| Writes `app: "ios"` | done |
