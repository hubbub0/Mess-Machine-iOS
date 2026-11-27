import AVFoundation
import Foundation
import Network
import UIKit
import UniformTypeIdentifiers

#if canImport(MessMachine)
import MessMachine

/// The iPhone's Platform for the shared AppState (core/ui, CMP step 7). Settings, the main thread, the worker and the
/// file store are the Kotlin ones from IosBasics.kt; everything that talks to the phone is here, in Swift, built on the
/// pieces this repo already had (AudioHost, MicIn, Workbench, VoiceNote, Notes, Background).
final class IosPlatform: NSObject, Platform {
    let device: Device
    let settings: Settings = IosSettings(prefix: "mess.")
    let main: MainThread = IosMainThread()
    let worker: Worker = IosWorker(name: "mess-worker")
    let files: FileStore = IosFileStore.shared
    let filesDir: String
    let cacheDir: String

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path
        filesDir = docs
        cacheDir = caches
        device = IosDevice(filesDir: docs)
        super.init()
        MFile.Companion.shared.store = IosFileStore.shared
    }

    func audioOut(engine: Engine, rate: Int32, burst: Int32) -> AudioOut { IosAudioOut(engine: engine) }
    func bench(lib: Library) -> Bench { IosBench(dir: filesDir + "/bench", lib: lib) }
    func notes() -> NoteBook { IosNoteBook(dir: filesDir, device: device) }
    func packs(lib: Library) -> Packs { IosPacks(root: filesDir, lib: lib) }
    func speech(heard: @escaping (String) -> Void, done: @escaping (String, String?) -> Void) -> SpeechIn {
        IosSpeechIn(heard: heard, done: done)
    }
    func updater() -> AppUpdater { IosAppUpdater(current: (device as? IosDevice)?.buildCode ?? 0) }
    func mouthIn() -> MouthIn { IosMouthIn() }
}

// MARK: - the phone

final class IosDevice: NSObject, Device {
    private let filesDir: String
    private let monitor = NWPathMonitor()
    private var expensive = false
    private let background = Background()

    init(filesDir: String) {
        self.filesDir = filesDir
        super.init()
        monitor.pathUpdateHandler = { [weak self] p in self?.expensive = p.isExpensive || p.isConstrained }
        monitor.start(queue: DispatchQueue(label: "mess-net"))
    }

    /// Files bundled with the app: the Android app's assets folder (sounds/..., guide.json).
    func readAsset(path: String) -> KotlinByteArray {
        // Kotlin's file reader copies in one go (a Swift loop would cross into Kotlin once per byte); it throws on a
        // missing file, and a Kotlin throw through Swift ends the app, so check first
        let full = Bundle.main.bundlePath + "/assets/" + path
        guard !path.split(separator: "/").contains(".."), FileManager.default.fileExists(atPath: full) else { return KotlinByteArray(size: 0) }
        return IosFileStore.shared.readBytes(path: full)
    }

    var outputRate: KotlinInt? { KotlinInt(int: Int32(AudioHost.prepareSession())) }
    var outputBurst: KotlinInt? {
        let s = AVAudioSession.sharedInstance()
        let f = Int32((s.ioBufferDuration * s.sampleRate).rounded())
        return f > 0 ? KotlinInt(int: f) : nil
    }
    func uptimeMillis() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
    func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    func nanoTime() -> Int64 { mm_now_ns() }
    var isTestRun: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func backgroundPlay(on: Bool) -> Bool {
        DispatchQueue.main.async {
            if on { self.background.playing(line: "Mess Machine") { NotificationCenter.default.post(name: .messStopFromLockScreen, object: nil) } }
            else { self.background.stopped() }
        }
        return true
    }

    func shareFile(f: MFile, mime: String, title: String, subject: Bool) {
        let url = URL(fileURLWithPath: f.path)
        DispatchQueue.main.async { Self.present(UIActivityViewController(activityItems: [url], applicationActivities: nil)) }
    }

    func shareText(text: String, title: String) {
        DispatchQueue.main.async { Self.present(UIActivityViewController(activityItems: [text], applicationActivities: nil)) }
    }

