import SwiftUI
import UniformTypeIdentifiers

/// The day-one shell: every iPhone-only piece, working, on one screen, until the shared Compose screens arrive.
/// Sound (the Core Audio host with a test tone standing in for the engine), mic, MIDI, mess files and notes.
struct DayOneView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var audio: AudioHost
    @EnvironmentObject var mic: MicIn
    @EnvironmentObject var midi: MidiIn
    @EnvironmentObject var notes: NotesBook
    @EnvironmentObject var bench: Workbench

    @State private var importing = false
    @State private var importingSound = false
    @State private var noteOpen = false
    @State private var bluetoothOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                soundPanel
                micPanel
                benchPanel
                midiPanel
                messPanel
                if !app.say.isEmpty {
                    Text(app.say).font(F.text(13)).foregroundStyle(Ink.cream)
                        .accessibilityIdentifier("status-line")
                }
            }
            .padding(16)
        }
        .background(Ink.paper.ignoresSafeArea())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case let .success(url) = r { app.open(url) }
        }
        .sheet(isPresented: $noteOpen) {
            NoteSheet().environmentObject(app).environmentObject(notes).environmentObject(app.voice)
        }
        .sheet(isPresented: $bluetoothOpen) { BluetoothMidiPicker().ignoresSafeArea() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MESS MACHINE").font(F.heading(28)).foregroundStyle(Ink.teal)
                    .shadow(color: Ink.pink, radius: 0, x: 2, y: 2)
                Text("iPhone build \(AppModel.build) · test screen: the shared engine and the iPhone pieces, before the shared screens")
                    .font(F.mono(11)).foregroundStyle(Ink.dim)
            }
            Spacer()
            Key(label: "Bug", tag: "bar-notes") { noteOpen = true }
        }
    }

    private var soundPanel: some View {
        Panel(title: "Sound") {
            Button {
                app.hitPad()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Ink.card2)
                    RoundedRectangle(cornerRadius: 10).stroke(app.flash ? Ink.yellow : Ink.teal, lineWidth: 3)
                    Text(audio.running ? "HIT ME" : "START SOUND").font(F.heading(22)).foregroundStyle(Ink.cream)
                }
                .frame(height: 120)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pad-0")
            HStack {
                let on = app.mess != nil && app.pads.count > 0 ? app.loopPlaying : audio.running
                Key(label: on ? "Stop" : (app.mess != nil && !app.pads.isEmpty ? "Play loop" : "Play"), lit: on, tag: "bar-play") { app.togglePlay() }
            }
            if !app.pads.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(app.pads) { p in
                        Button { app.hit(pad: p.pad) } label: {
                            Text(Self.padName(p.key)).font(F.text(11)).foregroundStyle(Ink.cream).lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Ink.card2)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.teal.opacity(0.7), lineWidth: 2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mess-pad-\(p.pad)")
                    }
                }
            }
            Readout(label: "Engine", value: app.engineName, tag: "audio-engine")
            Readout(label: "Path", value: audio.path, tag: "audio-path")
            Readout(label: "Writer", value: audio.realtime ? "real-time thread" : "normal thread", tag: "audio-writer")
            Readout(label: "Rate", value: "\(audio.rate) Hz")
            Readout(label: "Ring", value: "\(audio.fill) frames")
            Readout(label: "Device", value: "\(audio.deviceFrames) frames a callback")
            Readout(label: "Out", value: audio.outputMs < 0 ? "not known yet" : String(format: "%.1f ms", audio.outputMs))
            Readout(label: "Clicks", value: "\(audio.clicks)", tag: "audio-clicks")
            Readout(label: "Route", value: audio.route)
            if !audio.status.isEmpty { Text(audio.status).font(F.mono(11)).foregroundStyle(Ink.dim) }
        }
    }

    /// "samples/basement-kick.wav" -> "basement kick"; "synth:1" -> "synth 1".
    static func padName(_ key: String) -> String {
        var k = key
        if let slash = k.lastIndex(of: "/") { k = String(k[k.index(after: slash)...]) }
        if let dot = k.lastIndex(of: "."), k.distance(from: dot, to: k.endIndex) <= 5 { k = String(k[..<dot]) }
        return k.replacingOccurrences(of: ":", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    private var micPanel: some View {
        Panel(title: "Mic") {
            HStack {
                Key(label: mic.running ? "Mic off" : "Mic on", lit: mic.running, tag: "mic-toggle") { app.toggleMic() }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.ink)
                        Capsule().fill(Ink.pink).frame(width: max(4, g.size.width * CGFloat(min(1, mic.level))))
                    }
                }
                .frame(height: 12)
                .accessibilityIdentifier("mic-level")
            }
            Text(mic.status).font(F.mono(11)).foregroundStyle(Ink.dim)
        }
    }

    private var benchPanel: some View {
        Panel(title: "Workbench") {
            HStack(spacing: 8) {
                Key(label: bench.recording ? String(format: "Keep %.1fs", bench.recordSeconds) : "Record", lit: bench.recording, tag: "mic") { app.toggleTake() }
                Key(label: "Import", tag: "import") { importingSound = true }
            }
            if bench.items.isEmpty {
                Text("Mic takes and sounds you bring in land here.").font(F.mono(11)).foregroundStyle(Ink.dim)
            }
            ForEach(bench.items.prefix(5)) { b in
                HStack {
                    Key(label: "Play", tag: "bench-play-\(b.id)") { app.play(b) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).font(F.text(13)).foregroundStyle(Ink.cream).lineLimit(1)
                        Text(String(format: "%@ · %.1f s", b.kind == "mic" ? "mic take" : "import", b.seconds)).font(F.mono(10)).foregroundStyle(Ink.dim)
                    }
                    Spacer()
                    Button { bench.remove(b) } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Ink.dim).frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("bench-remove-\(b.id)")
                }
            }
        }
        .fileImporter(isPresented: $importingSound, allowedContentTypes: [.audio]) { r in
            if case let .success(url) = r { app.importSound(url) }
        }
    }

    private var midiPanel: some View {
        Panel(title: "MIDI in") {
            Readout(label: "Devices", value: midi.devices.isEmpty ? "none plugged in" : midi.devices.joined(separator: ", "), tag: "midi-devices")
            Readout(label: "Last", value: midi.last, tag: "midi-last")
            Key(label: "Bluetooth", tag: "midi-bluetooth") { bluetoothOpen = true }
        }
    }

    private var messPanel: some View {
        Panel(title: "Messes") {
            HStack(spacing: 8) {
                Key(label: "Example", tag: "file-example") { app.openExample() }
                Key(label: "Open", tag: "file-open") { importing = true }
                if let url = app.shareURL {
                    ShareLink(item: url) {
                        Text("SHARE").font(F.text(13)).tracking(1).foregroundStyle(Ink.cream)
                            .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44)
                            .background(Ink.card2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.yellow.opacity(0.45), lineWidth: 1.5))
                    }
                    .accessibilityIdentifier("file-share")
                }
            }
            if let m = app.mess {
                Readout(label: "Mess", value: m.summary, tag: "mess-summary")
                if app.missing > 0 {
                    Text("\(app.missing) pads use sounds this phone does not have. They show as Missing and stay in the mess.")
                        .font(F.mono(11)).foregroundStyle(Ink.riot)
                }
            }
            Readout(label: "Built-in sounds", value: "\(SoundLibrary.bundled.count) known keys")
        }
    }
}

