import XCTest

/// iPad layout proof: every main screen plus onboarding and the paywall, in
/// portrait and landscape, on the DEBUG fixture provider. Attachments are named
/// `<orientation>_<n>_<what>` so a run reads top to bottom.
@MainActor
final class StatScoutIPadUITests: XCTestCase {
    private let skater = "Callum Therrien"
    private let goalie = "Henrik Dalgaard"
    private let bundle = "com.jackwallner.hockey"
    private var orientationUnderTest: UIDeviceOrientation = .portrait

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testPortraitTour() throws { try tour(prefix: "portrait", orientation: .portrait) }
    func testLandscapeTour() throws { try tour(prefix: "landscape", orientation: .landscapeLeft) }

    private func tour(prefix: String, orientation: UIDeviceOrientation) throws {
        var n = 0
        func shot(_ app: XCUIApplication, _ what: String) {
            n += 1
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = String(format: "%@_%02d_%@", prefix, n, what)
            attachment.lifetime = .keepAlways
            add(attachment)
            if prefix == "landscape" {
                let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screen.name = String(format: "%@_%02d_%@_screen", prefix, n, what)
                screen.lifetime = .keepAlways
                add(screen)
            }
        }

        orientationUnderTest = orientation
        XCUIDevice.shared.orientation = orientation

        // Onboarding
        var app = launch(["-FixtureFresh"], onboarding: true)
        waitForText("Skip", in: app)
        shot(app, "onboarding_1")
        tap("Continue", in: app)
        tap("Continue", in: app)
        waitForText("Go Deeper\nwith StatScout+", in: app, timeout: 15)
        shot(app, "onboarding_3")
        app.terminate()

        // Paywall and trial pitch
        app = launch(["-PaywallSnapshot", "yearly"], onboarding: false, tab: nil)
        waitForText("$9.99 / year", in: app, timeout: 60)
        shot(app, "paywall")
        app.terminate()
        app = launch(["-PaywallSnapshot", "trial"], onboarding: false, tab: nil)
        Thread.sleep(forTimeInterval: 4)
        shot(app, "trial_pitch")
        app.terminate()

        // Free tier gates (Trends, Compare)
        app = launch([], onboarding: false, tab: "trends", pro: false)
        waitForText("Heating up", in: app)
        shot(app, "trends_free")
        app.terminate()

        // Pro tabs
        app = launch([], onboarding: false, tab: "stats")
        waitForText(skater, in: app)
        shot(app, "stats")
        openLeader(skater, in: app)
        let card = app.staticTexts["ADVANCED PERCENTILES"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90))
        shot(app, "profile_top")
        app.swipeUp()
        shot(app, "profile_scrolled")
        app.terminate()

        app = launch([], onboarding: false, tab: "stats")
        tap("Goalies", in: app)
        openLeader(goalie, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        shot(app, "goalie_profile")
        app.terminate()

        for tab in ["trends", "games", "teams", "compare"] {
            app = launch([], onboarding: false, tab: tab)
            Thread.sleep(forTimeInterval: 6)
            shot(app, tab)
            app.terminate()
        }

        app = launch([], onboarding: false, tab: "teams")
        waitForText("TEAM ADVANCED STATS", in: app)
        let card2 = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Last game", "Today")
        ).firstMatch
        if card2.waitForExistence(timeout: 60) {
            card2.tap()
            waitForText("Expected goals", in: app, timeout: 30)
            shot(app, "game_detail")
        }
        app.terminate()

        app = launch([], onboarding: false, tab: "compare")
        waitForText("YOUR PLAYERS", in: app, timeout: 60)
        shot(app, "compare_pickers")
        tapContaining(skater, in: app)
        tapContaining("Mikael Sandvik", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "compare_slots_filled")
        tap("Compare", in: app)
        Thread.sleep(forTimeInterval: 4)
        shot(app, "player_comparison")
        app.terminate()

        app = launch([], onboarding: false, tab: "stats")
        waitForText(skater, in: app)
        let gear = app.buttons["Settings"].firstMatch
        if gear.waitForExistence(timeout: 20) {
            gear.tap()
            Thread.sleep(forTimeInterval: 2)
            shot(app, "settings")
        }
        app.terminate()
    }

    // MARK: - Helpers

    private func launch(
        _ extra: [String],
        onboarding: Bool,
        tab: String? = "stats",
        pro: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchEnvironment = pro
            ? ["FORCE_PRO": "1", "STATSCOUT_FORCE_PRO": "1", "SCREENSHOT_MODE": "1"]
            : ["SCREENSHOT_MODE": "1"]
        var args = ["-ScreenshotData", "-ResetUITestState"]
        if !onboarding { args += ["-hasCompletedOnboarding", "YES"] }
        if let tab { args += ["-StartTab", tab] }
        app.launchArguments = args + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCUIDevice.shared.orientation = orientationUnderTest
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", label)
        ).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 60), "\(label) should exist")
        button.tap()
    }

    private func tapContaining(_ text: String, in app: XCUIApplication) {
        let button = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", text)
        ).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 60), "\(text) should exist")
        button.tap()
    }

    private func openLeader(_ name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Fixture leader row \(name) should load")
        row.tap()
    }

    private func waitForText(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 90) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts[text].firstMatch.exists || app.buttons[text].firstMatch.exists { return }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("Expected \(text) to appear")
    }
}
