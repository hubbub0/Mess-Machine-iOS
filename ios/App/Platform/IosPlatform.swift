import AVFoundation
import Foundation
import Network
import UIKit

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
    func bench(lib: Library) -> Bench { IosBench(dir: filesDir + "/bench") }
    func notes() -> NoteBook { IosNoteBook(dir: filesDir, device: device) }
    func packs(lib: Library) -> Packs { IosPacks() }
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
        let url = Bundle.main.url(forResource: "assets", withExtension: nil)?.appendingPathComponent(path)
        let d = url.flatMap { try? Data(contentsOf: $0) } ?? Data()
        return d.kotlinByteArray()
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
        return (try? Data(contentsOf: url))?.kotlinByteArray()
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
    private let statLock = NSLock()

    init(engine: Engine) {
        self.engine = engine
        super.init()
        NotificationCenter.default.addObserver(forName: .messStopFromLockScreen, object: nil, queue: .main) { [weak self] _ in self?.engine.stop() }
    }

    func render(_ buf: UnsafeMutablePointer<Float>, frames: Int, rate: Int) {
        let t0 = mm_now_ns()
        engine.renderInto(out: buf, frames: Int32(frames))
        let dt = Double(mm_now_ns() - t0)
        statLock.lock(); renderNs = renderNs == 0 ? dt : renderNs * 0.98 + dt * 0.02; statLock.unlock()
    }

    func start() { onMain { self.host.start() } }
    func stop() { onMain { self.host.stop() } }
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

/// Your own sounds as WAVs (Documents/bench), as the Android Workbench keeps them. Mic takes come from MicIn.
final class IosBench: NSObject, Bench {
    let dir: String
    var items: NSMutableArray = []
    private let mic = MicIn()
    private var take: [Float] = []
    private var takeRate = 48000.0
    private var recording = false
    private let lock = NSLock()
    private var done: ((Sample?) -> Void)?
    private var trimTake = true

    init(dir: String) {
        self.dir = dir
        super.init()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        load()
    }

    private var indexPath: String { dir + "/bench.json" }

    private func load() {
        guard let d = FileManager.default.contents(atPath: indexPath),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        for o in arr {
            let b = MessMachine.BenchItem(id: o["id"] as? String ?? "", kind: o["kind"] as? String ?? "imp", title: o["title"] as? String ?? "",
                                          at: (o["at"] as? NSNumber)?.int64Value ?? 0, base: o["base"] as? String ?? "",
                                          st: (o["st"] as? NSNumber)?.doubleValue ?? 0, en: (o["en"] as? NSNumber)?.doubleValue ?? 1,
                                          bpm: (o["bpm"] as? NSNumber)?.doubleValue ?? 0, beats: (o["beats"] as? NSNumber)?.int32Value ?? 0,
                                          mkey: o["mkey"] as? String)
            if b.kind == "chop" || FileManager.default.fileExists(atPath: wav(b.id)) { items.add(b) }
        }
    }

    private func save() {
        let arr: [[String: Any]] = items.compactMap { $0 as? MessMachine.BenchItem }.map { b in
            var o: [String: Any] = ["id": b.id, "kind": b.kind, "title": b.title, "at": b.at, "base": b.base, "st": b.st, "en": b.en,
                                    "bpm": b.bpm, "beats": b.beats]
            if let k = b.mkey { o["mkey"] = k }
            return o
        }
        if let d = try? JSONSerialization.data(withJSONObject: arr) { FileManager.default.createFile(atPath: indexPath, contents: d) }
    }

    private func wav(_ id: String) -> String { dir + "/" + id + ".wav" }
    private var list: [MessMachine.BenchItem] { items.compactMap { $0 as? MessMachine.BenchItem } }

    func keyOf(b: MessMachine.BenchItem) -> String { "bn:" + b.id }
    func item(key: String) -> MessMachine.BenchItem? { list.first { keyOf(b: $0) == key } }

