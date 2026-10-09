import XCTest

/// Product-only captures for the App Store set. The app is launched with its
/// DEBUG fixture provider (`-ScreenshotData`), invented NHL players and games
/// only, but every frame is rendered by the same navigation destinations and
/// views shipped to customers.
///
/// Attachment names are the file names the capture script exports, so the
/// order here is the order of the set.
@MainActor
final class StatScoutScreenshotUITests: XCTestCase {
    private let skater = "Callum Therrien"
    private let goalie = "Henrik Dalgaard"
    private let comparisonPlayer = "Rasmus Holloway"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCapture01LeagueLeaders() throws {
        let app = launch(tab: "stats")
        waitForText("League leaders", in: app)
        waitForText(skater, in: app)
        // Forwards, ranked by ixG, the Advanced board.
        waitForText("ixG", in: app)
        capture(app, name: "01_league_leaders")
    }

    func testCapture02PlayerProfile() throws {
        let app = launch(tab: "stats")
        openLeader(skater, in: app)
        let card = app.staticTexts["ADVANCED PERCENTILES"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90), "Percentile card should load")
        // Under the profile header: the bars for all three skater categories
        // (production and expected goals, then possession) share one frame.
        scroll(app, until: card, isNear: 140)
        capture(app, name: "02_player_profile")
    }

    func testCapture03GoalieProfile() throws {
        let app = launch(tab: "stats")
        let goalies = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Goalies")
        ).firstMatch
        XCTAssertTrue(goalies.waitForExistence(timeout: 90), "Goalies tab should load")
        goalies.tap()
        openLeader(goalie, in: app)
        let card = app.staticTexts["ADVANCED PERCENTILES"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 90), "Percentile card should load")
        scroll(app, until: card, isNear: 140)
        capture(app, name: "03_goalie_profile")
    }

    func testCapture04Trends() throws {
        let app = launch(tab: "trends")
        waitForText("Heating up", in: app)
        waitForText(skater, in: app)
        capture(app, name: "04_trends")
    }

    func testCapture05GameDetail() throws {
        let app = launch(tab: "teams")
        openTeamGameCard(in: app)
        let race = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] %@", "xG race")
        ).firstMatch
        XCTAssertTrue(race.waitForExistence(timeout: 90), "The xG race card should load")
        // Bring the chart to the top third of the screen, with the first rows
        // of the chances list under it.
        scroll(app, until: race, isNear: 200)
        XCTAssertGreaterThan(race.frame.minY, 110, "The xG race card scrolled under the nav bar: \(race.frame)")
        XCTAssertLessThan(race.frame.minY, 330, "The xG race card should be near the top: \(race.frame)")
        capture(app, name: "05_game_detail")
    }

    func testCapture06Team() throws {
        let app = launch(tab: "teams")
        waitForText("TEAM ADVANCED STATS", in: app)
        waitForText("Seattle Kraken", in: app)
        let roster = app.buttons["Roster"].firstMatch
        XCTAssertTrue(roster.waitForExistence(timeout: 30), "Roster tab should load")
        roster.tap()
        waitForText(skater, in: app)
        capture(app, name: "06_team")
    }

    func testCapture07Comparison() throws {
        let app = launch(tab: "stats")
        openLeader(skater, in: app)

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
        capture(app, name: "07_comparison")
    }

    func testCapture08Standings() throws {
        let app = launch(tab: "teams")
        // The Teams tab opens on the favorite club; the standings are one level up.
        waitForText("TEAM ADVANCED STATS", in: app)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 30), "Team page should have a back button")
        back.tap()
        let standings = app.buttons["Standings"].firstMatch
        XCTAssertTrue(standings.waitForExistence(timeout: 60), "Standings control should load")
        standings.tap()
        // The column header exists only on the standings tables, not on the
        // Clubs grid that shares the division names.
        let header = app.staticTexts["W-L-OTL"].firstMatch
        if !header.waitForExistence(timeout: 10) { standings.tap() }
        XCTAssertTrue(header.waitForExistence(timeout: 30), "Standings tables should load")
        capture(app, name: "08_standings")
    }

    // MARK: - Helpers

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchEnvironment = [
            "FORCE_PRO": "1",
            "STATSCOUT_FORCE_PRO": "1",
            "SCREENSHOT_MODE": "1",
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

    /// Opens a player from the League leaders board. Rows are buttons labelled
    /// "<rank>, <name>, <position>, <team>, <stat>".
    private func openLeader(_ name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Fixture leader row \(name) should load")
        row.tap()
        waitForText(name, in: app)
    }

    /// Team page -> last game card -> game page. The card is a button whose
    /// label starts with its heading ("LAST GAME"), so it cannot be confused
    /// with the Games tab row for the same game, which is mounted but hidden.
    private func openTeamGameCard(in app: XCUIApplication) {
        waitForText("TEAM ADVANCED STATS", in: app)
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Last game", "Today")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60), "Team game card should load")
        // The first tap can land while the team page is still settling from
        // its push; tap again while the card is still the thing on screen.
        for _ in 0..<3 {
            card.tap()
            let page = app.staticTexts.matching(
                NSPredicate(format: "label ==[c] %@", "Expected goals")
            ).firstMatch
            if page.waitForExistence(timeout: 20) { return }
            if !card.exists || !card.isHittable { return }
        }
    }

    /// Drags the page up in small steps until `element` sits within `top`
    /// points of the top of the screen (or the page runs out).
    private func scroll(_ app: XCUIApplication, until element: XCUIElement, isNear top: CGFloat) {
        var steps = 0
        var stalls = 0
        var last = element.frame.minY
        while element.frame.minY > top, steps < 120, stalls < 2 {
            // Slow, then held before release: no fling, so a step moves the
            // page by about the distance dragged.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
            steps += 1
            let now = element.frame.minY
            stalls = abs(now - last) < 1 ? stalls + 1 : 0
            last = now
        }
    }

    private func waitForText(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 90) {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR value == %@", text, text)
        ).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(text) to appear")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        // Let the last animation and any async row settle before the frame.
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
