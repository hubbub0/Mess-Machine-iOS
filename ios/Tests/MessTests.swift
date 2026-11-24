import XCTest
@testable import MessMachine

/// The shared mess fixtures (core/shared/fixtures), checked the same way RoundTrip.java checks them on Android.
final class MessTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let dir = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixtures", withExtension: nil), "fixtures folder missing from the test bundle")
        return try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    private let lib = SoundLibrary.bundled
    private func load(_ text: String) throws -> Mess.Loaded { try Mess.load(text, known: lib.has) }

    /// Parsed JSON with "at" and "app" taken out: files compare by what they hold, not by bytes.
    private func canonical(_ o: Any) -> NSDictionary {
        var d = o as! [String: Any]
        d.removeValue(forKey: "at"); d.removeValue(forKey: "app")
        return d as NSDictionary
    }

    func testLibraryShipsWithTheApp() {
        XCTAssertGreaterThan(lib.count, 300, "library.json from core/ should list the app's built-in sounds")
        XCTAssertTrue(lib.has("samples/basement-kick.wav"))
        XCTAssertTrue(lib.has("qb:stwretch-hit"), "aliases resolve")
    }

    func testExampleRoundTrips() throws {
        let text = try fixture("example.mess.json")
        let L = try load(text)
        XCTAssertEqual(L.missing, 0, "every sound in the example is known")
        let saved = L.mess.json()
        let want = canonical(try JSONSerialization.jsonObject(with: Data(text.utf8)))
        let got = canonical(saved)
        if got != want {
            for k in Set((want.allKeys as! [String]) + (got.allKeys as! [String])).sorted() where !(want[k].map { ($0 as AnyObject).isEqual(got[k]) } ?? false) {
                XCTFail("key \(k) differs:\n fixture: \(String(describing: want[k]))\n saved:   \(String(describing: got[k]))")
            }
        }
        // a second load and save changes nothing
        let again = try load(L.mess.text()).mess.json()
        XCTAssertEqual(canonical(again), canonical(saved))
        XCTAssertEqual(saved["app"] as? String, "ios")
    }

    func testExampleMeaning() throws {
        let p = try load(try fixture("example.mess.json")).mess
        let A = p.pats[0], B = p.pats[1]
        let K = "samples/basement-kick.wav", Cl = "samples/wet-clap.wav", S = "synth:1", LP = "loop:ametrine-1"
        XCTAssertEqual(p.bpm, 96); XCTAssertEqual(p.swing, 20); XCTAssertEqual(p.squash, 0.6, accuracy: 1e-9); XCTAssertEqual(p.level, 1)
        XCTAssertEqual(p.scale, "Minor"); XCTAssertEqual(p.root, 9); XCTAssertFalse(p.fold)
        XCTAssertTrue(p.songMode); XCTAssertEqual(p.song, [0, 1, -1, 1])
        XCTAssertEqual(A.len, 16); XCTAssertEqual(B.len, 32)
        XCTAssertTrue(A.step(K, 0) && A.step(K, 6) && A.step(K, 8) && A.step(K, 11) && !A.step(K, 1))
        XCTAssertTrue(B.step(K, 28) && B.step(LP, 16))
        XCTAssertEqual(A.notes[S], [Mess.Note(s: 0, p: 0, l: 4), Mess.Note(s: 8, p: -5, l: 4)])
        XCTAssertEqual(A.offs[Cl], [92, 284])
        XCTAssertNotNil(p.synths[S])
    }

    func testLegacyV1TopLevelStepsBecomeLoopA() throws {
        let v1 = try load(try fixture("legacy-v1.mess.json")).mess
        XCTAssertTrue(v1.pats[0].step("samples/basement-kick.wav", 4))
        XCTAssertTrue(v1.pats[0].step("samples/wet-clap.wav", 12))
        XCTAssertEqual(v1.songLen, 0); XCTAssertEqual(v1.scale, "Chromatic"); XCTAssertEqual(v1.swing, 10)
    }

    func testLegacyV2InstNotes() throws {
        let L = try load(try fixture("legacy-v2-inst.mess.json"))
        let hit = "qb:stwretch-hit"
        XCTAssertEqual(L.missing, 0); XCTAssertEqual(L.mess.kit[1], hit, "the old qb: key keeps its spelling")
        XCTAssertEqual(L.mess.pats[0].len, 32)
        XCTAssertEqual(L.mess.pats[0].notes[hit]?.count, 2); XCTAssertEqual(L.mess.pats[0].notes[hit]?[1].p, -3)
        let again = try load(L.mess.text()).mess
        XCTAssertEqual(again.pats[0].notes[hit]?.count, 2, "re-saved as a notes map")
    }

    func testSiteV3MissingSounds() throws {
        let L = try load(try fixture("site-v3.mess.json"))
        let st = L.mess
        XCTAssertEqual(L.missing, 2, "the upload and the workbench sound are missing")
        XCTAssertTrue(st.kit[1].isEmpty && st.kit[2].isEmpty); XCTAssertEqual(st.kit[3], "samples/wet-clap.wav")
        XCTAssertEqual(st.pats[0].steps.count, 2, "steps of a missing sound are dropped")
        XCTAssertFalse(st.text().contains("a:uploaded1\":"), "and gone from the next save")
        XCTAssertEqual(st.sel, 0, "sel on an empty pad falls back to the first loaded pad")
        XCTAssertEqual(st.scale, "Dorian"); XCTAssertEqual(st.root, 2); XCTAssertTrue(st.fold)
        XCTAssertFalse(st.songMode); XCTAssertEqual(st.songLen, 1)
    }

    func testTolerance() throws {
        let empty = try load("{}").mess
        XCTAssertEqual(empty.bpm, 112); XCTAssertEqual(empty.loadedCount, 0); XCTAssertEqual(empty.scale, "Chromatic")
        let odd = try load(#"{"bpm":999,"swing":-5,"root":40,"cur":12,"kit":["samples/basement-kick.wav","samples/basement-kick.wav"],"pats":[{"len":20}],"scale":"Nope"}"#).mess
        XCTAssertEqual(odd.bpm, 180); XCTAssertEqual(odd.swing, 0); XCTAssertEqual(odd.root, 11); XCTAssertEqual(odd.cur, 7)
        XCTAssertEqual(odd.pats[0].len, 16); XCTAssertTrue(odd.kit[1].isEmpty); XCTAssertEqual(odd.scale, "Chromatic")
        XCTAssertThrowsError(try load(#"{"name":"#), "broken JSON is not a Mess Machine file")
        XCTAssertEqual(try load(#"{"fold":1}"#).mess.fold, false, "fold must be a real boolean")
    }

    func testNotesClampAndOffsOnAStep() {
        XCTAssertEqual(Mess.decNotes("0.0.40, 15.-50.2, 16.0.1, x.1.1, 3.30", len: 16),
                       [Mess.Note(s: 0, p: 0, l: 16), Mess.Note(s: 15, p: -36, l: 1)])
    }
}
