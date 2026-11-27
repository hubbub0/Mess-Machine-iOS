import XCTest

/// The real Mess Machine screens (shared Compose) on the Simulator: launches, waits for the first frame, taps around
/// and keeps screenshots plus the accessibility tree (to learn which shared test tags reach iOS).
final class SharedScreensUITests: XCTestCase {
    private var shot = 0

    private func snap(_ app: XCUIApplication, _ name: String) {
        shot += 1
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = String(format: "shared-%02d-%@", shot, name)
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let base = URL(fileURLWithPath: dir)
            try? s.pngRepresentation.write(to: base.appendingPathComponent(String(format: "shared-%02d-%@.png", shot, name)))
            try? app.debugDescription.write(to: base.appendingPathComponent(String(format: "shared-%02d-%@.txt", shot, name)),
                                            atomically: true, encoding: .utf8)
        }
    }

    func testSharedScreensStart() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(4)  // Compose draws its first frame after launch
        snap(app, "launch")

        // the start guide shows on a fresh install: tap through it the way a person would
        let w = app.windows.firstMatch
        for i in 0..<3 {
            w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)).tap()
            sleep(1)
            snap(app, "tap-\(i)")
            XCTAssertEqual(app.state, .runningForeground, "the app closed after a tap")
        }

        // the pads live in the middle of the play screen
        for (x, y) in [(0.25, 0.55), (0.5, 0.55), (0.75, 0.55)] {
            w.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        }
        sleep(1)
        snap(app, "pads")
        XCTAssertEqual(app.state, .runningForeground, "the app closed on the play screen")
    }
}
