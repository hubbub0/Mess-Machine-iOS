import AVFoundation
import Foundation
import Speech

/// Say a note instead of typing it (Android: VoiceNote.kt, SpeechRecognizer restarted until the second tap).
/// iOS keeps listening on one request until stopped, so one tap starts and the next one stops.
final class VoiceNote: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    @Published private(set) var status = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// Ask for speech and the mic, then listen. `prepareSession` switches the audio session to play and record.
    func start(prepareSession: () -> Void) {
        guard !listening else { return }
        guard let recognizer, recognizer.isAvailable else { status = "Speech isn't available on this device right now. Type the note instead."; return }
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                guard auth == .authorized else {
                    self.status = "Speech is off for Mess Machine. Turn it on in Settings, Privacy, Speech Recognition."
                    return
                }
                MicIn.ask { ok in
                    guard ok else { self.status = "The mic is off for Mess Machine. Turn it on in Settings, Privacy, Microphone."; return }
                    self.listen(recognizer)
                }
            }
        }
        prepareSession()
    }

    private func listen(_ recognizer: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // on the phone when it can: nothing leaves it
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        heard = ""
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { status = "No mic on this device."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            status = "The mic would not open: \(error.localizedDescription)"
            return
        }
        listening = true
        status = "Listening. Tap again when you're done."
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let r = result { self.heard = r.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self.finish() }
            }
        }
    }

    /// Stop listening; what was heard stays in `heard`.
    func stop() {
        guard listening else { return }
        request?.endAudio()
        finish()
    }

    private func finish() {
        guard listening else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        task?.finish()
        task = nil
        request = nil
        listening = false
        status = heard.isEmpty ? "Didn't catch anything." : ""
    }
}
