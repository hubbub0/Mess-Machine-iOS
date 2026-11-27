import XCTest
@testable import MessMachineApp
#if canImport(MessMachine)
import MessMachine
#endif

/// The zip reader and sound packs, on zips made by Python's zipfile (deflated and stored).
final class ZipReaderTests: XCTestCase {
    static let goodPack = Data(base64Encoded: "UEsDBBQAAAAIAFCzel3q7Lw+jgAAAPQAAAAJAAAAcGFjay5qc29uZYzBCsIwEER/ZdlzbcFjjn6BB2/SQ4zbupgmwV0VKf13SRqh4HFm3rwZ+YoGUEl0l6y7YwMY7ES5PJEoHGv5oodwDGhg3wA6z0nQwHmugkuMU8YG9uVbgC637eCty5OyrtuhsvpJJd9YS7RjUaKPb+yXBn7uMQb6d08swmFc9Rs6PnULt21H4myiCvbLF1BLAwQUAAAACABQs3pdAAAAAAIAAAAAAAAABgAAAGNsaXBzLwMAUEsDBBQAAAAIAFCzel38RXmXcQEAAAQoAAAPAAAAY2xpcHMvYm9vbS5mbGFjS/NJdGZgZGJmYWVj5+Dk4ubh5eMXEBQSFhEVE5eQlJKWkZWTV1BUUlZRVVPX0NTS1tHV0zcwNDI2MTUzt7C0sraxtbN3cHRydnF1c/fw9PL28fXzDwgMCg4JDQuPiIyKjomNi09ITEpOSU1Lz8jMys7JzcsvKCwqLiktK6+orKquqa2rb2hsam5pbWvv6Ozq7unt658wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLV+xctXqNWvXrd+wcdPmLVu3bd+xc9fuPXv37T9w8NDhI0ePHT9x8tTpM2fPnb9w8dLlK1evXb9x89btO3fv3X/w8NHjJ0+fPX/x8tXrN2/fvf/w8dPnL1+/ff/x89fvP3///R/1/6j/R/0/6v9R/4/6f9T/o/4f9f+o/0f9P+r/Uf+P+n/U/6P+H/X/qP9H/T/q/1H/j/p/1P+j/h/1/6j/R/0/6v9R/4/6f9T/o/4f9f+o/0f9P+r/Uf+P+n8o+h8AUEsBAhQDFAAAAAgAULN6XersvD6OAAAA9AAAAAkAAAAAAAAAAAAAAIABAAAAAHBhY2suanNvblBLAQIUAxQAAAAIAFCzel0AAAAAAgAAAAAAAAAGAAAAAAAAAAAAEAD9QbUAAABjbGlwcy9QSwECFAMUAAAACABQs3pd/EV5l3EBAAAEKAAADwAAAAAAAAAAAAAAgAHbAAAAY2xpcHMvYm9vbS5mbGFjUEsFBgAAAAADAAMAqAAAAHkCAAAAAA==")!
    static let stored = Data(base64Encoded: "UEsDBBQAAAAAAFCzel2Oo3MkDAAAAAwAAAAFAAAAYS50eHRoZWxsbyBzdG9yZWRQSwECFAMUAAAAAABQs3pdjqNzJAwAAAAMAAAABQAAAAAAAAAAAAAAgAEAAAAAYS50eHRQSwUGAAAAAAEAAQAzAAAALwAAAAAA")!
    static let escaping = Data(base64Encoded: "UEsDBBQAAAAIAFCzel3q7Lw+jgAAAPQAAAAJAAAAcGFjay5qc29uZYzBCsIwEER/ZdlzbcFjjn6BB2/SQ4zbupgmwV0VKf13SRqh4HFm3rwZ+YoGUEl0l6y7YwMY7ES5PJEoHGv5oodwDGhg3wA6z0nQwHmugkuMU8YG9uVbgC637eCty5OyrtuhsvpJJd9YS7RjUaKPb+yXBn7uMQb6d08swmFc9Rs6PnULt21H4myiCvbLF1BLAwQUAAAACABQs3pdHyiqZwQAAAACAAAADgAAAC4uLy4uL2V2aWwudHh0y8sHAFBLAQIUAxQAAAAIAFCzel3q7Lw+jgAAAPQAAAAJAAAAAAAAAAAAAACAAQAAAABwYWNrLmpzb25QSwECFAMUAAAACABQs3pdHyiqZwQAAAACAAAADgAAAAAAAAAAAAAAgAG1AAAALi4vLi4vZXZpbC50eHRQSwUGAAAAAAIAAgBzAAAA5QAAAAAA")!
    static let noPackJson = Data(base64Encoded: "UEsDBBQAAAAIAFCzel2DFtyMAwAAAAEAAAAPAAAAY2xpcHMvYm9vbS5mbGFjqwAAUEsBAhQDFAAAAAgAULN6XYMW3IwDAAAAAQAAAA8AAAAAAAAAAAAAAIABAAAAAGNsaXBzL2Jvb20uZmxhY1BLBQYAAAAAAQABAD0AAAAwAAAAAAA=")!

