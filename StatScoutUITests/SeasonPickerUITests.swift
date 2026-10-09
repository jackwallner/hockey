import XCTest

/// The nav-bar season control: what it offers, and that choosing something takes
/// effect. Runs on the invented fixture data (`-ScreenshotData`), so it needs no
/// network and the board is up in seconds.
final class SeasonPickerUITests: XCTestCase {
    var app: XCUIApplication!

    private let loadTimeout: TimeInterval = 120

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.hockey")
        app.launchArguments += [
            "-ScreenshotData",
            "-hasCompletedOnboarding", "YES",
            "-stats.board", "advanced",
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
        ]
        app.launch()
    }

    /// Season and phase share one pill, labelled for VoiceOver as
    /// "Season and season type" with a value like "2026-27, Regular Season".
    ///
    /// The *hittable* one, and both words are load-bearing: Stats, Trends and
    /// Teams each mount this control, so a bare query matches several elements
    /// and `firstMatch` can answer with a background tab's, whose value is not
    /// redrawn when the season changes.
    private func seasonControl() -> XCUIElement {
        let matches = app.buttons.matching(
            NSPredicate(format: "label == %@", "Season and season type")
        )
        for element in matches.allElementsBoundByIndex where element.isHittable {
            return element
        }
        return matches.firstMatch
    }

    private func waitForBoard() -> Bool {
        app.staticTexts["RANK"].waitForExistence(timeout: loadTimeout)
    }

    func testSeasonMenuOffersEveryStoredSeason() throws {
        XCTAssertTrue(waitForBoard(), "Leaderboard should appear")

        let control = seasonControl()
        XCTAssertTrue(control.waitForExistence(timeout: 15), "Season control should exist in the nav bar")
        XCTAssertEqual(control.value as? String, "2026-27, Regular Season")
        control.tap()

        // The menu carries the career rollup plus the full 2008-09 to current
        // range. Spot-check the ends and the sentinel rather than every row,
        // since a long menu scrolls and off-screen rows aren't hittable.
        XCTAssertTrue(
            app.buttons["All Time"].waitForExistence(timeout: 20),
            "Season menu should offer the career rollup"
        )
        XCTAssertTrue(app.buttons["2025-26"].exists, "Season menu should offer last season")

        // Every year reads as two years, never a bare year or a thousands-separated one.
        let badYears = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9],?[0-9]{3}$")
        )
        XCTAssertEqual(badYears.count, 0, "Season labels should be in 2026-27 form")
    }

    func testSelectingAnotherSeasonKeepsTheBoardAlive() throws {
        XCTAssertTrue(waitForBoard(), "Leaderboard should appear")

        let control = seasonControl()
        guard control.waitForExistence(timeout: 15) else {
            return XCTFail("Season control should exist")
        }
        let before = control.value as? String

        control.tap()
        let target = app.buttons["2025-26"]
        guard target.waitForExistence(timeout: 5) else {
            return XCTFail("Season menu should offer last season")
        }
        target.tap()

        // Either the board comes back for the new season, or the trial sheet
        // intercepted the locked year. Both are correct; a blank screen isn't.
        let board = app.staticTexts["RANK"].waitForExistence(timeout: loadTimeout)
        let paywall = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'trial' OR label CONTAINS[c] 'unlock'")
        ).firstMatch.exists
        XCTAssertTrue(board || paywall, "Season change should leave the app in a usable state")

        // A locked season is a legitimate outcome: the tap opens the trial
        // sheet and the board stays where it was. Only assert the season moved
        // when nothing intercepted the tap.
        if board, !paywall, let before {
            let after = seasonControl().value as? String
            XCTAssertNotEqual(after, before, "The control should report the newly selected season")
        }
    }

    func testPhaseIsSelectableFromTheSameControl() throws {
        XCTAssertTrue(waitForBoard(), "Leaderboard should appear")

        let control = seasonControl()
        guard control.waitForExistence(timeout: 15) else {
            return XCTFail("Season control should exist")
        }
        control.tap()

        // Season and phase were two separate pills until they were merged to
        // stop iOS pushing the upgrade CTA into a "..." overflow. Both sections
        // must still be reachable from the one menu.
        let playoffs = app.buttons["Playoffs"]
        XCTAssertTrue(
            playoffs.waitForExistence(timeout: 5),
            "The merged menu should still offer the season type"
        )
        XCTAssertTrue(app.buttons["Regular Season"].exists, "Regular season should be listed too")

        // `exists` alone is not enough: the season section lists many rows
        // above these two, so the phase can sit below the fold of a scrolling
        // menu. Hittability is the assertion that catches it.
        XCTAssertTrue(
            playoffs.isHittable,
            "Season type must be visible when the menu opens, not buried under the season list"
        )

        playoffs.tap()

        let value = seasonControl().value as? String
        XCTAssertEqual(
            value?.contains("Playoffs"), true,
            "Choosing Playoffs should be reflected in the pill, got \(value ?? "nil")"
        )
    }
}