    static func present(_ vc: UIViewController) {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        if let pop = vc.popoverPresentationController {  // iPad: anchor the sheet somewhere
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(vc, animated: true)
    }

    func hasMicPermission() -> Bool { AVAudioApplication.shared.recordPermission == .granted }

    func screenDp() -> KotlinPair<KotlinInt, KotlinInt> {
        let b = UIScreen.main.bounds
        return KotlinPair(first: KotlinInt(int: Int32(b.width)), second: KotlinInt(int: Int32(b.height)))
    }

    func unmeteredNetwork() -> Bool { !expensive }
    func clipboardText() -> String { UIPasteboard.general.hasStrings ? (UIPasteboard.general.string ?? "") : "" }

    /// A picked file: the document picker hands its file URL as the address (see AppHooks.pick).
    func readUri(uri: String) -> KotlinByteArray? {
        guard let url = URL(string: uri) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return IosFileStore.shared.readBytes(path: url.path)
    }

    func displayName(uri: String) -> String { URL(string: uri)?.lastPathComponent.removingPercentEncoding ?? "" }

    var buildCode: Int32 { Int32(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    var buildVersion: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1") + ".\(buildCode)" }
    var gitSha: String { Bundle.main.object(forInfoDictionaryKey: "MMGitSha") as? String ?? "local" }
    var siteHost: String { Bundle.main.object(forInfoDictionaryKey: "MMSiteHost") as? String ?? "" }

    func describe() -> String { NotesBook.device() }

    /// The speaker check needs the mic and the speaker at once; not on iPhone yet.
    func speakerTest(engine: Engine, rate: Int32, click: Sample) -> KotlinPair<KotlinDouble, NSString> {
        KotlinPair(first: KotlinDouble(double: -1), second: "The speaker check is not on iPhone yet." as NSString)
    }

    func writeZip(f: MFile, entries: [KotlinPair<NSString, KotlinByteArray>]) {
        let list = entries.compactMap { p -> (String, Data)? in
            guard let n = p.first as String?, let b = p.second else { return nil }
            return (n, b.data())
        }
        try? Zip.store(list).write(to: URL(fileURLWithPath: f.path), options: .atomic)
    }

    func thread(name: String, f: @escaping () -> Void) {
        let t = Thread { f() }
        t.name = name
        t.start()
    }

    func lowWorker(name: String) -> Worker { IosWorker(name: name) }
    func cloudTokens() -> TokenStore { KeychainTokens() }
    func cloudCache() -> CloudCache { FileCloudCache(dir: filesDir + "/cloud") }
}

extension Notification.Name {
    static let messStopFromLockScreen = Notification.Name("messStopFromLockScreen")
}

final class KeychainTokens: NSObject, TokenStore {
    func load() -> String? { Keychain.get("cloud-session") }
    func save(json: String?) { if let j = json { Keychain.set("cloud-session", j) } else { Keychain.remove("cloud-session") } }
}

final class FileCloudCache: NSObject, CloudCache {
    let dir: String
    init(dir: String) {
        self.dir = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    func load(name: String) -> String? { try? String(contentsOfFile: dir + "/" + name, encoding: .utf8) }
    func save(name: String, json: String?) {
        let p = dir + "/" + name
        if let j = json { try? j.write(toFile: p, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(atPath: p) }
    }
}

// MARK: - sound out

/// The engine to the speaker through this repo's Core Audio host: the writer thread asks for a real-time schedule,
/// waits on the callback's semaphore, and renders with Engine.renderInto (nothing created per block).
final class IosAudioOut: NSObject, AudioOut, BlockRenderer {
    let engine: Engine
    private(set) lazy var host = AudioHost(engine: self)
    var useAAudio: Bool = true
    var growCap: Int32 = 3 { didSet { host.growCap = Int(growCap) } }
    var lastSlowFrameNanos: Int64 = 0
    private var clickTimes: [Date] = []
    private var lastClicks = 0
    private var renderNs: Double = 0
    private var peak: Float = 0
    private var loudest: Float = 0
    private let statLock = NSLock()

    /// The one sound output (AppState makes it once), for the app's lifecycle and the test meter.
    static weak var current: IosAudioOut?

    init(engine: Engine) {
        self.engine = engine
        super.init()
        Self.current = self
        NotificationCenter.default.addObserver(forName: .messStopFromLockScreen, object: nil, queue: .main) { [weak self] _ in self?.engine.stop() }
        // Stopgap until IosApp (core PR #26): nothing in the shared code starts the sound on iPhone, so it starts here,
        // as Android's MainActivity.onStart does.
        DispatchQueue.main.async { if UIApplication.shared.applicationState != .background { self.host.start() } }
    }

    func render(_ buf: UnsafeMutablePointer<Float>, frames: Int, rate: Int) {
        let t0 = mm_now_ns()
        engine.renderInto(out: buf, frames: Int32(frames))
        let dt = Double(mm_now_ns() - t0)
        var p: Float = 0
        for i in 0..<(frames * 2) { let v = abs(buf[i]); if v > p { p = v } }
        statLock.lock()
        renderNs = renderNs == 0 ? dt : renderNs * 0.98 + dt * 0.02
        peak = max(p, peak * 0.9)
        loudest = max(loudest, p)
        statLock.unlock()
    }

    /// The level now (decaying peak) and the loudest block since the app started, both 0 to 1.
    func levels() -> (now: Float, loudest: Float) { statLock.lock(); defer { statLock.unlock() }; return (peak, loudest) }

    func start() { onMain { self.host.start() } }
    /// Stopgap until IosApp (core PR #26): AppState stops the sound only when it thinks the app is off screen, and on
    /// iPhone nothing tells it the app is on screen, so a stop while the app is showing is ignored.
    func stop() { onMain { if UIApplication.shared.applicationState == .active { return }; self.host.stop() } }

    /// The app came back on screen (Android: onStart).
    func appShown() { onMain { self.host.start() } }
    /// The app left the screen (Android: onStop): keep sounding only while the music plays and Settings allows it.
    func appHidden(backgroundPlay: Bool) {
        onMain { if !(self.engine.isPlaying() && backgroundPlay) { self.host.stop() } }
    }
    func restart() { onMain { self.host.stop(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.host.start() } } }

    private func onMain(_ f: @escaping () -> Void) { Thread.isMainThread ? f() : DispatchQueue.main.async(execute: f) }

    var bufferFrames: Int32 { Int32(host.fill) }
    var underruns: Int32 { Int32(mm_clicks()) }
    var outputMs: Double { host.outputMs }
    var fastPath: String { host.realtime ? "Core Audio, real-time writer" : "Core Audio" }
    var cpuHint: String { "" }
    var grown: Int32 { 0 }
    var shrunk: Int32 { 0 }
    var growVoices: Int32 { 0 }
    var path: String { host.path }

    func clicksLastMinute() -> Int32 {
        let now = Date(), c = Int(mm_clicks())
        if c > lastClicks { for _ in 0..<(c - lastClicks) { clickTimes.append(now) } }
        lastClicks = c
        clickTimes.removeAll { now.timeIntervalSince($0) > 60 }
        return Int32(clickTimes.count)
    }

    /// How much of each block's time the engine takes to make it.
    func load_() -> Double {
        statLock.lock(); let ns = renderNs; statLock.unlock()
        let blockNs = 256.0 * 1e9 / Double(max(host.rate, 1))
        return ns / blockNs
    }
    func loadText() -> String { String(format: "%.0f%%", load_() * 100) }
    func ms(frames: Int32) -> Double { Double(frames) * 1000 / Double(max(host.rate, 1)) }
    func longBlocksText(max: Int32) -> String { "" }
}

// MARK: - the Workbench

/// Your own sounds (Documents/bench), as Android's Workbench: WAVs plus bench.json, each one registered in the
/// Library ("bn:<id>", chops "chop:<id>", jar "mine") so it plays on pads and shows in Sounds. Mic takes come from MicIn.
final class IosBench: NSObject, Bench {
    let dir: String
    private let lib: Library
    let items: NSMutableArray = []
    private let lock = NSRecursiveLock()
    private let mic = MicIn()
    private var take: [Float] = []
    private var takeRate = 48000.0
    private var recording = false
    private let takeLock = NSLock()
    private var done: ((Sample?) -> Void)?
    private var trimTake = true

    init(dir: String, lib: Library) {
        self.dir = dir
        self.lib = lib
        super.init()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        load()
    }

    private var indexPath: String { dir + "/bench.json" }
    private func wav(_ id: String) -> String { dir + "/" + id + ".wav" }
    private var list: [BenchItem] { lock.lock(); defer { lock.unlock() }; return items.compactMap { $0 as? BenchItem } }

    private func load() {
        guard let d = FileManager.default.contents(atPath: indexPath),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        for o in arr {
            let b = BenchItem(id: o["id"] as? String ?? "", kind: o["kind"] as? String ?? "imp", title: o["title"] as? String ?? "Sound",
                              at: (o["at"] as? NSNumber)?.int64Value ?? 0, base: o["base"] as? String ?? "",
                              st: (o["st"] as? NSNumber)?.doubleValue ?? 0, en: (o["en"] as? NSNumber)?.doubleValue ?? 1,
                              bpm: (o["bpm"] as? NSNumber)?.doubleValue ?? 0, beats: (o["beats"] as? NSNumber)?.int32Value ?? 0,
                              mkey: o["mkey"] as? String)
            if b.kind == "chop" || FileManager.default.fileExists(atPath: wav(b.id)) { items.add(b); register(b) }
        }
    }

    private func group(_ kind: String) -> String {
        switch kind { case "imp": return "Imports"; case "mic": return "Mic takes"; case "rs": return "Resampled loops"
        case "take": return "Saved edits"; default: return "Chops" }
    }

    private func register(_ b: BenchItem) {
        let file = b.kind == "chop" ? "" : wav(b.id)
        let snd = Library.Sound(key: keyOf(b: b), title: b.title, cab: "mine", file: file, a: 0, d: 0, group: group(b.kind), album: "")
        // only a sound that knows its length in beats (a resampled loop) follows the mess's tempo
        if b.bpm > 0 && b.beats > 0 { snd.bpm = b.bpm; snd.beats = b.beats }
        snd.mkey = b.mkey ?? ""
        lib.addUser(s: snd, chopOf: b.kind == "chop" ? b.base : nil)
    }

    private func save() {
        let arr: [[String: Any]] = list.map { b in
            var o: [String: Any] = ["id": b.id, "kind": b.kind, "title": b.title, "at": b.at, "base": b.base, "st": b.st, "en": b.en]
            if b.bpm > 0 { o["bpm"] = b.bpm; o["beats"] = b.beats }
            if let k = b.mkey { o["mkey"] = k }
            return o
        }
        if let d = try? JSONSerialization.data(withJSONObject: arr) { try? d.write(to: URL(fileURLWithPath: indexPath), options: .atomic) }
    }

    private func newId() -> String { String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 100...999)) }
    private func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func keyOf(b: BenchItem) -> String { (b.kind == "chop" ? "chop:" : "bn:") + b.id }
    func item(key: String) -> BenchItem? { list.first { keyOf(b: $0) == key } }

    private func append(_ b: BenchItem) { lock.lock(); items.add(b); register(b); save(); lock.unlock() }

    /// Keep a sound: a WAV in the Workbench jar, its key measured, the tempo it was made at. Off the main thread.
    func addSample(kind: String, title: String, s: Sample, bpm: Double, beats: Int32) -> String {
        let mk = KeyFinder.shared.find(data: s.data, rate: s.rate)
        let b = BenchItem(id: newId(), kind: kind, title: String(title.prefix(40)), at: now(), base: "", st: 0, en: 1, bpm: bpm, beats: beats, mkey: mk)
        IosFileStore.shared.writeBytes(path: wav(b.id), b: Wav.shared.writeMono16(d: s.data, rate: s.rate))
        append(b)
        let k = keyOf(b: b)
        let put = Sample(key: k, data: s.data, rate: s.rate)
        if bpm > 0 && beats > 0 { put.bpm = bpm; put.beats = beats }
        lib.putSample(key: k, s: put)
        return k
    }

    /// One of your own sounds down from your account: same key as on your other phone.
    func adoptCloud(id: String, kind: String, title: String, from: MFile, bpm: Double, beats: Int32, mkey: String) -> Bool {
        if id.isEmpty || item(key: "bn:" + id) != nil { return false }
        let fm = FileManager.default
        try? fm.removeItem(atPath: wav(id))
        guard (try? fm.copyItem(atPath: from.path, toPath: wav(id))) != nil else { return false }
        let k = ["imp", "mic", "rs", "take"].contains(kind) ? kind : "imp"
        append(BenchItem(id: id, kind: k, title: String((title.isEmpty ? "Sound" : title).prefix(40)), at: now(), base: "", st: 0, en: 1,
                         bpm: bpm, beats: beats, mkey: mkey))
        return true
    }

    func addChop(base: String, title: String, st: Double, en: Double) -> String {
        let b = BenchItem(id: newId(), kind: "chop", title: String(title.prefix(40)), at: now(), base: base, st: st, en: en, bpm: 0, beats: 0, mkey: nil)
        append(b)
        return keyOf(b: b)
    }

    func remove(key: String) {
        guard let b = item(key: key) else { return }
        lock.lock()
        items.remove(b)
        if b.kind != "chop" { try? FileManager.default.removeItem(atPath: wav(b.id)) }
        lib.removeUser(key: key)
        // chops of this sound go too
        for c in list where c.kind == "chop" && c.base == key { items.remove(c); lib.removeUser(key: keyOf(b: c)) }
        save()
        lock.unlock()
    }

    func count(kind: String) -> Int32 { Int32(list.filter { $0.kind == kind }.count) }

    /// An audio file the person picked: mono, at most 60 s, at its own rate.
    func decode(uri: String) -> Sample {
        let url = URL(string: uri) ?? URL(fileURLWithPath: uri)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (mono, rate) = (try? Workbench.readMono(url)) ?? ([], 44100)
        let cut = Array(mono.prefix(Int(rate * 60)))
        return Sample(key: "", data: cut.kotlinFloatArray(), rate: Int32(rate))
    }

    // Auto sample (Android's startMic): wait for a sound over the room's hiss, then stop after a third of a second of quiet
    private var auto = false
    private var floor: Float = 1
    private var started = false
    private var heardFor = 0
    private var quietFor = 0

    func startMic(trim: Bool, auto: Bool, done: @escaping (Sample?) -> Void) {
        guard !recording else { return }
        self.done = done
        trimTake = trim
        takeLock.lock()
        take.removeAll(); self.auto = auto; floor = 1; started = false; heardFor = 0; quietFor = 0
        takeLock.unlock()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        mic.onSamples = { [weak self] p, n, rate in self?.feed(p, n, rate: rate) }
        // AppState calls this on the main thread; MicIn wants the main thread
        recording = Thread.isMainThread ? mic.start() : DispatchQueue.main.sync { mic.start() }
        if !recording { done(nil); self.done = nil }
    }

    private func feed(_ p: UnsafePointer<Float>, _ n: Int, rate: Double) {
        guard n > 0 else { return }
        takeLock.lock()
        takeRate = rate
        take.append(contentsOf: UnsafeBufferPointer(start: p, count: n))
        var stop = Double(take.count) >= rate * 30
        if auto {
            var e = 0.0
            for i in 0..<n { e += Double(p[i]) * Double(p[i]) }
            let r = Float((e / Double(n)).squareRoot())
            heardFor += n
            if !started {
                // the room's hiss: the quietest stretch so far (the first tenth of a second settles it)
                floor = min(floor, max(r, 0.0005))
                if Double(heardFor) > rate / 10 && r > max(floor * 6, 0.02) { started = true }
                else if Double(take.count) > rate / 2 { take.removeFirst(take.count - Int(rate / 2)) }
            } else {
                quietFor = r < max(floor * 2.5, 0.008) ? quietFor + n : 0
                if Double(quietFor) > rate / 3 { stop = true }
            }
        }
        takeLock.unlock()
        if stop { DispatchQueue.main.async { self.stopMic() } }
    }

    func stopMic() {
        guard recording else { return }
        recording = false
        mic.stop()
        takeLock.lock(); let s = take; let r = takeRate; take.removeAll(); takeLock.unlock()
        let raw = Sample(key: "mic", data: s.kotlinFloatArray(), rate: Int32(r))
        let out = trimTake ? trimSilence(s: raw) : (s.isEmpty ? nil : raw)
        let d = done; done = nil
        d?(out)
    }

    func isRecording() -> Bool { recording }

    /// Cut the quiet off both ends (Auto trim), line for line Android's: 5 ms windows, the room's hiss is the quietest
    /// tenth, 5 ms kept before the sound and 50 ms after with a short fade.
    func trimSilence(s: Sample) -> Sample? {
        let d = s.data.floats()
        if d.isEmpty { return nil }
        var peak: Float = 0
        for v in d where abs(v) > peak { peak = abs(v) }
        if peak < 0.002 { return nil }
        let rate = Int(s.rate)
        let w = max(1, rate / 200)
        let nw = (d.count + w - 1) / w
        var rms = [Float](repeating: 0, count: nw)
        for k in 0..<nw {
            var e = 0.0
            let a0 = k * w, a1 = min(d.count, a0 + w)
            for i in a0..<a1 { e += Double(d[i]) * Double(d[i]) }
            rms[k] = Float((e / Double(max(1, a1 - a0))).squareRoot())
        }
        let sorted = rms.sorted()
        let floor = sorted[min(sorted.count - 1, sorted.count / 10)]
        let th = max(peak * 0.03, floor * 4, 0.001)
        var first = 0
        while first < nw && rms[first] < th { first += 1 }
        if first >= nw { return nil }
        var last = nw - 1
        while last > first && rms[last] < th { last -= 1 }
        let a = max(0, first * w - rate / 200)
        let z = min(d.count - 1, (last + 1) * w + rate / 20)
        var out = Array(d[a...z])
        let fade = min(out.count, rate / 100)
        for i in 0..<fade { out[out.count - 1 - i] *= Float(i) / Float(fade) }
        return Sample(key: "mic", data: out.kotlinFloatArray(), rate: s.rate)
    }
}

// MARK: - notes (the BUG button)

/// The notes as AppState sees them, sent and read back with this repo's Notes.swift (same issue shape, plus `ios`).
final class IosNoteBook: NSObject, NoteBook {
    var notes: NSMutableArray = []
    private(set) var checking = false
    private(set) var lastCheck = ""
    private let file: URL
    private let device: Device
    private let book: NotesBook

    init(dir: String, device: Device) {
        self.device = device
        file = URL(fileURLWithPath: dir).appendingPathComponent("notes-shared.json")
        book = NotesBook(dir: URL(fileURLWithPath: dir))
        super.init()
        if let d = try? Data(contentsOf: file), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            for o in arr { notes.add(Self.note(from: o)) }
        }
    }

    var hasKey: Bool { (Keychain.get("notes-key") ?? "").isEmpty == false }
    private var list: [MNote] { notes.compactMap { $0 as? MNote } }

    static func note(from o: [String: Any]) -> MNote {
        MNote(id: o["id"] as? String ?? "", cat: o["cat"] as? String ?? "bug", topic: o["topic"] as? String ?? "",
                          text: o["text"] as? String ?? "", at: (o["at"] as? NSNumber)?.int64Value ?? 0, build: o["build"] as? String ?? "",
                          screen: o["screen"] as? String ?? "", extra: o["extra"] as? String ?? "", sent: o["sent"] as? Bool ?? false,
                          issue: (o["issue"] as? NSNumber)?.int32Value ?? 0, status: o["status"] as? String ?? "",
                          replies: o["replies"] as? [String] ?? [], ctx: o["ctx"] as? String ?? "", ctxTrail: o["ctxTrail"] as? String ?? "")
    }

    static func dict(_ n: MNote) -> [String: Any] {
        ["id": n.id, "cat": n.cat, "topic": n.topic, "text": n.text, "at": n.at, "build": n.build, "screen": n.screen, "extra": n.extra,
         "sent": n.sent, "issue": n.issue, "status": n.status, "replies": n.replies, "ctx": n.ctx, "ctxTrail": n.ctxTrail]
    }

    private func save() {
        if let d = try? JSONSerialization.data(withJSONObject: list.map(Self.dict)) { try? d.write(to: file, options: .atomic) }
    }

    private func with(_ n: MNote, issue: Int32? = nil, status: String? = nil, sent: Bool? = nil, replies: [String]? = nil) -> MNote {
        MNote(id: n.id, cat: n.cat, topic: n.topic, text: n.text, at: n.at, build: n.build, screen: n.screen, extra: n.extra,
                          sent: sent ?? n.sent, issue: issue ?? n.issue, status: status ?? n.status, replies: replies ?? n.replies,
                          ctx: n.ctx, ctxTrail: n.ctxTrail)
    }

    private func replace(_ n: MNote) {
        DispatchQueue.main.async {
            if let i = self.list.firstIndex(where: { $0.id == n.id }) { self.notes.replaceObject(at: i, with: n); self.save() }
        }
    }

    func trail(what: String) { book.trail(what) }
    func trailText() -> String { book.body(IosNote(id: "", cat: "bug", text: "", at: Date(), build: "", screen: ""), details: "").components(separatedBy: "```\n").dropFirst().first?.components(separatedBy: "\n```").first ?? "" }
    func add(n: MNote) { notes.insert(n, at: 0); save() }
    func remove(id: String) { if let i = list.firstIndex(where: { $0.id == id }) { notes.removeObject(at: i); save() } }

    func parsePrefix(text: String, cat: String, topic: String) -> KotlinTriple<NSString, NSString, NSString> {
        let (c, t, w) = NotesBook.parsePrefix(text, cat: cat, topic: topic)
        return KotlinTriple(first: c as NSString, second: t as NSString, third: w as NSString)
    }

    func saveKey(k: String) { Keychain.set("notes-key", k.trimmingCharacters(in: .whitespacesAndNewlines)) }
    func forgetKey() { Keychain.remove("notes-key") }

    /// The Swift note shape Notes.swift already sends (same title, body, marker and labels as Android, plus `ios`).
    private func swiftNote(_ n: MNote) -> IosNote {
        IosNote(id: n.id, cat: n.cat, topic: n.topic, text: n.text, at: Date(timeIntervalSince1970: Double(n.at) / 1000), build: n.build, screen: n.screen)
    }

    func send(n: MNote, details: String, done: @escaping (String) -> Void) {
        let s = swiftNote(n)
        book.add(s)
        book.send(s, details: details + n.extra) { [weak self] msg in
            guard let self else { return }
            if let sent = self.book.notes.first(where: { $0.id == n.id }) {
                self.replace(self.with(n, issue: Int32(sent.issue), status: sent.status, sent: sent.issue > 0))
            }
            done(msg)
        }
        if !hasKey { replace(with(n, status: NoteBookKt.OPENED)) }
    }

    func sendWaiting(details: @escaping (MNote) -> String, done: @escaping (String) -> Void) {
        let waiting = list.filter { !$0.sent && $0.issue == 0 }
        guard !waiting.isEmpty else { done("Nothing waiting."); return }
        for n in waiting { send(n: n, details: details(n)) { _ in } }
        done("Sending \(waiting.count) note\(waiting.count == 1 ? "" : "s").")
    }

    /// Without a key: one GitHub page holding every waiting note.
    func openBundle(waiting: [MNote], details: String) -> Int32 {
        guard !waiting.isEmpty else { return 0 }
        let first = swiftNote(waiting[0])
        let text = waiting.map { "### " + NoteBookKt.catLabel(c: $0.cat) + "\n" + $0.text + "\n<!-- mm-note:\($0.id) -->" }.joined(separator: "\n\n")
        let bundle = IosNote(id: first.id, cat: first.cat, topic: first.topic, text: text, at: first.at, build: first.build, screen: first.screen)
        DispatchQueue.main.async { UIApplication.shared.open(self.book.pageURL(bundle, details: details)) }
        for n in waiting { replace(with(n, status: NoteBookKt.OPENED)) }
        return Int32(waiting.count)
    }

    func checkReplies(done: @escaping (String) -> Void) {
        checking = true
        for n in list where !book.notes.contains(where: { $0.id == n.id }) { book.add(swiftNote(n)) }
        book.checkReplies { [weak self] msg in
            guard let self else { return }
            for s in self.book.notes {
                if let n = self.list.first(where: { $0.id == s.id }) {
                    self.replace(self.with(n, issue: Int32(s.issue), status: s.status, sent: s.issue > 0 ? true : n.sent, replies: s.replies ?? n.replies))
                }
            }
            self.checking = false
            self.lastCheck = msg
            done(msg)
        }
    }
}

// MARK: - packs, speech, mouth, updates

/// Speech to text for a quick note, with this repo's VoiceNote (SFSpeechRecognizer, on the phone where it can).
final class IosSpeechIn: NSObject, SpeechIn {
    private let voice = VoiceNote()
    private let heard: (String) -> Void
    private let done: (String, String?) -> Void
    private var watch: NSKeyValueObservation?
    private var timer: Timer?
    private var last = ""

    init(heard: @escaping (String) -> Void, done: @escaping (String, String?) -> Void) {
        self.heard = heard
        self.done = done
    }

    func available() -> Bool { true }

    func start_() -> Bool {
        DispatchQueue.main.async {
            self.voice.start { _ = AudioHost.prepareSession() }
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.voice.heard != self.last { self.last = self.voice.heard; self.heard(self.last) }
                if !self.voice.listening && !self.voice.status.isEmpty && self.voice.status != "Listening. Tap again when you're done." {
                    self.finish(problem: self.voice.heard.isEmpty ? self.voice.status : nil)
                }
            }
        }
        return true
    }

    private func finish(problem: String?) {
        timer?.invalidate(); timer = nil
        done(voice.heard, problem)
    }

    func stop() { DispatchQueue.main.async { self.voice.stop(); self.finish(problem: nil) } }
    func cancel() { DispatchQueue.main.async { self.voice.stop(); self.timer?.invalidate(); self.timer = nil } }
}

/// The mic feeding the mouth tracker at 16 kHz, as Android's MouthMic does.
final class IosMouthIn: NSObject, MouthIn {
    let tracker = MouthTracker(rate: 16000)
    private let mic = MicIn()
    private var buf = [Float]()
    private(set) var running = false