/// The note sheet: kind, words, Send. Same kinds and prefixes as Android.
struct NoteSheet: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var notes: NotesBook
    @EnvironmentObject var voice: VoiceNote
    @Environment(\.dismiss) private var dismiss
    @State private var cat = "bug"
    @State private var text = ""
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NOTE TO CLAUDE").font(F.heading(20)).foregroundStyle(Ink.yellow)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(Ink.cream)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("sheet-close")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(NoteKinds.all.map { $0.0 }, id: \.self) { c in
                        Key(label: NoteKinds.label(c), lit: cat == c, tag: "note-cat-\(c)") { cat = c }
                    }
                }
            }
            TextField("What happened, or what you want", text: $text, axis: .vertical)
                .lineLimit(4...8)
                .font(F.text(15))
                .padding(10)
                .background(Ink.card2)
                .foregroundStyle(Ink.cream)
                .accessibilityIdentifier("note-text")
            HStack(spacing: 8) {
                Key(label: voice.listening ? "Done talking" : "Say it", lit: voice.listening, tag: "note-voice") {
                    if voice.listening { voice.stop() } else { voice.start { app.audio.configureSession(mic: true) } }
                }
                Key(label: "Send", tag: "note-send") {
                    voice.stop()
                    app.sendNote(cat: cat, text: text)
                    dismiss()
                }
            }
            if !voice.status.isEmpty { Text(voice.status).font(F.mono(11)).foregroundStyle(Ink.dim) }
            Text(Keychain.get("notes-key") == nil
                 ? "No key yet: Send opens the filled-in GitHub page and you tap Submit there."
                 : "Send posts the note straight to Claude.")
                .font(F.mono(11)).foregroundStyle(Ink.dim)
            HStack {
                SecureField("Paste a notes key (optional)", text: $key)
                    .font(F.mono(12)).padding(8).background(Ink.card2).foregroundStyle(Ink.cream)
                    .accessibilityIdentifier("note-key")
                Key(label: "Keep", tag: "note-key-save") { if !key.isEmpty { Keychain.set("notes-key", key); key = "" } }
            }
            HStack {
                Text("YOUR NOTES").font(F.heading(14)).foregroundStyle(Ink.yellow)
                Spacer()
                Key(label: notes.checking ? "Checking" : "Replies", tag: "note-check") { notes.checkReplies() }
            }
            if !notes.lastMessage.isEmpty { Text(notes.lastMessage).font(F.mono(11)).foregroundStyle(Ink.dim) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if notes.notes.isEmpty { Text("Nothing sent yet.").font(F.mono(11)).foregroundStyle(Ink.dim) }
                    ForEach(notes.notes.prefix(20)) { n in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(NotesBook.title(n)).font(F.text(13)).foregroundStyle(Ink.cream)
                            Text((n.issue > 0 ? "#\(n.issue) · " : "") + (n.status.isEmpty ? "kept on the phone" : n.status))
                                .font(F.mono(10)).foregroundStyle(n.status == "fixed" ? Ink.teal : Ink.dim)
                            ForEach(Array((n.replies ?? []).enumerated()), id: \.offset) { _, r in
                                Text(r).font(F.mono(11)).foregroundStyle(Ink.yellow).padding(.leading, 8)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.card)
                    }
                }
            }
        }
        .padding(16)
        .background(Ink.paper.ignoresSafeArea())
        .onChange(of: voice.heard) { _, h in if !h.isEmpty { text = h } }
        .onDisappear { voice.stop() }
    }
}
