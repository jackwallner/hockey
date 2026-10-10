import XCTest

/// A visual tour of every reachable screen and state, for QA before a
/// submission. Each test launches the app on the DEBUG fixture provider
/// (`-ScreenshotData`, invented players and games only) and keeps a screenshot
/// attachment per frame, named `<test>-<step>_<what>`. Long pages are walked
/// top to bottom in page-sized drags, so a tab bar covering the last row, or a
/// clipped footer, shows up.
///
/// Export with `scripts/export-tour.sh`, which numbers the frames in order.
@MainActor
final class StatScoutTourUITests: XCTestCase {
    private let skater = "Callum Therrien"
    private let defenseman = "Mikael Sandvik"
    private let goalie = "Henrik Dalgaard"
    private let peer = "Rasmus Holloway"

    private var section = "00"
    private var step = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - 01 Onboarding and paywall

    func testT01Onboarding() throws {
        let app = launch(pro: false, onboarding: true, extra: ["-FixtureFresh"])
        begin("01")
        waitForText("Skip", in: app)
        shot(app, "onboarding_page_1")
        tapButton("Continue", in: app)
        waitForText("Find Insights\nFast", in: app, timeout: 10)
        shot(app, "onboarding_page_2")
        tapButton("Continue", in: app)
        waitForText("Go Deeper\nwith StatScout+", in: app, timeout: 10)
        shot(app, "onboarding_page_3_upsell")
    }

