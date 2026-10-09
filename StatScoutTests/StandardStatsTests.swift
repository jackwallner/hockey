import XCTest
@testable import Hockey_StatScout

final class StandardStatsTests: XCTestCase {
    func testPositionCatalogUsesHockeyStatLines() {
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .forward), "P")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .defense), "P")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .goalie), "SV%")
        XCTAssertTrue(StandardStatCatalog.stats(for: .forward).contains("TOI/GP"))
        XCTAssertTrue(StandardStatCatalog.stats(for: .goalie).contains("GAA"))
        XCTAssertFalse(StandardStatCatalog.stats(for: .goalie).contains("G"), "goalies do not score")
        XCTAssertFalse(StandardStatCatalog.stats(for: .forward).contains("SV%"))
    }

    func testWalkingThePositionTabsRanksEachPositionByItsOwnDefault() {
        var stat = StandardStatCatalog.defaultStat(for: .forward)
        var position = PlayerPositionGroup.forward
        for next in [PlayerPositionGroup.defense, .goalie, .forward, .goalie, .defense] {
            stat = StandardStatCatalog.stat(keeping: stat, from: position, to: next)
            position = next
            XCTAssertEqual(stat, StandardStatCatalog.defaultStat(for: next))
        }
    }

    func testDeliberatelyChosenStatFollowsToPositionsThatOfferIt() {
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "G", from: .forward, to: .defense),
            "G"
        )
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "G", from: .defense, to: .forward),
            "G"
        )
        // Goalies do not score: the choice falls back to their own default.
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "G", from: .forward, to: .goalie),
            "SV%"
        )
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "GP", from: .goalie, to: .forward),
            "GP"
        )
    }

    func testGoalsAgainstAndPenaltiesDefaultLowestFirst() {
        XCTAssertFalse(StandardStatCatalog.defaultDescending(for: "GAA", position: .goalie))
        XCTAssertFalse(StandardStatCatalog.defaultDescending(for: "PIM", position: .forward))
        XCTAssertFalse(StandardStatCatalog.defaultDescending(for: "L", position: .goalie))
        XCTAssertTrue(StandardStatCatalog.defaultDescending(for: "SV%", position: .goalie))
        XCTAssertTrue(StandardStatCatalog.defaultDescending(for: "P", position: .forward))
    }

    func testTimeOnIceRanksByItsMinutes() {
        XCTAssertEqual(
            StandardStatSemantics.numericValue(label: "TOI/GP", value: "19:42")!,
            19.7,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StandardStatSemantics.numericValue(label: "FO%", value: "54.2%")!,
            54.2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StandardStatSemantics.numericValue(label: "SV%", value: ".915")!,
            0.915,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "TOI/GP", left: "21:05", right: "19:42"),
            .left,
            "a clock compares as minutes, not as the text before the colon"
        )
    }

    func testStandardComparisonRespectsDirectionAndRates() {
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "SV%", left: ".915", right: ".907"),
            .left
        )
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "GAA", left: "2.31", right: "2.88"),
            .left,
            "the lower goals-against average wins"
        )
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "PIM", left: "30", right: "12"),
            .right
        )
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "L", left: "14", right: "9"),
            .right
        )
        XCTAssertNil(StandardStatSemantics.winner(label: "G", left: "1", right: "1"))
        XCTAssertNil(StandardStatSemantics.winner(label: "G", left: nil, right: "1"))
    }

    func testEveryExistingStandardStatGetsAPercentile() {
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "TOI/GP",
                value: "19:42",
                peerValues: ["19:42", "15:00", "22:30"]
            ),
            50
        )
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "G",
                value: "1",
                peerValues: []
            ),
            50
        )
    }

    func testPercentileRanksAgainstWhicheverPeersHaveTheStat() {
        // Opening week: two peers, and a value that beats one of them.
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "SOG",
                value: "8",
                peerValues: ["8", "2"]
            ),
            75
        )
        // A cohort of one is the middle of its own distribution, never 0.
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "SOG",
                value: "8",
                peerValues: ["8"]
            ),
            50
        )
        // Direction still applies with a thin pool: fewer penalty minutes is better.
        XCTAssertGreaterThan(
            StandardStatSemantics.percentile(
                label: "PIM",
                value: "0",
                peerValues: ["0", "12"]
            ),
            StandardStatSemantics.percentile(
                label: "PIM",
                value: "12",
                peerValues: ["0", "12"]
            )
        )
    }

    func testPercentileIsNeverZeroForAnExistingValue() {
        // The floor the profile, the team card and the boards all rely on: a
        // stat that exists always lands on a drawable 1-100 bar.
        for value in ["0", "1", "250", "0.0%"] {
            let pct = StandardStatSemantics.percentile(
                label: "SOG",
                value: value,
                peerValues: ["0", "1", "250", "999"]
            )
            XCTAssertGreaterThanOrEqual(pct, 1, "\(value) produced \(pct)")
            XCTAssertLessThanOrEqual(pct, 100, "\(value) produced \(pct)")
        }
    }

    func testLeagueCurveInterpolatesFromTwoPoints() {
        // Was nil below five points, which dropped the Recent Form bar
        // entirely on opening night.
        let curve = LeaguePercentileCurve(points: [(100, 20), (300, 80)])
        XCTAssertNotNil(curve)
        XCTAssertEqual(curve?.percentile(for: 200), 50)
        XCTAssertEqual(curve?.percentile(for: 50), 20)
        XCTAssertEqual(curve?.percentile(for: 400), 80)
        XCTAssertNil(LeaguePercentileCurve(points: [(100, 20)]))
    }
}
