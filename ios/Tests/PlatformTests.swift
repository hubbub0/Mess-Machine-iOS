import XCTest
import UIKit
@testable import MessMachine

final class MidiParserTests: XCTestCase {
    func testNotesRunningStatusAndVelocityZero() {
        var p = MidiParser()
        // note on 36 vel 100, running status note 38 vel 90, then 36 vel 0 (= off)
        XCTAssertEqual(p.feed([0x90, 36, 100, 38, 90, 36, 0]), [.down(note: 36, vel: 100), .down(note: 38, vel: 90), .up(note: 36)])
    }

    func testRealtimeBytesInsideAMessageAreSkipped() {
        var p = MidiParser()
        XCTAssertEqual(p.feed([0x90, 0xF8, 60, 0xFE, 64]), [.down(note: 60, vel: 64)])
    }

    func testProgramChangeCarriesOneDataByte() {
        var p = MidiParser()
        XCTAssertEqual(p.feed([0xC0, 5, 0x80, 60, 0]), [.up(note: 60)], "the program number must not pair with the next byte")
    }

    func testControlChangeAndPitchBend() {
        var p = MidiParser()
        let e = p.feed([0xB0, 74, 127, 0xE0, 0x00, 0x40, 0xE0, 0x7F, 0x7F])
        XCTAssertEqual(e[0], .cc(num: 74, val: 127))
        XCTAssertEqual(e[1], .bend(0))
        if case let .bend(b) = e[2] { XCTAssertEqual(b, 8191.0 / 8192, accuracy: 1e-6) } else { XCTFail() }
    }

    func testUMPWordsBecomeMidi1Bytes() {
        XCTAssertEqual(MidiParser.bytes(ofUMP: 0x2090_2464), [0x90, 0x24, 0x64])
        XCTAssertEqual(MidiParser.bytes(ofUMP: 0x10F8_0000), [], "system real time (type 1) is not a note")
    }
}

final class NotesTests: XCTestCase {
    private func note(_ cat: String, _ text: String, topic: String = "", ago: TimeInterval = 0) -> MNote {
        MNote(id: "abc123", cat: cat, topic: topic, text: text, at: Date().addingTimeInterval(-ago), build: "ios 7", screen: "day one")
    }

    func testTitlesMatchAndroid() {
        XCTAssertEqual(NotesBook.title(note("bug", "Pads click\nmore words")), "[Bug] Pads click")
        XCTAssertEqual(NotesBook.title(note("discuss", "jump height", topic: "jumping")), "[Discuss: jumping] jump height")
        XCTAssertTrue(NotesBook.title(note("feature", "x", ago: 3600)).hasPrefix("[Feature] (written "))
        XCTAssertEqual(NotesBook.title(note("bug", "")), "[Bug] (no text)")
    }

    func testPrefixesPickTheKind() {
        XCTAssertEqual(NotesBook.parsePrefix("wishlist: a jam station", cat: "bug", topic: "").0, "wishlist")
        let d = NotesBook.parsePrefix("discuss jumping: too floaty", cat: "bug", topic: "")
        XCTAssertEqual(d.0, "discuss"); XCTAssertEqual(d.1, "jumping"); XCTAssertEqual(d.2, "too floaty")
        XCTAssertEqual(NotesBook.parsePrefix("just words", cat: "tuning", topic: "").0, "tuning")
    }

    func testBodyCarriesTheMarkerAndLabelsSayIOS() {
        let book = NotesBook(dir: FileManager.default.temporaryDirectory)
        let n = note("bug", "it broke")
        let b = book.body(n, details: "**Device:** test\n")
        XCTAssertTrue(b.contains("**Category:** Bug"))
        XCTAssertTrue(b.contains("<!-- mm-note:abc123 -->"))
        XCTAssertEqual(NotesBook.labels(n), ["from-app", "bug", "ios"])
        let url = book.pageURL(n, details: "**Device:** test\n").absoluteString
        XCTAssertTrue(url.hasPrefix("https://github.com/hubbub0/Mess-Machine/issues/new?title="))
        XCTAssertTrue(url.contains("labels=from-app%2Cbug%2Cios"))
    }
}

