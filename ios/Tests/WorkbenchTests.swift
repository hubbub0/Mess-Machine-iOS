import XCTest
@testable import MessMachineApp

final class WorkbenchTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func tone(_ n: Int, rate: Double = 48000) -> [Float] {
        (0..<n).map { Float(sin(2 * Double.pi * 440 * Double($0) / rate)) * 0.5 }
    }

    func testKeptTakeIsAWavThatReadsBackTheSame() throws {
        let b = Workbench(dir: dir)
        let s = tone(4800)
        let item = try XCTUnwrap(b.keep(samples: s, rate: 48000, kind: "mic", title: "Mic take 1"))
        XCTAssertTrue(item.key.hasPrefix("bn:"))
        XCTAssertEqual(item.seconds, 0.1, accuracy: 1e-9)
        let (back, rate) = try Workbench.readMono(b.url(of: item))
        XCTAssertEqual(rate, 48000)
        XCTAssertEqual(back.count, s.count)
        for i in stride(from: 0, to: s.count, by: 97) { XCTAssertEqual(back[i], s[i], accuracy: 1.0 / 16000) }
    }

    func testTheIndexSurvivesARestart() {
        let a = Workbench(dir: dir)
        a.keep(samples: tone(480), rate: 48000, kind: "imp", title: "Thing")
        let again = Workbench(dir: dir)
        XCTAssertEqual(again.items.map(\.title), ["Thing"])
        XCTAssertNotNil(again.item(key: again.items[0].key))
        again.remove(again.items[0])
        XCTAssertTrue(Workbench(dir: dir).items.isEmpty)
    }

    func testTakesLoseTheirSilentEdges() {
        let s = [Float](repeating: 0, count: 4800) + tone(4800) + [Float](repeating: 0, count: 4800)
        let t = Workbench.trimSilence(s, rate: 48000)
        XCTAssertLessThan(t.count, 4800 + 2 * 480 + 2)
        XCTAssertGreaterThan(t.count, 4700)
        XCTAssertTrue(Workbench.trimSilence([Float](repeating: 0.001, count: 1000)).isEmpty, "a quiet take keeps nothing")
    }

    func testTakeRecordedThroughFeedIsKept() {
        let b = Workbench(dir: dir)
        b.startTake()
        let s = tone(9600)
        s.withUnsafeBufferPointer { p in
            for k in stride(from: 0, to: s.count, by: 480) { b.feed(p.baseAddress! + k, 480, rate: 48000) }
        }
        let item = b.stopTake()
        XCTAssertEqual(item?.kind, "mic")
        XCTAssertEqual(item?.title, "Mic take 1")
        XCTAssertFalse(b.recording)
    }

    func testResampleKeepsTheLength() {
        XCTAssertEqual(Workbench.resample(tone(44100, rate: 44100), from: 44100, to: 48000).count, 48000)
        XCTAssertEqual(Workbench.resample([1, 2, 3], from: 48000, to: 48000), [1, 2, 3])
    }
}
