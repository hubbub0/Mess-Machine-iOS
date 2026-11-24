import Foundation

/// The saved mess file, format v3, read and written the way core/shared/MESS-FORMAT.md says.
///
/// This is the iPhone's own check of the format until the shared Kotlin engine takes over loading. It reads every
/// top-level key, the loops, the song and the older forms (sections 3 to 7 and 9). The nested objects (`edits`,
/// `synths`, `padOpts`) and the motion, accent, chance and lock strings are carried through as they came, limited to
/// sounds on a pad, so a mess opened and saved here loses nothing the format keeps.
struct Mess {
    static let pads = 65            // 0...63 plus slot 64, the Synth tab's scratch synth
    static let slots = 8            // loops A to H
    static let letters = Array("ABCDEFGH")
    static let maxSteps = 128
    static let maxSong = 64
    static let ticks = 24
    static let scales = ["Chromatic", "Major", "Minor", "Harmonic minor", "Dorian", "Phrygian", "Mixolydian",
                         "Major pentatonic", "Minor pentatonic", "Blues"]

    struct Note: Equatable { var s: Int; var p: Int; var l: Int }

    struct Loop {
        var len = 16
        /// Rows with at least one hit; index = step.
        var steps: [String: [Bool]] = [:]
        var notes: [String: [Note]] = [:]
        var offs: [String: [Int]] = [:]
        var motion: [String: String] = [:]
        var acc: [String: String] = [:]
        var chance: [String: String] = [:]
        var locks: [String: String] = [:]

        func step(_ key: String, _ i: Int) -> Bool { (steps[key] ?? []).indices.contains(i) && steps[key]![i] }
        var used: Bool { steps.values.contains { $0.contains(true) } || !notes.isEmpty || !offs.isEmpty }
    }

    var name = ""
    var bpm = 112
    var kit = Array(repeating: "", count: Mess.pads)
    var sel = 0
    var pats = Array(repeating: Loop(), count: Mess.slots)
    /// One entry per bar slot: 0...7 a loop, -1 a rest. Trailing rests are not kept.
    var song: [Int] = []
    var swing = 0
    var squash = 0.5
    var level = 1.0
    var mutes: [String] = []
    var solos: [String] = []
    var scale = "Chromatic"
    var root = 0
    var fold = false
    var edits: [String: Any] = [:]
    var synths: [String: Any] = [:]
    var padOpts: [String: Any] = [:]
    var songMode = false
    var cur = 0

    var loadedCount: Int { kit.prefix(64).filter { !$0.isEmpty }.count }
    var loopsUsed: Int { pats.filter(\.used).count }
    private var onPad: Set<String> { Set(kit.filter { !$0.isEmpty }) }

    struct Loaded { var mess: Mess; var missing: Int }

    enum LoadError: Error { case notJSON }

    // MARK: reading

    /// `known` says whether a sound key resolves on this device (library, alias, pack, Workbench).
    static func load(_ text: String, known: (String) -> Bool) throws -> Loaded {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { throw LoadError.notJSON }
        var m = Mess()
        // valid JSON that is not an object loads as an empty mess, like Android (MESS-FORMAT section 10)
        guard let o = obj as? [String: Any] else { return Loaded(mess: m, missing: 0) }

        m.name = str(o["name"]) ?? ""
        m.bpm = Int(clamp(num(o["bpm"]) ?? 112, 60, 180))
        let synthsIn = (o["synths"] as? [String: Any]) ?? [:]

        // the kit: known keys go on their pad, a repeated key keeps only its first pad, unknown keys count as missing
        var missing = 0
        var placed = Set<String>()
        if let kit = o["kit"] as? [Any] {
            for (i, v) in kit.prefix(pads).enumerated() {
                guard let k = v as? String, !k.isEmpty else { continue }
                let ok = k.hasPrefix("synth:") ? synthsIn[k] != nil : known(k)
                if !ok { missing += 1; continue }
                if placed.contains(k) { continue }
                placed.insert(k)
                m.kit[i] = k
            }
        }
        let first = (0..<64).first { !m.kit[$0].isEmpty } ?? 0
        if let s = num(o["sel"]), s >= 0, s < 64, !m.kit[Int(s)].isEmpty { m.sel = Int(s) } else { m.sel = first }

        // loops: pats, or the oldest files' top-level steps as loop A
        if let pats = o["pats"] as? [Any], !pats.isEmpty {
            for (i, p) in pats.prefix(slots).enumerated() {
                if let d = p as? [String: Any] { m.pats[i] = readLoop(d, onPad: placed) }
            }
            if let s = str(o["song"]) {
                var song = s.prefix(maxSong).map { c -> Int in letters.firstIndex(of: c) ?? -1 }
                while song.last == -1 { song.removeLast() }
                m.song = song
            }
        } else if let st = o["steps"] as? [String: Any] {
            m.pats[0] = readLoop(["len": 16, "steps": st], onPad: placed)
        }

        m.swing = Int(clamp(num(o["swing"]) ?? 0, 0, 100))
        m.squash = clamp(num(o["squash"]) ?? 0.5, 0, 1)
        m.level = clamp(num(o["level"]) ?? 1, 0, 1.6)
        m.mutes = (o["mutes"] as? [Any] ?? []).compactMap { $0 as? String }
        m.solos = (o["solos"] as? [Any] ?? []).compactMap { $0 as? String }
        let sc = str(o["scale"]) ?? "Chromatic"
        m.scale = scales.contains(sc) ? sc : "Chromatic"
        m.root = Int(clamp(num(o["root"]) ?? 0, 0, 11))
        m.fold = bool(o["fold"]) ?? false
        m.edits = ((o["edits"] as? [String: Any]) ?? [:]).filter { placed.contains($0.key) }
        m.synths = synthsIn.filter { $0.key.hasPrefix("synth:") }
        m.padOpts = ((o["padOpts"] as? [String: Any]) ?? [:]).filter { k, _ in Int(k).map { (0...64).contains($0) } ?? false }
        m.songMode = str(o["mode"]) == "song" && m.songLen > 0
        m.cur = Int(clamp(num(o["cur"]) ?? 0, 0, 7))
        return Loaded(mess: m, missing: missing)
    }

