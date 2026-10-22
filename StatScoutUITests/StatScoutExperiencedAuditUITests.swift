import XCTest

/// Repeat-use flows for an experienced fan on the invented fixture data
/// (`-ScreenshotData`). Each test keeps screenshot attachments named
/// `<test>-<step>_<what>` and a `measurements` text attachment where a frame or
/// a label was read, so the audit report can cite runtime observations.
@MainActor
final class StatScoutExperiencedAuditUITests: XCTestCase {
    private let skater = "Callum Therrien"
    private let peer = "Rasmus Holloway"
    private let goalie = "Henrik Dalgaard"

    private var prefix = "x"
    private var step = 0
    private var notes: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func tearDown() {
        if !notes.isEmpty {
            let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
            attachment.name = "\(prefix)-measurements"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.tearDown()
    }

    // MARK: - Flows

    /// Goalie routine: pick the position, pick a stat, flip it, wander off to
    /// another position and back. Does the choice survive the wander?
    func testA1GoalieRoutineKeepsChoices() throws {
        let app = launch(pro: true)
        begin("A1")
        waitForText("RANK", in: app)
        tapButton("Goalies", in: app)
        waitForText("GSAx", in: app)
        shot("goalies_default")
        note("goalies default stat pill: \(statPillValue(app))")
        tapButton("Stat", in: app)
        tapMenuItem("SV%", in: app)
        shot("goalies_sv_pct")
        tapButton("Sort direction", in: app)
        shot("goalies_sv_pct_flipped")
        note("after pick SV% + flip: stat=\(statPillValue(app)) sort=\(sortValue(app))")
        tapButton("Forwards", in: app)
        shot("forwards_after_goalies")
        note("forwards stat pill: \(statPillValue(app))")
        tapButton("Goalies", in: app)
        shot("goalies_again")
        note("goalies again stat=\(statPillValue(app)) sort=\(sortValue(app))")
    }

    /// Search "Holloway", read his rank on both boards, then change stat across
    /// the Advanced/Standard boundary and see whether the query survives.
    func testA2SearchRankAndQueryCarryOver() throws {
        let app = launch(pro: true)
        begin("A2")
        waitForText("RANK", in: app)
        let fullRank = rankLabel(of: peer, in: app)
        note("advanced full-board row: \(fullRank)")
        tapButton("Search players or teams", in: app)
        app.textFields.firstMatch.typeText("Holloway")
        Thread.sleep(forTimeInterval: 1)
        shot("advanced_search_holloway")
        note("advanced row while searching: \(rankLabel(of: peer, in: app))")
        tapButton("Stat", in: app)
        tapMenuItem("G", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot("after_switch_to_standard_G")
        note("search field present after switch to Standard: \(app.textFields.firstMatch.exists)")
        note("Holloway row on standard board: \(rankLabel(of: peer, in: app))")
        note("Callum row visible after switch: \(rankLabel(of: skater, in: app))")
    }

    /// Scroll deep into the board, open a player, come back: where are we?
    func testA3ScrollPositionAfterProfileRoundTrip() throws {
        let app = launch(pro: true)
        begin("A3")
        waitForText("RANK", in: app)
        for _ in 0..<2 { dragUp(app) }
        Thread.sleep(forTimeInterval: 1)
        shot("board_scrolled")
        let visible = visibleRowLabels(app)
        note("rows visible after scroll: \(visible.prefix(3))")
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+, .*")).allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.midY > 300 }
        row?.tap()
        waitForText("ADVANCED PERCENTILES", in: app)
        shot("profile_opened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("board_after_back")
        note("rows visible after back: \(visibleRowLabels(app).prefix(3))")
    }

    /// Position and season across tab hops.
    func testA4TabHopKeepsPositionAndSeason() throws {
        let app = launch(pro: true)
        begin("A4")
        waitForText("RANK", in: app)
        tapButton("Defensemen", in: app)
        waitForText("RANK", in: app)
        tapButton("Season and season type", in: app)
        shot("season_menu")
        let items = app.menuItems.allElementsBoundByIndex.map(\.label)
        note("season menu items: \(items)")
        dismissMenu(app)
        tapTab("Teams", in: app)
        Thread.sleep(forTimeInterval: 2)
        shot("teams_tab")
        tapTab("Stats", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot("stats_after_hop")
        let defenseSelected = button("Defensemen", in: app).isSelected
        note("Defensemen selected after tab hop: \(defenseSelected)")
        let before = app.state
        _ = before
        app.terminate()
        let again = launch(pro: true, reset: false)
        waitForText("RANK", in: again)
        shot("relaunch_stats")
        note("after relaunch Defensemen selected: \(button("Defensemen", in: again).isSelected); Forwards selected: \(button("Forwards", in: again).isSelected)")
    }

    /// Tap target sizes of the controls used every session.
    func testA5ControlSizes() throws {
        let app = launch(pro: true)
        begin("A5")
        waitForText("RANK", in: app)
        for label in ["Stat", "Sort direction", "Search players or teams", "View options", "Forwards", "Defensemen", "Goalies", "Following", "Season and season type", "Stats", "Teams", "Compare", "Trends", "Games"] {
            let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
            guard let element = onScreen(matches, in: app).first else {
                note("\(label): not found on screen")
                continue
            }
            let frame = element.frame
            note("\(label): \(Int(frame.width))x\(Int(frame.height)) hittable=\(element.isHittable)")
        }
        shot("controls")
    }

    /// Compare from a profile and the exits afterwards.
    func testA6CompareFromProfileAndBack() throws {
        let app = launch(pro: true)
        begin("A6")
        openLeader(skater, in: app)
        shot("profile")
        tapButton("Compare with another player", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot("picker")
        tapAnyButton(containing: peer, in: app)
        waitForText("Player Comparison", in: app)
        shot("comparison_top")
        let titles = app.buttons.allElementsBoundByIndex.filter { $0.isHittable }.map(\.label).prefix(20)
        note("hittable buttons on comparison: \(Array(titles))")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1)
        shot("after_back_one")
        note("back once lands on profile: \(app.staticTexts["ADVANCED PERCENTILES"].exists)")
    }

    /// Free-tier version of the same routines: where does a repeat user hit
    /// the wall, and what does the wall say?
    func testA7FreeTierRepeatUser() throws {
        let app = launch(pro: false)
        begin("A7")
        waitForText("RANK", in: app)
        tapButton("View options", in: app)
        tapMenuItem("Best & Worst (StatScout+)", in: app, orElse: "Best & Worst")
        Thread.sleep(forTimeInterval: 1.5)
        shot("best_worst_gate")
        tapButton("View options", in: app)
        tapMenuItem("Leaderboard", in: app)
        openLeader(skater, in: app)
        shot("free_profile_first_open")
        tapButton("Year Compare", in: app)
        Thread.sleep(forTimeInterval: 2)
        shot("free_year_compare")
        tapButton("Season and season type", in: app, required: false)
        shot("free_season_menu")
    }

    /// Following: follow from profile, check the star target and where it shows.
    func testA8FollowFromProfile() throws {
        let app = launch(pro: true, extra: ["-FixtureFresh", "-hasCompletedOnboarding", "YES"])
        begin("A8")
        openLeader(skater, in: app)
        shot("profile_top")
        let follow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "follow")).allElementsBoundByIndex
        note("follow-like buttons on profile: \(follow.map { "\($0.label) \(Int($0.frame.width))x\(Int($0.frame.height))" })")
        if let first = follow.first(where: { $0.isHittable }) {
            first.tap()
            Thread.sleep(forTimeInterval: 1)
            shot("after_follow_tap")
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tapButton("Following", in: app)
        Thread.sleep(forTimeInterval: 1)
        shot("following_board")
        note("Following board shows \(skater): \(app.staticTexts[skater].exists || app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", skater)).firstMatch.exists)")
    }

    // MARK: - Launch and capture

    private func launch(pro: Bool, reset: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchEnvironment = ["SCREENSHOT_MODE": "1"]
        if pro {
            app.launchEnvironment["FORCE_PRO"] = "1"
            app.launchEnvironment["STATSCOUT_FORCE_PRO"] = "1"
        }
        var arguments = [
            "-ScreenshotData",
            "-stats.board", "advanced",
            "-stats.qualifier", "All Players",
            "-profileOpenCount", "0",
            "-hasCompletedOnboarding", "YES",
        ]
        if reset { arguments.append("-ResetUITestState") }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        return app
    }

    private func begin(_ id: String) { prefix = id; step = 0 }

    private func note(_ text: String) { notes.append(text) }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        step += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(prefix)-\(String(format: "%02d", step))_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dragUp(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)
    }

