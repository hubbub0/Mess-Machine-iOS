import CoreMIDI
import Foundation

/// What a MIDI device asked for, in the words Android's AppState uses (midiDown, midiUp, midiCc, midiBend).
enum MidiEvent: Equatable {
    case down(note: Int, vel: Int)
    case up(note: Int)
    case cc(num: Int, val: Int)
    /// -1 ... 1, 0 is no bend
    case bend(Float)
}

/// Reads note on, note off, control change and pitch bend from the bytes a device sends. A line-for-line port of
/// the Parser in Android's Midi.kt, running status and all, so both apps read a controller the same way.
struct MidiParser {
    private var status = 0
    private var d1 = -1

    mutating func feed<S: Sequence>(_ bytes: S) -> [MidiEvent] where S.Element == UInt8 {
        var out: [MidiEvent] = []
        for byte in bytes {
            let b = Int(byte)
            if b >= 0xF8 { continue } // clock and other real-time bytes can arrive anywhere
            if b >= 0x80 { status = b; d1 = -1; continue }
            // program change and channel pressure carry one data byte, not two: skip it, or every pair after it is off by one
            if (status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0 { continue }
            if d1 < 0 { d1 = b; continue }
            let note = d1, vel = b
            d1 = -1 // running status: the next pair uses the same status
            switch status & 0xF0 {
            case 0x90: out.append(vel > 0 ? .down(note: note, vel: vel) : .up(note: note))
            case 0x80: out.append(.up(note: note))
            case 0xB0: out.append(.cc(num: note, val: vel))
            case 0xE0: out.append(.bend(Float(((vel << 7) | note) - 8192) / 8192))
            default: break
            }
        }
        return out
    }

    /// The MIDI 1.0 bytes inside one Universal MIDI Packet message (type 2, MIDI 1.0 channel voice). Other types: none.
    static func bytes(ofUMP word: UInt32) -> [UInt8] {
        guard word >> 28 == 0x2 else { return [] }
        return [UInt8((word >> 16) & 0xFF), UInt8((word >> 8) & 0x7F), UInt8(word & 0x7F)]
    }
}

/// MIDI in over USB (MM-12 on Android). Every source is listened to; plugging in or out is noticed.
/// Notes 36 to 51 hit pads 1 to 16 of the bank on screen; the rest play the selected pad as keys (the shared
/// screens will do that mapping; here the events are handed on).
final class MidiIn: ObservableObject {
    @Published private(set) var devices: [String] = []
    @Published private(set) var last = "nothing yet"

    var onEvent: ((MidiEvent) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var parsers: [MIDIEndpointRef: MidiParser] = [:]
    private let lock = NSLock()

    func start() {
        guard client == 0 else { return }
        let ok = MIDIClientCreateWithBlock("Mess Machine" as CFString, &client) { [weak self] note in
            if note.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.connectAll() } }
        }
        guard ok == noErr else { last = "MIDI would not start (\(ok))"; return }
        let p = MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { [weak self] list, src in
            self?.received(list, from: src)
        }
        guard p == noErr else { last = "MIDI input would not open (\(p))"; return }
        connectAll()
    }

    func stop() {
        if port != 0 { MIDIPortDispose(port); port = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
        devices = []
    }

    private func connectAll() {
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(port, src, UnsafeMutableRawPointer(bitPattern: Int(src)))
            names.append(Self.name(of: src))
        }
        let before = Set(devices)
        devices = names
        if let new = names.first(where: { !before.contains($0) }) {
            last = "\(new) plugged in. Notes 36 to 51 hit pads 1 to 16; the rest play the selected pad as keys."
        }
    }

    static func name(of e: MIDIEndpointRef) -> String {
        var s: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s) == noErr, let v = s?.takeRetainedValue() { return v as String }
        return "a MIDI device"
    }

    /// Called on CoreMIDI's own thread. Parses, then hands events to the main thread.
    private func received(_ list: UnsafePointer<MIDIEventList>, from src: UnsafeMutableRawPointer?) {
        let key = MIDIEndpointRef(UInt(bitPattern: src))
        var words: [UInt32] = []
        for packet in list.unsafeSequence() {
            let n = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let w = raw.bindMemory(to: UInt32.self)
                for i in 0..<min(n, w.count) { words.append(w[i]) }
            }
        }
        lock.lock()
        var parser = parsers[key] ?? MidiParser()
        var events: [MidiEvent] = []
        for w in words { events += parser.feed(MidiParser.bytes(ofUMP: w)) }
        parsers[key] = parser
        lock.unlock()
        guard !events.isEmpty else { return }
        DispatchQueue.main.async {
            for e in events { self.onEvent?(e) }
            if let e = events.last { self.last = Self.describe(e) }
        }
    }

    static func describe(_ e: MidiEvent) -> String {
        switch e {
        case let .down(n, v): return n >= 36 && n <= 51 ? "Note \(n) (pad \(n - 35)), velocity \(v)" : "Note \(n), velocity \(v)"
        case let .up(n): return "Note \(n) off"
        case let .cc(c, v): return "Knob \(c) to \(v)"
        case let .bend(b): return String(format: "Pitch wheel %.2f", b)
        }
    }
}