    func testDeflatedEntriesComeBackWhole() throws {
        let e = try ZipReader.entries(Self.goodPack)
        XCTAssertEqual(e.map(\.name), ["pack.json", "clips/", "clips/boom.flac"])
        XCTAssertTrue(e[1].isDirectory)
        XCTAssertEqual(e[2].data.count, 4 + 256 * 40)
        XCTAssertEqual(Array(e[2].data.prefix(4)), Array("fLaC".utf8))
        XCTAssertEqual(e[2].data[4 + 255], 255)
    }

    func testStoredEntries() throws {
        let e = try ZipReader.entries(Self.stored)
        XCTAssertEqual(String(decoding: e[0].data, as: UTF8.self), "hello stored")
    }

    func testOurOwnStoredZipReadsBack() throws {
        let z = Zip.store([("x/a.wav", Data([1, 2, 3])), ("b.txt", Data("hi".utf8))])
        let e = try ZipReader.entries(z)
        XCTAssertEqual(e.map(\.name), ["x/a.wav", "b.txt"])
        XCTAssertEqual(e[0].data, Data([1, 2, 3]))
    }

    func testNotAZip() {
        XCTAssertThrowsError(try ZipReader.entries(Data("hello".utf8)))
    }
}

#if canImport(MessMachine)
final class PacksTests: XCTestCase {
    private var dir: URL!
    private var lib: Library!
    private var packs: IosPacks!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("packs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lib = try Library(files: MMBundleSoundFiles(), base: "sounds/")
        packs = IosPacks(root: dir.path, lib: lib)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func zip(_ d: Data) -> URL {
        let u = dir.appendingPathComponent("in-\(UUID().uuidString).zip")
        try? d.write(to: u)
        return u
    }

    func testAPackInstallsRegistersAndComesBackAfterARestart() throws {
        try packs.unpack(zip(Self.good), id: "test-pack")
        XCTAssertEqual((packs.installed["test-pack"] as? KotlinInt)?.intValue, 2)
        XCTAssertTrue(lib.has(key: "pack:test-pack:boom"))
        XCTAssertFalse(lib.has(key: "pack:test-pack:gone"), "a clip whose file is missing is skipped")
        XCTAssertFalse(lib.has(key: "pack:test-pack:out"), "a clip outside the pack folder is skipped")

        let lib2 = try Library(files: MMBundleSoundFiles(), base: "sounds/")
        let again = IosPacks(root: dir.path, lib: lib2)
        again.loadInstalled()
        XCTAssertTrue(lib2.has(key: "pack:test-pack:boom"))
    }

    func testRemoveTakesItOff() throws {
        try packs.unpack(zip(Self.good), id: "test-pack")
        packs.remove(id: "test-pack")
        XCTAssertNil(packs.installed["test-pack"])
        XCTAssertFalse(lib.has(key: "pack:test-pack:boom"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("packs/test-pack").path))
    }

    func testAnEntryOutsideItsFolderIsRefusedAndNothingIsLeft() {
        XCTAssertThrowsError(try packs.unpack(zip(Self.escaping), id: "evil"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("packs/evil.part").path))
        XCTAssertNil(packs.installed["evil"])
    }

    func testAZipWithoutPackJsonIsNotAPack() {
        XCTAssertThrowsError(try packs.unpack(zip(Self.noPack), id: "nopack"))
    }

    func testBadIdsAreRefused() {
        XCTAssertFalse(IosPacks.safe("../x"))
        XCTAssertFalse(IosPacks.safe("Caps"))
        XCTAssertTrue(IosPacks.safe("vault-01"))
    }

    static let good = ZipReaderTests.goodPack
    static let escaping = ZipReaderTests.escaping
    static let noPack = ZipReaderTests.noPackJson
}
#endif
