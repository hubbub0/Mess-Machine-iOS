import Foundation

/// The built-in sounds, bundled inside the app's `assets/` folder (assets/sounds) (a copy of core/app/src/main/assets/sounds: library.json,
/// the one-shots, loops/ and hits/). This is what the shared Kotlin engine's `SoundFiles.read(path)` reads on iOS.
enum BundleSounds {
    static let root: URL? = Bundle.main.url(forResource: "assets", withExtension: nil)?.appendingPathComponent("sounds")

    /// The bytes of a file under sounds/, or nil when there is none. Accepts "loops/x.flac" or "sounds/loops/x.flac";
    /// never reads outside the folder. A path starting with "/" is a full path on the phone (a Workbench sound), as the
    /// shared engine's SoundFiles contract says; only files inside the app's own container are read.
    static func read(_ path: String) -> Data? {
        if path.hasPrefix("/") {
            let home = NSHomeDirectory()
            let full = URL(fileURLWithPath: path).standardizedFileURL.path
            guard full.hasPrefix(home + "/") || full.hasPrefix(Bundle.main.bundlePath + "/") else { return nil }
            return try? Data(contentsOf: URL(fileURLWithPath: full))
        }
        guard let root else { return nil }
        var p = path
        if p.hasPrefix("sounds/") { p.removeFirst("sounds/".count) }
        guard !p.isEmpty, !p.split(separator: "/").contains("..") else { return nil }
        return try? Data(contentsOf: root.appendingPathComponent(p))
    }
}