    func start_() -> Bool {
        guard !running else { return true }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
        let t = tracker
        mic.onSamples = { p, n, rate in
            // down to 16 kHz by picking samples (the tracker only follows loudness and brightness)
            let step = rate / 16000.0
            var out = [Float](); out.reserveCapacity(Int(Double(n) / step) + 1)
            var x = 0.0
            while Int(x) < n { out.append(p[Int(x)]); x += step }
            let arr = out.kotlinFloatArray()
            _ = t.feed(x: arr, off: 0, len: Int32(out.count))
        }
        running = Thread.isMainThread ? mic.start() : DispatchQueue.main.sync { mic.start() }
        return running
    }

    func stop() { running = false; DispatchQueue.main.async { self.mic.stop() } }
}

/// The App Store updates the app on iPhone, so this finds nothing.
final class IosAppUpdater: NSObject, AppUpdater {
    let current: Int32
    init(current: Int32) { self.current = current }
    var latest: Int32 { current }
    var status: String { "Updates come from the App Store on iPhone." }
    var busy: Bool { false }
    var later: Bool = false
    var ready: Bool { false }
    func found(build: Int32, url: String, size: Int64) {}
    func check(quiet: Bool, done: @escaping (String) -> Void) { done(status) }
    func allowed() -> Bool { false }
    func download(before: @escaping () -> Void) {}
}

// MARK: - the hooks the shared screens call (PlatformUi.ios.kt)

enum AppHooks {
    private static var pickerDelegate: PickerDelegate?

