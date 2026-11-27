import XCTest

/// The real Mess Machine screens (shared Compose) on the Simulator. Compose on iPhone does not put its controls in
/// the accessibility tree, so these tap by position (taken from the 921 x 2000 launch screenshot of an iPhone 17) and
/// check the app is still running; the screenshots are for looking at. The sound check reads the `-soundProbe` meter.
final class SharedScreensUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shot = 0
    private var prefix = ""

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-soundProbe"]
    }

    private func launch(_ name: String) {
        prefix = name
        shot = 0
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(4)  // Compose draws its first frame after launch
        answerSystemAlert()  // a question left up by the last test would block every tap
    }

    /// A point in the launch screenshot's pixels (921 wide, 2000 high).
    private func tap(_ x: Double, _ y: Double, hold: Double = 0) {
        let c = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x / 921, dy: y / 2000))
        if hold > 0 { c.press(forDuration: hold) } else { c.tap() }
    }

    private func snap(_ name: String) {
        shot += 1
        let s = XCUIScreen.main.screenshot()
        let file = String(format: "shared-%@-%02d-%@", prefix, shot, name)
        let a = XCTAttachment(screenshot: s)
        a.name = file
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file + ".png"))
        }
    }

    private func stillRunning(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "the app closed after: \(what)", file: file, line: line)
    }

    /// Answer the system's mic question if it is up (an empty pad records, which asks).
    private func answerSystemAlert(allow: Bool = true) {
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let b = board.buttons[allow ? "Allow" : "Don\u{2019}t Allow"]
        if b.waitForExistence(timeout: 1) { b.tap() }
    }

    private func loudest() -> Double {
        let t = app.staticTexts["sound-probe"]
        guard t.waitForExistence(timeout: 5) else { return -1 }
        return Double(t.label.replacingOccurrences(of: "loudest ", with: "")) ?? -1
    }

    // MARK: sound

    func testPadsAndPlayMakeSound() {
        launch("sound")
        let before = loudest()
        XCTAssertGreaterThanOrEqual(before, 0, "the sound meter is missing")
        snap("before")

        tap(122, 600)   // pad 1, Basement Kick
        sleep(1)
        let afterPad = loudest()
        snap("pad-1")
        XCTAssertGreaterThan(afterPad, 0.01, "tapping pad 1 made no sound (loudest \(afterPad))")

        tap(765, 600)   // pad 4, BW Snare
        tap(62, 230)    // Play
        sleep(3)
        snap("playing")
        stillRunning("play")
        tap(160, 230)   // Stop
        sleep(1)
        snap("stopped")
        stillRunning("stop")

        // after Stop the pads must still sound (on iPhone the sound output must not shut off while on screen)
        let t0 = loudest()
        tap(335, 600)   // pad 2, Wet Clap
        sleep(1)
        XCTAssertGreaterThanOrEqual(loudest(), t0, "meter went backwards")
        snap("pad-after-stop")
    }

    // MARK: every screen

    func testEveryTab() {
        launch("tabs")
        snap("play")
        for (name, x) in [("synth", 391.0), ("seq", 538.0), ("perform", 686.0), ("sounds", 833.0), ("play", 243.0)] {
            tap(x, 1830)
            sleep(2)
            snap(name)
            stillRunning("the \(name) tab")
        }
    }

    func testBanksAndPerformRow() {
        launch("perform-row")
        for (name, x) in [("bank-2", 307.0), ("bank-3", 434.0), ("bank-4", 561.0), ("bank-1", 180.0)] {
            tap(x, 415)
            sleep(1)
            stillRunning(name)
        }
        snap("banks")
        for (name, x) in [("edit", 62.0), ("hold", 283.0), ("chords", 394.0), ("repeat", 504.0), ("mute", 614.0), ("drop", 725.0)] {
            tap(x, 1650)
            sleep(1)
            snap(name)
            stillRunning(name)
            tap(x, 1650)  // and back off
            sleep(1)
        }
        tap(122, 600)
        tap(122, 600, hold: 1.2)  // long press on a pad
        sleep(1)
        snap("pad-long-press")
        stillRunning("long press on a pad")
    }

    func testMenuFaqAndNote() {
        launch("sheets")
        tap(858, 230)  // Menu
        sleep(2)
        snap("menu")
        stillRunning("menu")

        app.terminate()
        launch("sheets-faq")
        tap(760, 230)  // FAQ
        sleep(2)
        snap("faq")
        stillRunning("faq")

        app.terminate()
        launch("sheets-note")
        tap(78, 1830)  // Note (the bug button): a quick note listens, so it asks for the mic and speech
        sleep(2)
        snap("note-asks")
        answerSystemAlert()
        answerSystemAlert()
        sleep(2)
        snap("note")
        stillRunning("note")
    }

    func testEmptyPadAsksForTheMic() {
        launch("empty-pad")
        tap(122, 1030)  // pad 9, empty
        sleep(1)
        snap("asked")
        answerSystemAlert()
        sleep(2)
        snap("after-allow")
        stillRunning("an empty pad and the mic question")
    }
}
