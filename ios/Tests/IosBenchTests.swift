import XCTest
@testable import MessMachineApp
#if canImport(MessMachine)
import MessMachine

/// The iPhone Workbench as the shared screens use it: kept sounds must be in the Library (Android build 20 showed a
/// kept sound as "Missing" because they were not), survive a restart, and leave with their chops.
final class IosBenchTests: XCTestCase {
    private var dir: String!
    private var lib: Library!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "bench-\(UUID().uuidString)"
        lib = try Library(files: MMBundleSoundFiles(), base: "sounds/")
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    private func tone(seconds: Double = 0.5, rate: Int32 = 48000) -> Sample {
        let n = Int(Double(rate) * seconds)
        let f = (0..<n).map { Float(sin(Double($0) * 2 * .pi * 220 / Double(rate)) * 0.5) }
        return Sample(key: "", data: f.kotlinFloatArray(), rate: rate)
    }

    func testAKeptSoundIsInTheLibraryWithItsTitle() {
        let b = IosBench(dir: dir, lib: lib)
        let k = b.addSample(kind: "take", title: "Basement Kick", s: tone(), bpm: 100, beats: 0)
        XCTAssertTrue(k.hasPrefix("bn:"))
        XCTAssertTrue(lib.has(key: k))
        XCTAssertEqual(lib.titleOf(key: k), "Basement Kick")
        XCTAssertEqual(b.count(kind: "take"), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/" + String(k.dropFirst(3)) + ".wav"))
    }

    func testItComesBackAfterARestartAndPlaysFromItsWav() throws {
        let k = IosBench(dir: dir, lib: lib).addSample(kind: "mic", title: "Take 1", s: tone(), bpm: 0, beats: 0)
        let lib2 = try Library(files: MMBundleSoundFiles(), base: "sounds/")
        let b2 = IosBench(dir: dir, lib: lib2)
        XCTAssertNotNil(b2.item(key: k))
        XCTAssertTrue(lib2.has(key: k))
        XCTAssertEqual(lib2.sound(key: k)?.file, dir + "/" + String(k.dropFirst(3)) + ".wav")
    }

    func testRemoveTakesTheSoundAndItsChops() {
        let b = IosBench(dir: dir, lib: lib)
        let k = b.addSample(kind: "imp", title: "Loop", s: tone(), bpm: 0, beats: 0)
        let c = b.addChop(base: k, title: "Loop chop", st: 0.1, en: 0.4)
        XCTAssertTrue(c.hasPrefix("chop:"))
        XCTAssertTrue(lib.has(key: c))
        b.remove(key: k)
        XCTAssertNil(b.item(key: k))
        XCTAssertNil(b.item(key: c))
        XCTAssertFalse(lib.has(key: k))
        XCTAssertFalse(lib.has(key: c))
    }

    func testTrimKeepsTheSoundAndDropsTheQuiet() {
        let b = IosBench(dir: dir, lib: lib)
        let rate: Int32 = 48000
        var f = [Float](repeating: 0, count: 24000)                            // 0.5 s of silence
        f += (0..<9600).map { Float(sin(Double($0) * 0.05) * 0.5) }             // 0.2 s of sound
        f += [Float](repeating: 0, count: 24000)                               // 0.5 s of silence
        let t = b.trimSilence(s: Sample(key: "", data: f.kotlinFloatArray(), rate: rate))
        XCTAssertNotNil(t)
        let secs = Double(t!.data.size) / Double(rate)
        XCTAssertGreaterThan(secs, 0.19)
        XCTAssertLessThan(secs, 0.3, "the silence should be cut (got \(secs) s)")
        XCTAssertNil(b.trimSilence(s: Sample(key: "", data: [Float](repeating: 0, count: 4800).kotlinFloatArray(), rate: rate)))
    }
}
#endif
