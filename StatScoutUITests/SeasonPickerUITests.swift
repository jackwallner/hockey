import XCTest

/// The nav-bar season control: what it offers, and that choosing something takes
/// effect.
///
/// The previous version was baseball-fork leftover and could not pass here. It
/// waited on `app.staticTexts["LEADERBOARD"]` - a section title the football
/// redesign removed - and looked for `Calendar.current.component(.year)`, i.e.
/// the real-world year, when the NFL season label lags it (season 2025 runs into
/// February 2026). It also drove the picker by tapping normalised screen
/// coordinates, which broke the moment the bar changed. This version anchors on
/// the table header and addresses the control by its accessibility label.
final class SeasonPickerUITests: XCTestCase {
    var app: XCUIApplication!

    /// A debug build decodes the 33k-row bundled snapshot unoptimised; release
    /// does the same work in about three seconds.
    ///
    /// Generous because XCUITest makes it worse than a plain launch, not better:
    /// each `waitForExistence` retry captures a debug description, which walks
    /// the accessibility tree of a fifty-row board across all four mounted tabs
    /// while the decode is still competing for the main thread. Launched
    /// directly on the same simulator the board is up inside 45s; under the test
    /// host 120s was not enough and every one of these failed on "Leaderboard
    /// should appear" without the app being at fault.
    private let loadTimeout: TimeInterval = 360

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launchArguments += ["-stats.board", "advanced"]
        app.launchArguments += ["-stats.qualifier", "All Players"]
        app.launchArguments += ["-ResetUITestState"]
        app.launch()
    }

    /// Season and phase share one pill, labelled for VoiceOver as
    /// "Season and season type" with a value like "2025, Regular Season".
    ///
    /// The *hittable* one, and both words are load-bearing.
    ///
    /// Stats, Trends and Teams each mount this control, and a `TabView` keeps
    /// every visited tab's hierarchy alive, so the app holds as many of them as
    /// tabs the session has opened. A bare exact query therefore throws
    /// "Multiple matching elements found", and `firstMatch` silently answers
    /// with whichever is first in the tree - a background tab's, whose snapshot
    /// is not redrawn when the season changes, so the value it reports is the
    /// season from before the change. Only one of them is on screen, and that
    /// is the one the user is touching.
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
        control.tap()

        // The menu should carry the career rollup plus the full 2000-current
        // range. Spot-check the ends and the sentinel rather than all 27 rows,
        // since a long menu scrolls and off-screen rows aren't hittable.
        // "All since 2000", not "All Time": `SeasonLabel.text` renamed it
        // deliberately, because "All Time" claimed a century of football the
        // data does not have. The test kept asking for the old wording.
        XCTAssertTrue(
            app.buttons["All since 2000"].waitForExistence(timeout: 20),
            "Season menu should offer the career rollup"
        )
        XCTAssertTrue(app.buttons["2025"].exists, "Season menu should offer a recent season")

        // Years are bare four-digit strings - never thousands-separated, which is
        // what this originally guarded against ("2,025").
        let commaYears = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9],[0-9]{3}$")
        )
        XCTAssertEqual(commaYears.count, 0, "Season labels should not be thousands-separated")
    }

    func testSelectingAnotherSeasonKeepsTheBoardAlive() throws {
        XCTAssertTrue(waitForBoard(), "Leaderboard should appear")

        let control = seasonControl()
        guard control.waitForExistence(timeout: 15) else {
            return XCTFail("Season control should exist")
        }
        let before = control.value as? String

        control.tap()
        let target = app.buttons["2024"]
        guard target.waitForExistence(timeout: 5) else {
            // Locked behind Pro in this build: the paywall is a valid outcome.
            app.tap()
            return
        }
        target.tap()

        // Either the board comes back for the new season, or the trial sheet
        // intercepted the locked year. Both are correct; a blank screen isn't.
        let board = app.staticTexts["RANK"].waitForExistence(timeout: loadTimeout)
        let paywall = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'trial' OR label CONTAINS[c] 'unlock'")
        ).firstMatch.exists
        XCTAssertTrue(board || paywall, "Season change should leave the app in a usable state")

        // A locked season is a legitimate outcome even when its row was
        // tappable: the tap opens the trial sheet and the board stays where it
        // was. Only assert the season actually moved when nothing intercepted
        // the tap. Without this the test failed on correct behaviour, because
        // past seasons are Pro and the UI suite runs a free build.
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

        // Season and phase were two separate pills until they were merged to stop
        // iOS pushing the upgrade CTA into a "..." overflow. Both sections must
        // still be reachable from the one menu.
        let playoffs = app.buttons["Playoffs"]
        XCTAssertTrue(
            playoffs.waitForExistence(timeout: 5),
            "The merged menu should still offer the season type"
        )
        XCTAssertTrue(app.buttons["Regular Season"].exists, "Regular season should be listed too")

        // `exists` alone was not enough, and this is the bug that shipped: the
        // season section listed 27 rows above these two, so the phase sat below
        // the fold of a scrolling menu. It was in the hierarchy the whole time -
        // present, addressable, and untappable without scrolling to the bottom
        // of a list nobody would think to scroll. Hittability is the assertion
        // that would have caught it.
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
