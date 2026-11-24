import Foundation
import Security
import UIKit

/// The BUG button, iPhone edition (Android: Notes.kt). Notes go to the same inbox, hubbub0/Mess-Machine, as GitHub
/// issues labeled `from-app`, the category and `ios`, with the same title and body shape, so Claude triages both
/// apps' notes the same way. With a key (a GitHub token that can only write issues on that repo) Send posts from
/// inside the app; without one it opens GitHub's new-issue page, filled in, and you tap Submit there.
struct MNote: Identifiable, Codable, Equatable {
    var id: String
    var cat: String
    var topic: String = ""
    var text: String
    var at: Date
    var build: String
    var screen: String
    var issue: Int = 0
    var status: String = ""
    /// Claude's replies on the issue, "login: text". Optional so notes saved before replies existed still load.
    var replies: [String]? = nil
}

enum NoteKinds {
    static let all: [(String, String)] = [("bug", "Bug"), ("tuning", "Tuning"), ("feature", "Feature"),
                                          ("question", "Question"), ("discuss", "Discuss"), ("wishlist", "Wishlist")]
    static func label(_ c: String) -> String { all.first { $0.0 == c }?.1 ?? "Note" }
}

final class NotesBook: ObservableObject {
    static let repo = "hubbub0/Mess-Machine"
    @Published private(set) var notes: [MNote] = []
    @Published private(set) var lastMessage = ""
    @Published private(set) var checking = false

    private let file: URL
    private var trail: [String] = []
    private let t0 = Date()

    init(dir: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        file = dir.appendingPathComponent("notes.json")
        if let d = try? Data(contentsOf: file), let n = try? JSONDecoder().decode([MNote].self, from: d) { notes = n }
    }

    private func save() { if let d = try? JSONEncoder().encode(notes) { try? d.write(to: file, options: .atomic) } }

    func add(_ n: MNote) { notes.insert(n, at: 0); save() }

    private func replace(_ n: MNote) {
        if let i = notes.firstIndex(where: { $0.id == n.id }) { notes[i] = n; save() }
    }

    /// What happened lately, newest last, for the issue body (same stamp and ×n folding as Android).
    func trail(_ what: String) {
        let s = Int(Date().timeIntervalSince(t0))
        let stamp = String(format: "%d:%02d", s / 60, s % 60)
        if let last = trail.last, let sp = last.firstIndex(of: " ") {
            let body = last[last.index(after: sp)...]
            let name = body.components(separatedBy: " ×").first ?? String(body)
            if name == what {
                let n = Int(body.components(separatedBy: " ×").dropFirst().first ?? "1") ?? 1
                trail[trail.count - 1] = "\(stamp) \(what) ×\(n + 1)"
                return
            }
        }
        trail.append("\(stamp) \(what)")
        if trail.count > 60 { trail.removeFirst(trail.count - 60) }
    }

