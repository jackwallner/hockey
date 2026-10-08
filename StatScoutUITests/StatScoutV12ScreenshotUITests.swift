import XCTest

/// Product-only captures for the Football 1.2 App Store set. The app is
/// launched with its DEBUG fixture provider, but every frame is rendered by
/// the same navigation destinations and views shipped to customers.
@MainActor
final class StatScoutV12ScreenshotUITests: XCTestCase {
    private let fixturePlayer = "Caleb Mercer"
    private let comparisonPlayer = "Mason Reed"

    func testCapture01LeagueLeaders() throws {
        let app = launch(tab: "stats")
        waitForText("League leaders", in: app)
        waitForText(fixturePlayer, in: app)
        capture(app, name: "01_league_leaders")
    }

    func testCapture02PlayerProfile() throws {
        let app = launch(tab: "stats")
        openFixtureProfile(in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        capture(app, name: "02_player_profile")
    }

    func testCapture03Trends() throws {
        let app = launch(tab: "trends")
        waitForText("Heating up", in: app)
        waitForText(fixturePlayer, in: app)
        capture(app, name: "03_trends")
    }

    func testCapture04Team() throws {
        let app = launch(tab: "teams")
        waitForText("TEAM ADVANCED STATS", in: app)
        waitForText("Kansas City Chiefs", in: app)
        capture(app, name: "04_team")
    }

    func testCapture05Following() throws {
        let app = launch(tab: "stats")
        let following = app.buttons["Following"]
        XCTAssertTrue(following.waitForExistence(timeout: 90), "Following scope should load")
        following.tap()
        waitForText("Your players", in: app)
        waitForText(fixturePlayer, in: app)
        capture(app, name: "05_following")
    }

    func testCapture06PlayerComparison() throws {
        let app = launch(tab: "stats")
        openFixtureProfile(in: app)

        let compare = app.buttons["Compare with another player"]
        XCTAssertTrue(compare.waitForExistence(timeout: 30), "Profile comparison control should load")
        compare.tap()

        let otherPlayer = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", comparisonPlayer)
        ).firstMatch
        XCTAssertTrue(otherPlayer.waitForExistence(timeout: 30), "Comparison picker should show the fixture peer")
        otherPlayer.tap()
        waitForText("Player Comparison", in: app)
        waitForText(comparisonPlayer, in: app)
        capture(app, name: "06_player_comparison")
    }

    func testCapture07YearHistory() throws {
        let app = launch(tab: "stats")
        openFixtureProfile(in: app)

        let yearCompare = app.buttons["Year Compare"]
        XCTAssertTrue(yearCompare.waitForExistence(timeout: 30), "Year Compare tab should load")
        yearCompare.tap()
        waitForText("SEASON TOTALS", in: app)
        waitForText("2026", in: app)
        waitForText("2025", in: app)
        capture(app, name: "07_year_history")
    }

    func testCapture08Roster() throws {
        let app = launch(tab: "teams")
        waitForText("TEAM ADVANCED STATS", in: app)
        waitForText("Kansas City Chiefs", in: app)

        let roster = app.buttons["Roster"]
        XCTAssertTrue(roster.waitForExistence(timeout: 30), "Roster tab should load")
        roster.tap()
        waitForText(fixturePlayer, in: app)
        capture(app, name: "08_roster")
    }

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FORCE_PRO": "1",
            "STATSCOUT_FORCE_PRO": "1",
            "SCREENSHOT_MODE": "1",
            "TEST_RUNNER_SCREENSHOT_APP_VERSION": "1.2",
        ]
        app.launchArguments = [
            "-ScreenshotData",
            "-hasCompletedOnboarding", "YES",
            "-stats.board", "advanced",
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
            "-StartTab", tab,
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App should launch in the foreground")
        return app
    }

    private func openFixtureProfile(in app: XCUIApplication) {
        let row = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(fixturePlayer),.*")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Fixture leader row should load")
        row.tap()
        waitForText(fixturePlayer, in: app)
    }

    private func waitForText(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 90) {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR value == %@", text, text)
        ).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(text) to appear")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