    static func install() {
        let h = IosHooks.shared
        h.micGranted = { KotlinBoolean(bool: AVAudioApplication.shared.recordPermission == .granted) }
        h.askMic = { answer in MicIn.ask { ok in _ = answer(KotlinBoolean(bool: ok)) } }
        h.tap = { Haptics.pad() }
        h.pick = { types, multiple, done in
            DispatchQueue.main.async {
                let utis = types.compactMap { utType(forMime: $0) }
                let vc = UIDocumentPickerViewController(forOpeningContentTypes: utis.isEmpty ? [.item] : utis, asCopy: true)
                vc.allowsMultipleSelection = multiple.boolValue
                let d = PickerDelegate { urls in _ = done(urls.map { $0.absoluteString }) }
                pickerDelegate = d
                vc.delegate = d
                IosDevice.present(vc)
            }
        }
    }

    /// "audio/*", "application/json" and the like, as Android's pickers take them.
    static func utType(forMime m: String) -> UTType? {
        switch m {
        case "audio/*": return .audio
        case "*/*": return .item
        case "application/json", "text/json": return .json
        case "application/zip": return .zip
        case "audio/midi", "audio/x-midi": return UTType(mimeType: "audio/midi") ?? .midi
        default: return UTType(mimeType: m)
        }
    }