    // MARK: - Reading state

    private func statPillValue(_ app: XCUIApplication) -> String {
        let pill = onScreen(app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Stat")), in: app).first
        return pill.map { "\($0.value as? String ?? "?")" } ?? "no pill"
    }

    private func sortValue(_ app: XCUIApplication) -> String {
        let element = onScreen(app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Sort direction")), in: app).first
        return element.map { "\($0.value as? String ?? "?")" } ?? "no sort control"
    }

    private func rankLabel(of name: String, in app: XCUIApplication) -> String {
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")).firstMatch
        return row.waitForExistence(timeout: 5) ? row.label : "absent"
    }

    private func visibleRowLabels(_ app: XCUIApplication) -> [String] {
        let rows = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+, .*"))
        return onScreen(rows, in: app).map(\.label)
    }

    // MARK: - Finding things

    private func waitForText(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 90) {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", text, text)
        ).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(text) to appear")
    }

    private func onScreen(_ query: XCUIElementQuery, in app: XCUIApplication) -> [XCUIElement] {
        guard query.firstMatch.exists else { return [] }
        let screen = app.frame
        return query.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    private func button(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
        let visible = onScreen(matches, in: app)
        return visible.first(where: \.isHittable) ?? visible.first ?? matches.firstMatch
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

    private func tapTab(_ title: String, in app: XCUIApplication) {
        tapButton(title, in: app)
    }

    private func tapAnyButton(containing text: String, in app: XCUIApplication) {
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

    private func tapMenuItem(_ label: String, in app: XCUIApplication, orElse fallback: String? = nil) {
        for text in [label, fallback].compactMap({ $0 }) {
            let exact = NSPredicate(format: "label ==[c] %@", text)
            let queries = [
                app.menuItems.matching(exact),
                app.buttons.matching(exact),
                app.descendants(matching: .any).matching(exact),
            ]
            for matches in queries where matches.firstMatch.waitForExistence(timeout: 6) {
                (onScreen(matches, in: app).last ?? matches.element(boundBy: matches.count - 1)).tap()
                Thread.sleep(forTimeInterval: 0.8)
                return
            }
        }
        XCTFail("Menu item \(label) not found")
    }

    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func openLeader(_ name: String, in app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+, \(name),.*")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 90), "Fixture leader row \(name) should load")
        row.tap()
        waitForText(name, in: app)
    }
}