    func addSample(kind: String, title: String, s: Sample, bpm: Double, beats: Int32) -> String {
        let id = Workbench.newId()
        try? Wav.write(s.data.floats(), channels: 1, rate: Int(s.rate), to: URL(fileURLWithPath: wav(id)))
        let b = MessMachine.BenchItem(id: id, kind: kind, title: title, at: Int64(Date().timeIntervalSince1970 * 1000), base: "", st: 0, en: 1,
                                      bpm: bpm, beats: beats, mkey: nil)
        items.insert(b, at: 0); save()
        return keyOf(b: b)
    }

    func adoptCloud(id: String, kind: String, title: String, from: MFile, bpm: Double, beats: Int32, mkey: String) -> Bool {
        guard (try? FileManager.default.copyItem(atPath: from.path, toPath: wav(id))) != nil || FileManager.default.fileExists(atPath: wav(id)) else { return false }
        let b = MessMachine.BenchItem(id: id, kind: kind, title: title, at: Int64(Date().timeIntervalSince1970 * 1000), base: "", st: 0, en: 1,
                                      bpm: bpm, beats: beats, mkey: mkey)
        items.insert(b, at: 0); save()
        return true
    }

    func addChop(base: String, title: String, st: Double, en: Double) -> String {
        let id = Workbench.newId()
        let b = MessMachine.BenchItem(id: id, kind: "chop", title: title, at: Int64(Date().timeIntervalSince1970 * 1000), base: base, st: st, en: en,
                                      bpm: 0, beats: 0, mkey: nil)
        items.insert(b, at: 0); save()
        return keyOf(b: b)
    }

