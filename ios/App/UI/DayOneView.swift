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

    @State private var importing = false
    @State private var noteOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                soundPanel
                micPanel
                midiPanel
                messPanel
                if !app.say.isEmpty {
                    Text(app.say).font(F.text(13)).foregroundStyle(C.cream)
                        .accessibilityIdentifier("status-line")
                }
            }
            .padding(16)
        }
        .background(C.paper.ignoresSafeArea())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case let .success(url) = r { app.open(url) }
        }
        .sheet(isPresented: $noteOpen) { NoteSheet().environmentObject(app).environmentObject(notes) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MESS MACHINE").font(F.heading(28)).foregroundStyle(C.teal)
                    .shadow(color: C.pink, radius: 0, x: 2, y: 2)
                Text("iPhone build \(AppModel.build) · day one: the iPhone pieces, before the shared engine")
                    .font(F.mono(11)).foregroundStyle(C.dim)
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
                    RoundedRectangle(cornerRadius: 10).fill(C.card2)
                    RoundedRectangle(cornerRadius: 10).stroke(app.flash ? C.yellow : C.teal, lineWidth: 3)
                    Text(audio.running ? "HIT ME" : "START SOUND").font(F.heading(22)).foregroundStyle(C.cream)
                }
                .frame(height: 120)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pad-0")
            HStack {
                Key(label: audio.running ? "Stop" : "Play", lit: audio.running, tag: "bar-play") { app.togglePlay() }
            }
            Readout(label: "Path", value: audio.path, tag: "audio-path")
            Readout(label: "Writer", value: audio.realtime ? "real-time thread" : "normal thread", tag: "audio-writer")
            Readout(label: "Rate", value: "\(audio.rate) Hz")
            Readout(label: "Ring", value: "\(audio.fill) frames")
            Readout(label: "Device", value: "\(audio.deviceFrames) frames a callback")
            Readout(label: "Out", value: audio.outputMs < 0 ? "not known yet" : String(format: "%.1f ms", audio.outputMs))
            Readout(label: "Clicks", value: "\(audio.clicks)", tag: "audio-clicks")
            Readout(label: "Route", value: audio.route)
            if !audio.status.isEmpty { Text(audio.status).font(F.mono(11)).foregroundStyle(C.dim) }
        }
    }

    private var micPanel: some View {
        Panel(title: "Mic") {
            HStack {
                Key(label: mic.running ? "Mic off" : "Mic on", lit: mic.running, tag: "mic-toggle") { app.toggleMic() }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(C.ink)
                        Capsule().fill(C.pink).frame(width: max(4, g.size.width * CGFloat(min(1, mic.level))))
                    }
                }
                .frame(height: 12)
                .accessibilityIdentifier("mic-level")
            }
            Text(mic.status).font(F.mono(11)).foregroundStyle(C.dim)
        }
    }

    private var midiPanel: some View {
        Panel(title: "MIDI in") {
            Readout(label: "Devices", value: midi.devices.isEmpty ? "none plugged in" : midi.devices.joined(separator: ", "), tag: "midi-devices")
            Readout(label: "Last", value: midi.last, tag: "midi-last")
        }
    }

    private var messPanel: some View {
        Panel(title: "Messes") {
            HStack(spacing: 8) {
                Key(label: "Example", tag: "file-example") { app.openExample() }
                Key(label: "Open", tag: "file-open") { importing = true }
                if let url = app.shareURL {
                    ShareLink(item: url) {
                        Text("SHARE").font(F.text(13)).tracking(1).foregroundStyle(C.cream)
                            .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44)
                            .background(C.card2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(C.yellow.opacity(0.45), lineWidth: 1.5))
                    }
                    .accessibilityIdentifier("file-share")
                }
            }
            if let m = app.mess {
                Readout(label: "Mess", value: m.summary, tag: "mess-summary")
                if app.missing > 0 {
                    Text("\(app.missing) pads used sounds that only live on the site, so they are empty here.")
                        .font(F.mono(11)).foregroundStyle(C.riot)
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
    @Environment(\.dismiss) private var dismiss
    @State private var cat = "bug"
    @State private var text = ""
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NOTE TO CLAUDE").font(F.heading(20)).foregroundStyle(C.yellow)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(C.cream)
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
                .background(C.card2)
                .foregroundStyle(C.cream)
                .accessibilityIdentifier("note-text")
            Key(label: "Send", tag: "note-send") {
                app.sendNote(cat: cat, text: text)
                dismiss()
            }
            Text(Keychain.get("notes-key") == nil
                 ? "No key yet: Send opens the filled-in GitHub page and you tap Submit there."
                 : "Send posts the note straight to Claude.")
                .font(F.mono(11)).foregroundStyle(C.dim)
            HStack {
                SecureField("Paste a notes key (optional)", text: $key)
                    .font(F.mono(12)).padding(8).background(C.card2).foregroundStyle(C.cream)
                    .accessibilityIdentifier("note-key")
                Key(label: "Keep", tag: "note-key-save") { if !key.isEmpty { Keychain.set("notes-key", key); key = "" } }
            }
            Spacer()
        }
        .padding(16)
        .background(C.paper.ignoresSafeArea())
    }
}
