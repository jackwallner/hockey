import XCTest
@testable import Hockey_StatScout

/// The unfolded iPhone Duo splits into a tabs pane and a detail pane either
/// side of the fold. Everything else, the folded Duo included, keeps one column.
@MainActor
final class UnfoldedSplitTests: XCTestCase {

    func testCompactWidthNeverSplits() {
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 470...481))
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
    }

    func testTooNarrowForTwoPhonePanesStaysSingleColumn() {
        // The unfolded Duo held in portrait is regular width but 669 pt wide.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
        XCTAssertNil(UnfoldedSplit.make(width: 719, isRegularWidth: true, fold: nil))
    }

    func testPanesSitAtTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 470...481)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 470, secondaryX: 481, secondaryWidth: 470))
    }

    func testFoldOffCentreStillLeavesNothingUnderIt() {
        // A trailing vertical bar shortens the container, not the fold.
        let split = UnfoldedSplit.make(width: 880, isRegularWidth: true, fold: 470...481)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 470, secondaryX: 481, secondaryWidth: 399))
    }

    func testNoReportedFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldThatWouldSqueezeAPaneFallsBackToAnEvenSplit() {
        let early = UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 300...310)
        XCTAssertEqual(early, UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
        let late = UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 500...520)
        XCTAssertEqual(late, UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
    }

    func testEveryPaneIsAtLeastPhoneWidth() {
        for width in stride(from: 720, through: 1400, by: 37) {
            let w = CGFloat(width)
            for fold in [nil, (w / 2 - 6)...(w / 2 + 6), 360...372] as [ClosedRange<CGFloat>?] {
                guard let split = UnfoldedSplit.make(width: w, isRegularWidth: true, fold: fold) else {
                    return XCTFail("no split at \(w)")
                }
                XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
                XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
                XCTAssertGreaterThanOrEqual(split.secondaryX, split.primaryWidth)
                XCTAssertEqual(split.secondaryX + split.secondaryWidth, w)
            }
        }
    }

    func testDetailMatchesTheSamePageWhateverTheSeason() {
        func center(season: Int, phase: SeasonPhase) -> Player {
            Player(
                playerId: 8478402, name: "Connor McDavid", team: "EDM", position: "C",
                handedness: "", updatedAt: Date(), season: season, seasonPhase: phase,
                metrics: [], standardStats: [], games: []
            )
        }
        let regular = PaneDetail.player(center(season: 2026, phase: .regular))
        let playoffs = PaneDetail.player(center(season: 2025, phase: .playoffs))
        XCTAssertTrue(regular.matches(playoffs))
        XCTAssertNotEqual(regular.pageID, playoffs.pageID)
        XCTAssertFalse(regular.matches(.team(TeamDestination(abbr: "EDM"))))
        XCTAssertFalse(regular.matches(nil))
        XCTAssertTrue(PaneDetail.team(TeamDestination(abbr: "EDM")).matches(.team(TeamDestination(abbr: "EDM"))))
        XCTAssertTrue(PaneDetail.game(GameRoute(gameId: "2026020114")).matches(.game(GameRoute(gameId: "2026020114"))))
        XCTAssertFalse(PaneDetail.game(GameRoute(gameId: "2026020114")).matches(.game(GameRoute(gameId: "2026020115"))))
    }
}
