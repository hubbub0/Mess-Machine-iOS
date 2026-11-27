import AVFoundation
import Foundation

/// One sound of your own: a mic take or an import (Android: BenchSound in Workbench.kt). Its key is `bn:<id>`,
/// the same family Android uses, so a mess that names it loads on the device that made it.
struct BenchSound: Codable, Identifiable, Equatable {
    var id: String
    var kind: String        // "mic" or "imp", as on Android
    var title: String
    var at: Date
    var seconds: Double

    var key: String { "bn:" + id }
}

/// Your Workbench: mic takes and imported sounds, kept as WAV files in the app's own storage (Documents/bench),
/// with an index next to them. Chops, resamples and saved edits come with the shared engine.
final class Workbench: ObservableObject {
    @Published private(set) var items: [BenchSound] = []
    @Published private(set) var recording = false
    @Published private(set) var recordSeconds = 0.0

    let dir: URL
    private var index: URL { dir.appendingPathComponent("bench.json") }

    // the take being recorded: filled on the mic's thread, read on the main thread
    private let lock = NSLock()
    private var take: [Float] = []
    private var takeRate = 48000.0

    init(dir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bench")) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: index), let list = try? JSONDecoder().decode([BenchSound].self, from: d) {
            items = list.filter { FileManager.default.fileExists(atPath: url(of: $0).path) }
        }
    }

    func url(of b: BenchSound) -> URL { dir.appendingPathComponent(b.id + ".wav") }

    func item(key: String) -> BenchSound? { items.first { $0.key == key } }

    private func saveIndex() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: index, options: .atomic) }
    }

    static func newId() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 100...999))
    }

    // MARK: mic takes

    /// Start keeping what the mic hears. MicIn hands samples to `feed` while this is on.
    func startTake() {
        lock.lock(); take.removeAll(keepingCapacity: true); lock.unlock()
        recording = true
        recordSeconds = 0
    }

    /// Called on the mic's own thread.
    func feed(_ p: UnsafePointer<Float>, _ n: Int, rate: Double) {
        guard recording else { return }
        lock.lock()
        takeRate = rate
        // ten minutes at most, like a sensible take
        if Double(take.count) < rate * 600 { take.append(contentsOf: UnsafeBufferPointer(start: p, count: n)) }
        let secs = Double(take.count) / rate
        lock.unlock()
        DispatchQueue.main.async { self.recordSeconds = secs }
    }

    /// Stop and keep the take. Returns nil when nothing was heard.
    @discardableResult
    func stopTake() -> BenchSound? {
        recording = false
        lock.lock(); let s = take; let r = takeRate; take.removeAll(); lock.unlock()
        let trimmed = Self.trimSilence(s, rate: r)
        guard trimmed.count > Int(r * 0.05) else { return nil }
        let n = items.filter { $0.kind == "mic" }.count + 1
        return keep(samples: trimmed, rate: r, kind: "mic", title: "Mic take \(n)")
    }

    /// Takes start and end where the sound does: quiet edges under -50 dB are cut, with 10 ms kept either side.
    static func trimSilence(_ s: [Float], rate: Double = 48000) -> [Float] {
        let floor: Float = 0.00316
        guard let a = s.firstIndex(where: { abs($0) > floor }), let b = s.lastIndex(where: { abs($0) > floor }) else { return [] }
        let pad = Int(rate * 0.01)
        return Array(s[max(0, a - pad)...min(s.count - 1, b + pad)])
    }

    /// Write mono samples as a 16-bit WAV and add it to the bench.
    @discardableResult
    func keep(samples: [Float], rate: Double, kind: String, title: String) -> BenchSound? {
        let b = BenchSound(id: Self.newId(), kind: kind, title: title, at: Date(), seconds: Double(samples.count) / rate)
        do {
            try WavFile.write(samples, channels: 1, rate: Int(rate.rounded()), to: url(of: b))
        } catch { return nil }
        items.insert(b, at: 0)
        saveIndex()
        return b
    }

    // MARK: imports

    /// Bring in any audio file iOS can read (WAV, AIFF, MP3, M4A, FLAC, CAF). It is kept as WAV, mixed to mono.
    func importSound(_ src: URL) -> BenchSound? {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        guard let (mono, rate) = try? Self.readMono(src) , !mono.isEmpty else { return nil }
        let title = src.deletingPathExtension().lastPathComponent
        return keep(samples: mono, rate: rate, kind: "imp", title: String(title.prefix(40)))
    }

    func remove(_ b: BenchSound) {
        try? FileManager.default.removeItem(at: url(of: b))
        items.removeAll { $0.id == b.id }
        saveIndex()
    }

    /// Read any file as mono float at its own rate.
    static func readMono(_ url: URL) throws -> ([Float], Double) {
        let f = try AVAudioFile(forReading: url)
        let fmt = f.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(f.length)) else { return ([], fmt.sampleRate) }
        try f.read(into: buf)
        let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
        guard let data = buf.floatChannelData, n > 0 else { return ([], fmt.sampleRate) }
        var out = [Float](repeating: 0, count: n)
        for c in 0..<ch { for i in 0..<n { out[i] += data[c][i] / Float(ch) } }
        return (out, fmt.sampleRate)
    }

    /// A sound ready for the engine: mono at the engine's rate (linear resample; the shared engine has its own).
    func samples(of b: BenchSound, at rate: Int) -> [Float] {
        guard let (s, r) = try? Self.readMono(url(of: b)) else { return [] }
        return Self.resample(s, from: r, to: Double(rate))
    }

    static func resample(_ s: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !s.isEmpty, from > 0, to > 0 else { return s }
        let n = Int((Double(s.count) * to / from).rounded())
        var out = [Float](repeating: 0, count: n)
        let step = from / to
        for i in 0..<n {
            let x = Double(i) * step
            let a = Int(x), f = Float(x - Double(a))
            let v0 = s[min(a, s.count - 1)], v1 = s[min(a + 1, s.count - 1)]
            out[i] = v0 + (v1 - v0) * f
        }
        return out
    }
}

/// Plain 16-bit PCM WAV writing, the format Android's Workbench keeps.
enum WavFile {
    static func write(_ samples: [Float], channels: Int, rate: Int, to url: URL) throws {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + bytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(rate)); u32(UInt32(rate * channels * 2)); u16(UInt16(channels * 2)); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(bytes))
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * 32767).littleEndian }
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        try d.write(to: url, options: .atomic)
    }
}