    var songLen: Int { song.count }

    private static func readLoop(_ d: [String: Any], onPad: Set<String>) -> Loop {
        var L = Loop()
        if let n = num(d["len"]), (16.0...Double(maxSteps)).contains(n), n == n.rounded(), Int(n) % 16 == 0 { L.len = Int(n) }
        for (k, v) in (d["steps"] as? [String: Any]) ?? [:] where onPad.contains(k) {
            guard let s = v as? String else { continue }
            let row = s.prefix(maxSteps).map { $0 == "1" }
            if row.contains(true) { L.steps[k] = row }
        }
        // offs before notes, after len: a tick on a step becomes a normal hit
        for (k, v) in (d["offs"] as? [String: Any]) ?? [:] where onPad.contains(k) {
            guard let s = v as? String else { continue }
            var set = Set<Int>()
            for part in s.split(separator: ",") {
                guard let t = Int(part.trimmingCharacters(in: .whitespaces)) else { continue }
                let total = L.len * ticks
                let w = ((t % total) + total) % total
                if w % ticks == 0 {
                    var row = L.steps[k] ?? Array(repeating: false, count: L.len)
                    if row.count < L.len { row += Array(repeating: false, count: L.len - row.count) }
                    row[w / ticks] = true
                    L.steps[k] = row
                } else { set.insert(w) }
            }
            if !set.isEmpty { L.offs[k] = set.sorted() }
        }
        // notes: a map, or the older one-instrument string with "inst"
        if let map = d["notes"] as? [String: Any] {
            for (k, v) in map where onPad.contains(k) {
                if let s = v as? String { let ns = decNotes(s, len: L.len); if !ns.isEmpty { L.notes[k] = ns } }
            }
        } else if let s = d["notes"] as? String, let inst = d["inst"] as? String, !inst.isEmpty, onPad.contains(inst) {
            let ns = decNotes(s, len: L.len); if !ns.isEmpty { L.notes[inst] = ns }
        }
        L.motion = strings(d["motion"])
        L.acc = strings(d["acc"]).filter { onPad.contains($0.key) }
        L.chance = strings(d["chance"]).filter { onPad.contains($0.key) }
        L.locks = strings(d["locks"]).filter { k, _ in onPad.contains(k.components(separatedBy: "@").dropLast().joined(separator: "@")) }
        return L
    }

