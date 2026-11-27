# Mess Machine (iOS) notes for Claude

The iPhone version of Mess Machine, built to match the Android app in `hubbub0/Mess-Machine`. Read
`core/docs/handoff/IOS.md` first (it is the brief), then `core/CLAUDE.md`, `core/DESIGN.md` and `core/shared/`.
Never use em dashes in anything written for Tyler. Tag claims [Certain], [Likely] or [Guessing].

## How the two repos fit

- `core/` is a git submodule pointing at `hubbub0/Mess-Machine`, pinned to one commit. Shared code and assets come
  from there (fonts, `library.json`, the fixtures, later the Kotlin engine and Compose screens). Never edit files under
  `core/`. A shared change goes to `hubbub0/Mess-Machine` as a pull request titled `[iOS] ...`; once the Android chat
  merges it, move the pin: `git -C core fetch origin main && git -C core checkout <sha> && git add core`.
- Everything iPhone-only lives here: `ios/Audio` (C: ring and Core Audio), `ios/App` (SwiftUI shell and platform
  pieces), `ios/Tests`, `ios/UITests`, `project.yml`, `.github/workflows/ios.yml`.
- Parity: this repo keeps the iOS column in `PARITY-IOS.md` (one line per PARITY.md section or feature). Chosen
  over pull requests to `core/shared/PARITY.md` so status changes do not need the Android chat to merge.

## Building

The workspace is Linux and cannot build iOS. Everything builds on GitHub Actions (`.github/workflows/ios.yml`, macOS
runner, free on a public repo): precheck, the C ring tests, `xcodegen generate` (the `.xcodeproj` is generated from
`project.yml` and never committed), unit tests, then the UI test on an iPhone Simulator. Screenshots and the build
log go to the `test-screens` release. Watch with `gh api repos/hubbub0/Mess-Machine-iOS/actions/runs`.

The C ring is tested here too:
`cc -std=c11 -O2 -pthread -I ios/Audio ios/Audio/mm_ring.c ios/Audio/test/ring_test.c -o /tmp/r && /tmp/r`
(add `-fsanitize=thread` to check for races).

## The audio rule

Apple coalesces ordinary timers, so the Android-style "sleep and poll" writer woke late on a Mac runner (107 short
reads in about 370). Here the callback signals a semaphore when it frees room, and the writer thread asks for a
real-time schedule (`mm_thread_realtime`). That cut it to 7 on the shared CI machine. Keep both.

The render callback (`ios/Audio/mmaudio_ios.c`) only copies from the ring. It never allocates, locks, logs or calls
into Swift or Kotlin. The engine renders on the writer thread (`AudioHost.swift`), exactly like Android's
`AudioOut.kt` and `mmaudio.c`. `ToneEngine` stands in for the engine until the Kotlin module exists.

## Where the iPhone pieces are

| Piece | iOS | Android twin |
|---|---|---|
| Ring and output | `ios/Audio/mm_ring.c`, `mmaudio_ios.c`, `ios/App/Audio/AudioHost.swift` | `cpp/mmaudio.c`, `AudioOut.kt` |
| Mic | `ios/App/Platform/MicIn.swift` | `MouthMic.kt` |
| Workbench (mic takes, imports) | `ios/App/Platform/Workbench.swift` | `Workbench.kt` |
| Quick note speech | `ios/App/Platform/VoiceNote.swift` | `VoiceNote.kt` |
| MIDI in | `ios/App/Platform/MidiIn.swift` (parser is a line-for-line port), `BluetoothMidi.swift` (pairing) | `Midi.kt` |
| Background play with Stop | `ios/App/Platform/Background.swift` (audio background mode, lock screen Stop) | `PlaybackService.kt` |
| Bug notes | `ios/App/Platform/Notes.swift` (same inbox, labels `from-app`, kind, `ios`) | `Notes.kt` |
| Haptics | `Background.swift` `Haptics` | pad buzz |
| Mess files | `ios/App/Mess/Mess.swift` (stopgap reader and writer, tested on the shared fixtures) | `engine/Project.java` |

