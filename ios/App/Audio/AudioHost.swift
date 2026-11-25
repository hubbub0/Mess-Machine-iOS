import AVFoundation
import Foundation

/// Something that makes sound in blocks, the way the shared engine will (`Engine.render(buf, frames)` on Android).
/// Until the Kotlin engine lands, `ToneEngine` stands in for it.
protocol BlockRenderer: AnyObject {
    /// Fill `frames` interleaved stereo frames. Called on the writer thread only, never on the audio callback.
    func render(_ buf: UnsafeMutablePointer<Float>, frames: Int, rate: Int)
}

/// Feeds an engine to the speaker through the C ring and Core Audio (ios/Audio). The twin of Android's AudioOut.kt:
/// starts with a small ring for low lag, grows it a block at a time when it clicks, gives a block back after a quiet
/// ten seconds, and measures itself for notes and Settings.
final class AudioHost: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var rate = 48000
    @Published private(set) var block = 256
    @Published private(set) var deviceFrames = 0
    @Published private(set) var fill = 0
    @Published private(set) var clicks = 0
    @Published private(set) var outputMs = -1.0
    @Published private(set) var route = "not started"
    @Published private(set) var path = "not started"
    @Published private(set) var status = ""
    /// Whether the writer thread got a real-time schedule from the OS.
    @Published private(set) var realtime = false

    let engine: BlockRenderer
    /// Bursts the ring may grow past where it started (Android's "Tight" setting).
    var growCap = 3

    private var thread: Thread?
    private let stopLock = NSLock()
    private var stopFlag = false
    private var statsTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var resumeAfterInterruption = false

    init(engine: BlockRenderer) {
        self.engine = engine
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in self?.interrupted(n) })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in self?.routeChanged(n) })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in self?.mediaReset() })
    }

    deinit { for o in observers { NotificationCenter.default.removeObserver(o) } }

    // MARK: session

    /// Set the session up once before anything is built, and return the rate the engine must render at.
    static func prepareSession() -> Int {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setPreferredSampleRate(48000)
        try? s.setActive(true)
        return max(8000, Int(s.sampleRate.rounded()))
    }

    /// Playback only, not mixed with other apps, short IO buffer, the hardware's own rate.
    /// With `mic`, play and record (the mic and mouth control need it), still out of the speaker.
    func configureSession(mic: Bool = false) {
        let s = AVAudioSession.sharedInstance()
        do {
            if mic {
                try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            } else {
                try s.setCategory(.playback, mode: .default, options: [])
            }
            try s.setPreferredSampleRate(48000)
            try s.setPreferredIOBufferDuration(0.005)
            try s.setActive(true)
        } catch {
            status = "The audio session would not start: \(error.localizedDescription)"
        }
        rate = Int(s.sampleRate.rounded())
        route = Self.routeText(s)
        mm_set_output_latency(Int32((s.outputLatency * s.sampleRate).rounded()))
    }

    static func routeText(_ s: AVAudioSession) -> String {
        let outs = s.currentRoute.outputs.map { $0.portName }
        return outs.isEmpty ? "no output" : outs.joined(separator: ", ")
    }

    // MARK: start and stop

    func start() {
        guard !running else { return }
        configureSession(mic: AVAudioSession.sharedInstance().category == .playAndRecord)
        stopLock.lock(); stopFlag = false; stopLock.unlock()
        running = true
        let r = rate
        let t = Thread { [weak self] in self?.loop(rate: r) }
        t.name = "mess-audio"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.readStats() }
    }

    func stop() {
        stopLock.lock(); stopFlag = true; stopLock.unlock()
        mm_mark_dead()
        running = false
        statsTimer?.invalidate(); statsTimer = nil
        path = "stopped"
    }

    /// Start again (after a category change or a media reset), only if it was running.
    func restart() {
        guard running else { return }
        stop()
        // let the writer thread see the stop and close its stream
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.start() }
    }

    private var stopped: Bool { stopLock.lock(); defer { stopLock.unlock() }; return stopFlag }

    // MARK: the writer thread

    private func loop(rate: Int) {
        var tries = 0
        while !stopped && tries < 5 {
            switch loopCoreAudio(rate: rate) {
            case 0: return
            case 1:
                DispatchQueue.main.async { self.path = "Core Audio would not open"; self.running = false }
                return
            default: tries += 1
            }
        }
    }

    /// 0: stopped as asked; 1: Core Audio would not open; 2: the output died (open it again).
    private func loopCoreAudio(rate: Int) -> Int {
        let blk = 256
        var dev = Int(mm_open(Int32(rate), Int32(blk * 3)))
        // -2: the last writer thread has not closed its stream yet (a quick restart); give it a moment
        var waits = 0
        while dev == -2 && waits < 50 && !stopped { Thread.sleep(forTimeInterval: 0.02); waits += 1; dev = Int(mm_open(Int32(rate), Int32(blk * 3))) }
        if stopped && dev > 0 { mm_close(); return 0 }
        if dev <= 0 { return 1 }
        defer { mm_close() }
        let startFill = blk + min(dev, 1024) * 2
        var fill = startFill
        mm_set_fill(Int32(fill))
        DispatchQueue.main.async {
            self.block = blk
            self.fill = fill
            self.path = String(cString: mm_mode())
        }
        // a real-time schedule for this thread: Apple coalesces ordinary sleeps, which would run the ring dry
        let periodNs = Int64(blk) * 1_000_000_000 / Int64(rate)
        let rt = mm_thread_realtime(periodNs, periodNs / 2) == 0
        DispatchQueue.main.async { self.realtime = rt }
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: blk * 2)
        defer { buf.deallocate() }
        var seen = 0
        var n = 0
        var lastClick = DispatchTime.now().uptimeNanoseconds
        while !stopped {
            engine.render(buf, frames: blk, rate: rate)
            if mm_write(buf, Int32(blk), Int32(rate)) < 0 { return stopped ? 0 : 2 }
            n += 1
            if n % 64 == 0 {
                let u = Int(mm_clicks())
                let now = DispatchTime.now().uptimeNanoseconds
                if u > seen && fill < startFill + blk * growCap { fill += blk; mm_set_fill(Int32(fill)) }
                if u > seen { lastClick = now }
                else if fill > startFill && now - lastClick > 10_000_000_000 { fill -= blk; mm_set_fill(Int32(fill)); lastClick = now }
                seen = u
                let f = fill
                DispatchQueue.main.async { self.fill = f }
            }
        }
        return 0
    }

    private func readStats() {
        clicks = Int(mm_clicks())
        deviceFrames = Int(mm_device_buffer())
        let b = mm_behind(mm_now_ns(), Int32(rate))
        if b >= 0 {
            let ms = Double(b) * 1000.0 / Double(rate)
            if ms >= 0 && ms < 2000 { outputMs = outputMs < 0 ? ms : outputMs + (ms - outputMs) * 0.2 }
        }
    }

    /// One line for notes, the same shape as Android's **Audio:** line.
    func notesLine() -> String {
        "\(rate) Hz, ring \(fill) frames, device \(deviceFrames) frames per callback, clicks \(clicks), path \(path), writer \(realtime ? "real-time" : "normal"), out \(outputMs < 0 ? "not known" : String(format: "%.1f ms", outputMs)), route \(route)"
    }

    // MARK: the session's news

    private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            resumeAfterInterruption = running
            if running { stop() }
            status = "Paused by the phone (a call or another app)."
        case .ended:
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            if resumeAfterInterruption && opts.contains(.shouldResume) { start(); status = "Back after the interruption." }
            resumeAfterInterruption = false
        @unknown default: break
        }
    }

    private func routeChanged(_ n: Notification) {
        let s = AVAudioSession.sharedInstance()
        route = Self.routeText(s)
        mm_set_output_latency(Int32((s.outputLatency * s.sampleRate).rounded()))
        guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // headphones out: stop rather than blast the speaker, the way iPhone music apps behave
        if reason == .oldDeviceUnavailable && running {
            stop()
            status = "Headphones out: stopped."
        }
        // a new rate means a new stream: the engine renders at the stream's rate
        if Int(s.sampleRate.rounded()) != rate && running { restart() }
    }

    private func mediaReset() {
        let was = running
        if was { stop() }
        status = "The phone's audio restarted; opening it again."
        if was { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.start() } }
    }
}

