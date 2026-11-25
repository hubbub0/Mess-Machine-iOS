import Foundation

/// One pad of the open mess: its number (0 to 63) and sound key.
struct PadRef: Identifiable, Equatable {
    let pad: Int
    let key: String
    var id: Int { pad }
}

#if canImport(MessEngine)
import MessEngine

/// The shared Kotlin engine (core/core, built by tools/build-engine.sh as the static MessEngine framework), the same
/// code Android runs. It renders on AudioHost's writer thread straight into the block buffer (`renderInto`, iosMain);
/// pads, play and stop go through its command queue, so any thread may call them.
final class SharedEngine: BlockRenderer {
    let engine: Engine
    let lib: Library
    let rate: Int
    /// Workbench sounds still play through the stand-in until the engine's Workbench screens arrive.
    let extra = ToneEngine()
    private var mix = [Float]()
    private(set) var project: Project?
    private var nextId: Int32 = 1

    init(rate: Int) throws {
        self.rate = rate
        lib = try Library(files: MMBundleSoundFiles(), base: "sounds/")
        engine = Engine(rate: Int32(rate))
    }

    static var available: Bool { true }

    func render(_ buf: UnsafeMutablePointer<Float>, frames: Int, rate: Int) {
        engine.renderInto(out: buf, frames: Int32(frames))
        if mix.count < frames * 2 { mix = [Float](repeating: 0, count: frames * 2) }
        mix.withUnsafeMutableBufferPointer { m in
            extra.render(m.baseAddress!, frames: frames, rate: rate)
            for i in 0..<(frames * 2) { buf[i] += m[i] }
        }
    }

    /// Open a mess with the engine's own loader (the format's reference), decode its sounds, and hand it to the engine.
    /// Blocking: call off the main thread. Returns the missing count, or nil when the text is not a mess.
    @discardableResult
    func open(_ text: String) -> (missing: Int, newer: Bool)? {
        let known = Known(lib: lib)
        guard let loaded = try? Project.Companion.shared.fromJson(text: text, known: known) else { return nil }
        let p = loaded.project
        let kit = p.kit
        for i in 0..<Int(kit.size) {
            if let k = kit.get(index: Int32(i)) as? String, !k.isEmpty { _ = try? lib.load(key: k) }
        }
        project = p
        engine.setSnapshot(s: Engine.SnapshotCompanion.shared.build(p: p, src: lib, live: nil))
        return (Int(loaded.missing), loaded.newer)
    }

    func play() { engine.play() }
    func stop() { engine.stop() }
    var isPlaying: Bool { engine.isPlaying() }

    /// A pad tap, at the sound's own pitch, like a finger on the pad: down now, up after `holdMs`.
    func hit(pad: Int, velocity: Float = -1, holdMs: Int = 120) {
        let id = nextId; nextId &+= 1
        let pitches = KotlinIntArray(size: 1)
        pitches.set(index: 0, value: 0)
        engine.down(id: id, pad: Int32(pad), pitches: pitches, mel: false, latch: false, vel: velocity)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(holdMs)) { [engine] in engine.up(id: id) }
    }

    /// The first loaded pads of the open mess, for the day-one pad row.
    func loadedPads(max n: Int = 8) -> [PadRef] {
        guard let kit = project?.kit else { return [] }
        var out: [PadRef] = []
        for i in 0..<min(64, Int(kit.size)) where out.count < n {
            if let k = kit.get(index: Int32(i)) as? String, !k.isEmpty { out.append(PadRef(pad: i, key: k)) }
        }
        return out
    }

    private final class Known: ProjectKnown {
        let lib: Library
        init(lib: Library) { self.lib = lib }
        /// Android passes lib::has; the same here (Workbench keys join when the engine's Workbench does).
        func has(key: String) -> Bool { lib.has(key: key) }
    }
}

// The engine's SoundFiles is MMBundleSoundFiles (Objective-C, MMBundleSoundFiles.m): Kotlin's read(path) may both
// throw and return nothing, which a Swift class cannot implement for an Objective-C protocol.
#else
/// Built without the shared engine (core/ had none when this was built): ToneEngine stands in.
enum SharedEngineMissing {}
#endif
