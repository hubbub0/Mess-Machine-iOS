import Foundation

/// The built-in sounds, bundled as the app's `sounds/` folder (a copy of core/app/src/main/assets/sounds: library.json,
/// the one-shots, loops/ and hits/). This is what the shared Kotlin engine's `SoundFiles.read(path)` reads on iOS.
enum BundleSounds {
    static let root: URL? = Bundle.main.url(forResource: "sounds", withExtension: nil)

    /// The bytes of a file under sounds/, or nil when there is none. Accepts "loops/x.flac" or "sounds/loops/x.flac";
    /// never reads outside the folder.
    static func read(_ path: String) -> Data? {
        guard let root else { return nil }
        var p = path
        while p.hasPrefix("/") { p.removeFirst() }
        if p.hasPrefix("sounds/") { p.removeFirst("sounds/".count) }
        guard !p.isEmpty, !p.split(separator: "/").contains("..") else { return nil }
        return try? Data(contentsOf: root.appendingPathComponent(p))
    }
}
