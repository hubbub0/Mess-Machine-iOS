import XCTest
@testable import MessMachine

#if canImport(MessEngine)
import MessEngine

/// The shared Kotlin engine on iOS: it reads the bundled FLAC sounds, opens a mess and makes real sound.
final class SharedEngineTests: XCTestCase {
    private func peak(_ e: SharedEngine, blocks: Int) -> Float {
        let n = 256
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: n * 2)
        defer { buf.deallocate() }
        var p: Float = 0
        for _ in 0..<blocks {
            e.render(buf, frames: n, rate: 48000)
            for i in 0..<(n * 2) { p = max(p, abs(buf[i])) }
        }
        return p
    }

    private func example() throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "example.mess", withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSilentUntilAskedThenTheLoopPlays() throws {
        let e = try SharedEngine(rate: 48000)
        XCTAssertEqual(peak(e, blocks: 20), 0, "nothing loaded, nothing playing: silence")
        let r = try XCTUnwrap(e.open(try example()))
        XCTAssertEqual(r.missing, 0)
        XCTAssertGreaterThanOrEqual(e.loadedPads().count, 4)
        e.play()
        // two seconds of the example at 96 BPM: the kick on step 1 and more
        let p = peak(e, blocks: 375)
        XCTAssertGreaterThan(p, 0.02, "the example loop makes sound (peak \(p))")
        XCTAssertTrue(e.isPlaying)
        e.stop()
    }

    func testAPadHitMakesSound() throws {
        let e = try SharedEngine(rate: 48000)
        e.open(try example())
        let pad = try XCTUnwrap(e.loadedPads().first)
        e.hit(pad: pad.pad, holdMs: 1000)
        XCTAssertGreaterThan(peak(e, blocks: 40), 0.02, "pad \(pad.pad + 1) (\(pad.key)) sounds")
    }

    func testSoundFilesReadsTheBundleThroughKotlin() throws {
        let f = MMBundleSoundFiles()
        let kick = try XCTUnwrap(try f.read(path: "sounds/basement-kick.flac"))
        XCTAssertGreaterThan(kick.size, 1000)
        XCTAssertEqual(kick.get(index: 0), Int8(bitPattern: UInt8(ascii: "f")))
        XCTAssertEqual(MMBundleSoundFiles.data(forPath: "loops/../../Info.plist"), nil)
        XCTAssertEqual(MMBundleSoundFiles.data(forPath: "sounds/basement-kick.flac")?.count, Int(kick.size))
    }
}
#endif