final class RingTests: XCTestCase {
    /// The C ring linked into the app, driven the way Core Audio and the writer thread drive it.
    func testFramesComeOutInOrderAcrossTheWrap() {
        guard let r = mm_ring_new() else { return XCTFail("no ring") }
        defer { mm_ring_free(r) }
        mm_ring_reset(r, 4096)
        var input = [Float](repeating: 0, count: 2000), output = [Float](repeating: 0, count: 2000)
        var pos = 0
        for _ in 0..<40 {
            for i in 0..<1000 { input[i * 2] = Float(pos + i); input[i * 2 + 1] = -Float(pos + i) }
            XCTAssertEqual(mm_ring_write(r, input, 1000, 48000), 1000)
            mm_ring_read(r, &output, 1000)
            for i in 0..<1000 where output[i * 2] != Float(pos + i) { XCTFail("frame \(pos + i) out of order"); return }
            pos += 1000
        }
        XCTAssertEqual(mm_ring_dry(r), 0)
    }

    func testToneEngineMakesSoundAfterAHitAndSilenceBefore() {
        let t = ToneEngine()
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer { buf.deallocate() }
        t.render(buf, frames: 256, rate: 48000)
        XCTAssertEqual((0..<512).map { abs(buf[$0]) }.max(), 0)
        t.hit()
        t.render(buf, frames: 256, rate: 48000)
        XCTAssertGreaterThan((0..<512).map { abs(buf[$0]) }.max() ?? 0, 0.05)
    }
}

final class NoteRepliesTests: XCTestCase {
    func testStatusWordsMatchAndroid() {
        XCTAssertEqual(NotesBook.status(labels: ["from-app", "bug", "fixed"], closed: true), "fixed")
        XCTAssertEqual(NotesBook.status(labels: ["wishlist"], closed: true), "on the wishlist")
        XCTAssertEqual(NotesBook.status(labels: ["discuss"], closed: false), "waiting to discuss")
        XCTAssertEqual(NotesBook.status(labels: ["bug"], closed: true), "closed")
        XCTAssertEqual(NotesBook.status(labels: ["bug"], closed: false), "open")
    }

    func testABundleCarriesEveryNoteId() {
        XCTAssertEqual(NotesBook.noteIds(inBody: "a <!-- mm-note:abc123 --> b <!-- mm-note:Zx9 -->"), ["abc123", "Zx9"])
        XCTAssertEqual(NotesBook.noteIds(inBody: "no marker"), [])
    }

    func testNotesSavedBeforeRepliesStillLoad() throws {
        let old = #"[{"id":"a1","cat":"bug","topic":"","text":"x","at":0,"build":"ios 3","screen":"day one","issue":0,"status":""}]"#
        let n = try JSONDecoder().decode([MNote].self, from: Data(old.utf8))
        XCTAssertEqual(n.first?.id, "a1")
        XCTAssertNil(n.first?.replies)
    }
}

final class BundleSoundsTests: XCTestCase {
    func testTheEngineCanReadEveryKindOfBuiltInFile() throws {
        XCTAssertNotNil(BundleSounds.read("library.json"))
        let kick = try XCTUnwrap(BundleSounds.read("basement-kick.flac"))
        XCTAssertEqual(Array(kick.prefix(4)), Array("fLaC".utf8), "FLAC files arrive as they are")
        XCTAssertEqual(BundleSounds.read("sounds/basement-kick.flac"), kick)
        let lib = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(BundleSounds.read("library.json"))) as? [String: Any])
        let loop = try XCTUnwrap((lib["sounds"] as? [[String: Any]])?.compactMap { $0["f"] as? String }.first { $0.hasPrefix("loops/") })
        XCTAssertNotNil(BundleSounds.read(loop), "files in loops/ resolve")
    }

    func testItNeverReadsOutsideTheFolder() {
        XCTAssertNil(BundleSounds.read("../Info.plist"))
        XCTAssertNil(BundleSounds.read("loops/../../Info.plist"))
        XCTAssertNil(BundleSounds.read("no-such-sound.flac"))
    }
}

final class FontTests: XCTestCase {
    func testAllThreeArchivoWeightsAndTheOtherFontsLoad() {
        for name in ["Archivo-Medium", "Archivo-ExtraBold", "Archivo-Black", "Bungee-Regular", "IBMPlexMono-Regular", "IBMPlexMono-Bold", "ShareTechMono-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 12), "\(name) is registered")
        }
    }
}