    func testT02Paywall() throws {
        begin("02")
        for mode in ["yearly", "monthly", "lifetime"] {
            let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
            app.launchArguments = ["-PaywallSnapshot", mode, "-ResetUITestState"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
            waitForText("$9.99 / year", in: app, timeout: 60)
            scrollThrough(app, "paywall_\(mode)", maxPages: 5)
            app.terminate()
        }
        let trial = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        trial.launchArguments = ["-PaywallSnapshot", "trial", "-ResetUITestState"]
        trial.launch()
        Thread.sleep(forTimeInterval: 3)
        shot(trial, "trial_pitch_sheet")
        trial.terminate()
        let onboarding = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        onboarding.launchArguments = ["-PaywallSnapshot", "onboarding", "-ResetUITestState"]
        onboarding.launch()
        Thread.sleep(forTimeInterval: 3)
        shot(onboarding, "onboarding_purchase_page")
    }

    // MARK: - 03 Stats

    func testT03StatsAdvanced() throws {
        let app = launch(board: "advanced")
        begin("03")
        waitForText("ixG", in: app)
        scrollThrough(app, "forwards_advanced")
        for title in ["Defensemen", "Goalies"] {
            tapButton(title, in: app)
            Thread.sleep(forTimeInterval: 1)
            scrollThrough(app, "\(title.lowercased())_advanced", maxPages: 3)
        }
    }

    func testT04StatsStandard() throws {
        let app = launch(board: "standard")
        begin("04")
        waitForText("RANK", in: app)
        scrollThrough(app, "forwards_standard")
        for title in ["Defensemen", "Goalies"] {
            tapButton(title, in: app)
            Thread.sleep(forTimeInterval: 1)
            scrollThrough(app, "\(title.lowercased())_standard", maxPages: 3)
        }
    }

    func testT05SortSearchAndViewMenus() throws {
        let app = launch(board: "advanced")
        begin("05")
        waitForText("ixG", in: app)
        tapButton("Stat", in: app)
        shot(app, "stat_menu_open_advanced")
        tapMenuItem("GAx", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "sorted_by_gax")
        tapButton("Sort direction", in: app)
        shot(app, "sort_direction_flipped")
        tapButton("Stat", in: app)
        scrollMenu(app)
        shot(app, "stat_menu_scrolled_standard_section")
        dismissMenu(app)

        tapButton("View options", in: app)
        shot(app, "view_menu_open")
        tapMenuItem("Best & Worst", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "best_and_worst", maxPages: 4)
        tapButton("View options", in: app)
        tapMenuItem("Leaderboard", in: app)

        tapButton("Search players or teams", in: app)
        app.textFields.firstMatch.typeText("Sea")
        Thread.sleep(forTimeInterval: 1)
        shot(app, "search_sea_team_and_players")
        app.textFields.firstMatch.typeText("zzzz")
        Thread.sleep(forTimeInterval: 1)
        shot(app, "search_no_results")
    }

    func testT06StatsStandardMenusAndQualifier() throws {
        let app = launch(board: "standard")
        begin("06")
        waitForText("RANK", in: app)
        tapButton("Stat", in: app)
        shot(app, "stat_menu_open_standard")
        tapMenuItem("GAA", in: app, orElse: "SOG")
        Thread.sleep(forTimeInterval: 1)
        shot(app, "standard_sorted_other_stat")
        tapButton("Search players or teams", in: app)
        app.textFields.firstMatch.typeText("Holloway")
        Thread.sleep(forTimeInterval: 1)
        shot(app, "standard_search_query")
    }

    func testT07Following() throws {
        let empty = launch(extra: ["-FixtureFresh"])
        begin("07")
        waitForText("RANK", in: empty)
        tapButton("Following", in: empty)
        Thread.sleep(forTimeInterval: 1)
        shot(empty, "following_empty")
        tapButton("Choose players", in: empty)
        Thread.sleep(forTimeInterval: 1.5)
        shot(empty, "follow_players_sheet_empty")
        empty.terminate()

        let app = launch()
        waitForText("RANK", in: app)
        tapButton("Following", in: app)
        Thread.sleep(forTimeInterval: 1)
        scrollThrough(app, "following_favorites")
        tapButton("Manage", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "follow_players_sheet_with_favorites")
    }

    // MARK: - 08 Profiles

    func testT08SkaterProfile() throws {
        let app = launch()
        begin("08")
        openLeader(skater, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        scrollThrough(app, "skater_advanced_season", maxPages: 6)
        scrollToTop(app)
        tapButton("Recent", in: app)
        Thread.sleep(forTimeInterval: 2)
        shot(app, "skater_advanced_recent_mode")
        tapButton("Both", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "skater_advanced_both_mode", maxPages: 3)
        scrollToTop(app)
        tapButton("Standard", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "skater_standard", maxPages: 6)
        scrollToTop(app)
        tapButton("Year Compare", in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "skater_year_compare_tab", maxPages: 6)
    }

    func testT09GoalieAndDefenseProfiles() throws {
        let app = launch()
        begin("09")
        waitForText("RANK", in: app)
        tapButton("Goalies", in: app)
        openLeader(goalie, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        scrollThrough(app, "goalie_advanced", maxPages: 4)
        scrollToTop(app)
        tapButton("Standard", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "goalie_standard", maxPages: 5)
        scrollToTop(app)
        tapButton("Year Compare", in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "goalie_year_compare_tab", maxPages: 4)
        app.terminate()

        let second = launch()
        waitForText("RANK", in: second)
        tapButton("Defensemen", in: second)
        openLeader(defenseman, in: second)
        waitForText("ADVANCED PERCENTILES", in: second)
        scrollThrough(second, "defenseman_advanced", maxPages: 4)
        scrollToTop(second)
        tapButton("Standard", in: second)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(second, "defenseman_standard", maxPages: 5)
    }

    func testT10YearCompareAndMetricLeaderboard() throws {
        let app = launch()
        begin("10")
        openLeader(skater, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        tapButton("Year Compare", in: app)
        Thread.sleep(forTimeInterval: 3)
        shot(app, "year_compare_top")
        scrollToTop(app)
        tapButton("Advanced", in: app)
        // A percentile row drills down to that metric's league leaderboard.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ixG")).firstMatch
        if row.waitForExistence(timeout: 10), row.isHittable {
            row.tap()
            Thread.sleep(forTimeInterval: 2)
            scrollThrough(app, "metric_leaderboard_ixg", maxPages: 3)
        } else {
            XCTFail("No ixG percentile row to drill into")
        }
    }

    // MARK: - 11 Games

    func testT11GamesDays() throws {
        let app = launch(tab: "games", extra: ["-FixtureSlate"])
        begin("11")
        waitForText("Your team", in: app)
        scrollThrough(app, "games_default_day", maxPages: 4)
        for offset in [-1, 0, 1, 2] {
            guard let chip = dayChip(offsetFromToday: offset, in: app) else {
                XCTFail("No day chip for offset \(offset)")
                continue
            }
            chip.tap()
            Thread.sleep(forTimeInterval: 1.5)
            scrollThrough(app, "games_day_\(offset)", maxPages: 4)
            scrollToTop(app)
        }
    }

    func testT12GamePageFinal() throws {
        let app = launch(tab: "teams")
        begin("12")
        openTeamGameCard(in: app)
        waitForText("Expected goals", in: app)
        scrollThrough(app, "game_final", maxPages: 14)
    }

    func testT13GamePageUpcomingAndLive() throws {
        let app = launch(tab: "games", extra: ["-FixtureSlate"])
        begin("13")
        waitForText("Your team", in: app)
        if let today = dayChip(offsetFromToday: 0, in: app) {
            today.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        // First game under way, then one still to come.
        openGameRow(statusHint: "In progress", in: app)
        Thread.sleep(forTimeInterval: 2)
        shot(app, "game_in_progress")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1)
        if let tomorrow = dayChip(offsetFromToday: 1, in: app) {
            tomorrow.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        openGameRow(statusHint: nil, in: app)
        Thread.sleep(forTimeInterval: 2)
        shot(app, "game_not_started")
    }

    // MARK: - 14 Trends

    func testT14TrendsEachCohortAndWindow() throws {
        let app = launch(tab: "trends")
        begin("14")
        waitForText("Callum Therrien", in: app)
        scrollThrough(app, "trends_forwards_default", maxPages: 4)
        scrollToTop(app)
        for side in ["Forwards", "Defensemen", "Goalies"] {
            tapButton(side, in: app)
            for window in ["2 weeks", "4 weeks", "8 weeks"] {
                tapButton(window, in: app)
                Thread.sleep(forTimeInterval: 1.5)
                shot(app, "trends_\(side.lowercased())_\(window.replacingOccurrences(of: " ", with: "_"))")
            }
        }
        tapButton("Forwards", in: app)
        tapButton("Cooling off", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "trends_forwards_cooling_off")
        tapButton("Stat", in: app)
        shot(app, "trends_metric_menu")
    }

    // MARK: - 15 Teams

    func testT15TeamPageTabs() throws {
        let app = launch(tab: "teams")
        begin("15")
        waitForText("TEAM ADVANCED STATS", in: app)
        scrollThrough(app, "team_advanced", maxPages: 6)
        scrollToTop(app)
        tapButton("Standard", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "team_standard", maxPages: 6)
        scrollToTop(app)
        tapButton("Roster", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "team_roster", maxPages: 6)
        scrollToTop(app)
        tapButton("Recent", in: app, required: false)
        Thread.sleep(forTimeInterval: 2)
        shot(app, "team_roster_recent")
    }

    func testT16TeamScheduleAndSwitcher() throws {
        let app = launch(tab: "teams")
        begin("16")
        waitForText("TEAM ADVANCED STATS", in: app)
        tapButton("Schedule", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "team_schedule", maxPages: 4)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1)
        let candidates = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Seattle")
        )
        let switcher = candidates.allElementsBoundByIndex.first { $0.frame.minY < 200 && $0.frame.minY > 0 } ?? candidates.firstMatch
        if switcher.exists {
            switcher.tap()
            Thread.sleep(forTimeInterval: 1)
            shot(app, "team_switcher_menu")
            dismissMenu(app)
        } else {
            XCTFail("Team switcher is not exposed in the navigation bar")
        }
    }

    func testT17ClubsStandingsPower() throws {
        let app = launch(tab: "teams")
        begin("17")
        waitForText("TEAM ADVANCED STATS", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "clubs_grid", maxPages: 5)
        scrollToTop(app)
        tapButton("Standings", in: app)
        waitForText("W-L-OTL", in: app, timeout: 30)
        scrollThrough(app, "standings", maxPages: 7)
        scrollToTop(app)
        tapButton("Power", in: app)
        Thread.sleep(forTimeInterval: 2)
        scrollThrough(app, "power_ratings", maxPages: 6)
        scrollToTop(app)
        tapButton("Clubs", in: app)
        let search = app.textFields.firstMatch
        if search.waitForExistence(timeout: 10) {
            search.tap()
            search.typeText("Oil")
            Thread.sleep(forTimeInterval: 1)
            shot(app, "clubs_search_oil")
        }
    }

    func testT18OtherClubPage() throws {
        let app = launch(tab: "teams")
        begin("18")
        waitForText("TEAM ADVANCED STATS", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapButton("Standings", in: app)
        waitForText("W-L-OTL", in: app, timeout: 30)
        let edm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edmonton Oilers")).firstMatch
        if edm.waitForExistence(timeout: 10) {
            edm.tap()
            waitForText("TEAM ADVANCED STATS", in: app)
            Thread.sleep(forTimeInterval: 1.5)
            shot(app, "other_club_top")
        } else {
            XCTFail("No Edmonton row in the standings")
        }
    }

    // MARK: - 19 Compare

    func testT19CompareTab() throws {
        let app = launch(tab: "compare")
        begin("19")
        waitForText("YOUR PLAYERS", in: app)
        scrollThrough(app, "compare_tab", maxPages: 5)
        scrollToTop(app)
        tapButton("Edit", in: app, required: false)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "compare_follow_sheet")
    }

    func testT20ComparePickersAndComparison() throws {
        let app = launch(tab: "compare")
        begin("20")
        waitForText("YOUR PLAYERS", in: app)
        // Followed rows load slots A then B.
        tapAnyButton(containing: skater, in: app)
        tapAnyButton(containing: defenseman, in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "compare_slots_filled")
        tapButton("Compare", in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "player_comparison", maxPages: 8)
    }

    func testT21CompareProfileFlow() throws {
        let app = launch()
        begin("21")
        openLeader(skater, in: app)
        tapButton("Compare with another player", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "comparison_player_picker")
        tapAnyButton(containing: peer, in: app)
        waitForText("Player Comparison", in: app)
        scrollThrough(app, "profile_comparison", maxPages: 8)
    }

    func testT22CompareTeamAndYearOverYear() throws {
        let app = launch(tab: "compare")
        begin("22")
        waitForText("YOUR PLAYERS", in: app)
        scrollToBottom(app)
        shot(app, "compare_bottom_cards")
        tapButton("Choose a player", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot(app, "year_over_year_picker")
        tapAnyButton(containing: skater, in: app)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(app, "year_over_year_comparison", maxPages: 6)
        app.terminate()

        let teams = launch(tab: "compare")
        waitForText("YOUR PLAYERS", in: teams)
        scrollToBottom(teams)
        tapAnyButton(containing: "Team A", in: teams)
        Thread.sleep(forTimeInterval: 1.5)
        shot(teams, "team_picker")
        tapAnyButton(containing: "Seattle Kraken", in: teams)
        scrollToBottom(teams)
        tapAnyButton(containing: "Team B", in: teams)
        Thread.sleep(forTimeInterval: 1.5)
        tapAnyButton(containing: "Edmonton Oilers", in: teams)
        scrollToBottom(teams)
        shot(teams, "team_slots_filled")
        tapButton("Compare Teams", in: teams)
        Thread.sleep(forTimeInterval: 3)
        scrollThrough(teams, "team_comparison", maxPages: 6)
    }

    // MARK: - 23 Settings

    func testT23SettingsAndGlossary() throws {
        let app = launch()
        begin("23")
        waitForText("RANK", in: app)
        tapButton("Settings", in: app)
        XCTAssertTrue(app.staticTexts["REFERENCE"].firstMatch.waitForExistence(timeout: 30), "Settings should open")
        scrollThrough(app, "settings", maxPages: 10)
        scrollToTop(app)
        tapAnyButton(containing: "Stat Glossary", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        scrollThrough(app, "glossary", maxPages: 20)
        let search = app.textFields.firstMatch
        if search.exists {
            search.tap()
            search.typeText("ixG")
            Thread.sleep(forTimeInterval: 1)
            shot(app, "glossary_search_ixg")
            search.typeText("qqq")
            Thread.sleep(forTimeInterval: 1)
            shot(app, "glossary_search_empty")
        }
    }

    func testT24ReviewPrompt() throws {
        let app = launch()
        begin("24")
        waitForText("RANK", in: app)
        tapButton("Settings", in: app)
        tapAnyButton(containing: "Rate or Send Feedback", in: app)
        waitForText("Yes, I'm enjoying it", in: app, timeout: 15)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "review_prompt_enjoyment")
        tapButton("Yes, I'm enjoying it", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "review_prompt_pitch")
        app.terminate()

        let second = launch()
        waitForText("RANK", in: second)
        tapButton("Settings", in: second)
        tapAnyButton(containing: "Rate or Send Feedback", in: second)
        waitForText("Not really", in: second, timeout: 15)
        tapButton("Not really", in: second)
        Thread.sleep(forTimeInterval: 1)
        shot(second, "review_prompt_feedback")
    }

    // MARK: - 25 Season picker

    func testT25SeasonPicker() throws {
        let app = launch()
        begin("25")
        waitForText("RANK", in: app)
        seasonControl(in: app).tap()
        Thread.sleep(forTimeInterval: 1)
        shot(app, "season_menu_open")
        scrollMenu(app)
        shot(app, "season_menu_scrolled")
        tapMenuItem("2025-26", in: app)
        Thread.sleep(forTimeInterval: 4)
        scrollThrough(app, "past_season_2025_26", maxPages: 3)
        scrollToTop(app)
        seasonControl(in: app).tap()
        tapMenuItem("All Time", in: app)
        Thread.sleep(forTimeInterval: 5)
        scrollThrough(app, "all_time", maxPages: 3)
        scrollToTop(app)
        tapButton("Following", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot(app, "all_time_following")
        tapButton("League leaders", in: app)
        seasonControl(in: app).tap()
        tapMenuItem("Playoffs", in: app)
        Thread.sleep(forTimeInterval: 3)
        shot(app, "all_time_playoffs")
    }

    func testT26SeasonPickerOtherTabs() throws {
        let trends = launch(tab: "trends")
        begin("26")
        waitForText("Callum Therrien", in: trends)
        seasonControl(in: trends).tap()
        tapMenuItem("2025-26", in: trends)
        Thread.sleep(forTimeInterval: 3)
        shot(trends, "trends_past_season")
        trends.terminate()

        let teams = launch(tab: "teams")
        waitForText("TEAM ADVANCED STATS", in: teams)
        let pill = teams.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Season and season type")).firstMatch
        if pill.waitForExistence(timeout: 10) {
            pill.tap()
            tapMenuItem("2025-26", in: teams)
            Thread.sleep(forTimeInterval: 3)
            scrollThrough(teams, "team_past_season", maxPages: 4)
        } else {
            XCTFail("Team page has no season control")
        }
    }

    // MARK: - 27 Free tier

    func testT27FreeTierGates() throws {
        let trends = launch(tab: "trends", pro: false)
        begin("27")
        Thread.sleep(forTimeInterval: 4)
        shot(trends, "free_trends_gate")
        trends.terminate()

        let compare = launch(tab: "compare", pro: false)
        Thread.sleep(forTimeInterval: 4)
        scrollThrough(compare, "free_compare_gate", maxPages: 4)
        compare.terminate()

        let stats = launch(pro: false)
        waitForText("RANK", in: stats)
        scrollThrough(stats, "free_stats_board", maxPages: 3)
        scrollToTop(stats)
        tapButton("View options", in: stats)
        tapMenuItem("Best & Worst", in: stats)
        Thread.sleep(forTimeInterval: 2)
        shot(stats, "free_best_and_worst_gate")
        tapButton("View options", in: stats)
        tapMenuItem("Leaderboard", in: stats)
        seasonControl(in: stats).tap()
        tapMenuItem("2025-26", in: stats)
        Thread.sleep(forTimeInterval: 2)
        shot(stats, "free_locked_season_pitch")
    }

    func testT28FreeProfile() throws {
        let app = launch(pro: false)
        begin("28")
        openLeader(skater, in: app)
        waitForText("ADVANCED PERCENTILES", in: app)
        scrollThrough(app, "free_profile_first_open", maxPages: 6)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openLeader("Rasmus Holloway", in: app)
        Thread.sleep(forTimeInterval: 2.5)
        shot(app, "free_profile_second_open_pitch")
    }

    // MARK: - Launch

    private func launch(
        tab: String = "stats",
        board: String = "advanced",
        pro: Bool = true,
        onboarding: Bool = false,
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchEnvironment = ["SCREENSHOT_MODE": "1"]
        if pro {
            app.launchEnvironment["FORCE_PRO"] = "1"
            app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1"
        }
        var arguments = [
            "-ScreenshotData",
            "-stats.board", board,
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
            "-profileOpenCount", "0",
            "-StartTab", tab,
        ]
        if !onboarding { arguments += ["-hasCompletedOnboarding", "YES"] }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App should launch in the foreground")
        return app
    }

    // MARK: - Capture

    private func begin(_ id: String) {
        section = id
        step = 0
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        attach(XCUIScreen.main.screenshot(), name)
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        step += 1
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(section)-\(String(format: "%02d", step))_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Captures the page, then drags it up a page at a time until a drag no
    /// longer changes the frame.
    private func scrollThrough(_ app: XCUIApplication, _ name: String, maxPages: Int = 8) {
        Thread.sleep(forTimeInterval: 0.8)
        var previous = app.screenshot()
        attach(previous, "\(name)_p1")
        guard maxPages > 1 else { return }
        for page in 2...maxPages {
            dragUp(app)
            Thread.sleep(forTimeInterval: 0.8)
            var current = app.screenshot()
            if pixels(current) == pixels(previous) {
                // A drag that moved nothing may have missed the scroll view;
                // a swipe is the second opinion before calling it the end.
                app.swipeUp(velocity: .slow)
                Thread.sleep(forTimeInterval: 0.8)
                current = app.screenshot()
                if pixels(current) == pixels(previous) { return }
            }
            attach(current, "\(name)_p\(page)")
            previous = current
        }
    }

    /// The page without the status bar (its clock changes every minute) and
    /// without the right edge, where the scroll indicator fades in and out.
    private func pixels(_ screenshot: XCUIScreenshot) -> Data? {
        guard let image = screenshot.image.cgImage else { return nil }
        let top = 260
        let area = CGRect(x: 0, y: top, width: image.width - 40, height: image.height - top)
        return image.cropping(to: area)?.dataProvider?.data as Data?
    }

    private func dragUp(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<12 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func scrollToBottom(_ app: XCUIApplication) {
        for _ in 0..<12 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Finding things

    private func waitForText(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 90) {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", text, text)
        ).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(text) to appear")
    }

    /// The hittable match first: Stats, Trends, Teams and Compare each mount
    /// their own copy of a control, and the hidden ones are not tappable.
    private func button(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
        // Every tab stays in the tree at full-screen frames, so Trends' "Stat"
        // menu and Stats' "Defensemen" tab both count as on screen from the
        // other tab. Only the visible tab's copy is hittable.
        let visible = onScreen(matches, in: app)
        return visible.first(where: \.isHittable) ?? visible.first ?? matches.firstMatch
    }

    /// The matches whose frame sits inside the screen, in query order. A
    /// frame read never throws, unlike `isHittable` on an element scrolled
    /// out of its list.
    private func onScreen(_ query: XCUIElementQuery, in app: XCUIApplication) -> [XCUIElement] {
        guard query.firstMatch.exists else { return [] }
        let screen = app.frame
        return query.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    private func tapButton(_ label: String, in app: XCUIApplication, required: Bool = true) {
        let element = button(label, in: app)
        guard element.waitForExistence(timeout: required ? 30 : 5) else {
            if required { XCTFail("Button \(label) not found") }
            return
        }
        element.tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func tapAnyButton(containing text: String, in app: XCUIApplication) {
        // Leaderboard rows ("1, Name, ...") of the Stats tab behind this one stay
        // in the tree; they are never the target.
        let matches = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND NOT (label MATCHES %@) AND NOT (label MATCHES %@)",
                text, "^[0-9]+, .*", ".*, Final(/OT)?$"
            )
        )
        guard matches.firstMatch.waitForExistence(timeout: 30) else {
            return XCTFail("No button containing \(text)")
        }
        (onScreen(matches, in: app).first ?? matches.firstMatch).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// An item in the open menu. Menus sit above the app's own buttons, so
    /// the last match is the menu's.
    private func tapMenuItem(_ label: String, in app: XCUIApplication, orElse fallback: String? = nil) {
        for text in [label, fallback].compactMap({ $0 }) {
            // Exact text first: a board row beside the menu shares a prefix
            // with an item ("GAx: 1.2, 57th percentile" against "GAx").
            let exact = NSPredicate(format: "label ==[c] %@", text)
            let queries = [
                app.menuItems.matching(exact),
                app.buttons.matching(exact),
                app.descendants(matching: .any).matching(exact),
                app.menuItems.matching(NSPredicate(format: "label BEGINSWITH[c] %@", text)),
            ]
            for matches in queries where matches.firstMatch.waitForExistence(timeout: 6) {
                (onScreen(matches, in: app).last ?? matches.element(boundBy: matches.count - 1)).tap()
                Thread.sleep(forTimeInterval: 0.8)
                return
            }
        }
        XCTFail("Menu item \(label) not found")
    }

    private func scrollMenu(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func seasonControl(in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", "Season and season type"))
        return onScreen(matches, in: app).first ?? matches.firstMatch
    }

    private func openLeader(_ name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Fixture leader row \(name) should load")
        row.tap()
        waitForText(name, in: app)
    }

    private func openTeamGameCard(in app: XCUIApplication) {
        waitForText("TEAM ADVANCED STATS", in: app)
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Last game", "Today")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60), "Team game card should load")
        for _ in 0..<3 {
            card.tap()
            let page = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Expected goals")).firstMatch
            if page.waitForExistence(timeout: 20) { return }
            if !card.exists || !card.isHittable { return }
        }
    }

    // MARK: - Games tab

    private static let chipPredicate = NSPredicate(
        format: "label MATCHES %@", "^[A-Z][a-z]+day, [A-Z][a-z]+ [0-9]+$"
    )

    private func dayChip(offsetFromToday offset: Int, in app: XCUIApplication) -> XCUIElement? {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return nil }
        let label = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let chip = app.buttons[label].firstMatch
        return chip.waitForExistence(timeout: 10) ? chip : nil
    }

    private func openGameRow(statusHint: String?, in app: XCUIApplication) {
        var format = "label CONTAINS[c] ' at ' OR label CONTAINS[c] ' vs '"
        if let statusHint { format = "label CONTAINS[c] \"\(statusHint)\"" }
        let rows = app.buttons.matching(NSPredicate(format: format))
        guard rows.firstMatch.waitForExistence(timeout: 15) else {
            return XCTFail("No game row to open")
        }
        (onScreen(rows, in: app).first ?? rows.firstMatch).tap()
    }
}
