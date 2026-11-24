# Mess Machine for iPhone

The Mess Machine sequencer from Neat Shit and Dye, for iPhone and iPad. It shares its engine, screens, sounds and
saved messes with the Android app in [hubbub0/Mess-Machine](https://github.com/hubbub0/Mess-Machine), brought in
here as the `core/` submodule.

Today it is the day-one shell: Core Audio output with a test tone standing in for the engine, the mic, MIDI in,
background play with Stop, mess files and the bug button. The real instrument arrives when the shared Kotlin engine
and screens land in the Android repo.

Every push builds and tests on GitHub (an iPhone Simulator). Screenshots of each run are on the
[test-screens release](https://github.com/hubbub0/Mess-Machine-iOS/releases/tag/test-screens).

Clone with the shared code: `git clone --recurse-submodules https://github.com/hubbub0/Mess-Machine-iOS`, then
`xcodegen generate` and open `MessMachine.xcodeproj`.
