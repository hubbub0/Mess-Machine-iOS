import Foundation

#if canImport(MessMachine)
import MessMachine

/// Sound packs (SE-17), as Android's AndroidPacks: a pack is a zip on the `packs` release of hubbub0/Mess-Machine
/// (pack.json plus a clips folder of FLAC files), listed in that release's packs.json. Installed packs live in
/// Documents/packs and show up as a jar in Sounds; their keys ("pack:<id>:<clip>") save in messes like any sound.
final class IosPacks: NSObject, Packs {
    private let root: URL
    private let dir: URL
    private let lib: Library
    let installed = KotlinMutableDictionary<NSString, KotlinInt>()
    /// Why the last network or install step failed (Swift cannot throw into Kotlin until the interface says @Throws).
    private(set) var lastProblem = ""

    init(root: String, lib: Library) {
        self.root = URL(fileURLWithPath: root)
        dir = self.root.appendingPathComponent("packs")
        self.lib = lib
        super.init()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func safe(_ id: String) -> Bool { id.range(of: "^[a-z0-9][a-z0-9-]{0,40}$", options: .regularExpression) != nil }

    func loadInstalled() {
        let fm = FileManager.default
        for d in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            if (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, !d.lastPathComponent.hasSuffix(".part") {
                try? register(d)
            }
        }
    }

    #if MM_IOS_APP
    // Packs is @Throws (core PR #26): a failure reaches AppState's message, as on Android
    func fetchOffers() throws -> [PacksOffer] { try offers() }
    func install(o: PacksOffer) throws { try download(o) }
    func installZip(zip: MFile, id: String) throws { try unpack(URL(fileURLWithPath: zip.path), id: id) }
    #else
    func fetchOffers() -> [PacksOffer] {
        do { return try offers() } catch { lastProblem = "\(error)"; return [] }
    }
    func install(o: PacksOffer) {
        do { try download(o) } catch { lastProblem = "\(error)" }
    }
    func installZip(zip: MFile, id: String) {
        do { try unpack(URL(fileURLWithPath: zip.path), id: id) } catch { lastProblem = "\(error)" }
    }
    #endif

    func offers() throws -> [PacksOffer] {
        let rel = try json(get("https://api.github.com/repos/\(NoteBookKt.REPO)/releases/tags/packs", json: true)) as? [String: Any] ?? [:]
        let assets = (rel["assets"] as? [[String: Any]]) ?? []
        guard let index = assets.first(where: { $0["name"] as? String == "packs.json" }),
              let indexURL = index["browser_download_url"] as? String else { return [] }
        let list = try json(get(indexURL, json: false)) as? [[String: Any]] ?? []
        return list.compactMap { m -> PacksOffer? in
            let file = m["file"] as? String ?? ""
            guard let asset = assets.first(where: { $0["name"] as? String == file }) else { return nil }
            let id = m["id"] as? String ?? ""
            guard Self.safe(id) else { return nil }
            return PacksOffer(id: id, name: m["name"] as? String ?? "", blurb: m["blurb"] as? String ?? "",
                              version: Int32((m["version"] as? NSNumber)?.intValue ?? 1), clips: Int32((m["clips"] as? NSNumber)?.intValue ?? 0),
                              bytes: (asset["size"] as? NSNumber)?.int64Value ?? 0, url: asset["browser_download_url"] as? String ?? "")
        }
    }

    func download(_ o: PacksOffer) throws {
        let tmp = root.appendingPathComponent("pack-\(o.id).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try get(o.url, json: false, timeout: 30).write(to: tmp)
        try unpack(tmp, id: o.id)
    }

    /// Unpack a pack's zip into its own folder and register it. Every entry must stay inside that folder.
    func unpack(_ zip: URL, id: String) throws {
        guard Self.safe(id) else { throw Problem("bad pack id") }
        let fm = FileManager.default
        let into = dir.appendingPathComponent(id)
        let part = dir.appendingPathComponent(id + ".part")
        try? fm.removeItem(at: part)
        try fm.createDirectory(at: part, withIntermediateDirectories: true)
        let base = part.standardizedFileURL.path + "/"
        do {
            for e in try ZipReader.entries(Data(contentsOf: zip)) {
                let out = part.appendingPathComponent(e.name).standardizedFileURL
                guard out.path.hasPrefix(base) else { throw Problem("pack entry outside its folder: \(e.name)") }
                if e.isDirectory { try fm.createDirectory(at: out, withIntermediateDirectories: true); continue }
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try e.data.write(to: out)
            }
            guard fm.fileExists(atPath: part.appendingPathComponent("pack.json").path) else { throw Problem("not a pack: no pack.json") }
        } catch {
            try? fm.removeItem(at: part)
            throw error
        }
        remove(id: id)
        try fm.moveItem(at: part, to: into)
        try register(into)
    }

    /// Take a pack off the phone. Messes that use its sounds keep their keys; those pads go quiet until it is back.
    func remove(id: String) {
        lib.removeCab(id: "pack:\(id)")
        installed.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(id))
    }

    private func register(_ d: URL) throws {
        let m = try json(Data(contentsOf: d.appendingPathComponent("pack.json"))) as? [String: Any] ?? [:]
        let id = m["id"] as? String ?? d.lastPathComponent
        guard Self.safe(id) else { return }
        let name = m["name"] as? String ?? id
        let cab = "pack:\(id)"
        lib.addCab(id: cab, name: name, color: Int32(bitPattern: 0xFFFF7A1A))
        let folder = d.standardizedFileURL.path + "/"
        for c in (m["clips"] as? [[String: Any]]) ?? [] {
            let f = d.appendingPathComponent(c["file"] as? String ?? "").standardizedFileURL
            guard f.path.hasPrefix(folder), FileManager.default.fileExists(atPath: f.path) else { continue }
            let stem = f.deletingPathExtension().lastPathComponent
            let key = "pack:\(id):" + (c["id"] as? String ?? stem)
            let s = Library.Sound(key: key, title: c["title"] as? String ?? stem, cab: cab, file: f.path, a: 0, d: 0,
                                  group: c["group"] as? String ?? "", album: name)
            s.type = c["type"] as? String ?? "chop"
            s.bpm = (c["bpm"] as? NSNumber)?.doubleValue ?? 0
            s.beats = Int32((c["beats"] as? NSNumber)?.intValue ?? 0)
            for t in (c["tags"] as? [Any]) ?? [] { if let t = t as? String { s.tags.add(t) } }
            lib.addUser(s: s, chopOf: nil)
        }
        installed.setObject(KotlinInt(int: Int32((m["version"] as? NSNumber)?.intValue ?? 1)), forKey: id as NSString)
    }

    struct Problem: LocalizedError, CustomStringConvertible {
        let description: String
        init(_ s: String) { description = s }
        var errorDescription: String? { description }
    }

    private func json(_ d: Data) throws -> Any { try JSONSerialization.jsonObject(with: d) }

    /// A blocking GET: AppState calls packs on its worker thread, never the main one.
    private func get(_ u: String, json: Bool, timeout: TimeInterval = 15) throws -> Data {
        guard let url = URL(string: u) else { throw Problem("bad address") }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.setValue("MessMachine-iOS", forHTTPHeaderField: "User-Agent")
        if json { r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        var result: Result<Data, Error> = .failure(Problem("no connection"))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let err { result = .failure(err) }
            else if code == 404 { result = .failure(Problem("No packs have been sent yet.")) }
            else if !(200...299).contains(code) { result = .failure(Problem("GitHub said \(code)")) }
            else { result = .success(data ?? Data()) }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }
}
#endif
