import AVFoundation
import Foundation

/// The mic, for mouth control and pad takes (Android: MouthMic.kt and Workbench.kt). Reads the input at the
/// hardware's rate, keeps a level for the meter, and hands every block to `onSamples` (the shared engine's
/// MouthTracker will sit there). Nothing is stored or sent anywhere unless a take is being recorded.
final class MicIn: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var level: Float = 0
    @Published private(set) var status = "off"

    /// Mono samples, -1 ... 1, and their rate. Called on the audio input thread: keep it light.
    var onSamples: ((UnsafePointer<Float>, Int, Double) -> Void)?

    private let engine = AVAudioEngine()

    /// Asks for the mic the first time; `done(true)` when it is allowed.
    static func ask(_ done: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { ok in DispatchQueue.main.async { done(ok) } }
    }

    static var allowed: Bool { AVAudioApplication.shared.recordPermission == .granted }

    /// The audio session must already be play-and-record (AudioHost.configureSession(mic: true)).
    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { status = "no mic on this device"; return false }
        input.installTap(onBus: 0, bufferSize: 512, format: fmt) { [weak self] buf, _ in
            guard let self, let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
            self.onSamples?(UnsafePointer(ch), n, fmt.sampleRate)
            DispatchQueue.main.async { self.level = max(rms * 4, self.level * 0.8) }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            status = "the mic would not open: \(error.localizedDescription)"
            return false
        }
        running = true
        status = "listening at \(Int(fmt.sampleRate)) Hz"
        return true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
        status = "off"
    }
}