    static func decNotes(_ s: String, len: Int) -> [Note] {
        var out: [Note] = []
        for part in s.split(separator: ",") {
            let f = part.split(separator: ".", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard f.count >= 3, let st = f[0], let p = f[1], let l = f[2] else { continue }
            guard st >= 0, st < len else { continue }
            out.append(Note(s: st, p: max(-36, min(24, p)), l: max(1, min(len - st, l))))
        }
        return out
    }

    // MARK: writing

    /// The file as a JSON object, `app: "ios"`. Compare files by loading them, not by text (MESS-FORMAT section 1).
    func json(at date: Date = Date()) -> [String: Any] {
        let pads = onPad
        let loaded = kit.filter { !$0.isEmpty }
        func loopJSON(_ L: Loop) -> [String: Any] {
            var d: [String: Any] = ["len": L.len]
            var st: [String: String] = [:]
            for k in loaded {
                let row = L.steps[k] ?? []
                st[k] = String((0..<L.len).map { $0 < row.count && row[$0] ? Character("1") : Character("0") })
            }
            d["steps"] = st
            var ns: [String: String] = [:]
            for (k, v) in L.notes where pads.contains(k) && !v.isEmpty { ns[k] = v.map { "\($0.s).\($0.p).\($0.l)" }.joined(separator: ",") }
            d["notes"] = ns
            if !L.motion.isEmpty { d["motion"] = L.motion }
            let offs = L.offs.filter { pads.contains($0.key) && !$0.value.isEmpty }
            if !offs.isEmpty { d["offs"] = offs.mapValues { $0.map(String.init).joined(separator: ",") } }
            let acc = L.acc.filter { pads.contains($0.key) }
            if !acc.isEmpty { d["acc"] = acc }
            let ch = L.chance.filter { pads.contains($0.key) }
            if !ch.isEmpty { d["chance"] = ch }
            if !L.locks.isEmpty { d["locks"] = L.locks }
            return d
        }
        var o: [String: Any] = [:]
        let nm = name.isEmpty ? "Untitled mess" : name
        let units = Array(nm.utf16.prefix(48))
        o["name"] = String(utf16CodeUnits: units, count: units.count)
        o["bpm"] = bpm
        o["v"] = 3
        o["kit"] = kit
        o["sel"] = sel
        o["steps"] = (loopJSON(pats[0])["steps"] as? [String: String]) ?? [:]
        o["pats"] = pats.map(loopJSON)
        let songText = String(song.map { (i: Int) -> Character in i >= 0 && i < 8 ? Mess.letters[i] : Character("-") })
        o["song"] = songText.padding(toLength: max(16, song.count), withPad: "-", startingAt: 0)
        o["swing"] = swing
        if squash != 0.5 { o["squash"] = squash }
        if level != 1 { o["level"] = level }
        o["mutes"] = mutes
        o["solos"] = solos
        o["scale"] = scale
        o["root"] = root
        o["fold"] = fold
        o["edits"] = edits.filter { pads.contains($0.key) }
        let sy = synths.filter { pads.contains($0.key) }
        if !sy.isEmpty { o["synths"] = sy }
        if !padOpts.isEmpty { o["padOpts"] = padOpts }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        o["at"] = iso.string(from: date)
        o["app"] = "ios"
        o["mode"] = songMode ? "song" : "loop"
        o["cur"] = cur
        return o
    }

    func text() -> String {
        let data = (try? JSONSerialization.data(withJSONObject: json(), options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The shared file name: `<slug of the name>.json`.
    var fileName: String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let s = String(slug).split(separator: "-").joined(separator: "-")
        return (s.isEmpty ? "mess" : String(s.prefix(40))) + ".json"
    }

    /// One line for notes and the screen, like Android's **Mess:** line, never the name (the repo is public).
    var summary: String {
        "\(bpm) BPM, swing \(swing)%, \(loadedCount) pads, \(loopsUsed) loops, " +
            (songMode ? "song mode (\(songLen) bars)" : "loop \(Mess.letters[cur])") + ", \(root < 12 ? ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"][root] : "?") \(scale)"
    }

    // MARK: JSON helpers (wrong types count as missing, MESS-FORMAT section 10)

    private static func isBool(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }
    static func num(_ v: Any?) -> Double? { isBool(v) ? nil : (v as? NSNumber)?.doubleValue }
    static func str(_ v: Any?) -> String? { v as? String }
    static func bool(_ v: Any?) -> Bool? { isBool(v) ? (v as? NSNumber)?.boolValue : nil }
    static func strings(_ v: Any?) -> [String: String] { ((v as? [String: Any]) ?? [:]).compactMapValues { $0 as? String } }
    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
}

/// The built-in sound keys, from the same library.json the Android app ships (core/app/src/main/assets/sounds).
struct SoundLibrary {
    let keys: Set<String>
    let aliases: [String: String]

    init(keys: Set<String>, aliases: [String: String]) { self.keys = keys; self.aliases = aliases }

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        keys = Set(((o["sounds"] as? [[String: Any]]) ?? []).compactMap { $0["k"] as? String })
        aliases = (o["aliases"] as? [String: String]) ?? [:]
    }

    static let bundled: SoundLibrary = Bundle.main.url(forResource: "library", withExtension: "json").flatMap(SoundLibrary.init(url:))
        ?? SoundLibrary(keys: [], aliases: [:])

    /// Direct keys first; an alias never hides a real key. Packs and Workbench come later.
    func has(_ key: String) -> Bool { keys.contains(key) || aliases[key] != nil }

    var count: Int { keys.count }
}