/// The stand-in engine: silence, a plucked tone each time a pad is hit, and Workbench sounds played once.
/// Locks only on the writer thread, never in the audio callback.
final class ToneEngine: BlockRenderer {
    private struct Voice { var phase: Double; var freq: Double; var amp: Double }
    private struct SampleVoice { var data: [Float]; var pos: Int }
    private var voices: [Voice] = []
    private var sampleVoices: [SampleVoice] = []
    private var pending: [Double] = []
    private var pendingSamples: [[Float]] = []
    private let lock = NSLock()

    /// Play a mono sound once, already at the engine's rate. Safe from any thread.
    func play(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock(); pendingSamples.append(samples); lock.unlock()
    }

    /// Hit: a short decaying tone at `freq` Hz. Safe from any thread.
    func hit(freq: Double = 220) {
        lock.lock(); pending.append(freq); lock.unlock()
    }

    func render(_ buf: UnsafeMutablePointer<Float>, frames: Int, rate: Int) {
        lock.lock()
        for f in pending where voices.count < 16 { voices.append(Voice(phase: 0, freq: f, amp: 0.35)) }
        pending.removeAll(keepingCapacity: true)
        for s in pendingSamples where sampleVoices.count < 8 { sampleVoices.append(SampleVoice(data: s, pos: 0)) }
        pendingSamples.removeAll(keepingCapacity: true)
        lock.unlock()
        let decay = pow(0.001, 1.0 / (0.8 * Double(rate)))  // down 60 dB in 0.8 s
        for i in 0..<frames {
            var s = 0.0
            for k in sampleVoices.indices where sampleVoices[k].pos < sampleVoices[k].data.count {
                s += Double(sampleVoices[k].data[sampleVoices[k].pos])
                sampleVoices[k].pos += 1
            }
            for k in voices.indices {
                s += sin(voices[k].phase) * voices[k].amp
                voices[k].phase += 2 * .pi * voices[k].freq / Double(rate)
                if voices[k].phase > 2 * .pi { voices[k].phase -= 2 * .pi }
                voices[k].amp *= decay
            }
            let v = Float(max(-1, min(1, s)))
            buf[i * 2] = v
            buf[i * 2 + 1] = v
        }
        voices.removeAll { $0.amp < 0.0005 }
        sampleVoices.removeAll { $0.pos >= $0.data.count }
    }
}
