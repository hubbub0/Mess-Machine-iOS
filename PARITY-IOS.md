# iOS parity column

The iOS column for `core/shared/PARITY.md` (Android build 170). Kept here so status changes don't need the Android
chat to merge them. `done`, `part: <what is missing>`, `todo`, or `skip: <why>`.

## Feature sections

Since iOS build 18 the screens are shared too (core/ui, the MessMachine framework): AppState and every Compose screen
run on iPhone, on the iPhone platform pieces in `ios/App/Platform/IosPlatform.swift`. These sections of PARITY.md are
**part** on iPhone: the same code, every tab, sheet and the perform row driven on the Simulator with screenshots
(iOS build 21), pads and Play measured making sound, not yet played on a real phone:

Layouts and looks, Top bar, Tabs, Play page, Bottom dock and More, Settings tray and Edit tray, FannyPack strips,
Perform row and side dock, Hold chords and scales and note repeat, Mute and drop, Loop strip, Synth page,
Seq page (Steps and Roll), Perform page, Sheets, Recording, Undo.

| Row | iOS |
|---|---|
| MIDI in | part: CoreMIDI over USB and Bluetooth (Apple's pairing screen behind the Bluetooth key), every source, parser ported line for line (running status, program change and pressure skipped, bend); events reach the stand-in tone. Pad and key mapping waits on the shared screens. |
| MIDI map | todo |
| MIDI file out | todo (engine) |
| Mic onto a pad, Workbench | part: the shared Workbench screens on `IosBench`, a port of Android's Workbench.kt: mic takes with Auto sample and Android's trim, imports, chops, saved edits, keys measured by the shared KeyFinder, all registered in the Library (`bn:` and `chop:`). Not yet tried with a real mic. |

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
| Mic for mouth control and takes | part: mouth control feeds the shared MouthTracker at 16 kHz from MicIn; takes as above. Not yet tried with a real mic. |
| Pad buzz | done: UIImpactFeedbackGenerator on every pad hit (rigid for hard MIDI hits) |
| Lock pins the screen | skip: Guided Access is the user's own setting; no API |
| 60 Hz or Smooth screen | todo |
| Back button closes the top panel | skip: no back key; panels close with their X |
| Light status bar icons on light skins | todo (with skins) |
| Share sheet, open a mess file, import sounds | part: sharing (iOS share sheet) and in-app import work through the shared screens; opening a mess from Files, Mail or "Open in" and messmachine:// links wait on core PR #26 (`IosApp`). |
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
| Sound packs (SE-17) | part: `IosPacks.swift`, a port of AndroidPacks (packs release, zip unpacked with every entry kept inside its folder, jar in Sounds); tested on zips, not yet against a real pack. Failures report once core PR #26 adds @Throws. |
