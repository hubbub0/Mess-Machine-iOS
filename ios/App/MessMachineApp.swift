import SwiftUI
#if canImport(MessMachine)
import MessMachine
#endif

@main
struct MessMachineApp: App {
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark) }
    }
}

/// The real Mess Machine screens (shared Compose, core/ui) when this build has the MessMachine framework. The day one
/// test screen stays for builds without it and for the `-dayOne` launch argument (its UI test). Only one of the two is
/// ever made, so there is only ever one sound engine and one Core Audio host.
struct RootView: View {
    static let dayOne = ProcessInfo.processInfo.arguments.contains("-dayOne")

    var body: some View {
        #if canImport(MessMachine)
        if Self.dayOne { DayOneRoot() } else { SharedScreens().ignoresSafeArea() }
        #else
        DayOneRoot()
        #endif
    }
}

#if canImport(MessMachine)
struct SharedScreens: UIViewControllerRepresentable {
    /// Lives as long as the app: AppState holds on to it.
    static let platform = IosPlatform()

    func makeUIViewController(context: Context) -> UIViewController {
        AppHooks.install()
        return MainViewControllerKt.MainViewController(platform: Self.platform)
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
#endif

struct DayOneRoot: View {
    @StateObject private var app = AppModel()

    var body: some View {
        DayOneView()
            .environmentObject(app)
            .environmentObject(app.audio)
            .environmentObject(app.mic)
            .environmentObject(app.midi)
            .environmentObject(app.notes)
            .environmentObject(app.bench)
            .environmentObject(app.voice)
            .onOpenURL { app.open($0) }
    }
}

/// Holds the iPhone pieces and wires them together. The shared AppState (Kotlin) replaces most of this later.
final class AppModel: ObservableObject {
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    let tone: ToneEngine
    let audio: AudioHost
    /// What makes the sound: the shared Kotlin engine when this build has it, else the stand-in tone.
    let engineName: String
    #if canImport(MessMachine)
    let shared: SharedEngine?
    #endif
    let mic = MicIn()
    let midi = MidiIn()
    let notes = NotesBook()
    let bench = Workbench()
    let voice = VoiceNote()
    let background = Background()

    @Published var mess: Mess?
    @Published var missing = 0
    @Published var shareURL: URL?
    @Published var say = ""
    @Published var flash = false
    /// The open mess's first pads (shared engine only), for the pad row.
    @Published var pads: [PadRef] = []
    @Published var loopPlaying = false

    init() {
        let rate = AudioHost.prepareSession()
        #if canImport(MessMachine)
        let se = try? SharedEngine(rate: rate)
        shared = se
        tone = se?.extra ?? ToneEngine()
        audio = AudioHost(engine: se ?? tone as BlockRenderer)
        engineName = se != nil ? "shared Kotlin engine" : "stand-in tone (the engine would not start)"
        #else
        tone = ToneEngine()
        audio = AudioHost(engine: tone)
        engineName = "stand-in tone"
        #endif
        _ = rate
        midi.onEvent = { [weak self] e in self?.midiEvent(e) }
        midi.start()
        Haptics.prepare()
        let b = bench
        mic.onSamples = { p, n, rate in b.feed(p, n, rate: rate) }
    }

    func togglePlay() {
        #if canImport(MessMachine)
        if let se = shared, mess != nil {
            if loopPlaying { se.stop(); loopPlaying = false; notes.trail("stop"); return }
            if !audio.running { startAudio() }
            se.play(); loopPlaying = true; notes.trail("play")
            return
        }
        #endif
        if audio.running {
            audio.stop(); background.stopped(); loopPlaying = false; notes.trail("stop")
        } else {
            startAudio()
            notes.trail("play")
        }
    }

    private func startAudio() {
        audio.start()
        do {
            background.playing(line: mess?.name ?? "Mess Machine") { [weak self] in
                DispatchQueue.main.async {
                    #if canImport(MessMachine)
                    self?.shared?.stop()
                    #endif
                    self?.loopPlaying = false
                    self?.audio.stop(); self?.background.stopped()
                }
            }
        }
    }

    /// A pad of the open mess, through the shared engine.
    func hit(pad: Int) {
        #if canImport(MessMachine)
        guard let se = shared else { return }
        if !audio.running { startAudio() }
        se.hit(pad: pad)
        Haptics.pad()
        notes.trail("pad \(pad + 1)")
        #endif
    }

    func hitPad(freq: Double = 220, strong: Bool = false) {
        #if canImport(MessMachine)
        if shared != nil, let first = pads.first { hit(pad: first.pad); return }
        #endif
        if !audio.running { startAudio() }
        tone.hit(freq: freq)
        Haptics.pad(strong: strong)
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flash = false }
        notes.trail("pad")
    }

    private func midiEvent(_ e: MidiEvent) {
        #if canImport(MessMachine)
        // notes 36 to 51 hit pads 1 to 16, as on Android
        if shared != nil, case let .down(n, _) = e, (36...51).contains(n) { hit(pad: n - 36); return }
        #endif
        if case let .down(n, v) = e {
            // middle C plays the sound's own pitch, as on Android; the test tone sits at A3 (220 Hz)
            hitPad(freq: 220 * pow(2, Double(n - 57) / 12), strong: v > 100)
        }
    }

    func toggleMic() {
        if mic.running {
            mic.stop()
            audio.configureSession(mic: false)
            notes.trail("mic off")
            return
        }
        MicIn.ask { ok in
            guard ok else { self.say = "The mic is off for Mess Machine. Turn it on in Settings, Privacy, Microphone."; return }
            let was = self.audio.running
            self.audio.configureSession(mic: true)
            if !self.mic.start() { self.say = "The mic would not open: \(self.mic.status)." }
            if was { self.audio.restart() }
            self.notes.trail("mic on")
        }
    }

    // MARK: Workbench

    /// Tap to start a take, tap again to keep it (Android: tap start, tap stop). Turns the mic on when needed.
    func toggleTake() {
        if bench.recording {
            if let b = bench.stopTake() { say = "Kept \(b.title) (\(String(format: "%.1f", b.seconds)) s)."; notes.trail("keep take") }
            else { say = "Nothing heard, so nothing kept." }
            return
        }
        if mic.running { bench.startTake(); say = "Recording. Tap again to keep it."; notes.trail("record take"); return }
        MicIn.ask { ok in
            guard ok else { self.say = "The mic is off for Mess Machine. Turn it on in Settings, Privacy, Microphone."; return }
            let was = self.audio.running
            self.audio.configureSession(mic: true)
            guard self.mic.start() else { self.say = "The mic would not open: \(self.mic.status)."; return }
            if was { self.audio.restart() }
            self.bench.startTake()
            self.say = "Recording. Tap again to keep it."
            self.notes.trail("record take")
        }
    }

    func play(_ b: BenchItem) {
        if !audio.running { startAudio() }
        let rate = audio.rate
        let bench = bench, tone = tone
        DispatchQueue.global(qos: .userInitiated).async { tone.play(bench.samples(of: b, at: rate)) }
        Haptics.pad()
        notes.trail("play sound")
    }

    func importSound(_ url: URL) {
        if let b = bench.importSound(url) { say = "Added \(b.title) to your Workbench."; notes.trail("import sound") }
        else { say = "That file isn't a sound this phone can read." }
    }

    // MARK: messes

    func openExample() {
        guard let url = Bundle.main.url(forResource: "example.mess", withExtension: "json") else { say = "The example mess is missing from this build."; return }
        open(url)
    }

    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bench = bench
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let loaded = try? Mess.load(text, known: { SoundLibrary.bundled.has($0) || bench.item(key: $0) != nil }) else {
            say = "That does not look like a Mess Machine file."
            return
        }
        mess = loaded.mess
        missing = loaded.missing
        #if canImport(MessMachine)
        if let se = shared {
            if loopPlaying { se.stop(); loopPlaying = false }
            pads = []
            let t = text
            DispatchQueue.global(qos: .userInitiated).async {
                se.open(t)
                let p = se.loadedPads()
                DispatchQueue.main.async { self.pads = p }
            }
        }
        #endif
        say = "Opened \(loaded.mess.name.isEmpty ? "a mess" : loaded.mess.name)."
            + (loaded.mess.newer ? " It was made by a newer Mess Machine, so some parts may not show here." : "")
        // write it back out in this app's own words, ready to share
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(loaded.mess.fileName)
        try? loaded.mess.text().write(to: out, atomically: true, encoding: .utf8)
        shareURL = out
        notes.trail("open mess")
    }

    // MARK: notes

    func noteDetails(cat: String) -> String {
        var d = "**Device:** \(NotesBook.device())\n**Audio:** \(audio.notesLine())\n"
        if cat == "bug", let m = mess { d += "**Mess:** \(m.summary)\n" }
        return d
    }

    func sendNote(cat: String, text: String) {
        let (c, topic, words) = NotesBook.parsePrefix(text, cat: cat, topic: "")
        guard !words.isEmpty else { say = "Write something first."; return }
        let n = MNote(id: NotesBook.newId(), cat: c, topic: topic, text: words, at: Date(), build: "ios \(Self.build)", screen: "day one")
        notes.add(n)
        notes.send(n, details: noteDetails(cat: c)) { [weak self] msg in self?.say = msg }
    }
}
