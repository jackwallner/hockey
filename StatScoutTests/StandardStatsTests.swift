import XCTest
@testable import Gridiron_StatScout

final class StandardStatsTests: XCTestCase {
    func testPositionCatalogUsesNFLStatLines() {
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .qb), "Pass Yds")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .rb), "Rush Yds")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .wr), "Rec Yds")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .te), "Rec Yds")
        XCTAssertEqual(StandardStatCatalog.defaultStat(for: .defense), "Tackles")
    }

    func testWalkingThePositionTabsRanksEachPositionByItsOwnDefault() {
        var stat = StandardStatCatalog.defaultStat(for: .qb)
        var position = PlayerPositionGroup.qb
        for next in [PlayerPositionGroup.rb, .wr, .te, .defense, .qb] {
            stat = StandardStatCatalog.stat(keeping: stat, from: position, to: next)
            position = next
            XCTAssertEqual(stat, StandardStatCatalog.defaultStat(for: next))
        }
    }

    func testDeliberatelyChosenStatFollowsToPositionsThatOfferIt() {
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "Rush TD", from: .qb, to: .rb),
            "Rush TD"
        )
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "Rush TD", from: .rb, to: .wr),
            "Rush TD"
        )
        XCTAssertEqual(
            StandardStatCatalog.stat(keeping: "Rush TD", from: .wr, to: .defense),
            "Tackles"
        )
    }

    func testQuarterbackInterceptionsDefaultLowestFirst() {
        XCTAssertFalse(StandardStatCatalog.defaultDescending(for: "INT", position: .qb))
        XCTAssertTrue(StandardStatCatalog.defaultDescending(for: "Def INT", position: .defense))
    }

    func testMetricCategoryDecodesCaseInsensitively() throws {
        for rawValue in ["passing", "PASSING", "Passing"] {
            let json = """
            {"id":"m","label":"EPA/Play","value":"0.12","percentile":88,"category":"\(rawValue)"}
            """.data(using: .utf8)!
            let metric = try JSONDecoder().decode(Metric.self, from: json)
            XCTAssertEqual(metric.category, .passing)
        }
    }

    func testCompositeStandardStatsUseRatesInsteadOfLeadingCounts() {
        XCTAssertEqual(
            StandardStatSemantics.numericValue(label: "Rec/Tgt", value: "8/11")!,
            72.727,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StandardStatSemantics.numericValue(label: "Cmp/Att", value: "15/25")!,
            60,
            accuracy: 0.001
        )
    }

    func testStandardComparisonRespectsDirectionAndRates() {
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "Rec/Tgt", left: "8/11", right: "5/9"),
            .left
        )
        XCTAssertEqual(
            StandardStatSemantics.winner(label: "INT", left: "1", right: "3"),
            .left
        )
        XCTAssertNil(StandardStatSemantics.winner(label: "G", left: "1", right: "1"))
    }

    func testEveryExistingStandardStatGetsAPercentile() {
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "Rec/Tgt",
                value: "8/11",
                peerValues: ["8/11", "5/9", "10/10"]
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
        // Week one: two peers, and a value that beats one of them.
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "Rush Yds",
                value: "80",
                peerValues: ["80", "20"]
            ),
            75
        )
        // A cohort of one is the middle of its own distribution, never 0.
        XCTAssertEqual(
            StandardStatSemantics.percentile(
                label: "Rush Yds",
                value: "80",
                peerValues: ["80"]
            ),
            50
        )
        // Direction still applies with a thin pool: fewer picks is better.
        XCTAssertGreaterThan(
            StandardStatSemantics.percentile(
                label: "INT",
                value: "0",
                peerValues: ["0", "3"]
            ),
            StandardStatSemantics.percentile(
                label: "INT",
                value: "3",
                peerValues: ["0", "3"]
            )
        )
    }

    func testPercentileIsNeverZeroForAnExistingValue() {
        // The floor the profile, the team card and the boards all rely on: a
        // stat that exists always lands on a drawable 1-100 bar.
        for value in ["0", "1", "250", "0.0%"] {
            let pct = StandardStatSemantics.percentile(
                label: "Rec Yds",
                value: value,
                peerValues: ["0", "1", "250", "999"]
            )
            XCTAssertGreaterThanOrEqual(pct, 1, "\(value) produced \(pct)")
            XCTAssertLessThanOrEqual(pct, 100, "\(value) produced \(pct)")
        }
    }

    func testLeagueCurveInterpolatesFromTwoPoints() {
        // Was nil below five points, which dropped the Recent Form bar
        // entirely in an opening week.
        let curve = LeaguePercentileCurve(points: [(100, 20), (300, 80)])
        XCTAssertNotNil(curve)
        XCTAssertEqual(curve?.percentile(for: 200), 50)
        XCTAssertEqual(curve?.percentile(for: 50), 20)
        XCTAssertEqual(curve?.percentile(for: 400), 80)
        XCTAssertNil(LeaguePercentileCurve(points: [(100, 20)]))
    }

    func testRecentWindowCaptionNamesTheGamesInHand() {
        XCTAssertEqual(RecentFormWindow.caption(games: 1, span: 5), "1 game")
        XCTAssertEqual(RecentFormWindow.caption(games: 3, span: 5), "3 games")
        XCTAssertEqual(RecentFormWindow.caption(games: 5, span: 5), "5 games")
        // A window can never hold more than it asked for; if it somehow does,
        // the span is still what was requested.
        XCTAssertEqual(RecentFormWindow.caption(games: 9, span: 8), "8 games")
    }
}