    /// Voice or typed prefixes pick the category: "wishlist: ...", "discuss jumping: ...", "tuning: ...".
    static func parsePrefix(_ text: String, cat: String, topic: String) -> (String, String, String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = t.lowercased()
        for (c, _) in NoteKinds.all where low.hasPrefix("\(c):") || low.hasPrefix("\(c) ") {
            let rest = String(t.dropFirst(c.count)).trimmingCharacters(in: CharacterSet(charactersIn: ":,. "))
            if c == "discuss", let colon = rest.firstIndex(of: ":") {
                return (c, rest[..<colon].trimmingCharacters(in: .whitespaces), rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
            return (c, c == "discuss" ? topic : "", rest)
        }
        return (cat, topic, t)
    }

    static func newId() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 100...999))
    }

    static func late(_ n: MNote, now: Date = Date()) -> Bool { now.timeIntervalSince(n.at) > 30 * 60 }

    private static func fmt(_ f: String, _ d: Date) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = f
        return df.string(from: d)
    }

    static func title(_ n: MNote, now: Date = Date()) -> String {
        let head = n.cat == "discuss" ? "[Discuss: \(n.topic.isEmpty ? "general" : n.topic)] " : "[\(NoteKinds.label(n.cat))] "
        let written = late(n, now: now) ? "(written \(fmt("MMM d", n.at))) " : ""
        let first = String((n.text.components(separatedBy: "\n").first ?? "").prefix(70))
        return head + written + (first.isEmpty ? "(no text)" : first)
    }

    func body(_ n: MNote, details: String, trailLines: Int = 60, now: Date = Date()) -> String {
        var b = n.text.isEmpty ? "(no text)" : n.text
        if Self.late(n, now: now) {
            b += "\n\n**Written \(Self.fmt("MMM d, h:mm a", n.at)) on build \(n.build), sent \(Self.fmt("MMM d, h:mm a", now)).**"
        }
        b += "\n\n---\n**Category:** \(NoteKinds.label(n.cat))"
        if n.cat == "discuss" { b += " · **Topic:** \(n.topic.isEmpty ? "general" : n.topic)" }
        b += "\n**Screen:** \(n.screen) · **Build:** \(n.build)\n"
        b += details
        let tl = trail.suffix(trailLines)
        if !tl.isEmpty && trailLines > 0 {
            b += "\n<details><summary>Last \(tl.count) actions</summary>\n\n```\n" + tl.joined(separator: "\n") + "\n```\n</details>\n"
        }
        b += "\n<!-- mm-note:\(n.id) -->\n"
        return b
    }

    static func labels(_ n: MNote) -> [String] { ["from-app", n.cat, "ios"] }

    /// GitHub's new-issue page, filled in, cut to fit a URL the way Android does.
    func pageURL(_ n: MNote, details: String) -> URL {
        func enc(_ s: String) -> String {
            var ok = CharacterSet.alphanumerics; ok.insert(charactersIn: "-._~")
            return s.addingPercentEncoding(withAllowedCharacters: ok) ?? ""
        }
        var lines = 40
        func make() -> String {
            "https://github.com/\(Self.repo)/issues/new?title=" + enc(Self.title(n)) + "&labels=" + enc(Self.labels(n).joined(separator: ",")) +
                "&body=" + enc(body(n, details: details, trailLines: lines))
        }
        var u = make()
        while u.count > 7600 && lines > 0 { lines -= 10; u = make() }
        return URL(string: u)!
    }

    /// Send: post it with the key when there is one, else open the filled-in GitHub page.
    func send(_ n: MNote, details: String, done: @escaping (String) -> Void = { _ in }) {
        guard let key = Keychain.get("notes-key"), !key.isEmpty else {
            UIApplication.shared.open(pageURL(n, details: details))
            var m = n; m.status = "opened on GitHub, not seen there yet"; replace(m)
            return
        }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/issues")!)
        req.httpMethod = "POST"
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("MessMachine-iOS", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["title": Self.title(n), "body": body(n, details: details), "labels": Self.labels(n)])
        var m = n; m.status = "sending"; replace(m)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let msg: String
            var out = n
            if err != nil {
                out.status = "waiting to send"; msg = "No connection. The note waits; tap Send to try again."
            } else if (200...299).contains(code), let d = data,
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let num = o["number"] as? Int {
                out.issue = num; out.status = "open"; msg = "Sent to Claude as note #\(num)."
            } else if code == 401 || code == 403 {
                msg = "GitHub refused the key (it may have run out). Paste a new one, or send this one with the page."
            } else {
                msg = "GitHub said \(code). The note is kept; tap Send to try again."
            }
            DispatchQueue.main.async { self.replace(out); self.lastMessage = msg; done(msg) }
        }.resume()
    }

    /// The status a note shows, from its issue's labels and state (the same words as Android).
    static func status(labels: [String], closed: Bool) -> String {
        if labels.contains("fixed") { return "fixed" }
        if labels.contains("wishlist") { return "on the wishlist" }
        if labels.contains("wontfix") { return "won't fix" }
        if labels.contains("discuss") && !closed { return "waiting to discuss" }
        return closed ? "closed" : "open"
    }

    /// The note ids an issue body carries (a bundle can carry several).
    static func noteIds(inBody body: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "mm-note:([A-Za-z0-9]+)") else { return [] }
        return re.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        }
    }

    /// Read Claude's replies from the issues. Public repo, so no key is needed to read.
    func checkReplies(done: @escaping (String) -> Void = { _ in }) {
        guard !checking else { return }
        checking = true
        let mine = Set(notes.map(\.id))
        Task {
            var msg: String
            var updates: [MNote] = []
            do {
                let issues = try await Self.getJSON("https://api.github.com/repos/\(Self.repo)/issues?labels=from-app,ios&state=all&per_page=100") as? [[String: Any]] ?? []
                var matched = 0, fresh = 0
                for m in issues {
                    let ids = Self.noteIds(inBody: m["body"] as? String ?? "").filter { mine.contains($0) }
                    guard !ids.isEmpty else { continue }
                    let labels = (m["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    let st = Self.status(labels: labels, closed: (m["state"] as? String) == "closed")
                    var replies: [String] = []
                    if (m["comments"] as? Int ?? 0) > 0, let cu = m["comments_url"] as? String {
                        let cs = try await Self.getJSON(cu) as? [[String: Any]] ?? []
                        replies = cs.map { (($0["user"] as? [String: Any])?["login"] as? String ?? "") + ": " + ($0["body"] as? String ?? "") }
                    }
                    for id in ids {
                        guard var n = await MainActor.run(body: { self.notes.first { $0.id == id } }) else { continue }
                        matched += 1
                        fresh += max(0, replies.count - (n.replies?.count ?? 0))
                        n.issue = m["number"] as? Int ?? n.issue
                        n.status = st
                        n.replies = replies
                        updates.append(n)
                    }
                }
                msg = matched == 0 ? "None of your notes are on GitHub yet. Send one, then tap Submit on the page that opens."
                    : fresh > 0 ? "\(fresh) new repl\(fresh == 1 ? "y" : "ies")." : "No new replies."
            } catch {
                msg = "Could not reach GitHub: \(error.localizedDescription)"
            }
            let final = msg, ups = updates
            await MainActor.run {
                for u in ups { self.replace(u) }
                self.checking = false
                self.lastMessage = final
                done(final)
            }
        }
    }

    private static func getJSON(_ u: String) async throws -> Any {
        var req = URLRequest(url: URL(string: u)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MessMachine-iOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (d, r) = try await URLSession.shared.data(for: req)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "GitHub said \(code)"]) }
        return try JSONSerialization.jsonObject(with: d)
    }

    static func device() -> String {
        var sys = utsname(); uname(&sys)
        let model = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return "Apple \(model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
}

/// The notes key lives in the Keychain, never in the mess or the notes file.
enum Keychain {
    static func set(_ key: String, _ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}