## The shared engine

The engine is common Kotlin in `core/core/` (Kotlin Multiplatform, same names as the old Java engine), built for iOS
as the static framework `MessEngine` (docs: `core/docs/KOTLIN-ENGINE.md`, `core/docs/handoff/IOS.md`).

- `tools/build-engine.sh` (Mac only, run by CI) builds it with `-Pmm.coreOnly` (no Android tools), copies it to
  `build/engine/`, rewrites `engine.yml` so the app and unit tests link it, and keeps `build/engine/MessEngine.h`.
  CI prints the Swift names of the calls the app uses and puts the whole header on the `test-screens` release: read
  it before calling anything new.
- `ios/App/Audio/SharedEngine.swift` (`#if canImport(MessEngine)`): renders with `Engine.renderInto` (iosMain) on the
  writer thread, reads sounds through `MMBundleSoundFiles` (Objective-C, because Kotlin's `read` may throw or return nothing) (the bundled `sounds/` folder, a copy of
  `core/app/src/main/assets/sounds`), opens messes with `Project.fromJson(text, lib::has)` like Android, and drives
  pads, play and stop through the engine's command queue. Built without it, the app falls back to `ToneEngine`.
- The engine renders at the session's rate when the app starts (`AudioHost.prepareSession`). A later rate change
  (some Bluetooth outputs) is not handled yet.
- Next: the shared screens. Until then `Mess.swift` stays as a second check of the format.

## Putting it on an iPhone (waiting on Tyler)

Simulator only until Tyler decides. When he does, these are his steps; Claude never creates the account or keys:

1. Join the Apple Developer Program ($99 a year) at developer.apple.com with his Apple ID.
2. In App Store Connect, add an app with bundle ID `app.shotgunstudio.messmachine` (same id as Android since Nov 24;
   Android moved off `com.tideclock.messmachine`).
3. App Store Connect, Users and Access, Integrations: make an API key with the App Manager role and download the .p8.
4. In this repo's Settings, Secrets and variables, Actions, add `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and
   `ASC_KEY_P8` (the .p8 file's text). He pastes them himself.
5. Run "TestFlight (real iPhone)" from the Actions tab (`.github/workflows/testflight.yml`), then install TestFlight
   on the iPhone and accept the build.

The app icon (`ios/App/Assets.xcassets`) is made from the Android launcher art by `python3 tools/make_icon.py`;
rerun it when the core/ pin moves past an icon change.

## Tyler's notes

iPhone notes land in `hubbub0/Mess-Machine` issues with the `ios` label. Fix iOS-only bugs here and close them with
"Fixed in build <run number>: <one line>", following the bug-testing triage rules in `core/CLAUDE.md`.

## The shared screens (since build 18)

The app's root is `MainViewControllerKt.MainViewController(platform:)` from the `MessMachine` framework (core/ui,
engine exported), built by `tools/build-engine.sh`. `ios/App/Platform/IosPlatform.swift` is the iPhone side of
AppState's `Platform`, built on the pieces above. App types that clash with the framework were renamed (`IosNote`,
`BenchSound`, `WavFile`, `Ink`); check new type names against `build/engine/MessMachine.h`. The app's Swift module is
`MessMachineApp`. The old day one screen stays behind the `-dayOne` launch argument for its UI test.

## Known gaps (see PARITY-IOS.md)

- Sound packs, the speaker check, opening a mess from Files or a share sheet, and cloud (null until CMP step 8) are not
  wired on iPhone yet. The UI test only checks the screens start and take taps; nobody has heard them on a phone.
- Real-phone installs need Tyler's Apple Developer Program membership and signing in CI (TestFlight). Simulator only
  until then. Ask Tyler before touching his Apple account.
