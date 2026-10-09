import XCTest

/// Walks the hockey screens end to end on the invented fixture data
/// (`-ScreenshotData`): the F / D / G boards, a profile, Year Compare, search,
/// the Teams tab with its standings, the Games tab and a game page.
///
/// Nothing here reaches the network, so every assertion is about the shipped
/// views and navigation rather than about a backend's mood.
@MainActor
final class StatScoutComprehensiveUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 120

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(tab: String = "stats", pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments += [
            "-ScreenshotData",
            "-hasCompletedOnboarding", "YES",
            "-stats.board", "advanced",
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
            // Every test opens a profile, and the second open of any run shows
            // the free-tier pitch sheet. Pin the counter so each launch sees a
            // first visit.
            "-profileOpenCount", "0",
            "-StartTab", tab,
        ]
        if pro {
            app.launchEnvironment["FORCE_PRO"] = "1"
            app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1"
        }
        app.launch()
        return app
    }

    private func waitForBoard(in app: XCUIApplication) -> Bool {
        app.staticTexts["RANK"].waitForExistence(timeout: loadTimeout)
    }

    private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")
        ).firstMatch
    }

    @discardableResult
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            usleep(200_000)
        }
        return false
    }

    private func tabButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
    }

    private func openProfile(_ name: String, in app: XCUIApplication) -> Bool {
        guard waitForBoard(in: app) else { return false }
        let target = row(name, in: app)
        guard target.waitForExistence(timeout: 30) else { return false }
        target.tap()
        return waitUntilHittable(
            app.buttons["Compare with another player"].firstMatch,
            timeout: loadTimeout
        )
    }

    // MARK: - Stats tab

    func testForwardsBoardLoadsRankedByIxG() throws {
        let app = launch()
        XCTAssertTrue(waitForBoard(in: app), "Leaderboard should appear")
        XCTAssertTrue(row("Callum Therrien", in: app).waitForExistence(timeout: 30), "The top forward should lead the board")
        XCTAssertTrue(app.staticTexts["ixG"].exists, "The board should be ranked by ixG")
    }

    func testPositionTabsSwitchBetweenForwardsDefensemenAndGoalies() throws {
        let app = launch()
        XCTAssertTrue(waitForBoard(in: app))

        let defense = tabButton("Defensemen", in: app)
        XCTAssertTrue(defense.waitForExistence(timeout: 10), "Defensemen tab should exist")
        defense.tap()
        XCTAssertTrue(row("Mikael Sandvik", in: app).waitForExistence(timeout: 30), "The defense board should list its leader")
        XCTAssertFalse(row("Callum Therrien", in: app).exists, "Forwards do not show on the defense board")

        let goalies = tabButton("Goalies", in: app)
        XCTAssertTrue(goalies.exists, "Goalies tab should exist")
        goalies.tap()
        XCTAssertTrue(row("Henrik Dalgaard", in: app).waitForExistence(timeout: 30), "The goalie board should list its leader")
        XCTAssertTrue(app.staticTexts["GSAx"].waitForExistence(timeout: 10), "Goalies rank by GSAx")
    }

    func testSearchFindsAPlayer() throws {
        let app = launch()
        XCTAssertTrue(waitForBoard(in: app))
        let chip = app.buttons["Search players or teams"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Search control should carry an accessibility label")
        chip.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Search should reveal a field")
        field.typeText("Holloway")
        XCTAssertTrue(row("Rasmus Holloway", in: app).waitForExistence(timeout: 10), "Search should find the player")
        XCTAssertFalse(row("Callum Therrien", in: app).exists, "Search should filter the board")
    }

    func testPositionSelectorIsExposedToVoiceOver() throws {
        let app = launch()
        XCTAssertTrue(waitForBoard(in: app))
        for title in ["Forwards", "Defensemen", "Goalies"] {
            let tab = tabButton(title, in: app)
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(title) tab should exist")
            XCTAssertFalse(tab.label.isEmpty, "\(title) tab should have an accessibility label")
        }
    }

    // MARK: - Player profile

    func testProfileShowsPercentileSections() throws {
        let app = launch(pro: true)
        XCTAssertTrue(openProfile("Callum Therrien", in: app), "A player profile should open from the leaderboard")
        XCTAssertTrue(app.staticTexts["ADVANCED PERCENTILES"].waitForExistence(timeout: 30))
    }

    func testYearCompareShowsSeasonTotals() throws {
        let app = launch()
        XCTAssertTrue(openProfile("Callum Therrien", in: app), "A player profile should open from the leaderboard")
        let yearCompare = app.buttons["Year Compare"].firstMatch
        XCTAssertTrue(waitUntilHittable(yearCompare, timeout: 30), "Year Compare should be reachable for a player with history")
        yearCompare.tap()
        // Both the Pro comparison and the free preview lead with season totals.
        XCTAssertTrue(
            app.staticTexts["SEASON TOTALS"].waitForExistence(timeout: 30),
            "Year Compare should show season totals"
        )
    }

    // MARK: - Teams tab

    func testTeamsTabOpensTheFavoriteClub() throws {
        let app = launch(tab: "teams")
        XCTAssertTrue(app.staticTexts["TEAM ADVANCED STATS"].waitForExistence(timeout: loadTimeout), "The favorite club should open")
        XCTAssertTrue(app.staticTexts["Seattle Kraken"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Roster"].firstMatch.exists, "The club page should offer its roster")
    }

    func testTeamSearchFindsAClub() throws {
        let app = launch(tab: "teams")
        XCTAssertTrue(app.staticTexts["TEAM ADVANCED STATS"].waitForExistence(timeout: loadTimeout))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The Clubs grid owns a SearchField (a TextField in the a11y tree).
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 30), "Teams search field should exist")
        searchField.tap()
        searchField.typeText("Oilers")

        let match = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Edmonton Oilers")
        ).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 10), "Should find the Oilers in search results")
    }

    func testStandingsListEveryDivision() throws {
        let app = launch(tab: "teams")
        XCTAssertTrue(app.staticTexts["TEAM ADVANCED STATS"].waitForExistence(timeout: loadTimeout))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let standings = app.buttons["Standings"].firstMatch
        XCTAssertTrue(standings.waitForExistence(timeout: 30), "Standings control should exist")
        standings.tap()
        for division in ["ATLANTIC", "METROPOLITAN"] {
            XCTAssertTrue(
                app.staticTexts[division].waitForExistence(timeout: 20),
                "\(division) division should be listed"
            )
        }
        XCTAssertTrue(app.staticTexts["W-L-OTL"].firstMatch.exists, "Records read wins, losses, overtime losses")
    }

    // MARK: - Games tab

    func testGamesTabPinsTheFavoriteClubsGame() throws {
        let app = launch(tab: "games")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Your team")).firstMatch
                .waitForExistence(timeout: loadTimeout)
        )
        let game = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Seattle Kraken")
        ).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 10), "The favorite club's game should be pinned")
    }

    func testGamePageShowsTheXGRace() throws {
        let app = launch(tab: "teams")
        XCTAssertTrue(app.staticTexts["TEAM ADVANCED STATS"].waitForExistence(timeout: loadTimeout))
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Last game", "Today")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "Team game card should load")
        for _ in 0..<3 {
            card.tap()
            if app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Expected goals")).firstMatch
                .waitForExistence(timeout: 20) { break }
        }
        let expected = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Expected goals")).firstMatch
        XCTAssertTrue(expected.waitForExistence(timeout: 60), "The game page should show expected goals")
        let race = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "xG race")).firstMatch
        var swipes = 0
        while !race.exists, swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(race.exists, "The game page should draw the xG race")
    }

    // MARK: - Trends tab

    func testTrendsBoardLoads() throws {
        let app = launch(tab: "trends")
        XCTAssertTrue(app.buttons["Heating up"].firstMatch.waitForExistence(timeout: loadTimeout) || app.staticTexts["Heating up"].exists)
        XCTAssertTrue(row("Callum Therrien", in: app).waitForExistence(timeout: 30) || app.staticTexts["Callum Therrien"].exists)
    }
}