    func remove(key: String) {
        guard let b = item(key: key) else { return }
        try? FileManager.default.removeItem(atPath: wav(b.id))
        items.remove(b); save()
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

    func startMic(trim: Bool, auto: Bool, done: @escaping (Sample?) -> Void) {
        guard !recording else { return }
        self.done = done
        trimTake = trim
        lock.lock(); take.removeAll(); lock.unlock()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        mic.onSamples = { [weak self] p, n, rate in
            guard let self else { return }
            self.lock.lock()
            self.takeRate = rate
            self.take.append(contentsOf: UnsafeBufferPointer(start: p, count: n))
            let full = Double(self.take.count) >= rate * 30
            self.lock.unlock()
            if full { DispatchQueue.main.async { self.stopMic() } }
        }
        recording = DispatchQueue.main.sync { mic.start() }
        if !recording { done(nil); self.done = nil }
    }

    func stopMic() {
        guard recording else { return }
        recording = false
        mic.stop()
        lock.lock(); let s = take; let r = takeRate; take.removeAll(); lock.unlock()
        let sample = Sample(key: "", data: s.kotlinFloatArray(), rate: Int32(r))
        let out = trimTake ? trimSilence(s: sample) : sample
        let d = done; done = nil
        d?(out)
    }

    func isRecording() -> Bool { recording }

    func trimSilence(s: Sample) -> Sample? {
        let t = Workbench.trimSilence(s.data.floats(), rate: Double(s.rate))
        return t.count > Int(Double(s.rate) * 0.05) ? Sample(key: s.key, data: t.kotlinFloatArray(), rate: s.rate) : nil
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
    private var list: [MessMachine.MNote] { notes.compactMap { $0 as? MessMachine.MNote } }

    static func note(from o: [String: Any]) -> MessMachine.MNote {
        MessMachine.MNote(id: o["id"] as? String ?? "", cat: o["cat"] as? String ?? "bug", topic: o["topic"] as? String ?? "",
                          text: o["text"] as? String ?? "", at: (o["at"] as? NSNumber)?.int64Value ?? 0, build: o["build"] as? String ?? "",
                          screen: o["screen"] as? String ?? "", extra: o["extra"] as? String ?? "", sent: o["sent"] as? Bool ?? false,
                          issue: (o["issue"] as? NSNumber)?.int32Value ?? 0, status: o["status"] as? String ?? "",
                          replies: o["replies"] as? [String] ?? [], ctx: o["ctx"] as? String ?? "", ctxTrail: o["ctxTrail"] as? String ?? "")
    }

    static func dict(_ n: MessMachine.MNote) -> [String: Any] {
        ["id": n.id, "cat": n.cat, "topic": n.topic, "text": n.text, "at": n.at, "build": n.build, "screen": n.screen, "extra": n.extra,
         "sent": n.sent, "issue": n.issue, "status": n.status, "replies": n.replies, "ctx": n.ctx, "ctxTrail": n.ctxTrail]
    }

    private func save() {
        if let d = try? JSONSerialization.data(withJSONObject: list.map(Self.dict)) { try? d.write(to: file, options: .atomic) }
    }

    private func with(_ n: MessMachine.MNote, issue: Int32? = nil, status: String? = nil, sent: Bool? = nil, replies: [String]? = nil) -> MessMachine.MNote {
        MessMachine.MNote(id: n.id, cat: n.cat, topic: n.topic, text: n.text, at: n.at, build: n.build, screen: n.screen, extra: n.extra,
                          sent: sent ?? n.sent, issue: issue ?? n.issue, status: status ?? n.status, replies: replies ?? n.replies,
                          ctx: n.ctx, ctxTrail: n.ctxTrail)
    }

    private func replace(_ n: MessMachine.MNote) {
        DispatchQueue.main.async {
            if let i = self.list.firstIndex(where: { $0.id == n.id }) { self.notes.replaceObject(at: i, with: n); self.save() }
        }
    }

    func trail(what: String) { book.trail(what) }
    func trailText() -> String { book.body(MNote(id: "", cat: "bug", text: "", at: Date(), build: "", screen: ""), details: "").components(separatedBy: "```\n").dropFirst().first?.components(separatedBy: "\n```").first ?? "" }
    func add(n: MessMachine.MNote) { notes.insert(n, at: 0); save() }
    func remove(id: String) { if let i = list.firstIndex(where: { $0.id == id }) { notes.removeObject(at: i); save() } }

    func parsePrefix(text: String, cat: String, topic: String) -> KotlinTriple<NSString, NSString, NSString> {
        let (c, t, w) = NotesBook.parsePrefix(text, cat: cat, topic: topic)
        return KotlinTriple(first: c as NSString, second: t as NSString, third: w as NSString)
    }

    func saveKey(k: String) { Keychain.set("notes-key", k.trimmingCharacters(in: .whitespacesAndNewlines)) }
    func forgetKey() { Keychain.remove("notes-key") }

    /// The Swift note shape Notes.swift already sends (same title, body, marker and labels as Android, plus `ios`).
    private func swiftNote(_ n: MessMachine.MNote) -> MNote {
        MNote(id: n.id, cat: n.cat, topic: n.topic, text: n.text, at: Date(timeIntervalSince1970: Double(n.at) / 1000), build: n.build, screen: n.screen)
    }

    func send(n: MessMachine.MNote, details: String, done: @escaping (String) -> Void) {
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

    func sendWaiting(details: @escaping (MessMachine.MNote) -> String, done: @escaping (String) -> Void) {
        let waiting = list.filter { !$0.sent && $0.issue == 0 }
        guard !waiting.isEmpty else { done("Nothing waiting."); return }
        for n in waiting { send(n: n, details: details(n)) { _ in } }
        done("Sending \(waiting.count) note\(waiting.count == 1 ? "" : "s").")
    }

    /// Without a key: one GitHub page holding every waiting note.
    func openBundle(waiting: [MessMachine.MNote], details: String) -> Int32 {
        guard !waiting.isEmpty else { return 0 }
        let first = swiftNote(waiting[0])
        let text = waiting.map { "### " + NoteBookKt.catLabel(c: $0.cat) + "\n" + $0.text + "\n<!-- mm-note:\($0.id) -->" }.joined(separator: "\n\n")
        let bundle = MNote(id: first.id, cat: first.cat, topic: first.topic, text: text, at: first.at, build: first.build, screen: first.screen)
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

/// Sound packs from the packs release. Not on iPhone yet: no offers, nothing to install.
final class IosPacks: NSObject, Packs {
    let installed = KotlinMutableDictionary<NSString, KotlinInt>()
    func loadInstalled() {}
    func fetchOffers() -> [PacksOffer] { [] }
    func install(o: PacksOffer) {}
    func installZip(zip: MFile, id: String) {}
    func remove(id: String) { installed.removeObject(forKey: id as NSString) }
}

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