    final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        let done: ([URL]) -> Void
        init(done: @escaping ([URL]) -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done([]) }
    }
}

// MARK: - Kotlin arrays

extension Data {
    func kotlinByteArray() -> KotlinByteArray {
        let a = KotlinByteArray(size: Int32(count))
        withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            for i in 0..<count { a.set(index: Int32(i), value: Int8(bitPattern: p[i])) }
        }
        return a
    }
}

extension KotlinByteArray {
    func data() -> Data {
        var d = Data(count: Int(size))
        d.withUnsafeMutableBytes { (p: UnsafeMutableRawBufferPointer) in
            for i in 0..<Int(size) { p[i] = UInt8(bitPattern: get(index: Int32(i))) }
        }
        return d
    }
}

extension Array where Element == Float {
    func kotlinFloatArray() -> KotlinFloatArray {
        let a = KotlinFloatArray(size: Int32(count))
        for (i, v) in enumerated() { a.set(index: Int32(i), value: v) }
        return a
    }
}

extension KotlinFloatArray {
    func floats() -> [Float] { (0..<Int(size)).map { get(index: Int32($0)) } }
}
#endif

/// A zip with every file stored as it is (no compression): enough for stems, which are already WAV.
enum Zip {
    static func store(_ files: [(String, Data)]) -> Data {
        var out = Data(), central = Data()
        func u16(_ v: Int, _ d: inout Data) { var x = UInt16(truncatingIfNeeded: v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        func u32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = CRC32.of(data)
            let offset = UInt32(out.count)
            u32(0x04034b50, &out); u16(20, &out); u16(0x0800, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
            u32(crc, &out); u32(UInt32(data.count), &out); u32(UInt32(data.count), &out); u16(nameData.count, &out); u16(0, &out)
            out.append(nameData); out.append(data)
            u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0x0800, &central); u16(0, &central); u16(0, &central); u16(0x21, &central)
            u32(crc, &central); u32(UInt32(data.count), &central); u32(UInt32(data.count), &central); u16(nameData.count, &central)
            u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central)
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        u32(0x06054b50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
        u32(UInt32(central.count), &out); u32(cdOffset, &out); u16(0, &out)
        return out
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func of(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
