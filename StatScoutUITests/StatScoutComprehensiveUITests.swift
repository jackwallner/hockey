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

    private func launch(tab: String = "stats", pro: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
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
        ] + extraArguments
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

    /// Overnight audit 2026-10-30 (H3): Recent, then a window, before the
    /// games arrived left "No games in the last 2 weeks" over season bars.
    /// The second tap re-keyed the card's task, the new task found the fetch
    /// "loading" and returned, and the cancelled first fetch cleared the key.
    func testRecentFormSurvivesAWindowChangeMidLoad() throws {
        let app = launch(pro: true, extraArguments: ["-SlowGameLogs"])
        XCTAssertTrue(openProfile("Callum Therrien", in: app), "A player profile should open from the leaderboard")
        let recent = app.buttons["Recent"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 30))
        recent.tap()
        let twoWeeks = app.buttons["2 wks"].firstMatch
        XCTAssertTrue(twoWeeks.waitForExistence(timeout: 5))
        twoWeeks.tap()

        let loading = app.staticTexts["Loading recent games…"]
        let deadline = Date().addingTimeInterval(20)
        while loading.exists, Date() < deadline { usleep(200_000) }
        XCTAssertFalse(loading.exists, "the recent games never arrived")
        XCTAssertFalse(app.staticTexts["No games in the last 2 weeks"].exists,
                       "a quick second tap stranded the Recent card empty")
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

    // MARK: - Failed first load

    /// A first launch with no signal, on the Standard board (the default).
    /// It used to read "No data available" with no way to try again; it now
    /// shows the Advanced board's "No connection" state with Retry.
    func testStandardBoardOfflineFirstLoadOffersRetry() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments += [
            "-ScreenshotData",
            "-FixtureOffline",
            "-hasCompletedOnboarding", "YES",
            "-ResetUITestState",
            "-StartTab", "stats",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["No connection"].waitForExistence(timeout: loadTimeout))
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertFalse(app.staticTexts["No data available"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "standard_board_offline"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Store messages

    private func attachScreen(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The onboarding offer page offers Restore while the player data is
    /// still loading. The purchase-page harness never loads it, which is the
    /// slowest first launch there is; the loading line used to take the slot.
    func testOnboardingOfferPageOffersRestoreBeforeDataLoads() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments = ["-PaywallSnapshot", "onboarding", "-ResetUITestState"]
        app.launch()

        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 60))
        attachScreen(app, "onboarding_offer_restore")
    }

    /// Settings shows the result of its own Restore, not whatever another
    /// store call last left in the shared error. A restore on the onboarding
    /// page (which fails on a simulator) used to be repeated under the
    /// STATSCOUT+ card.
    func testSettingsShowsOnlyItsOwnRestoreResult() throws {
        let simulatorRestore = "Purchases are unavailable in simulator builds."
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments += [
            "-ScreenshotData", "-FixtureFresh", "-MockProducts", "-ResetUITestState",
            "-StartTab", "stats",
        ]
        app.launch()

        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: loadTimeout), "Onboarding should open")
        var taps = 0
        while continueButton.exists, taps < 4 {
            continueButton.tap()
            taps += 1
            Thread.sleep(forTimeInterval: 1)
        }
        let restore = app.buttons["Restore Purchases"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 30))
        restore.tap()
        XCTAssertTrue(app.staticTexts[simulatorRestore].waitForExistence(timeout: 20), "precondition: the store holds an error")
        app.buttons["Get Started"].firstMatch.tap()

        XCTAssertTrue(waitForBoard(in: app), "Stats should open")
        var gear = app.buttons["Settings"].firstMatch
        if !gear.waitForExistence(timeout: 10) {
            let bar = app.navigationBars.buttons
            bar.element(boundBy: max(bar.count - 1, 0)).tap()
            gear = app.buttons["Settings"].firstMatch
        }
        gear.tap()
        let settingsRestore = app.buttons["Restore Purchases"].firstMatch
        XCTAssertTrue(settingsRestore.waitForExistence(timeout: 30), "Settings should open")
        XCTAssertFalse(app.staticTexts[simulatorRestore].exists, "no stale store error in Settings")
        attachScreen(app, "settings_before_restore")

        settingsRestore.tap()
        XCTAssertTrue(app.staticTexts[simulatorRestore].waitForExistence(timeout: 20), "its own restore result shows")
        attachScreen(app, "settings_after_restore")
    }

    // MARK: - Largest text size

    private func launchAtLargestText(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments = [
            "-PaywallSnapshot", mode, "-ResetUITestState",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        return app
    }

    private func purchaseButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Start ", "Try StatScout+")
        ).firstMatch
    }

    /// At the largest accessibility size the onboarding offer page keeps its
    /// heading on screen and the billed price clear of the buy button. The
    /// purchase block used to fill the screen, pushing the heading up under
    /// the top edge, with the price sitting on the button's edge.
    func testOnboardingOfferPageFitsAtTheLargestTextSize() throws {
        let app = launchAtLargestText("onboarding")
        let price = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "/ month")).firstMatch
        XCTAssertTrue(price.waitForExistence(timeout: 60), "the billed price should show")
        let buy = purchaseButton(in: app)
        XCTAssertTrue(buy.exists, "the buy button should show")
        let title = app.staticTexts["Go Deeper\nwith StatScout+"]
        XCTAssertTrue(title.exists)
        attachScreen(app, "onboarding_offer_ax5")

        let screen = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(price.frame.maxY, buy.frame.minY + 1, "price clear of the button")
        XCTAssertLessThanOrEqual(buy.frame.maxY, screen.maxY)
        XCTAssertGreaterThanOrEqual(title.frame.minY, screen.minY + 44, "heading below the top bar")
    }

    /// The trial pitch at the largest accessibility size: price above the
    /// button, and the legal links and the way out still on screen.
    func testTrialPitchFitsAtTheLargestTextSize() throws {
        let app = launchAtLargestText("trial")
        let price = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "/ year")).firstMatch
        XCTAssertTrue(price.waitForExistence(timeout: 60), "the billed price should show")
        let buy = purchaseButton(in: app)
        XCTAssertTrue(buy.exists, "the buy button should show")
        Thread.sleep(forTimeInterval: 2)
        attachScreen(app, "trial_pitch_ax5")

        let screen = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(price.frame.maxY, buy.frame.minY + 1, "price clear of the button")
        for label in ["Terms", "Maybe later"] {
            let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(element.exists, label)
            XCTAssertLessThanOrEqual(element.frame.maxY, screen.maxY, "\(label) on screen")
            XCTAssertGreaterThanOrEqual(element.frame.minY, screen.minY, "\(label) on screen")
        }
    }
}
