import XCTest

/// Drives the day-one screen on the Simulator and keeps a screenshot of each stop. Screenshots go to the folder in
/// SCREENSHOT_DIR (CI sets TEST_RUNNER_SCREENSHOT_DIR) and into the test results.
final class DayOneUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shot = 0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-dayOne"]
        app.launch()
    }

    private func snap(_ name: String) {
        shot += 1
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = String(format: "%02d-%@", shot, name)
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", shot, name))
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: url)
        }
    }

    func testDayOneScreen() {
        XCTAssertTrue(app.buttons["pad-0"].waitForExistence(timeout: 10))
        snap("start")

        // sound: the pad starts Core Audio and the test tone
        app.buttons["pad-0"].tap()
        let path = app.staticTexts["audio-path"]
        let opened = NSPredicate(format: "label CONTAINS 'Core Audio'")
        expectation(for: opened, evaluatedWith: path)
        waitForExpectations(timeout: 10)
        for _ in 0..<4 { app.buttons["pad-0"].tap() }
        sleep(2)
        snap("sound-on")

        // messes: the shared example opens
        app.buttons["file-example"].tap()
        let summary = app.staticTexts["mess-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("96 BPM"), "example summary: \(summary.label)")
        XCTAssertTrue(summary.label.contains("4 pads"), "example summary: \(summary.label)")
        // the shared Kotlin engine: the mess's pads appear and play, and the loop plays
        XCTAssertTrue(app.staticTexts["audio-engine"].label.contains("shared"), "built with the shared engine: \(app.staticTexts["audio-engine"].label)")
        app.swipeDown()
        let pad = app.buttons["mess-pad-0"]
        XCTAssertTrue(pad.waitForExistence(timeout: 20), "the example's pads load")
        pad.tap()
        app.buttons["bar-play"].tap()
        sleep(3)
        snap("shared-engine-playing")
        app.buttons["bar-play"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["mic"].exists, "the Workbench record key")
        XCTAssertTrue(app.buttons["import"].exists, "the Workbench import key")
        XCTAssertTrue(app.buttons["midi-bluetooth"].exists, "the Bluetooth MIDI key")
        snap("example-mess")

        // notes: the sheet opens and closes with the X
        app.swipeDown()
        app.buttons["bar-notes"].tap()
        XCTAssertTrue(app.buttons["note-send"].waitForExistence(timeout: 5))
        app.buttons["note-cat-feature"].tap()
        XCTAssertTrue(app.buttons["note-voice"].exists)
        XCTAssertTrue(app.buttons["note-check"].exists)
        snap("note-sheet")
        app.buttons["sheet-close"].tap()

        // stop
        XCTAssertTrue(app.buttons["bar-play"].waitForExistence(timeout: 5))
        app.buttons["bar-play"].tap()
        snap("stopped")
    }
}
