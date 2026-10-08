import XCTest
@testable import Gridiron_StatScout

final class PlayerTests: XCTestCase {
    func testOverallPercentileDoubleAverage() {
        let metrics = [
            Metric(id: "m1", label: "A", value: "1", percentile: 75, category: .passing),
            Metric(id: "m2", label: "B", value: "2", percentile: 76, category: .passing),
            Metric(id: "m3", label: "C", value: "3", percentile: 77, category: .passing)
        ]
        let player = Player(
            playerId: 1, name: "Test", team: "KC", position: "QB",
            handedness: "",
            updatedAt: Date(), metrics: metrics, standardStats: [], games: []
        )
        XCTAssertEqual(player.overallPercentile, 76) // 75.9 rounded
    }

    func testShareSummaryIncludesTopSignal() {
        let metric = Metric(id: "m1", label: "Pass Yds", value: "4,918", percentile: 100, category: .passing)
        let player = Player(
            playerId: 1, name: "Patrick Mahomes", team: "KC", position: "QB",
            handedness: "",
            updatedAt: Date(), metrics: [metric], standardStats: [], games: []
        )
        let summary = player.shareSummary
        XCTAssertTrue(summary.contains("Patrick Mahomes"))
        XCTAssertTrue(summary.contains("Pass Yds"))
        XCTAssertTrue(summary.contains("100th"))
    }

    func testMultiCategoryOverallUsesBestCategoryAverage() {
        // A rushing QB carries both Passing and Rushing metrics - the headline
        // number should reflect the best category, not a blended average.
        let metrics = [
            Metric(id: "p1", label: "Pass Yds", value: "4,000", percentile: 95, category: .passing),
            Metric(id: "p2", label: "Rating", value: "105", percentile: 95, category: .passing),
            Metric(id: "r1", label: "Rush Yds", value: "500", percentile: 30, category: .rushing),
            Metric(id: "r2", label: "Rush TD", value: "5", percentile: 30, category: .rushing)
        ]
        let player = Player(
            playerId: 1, name: "Dual Threat", team: "BUF", position: "QB",
            handedness: "",
            updatedAt: Date(), playerType: "qb",
            metrics: metrics, standardStats: [], games: []
        )
        XCTAssertEqual(player.overallPercentile, 95)
    }

    func testPlayerDecodesSeasonAndPlayerType() throws {
        let json = """
        {
            "id": 1,
            "name": "Test",
            "team": "KC",
            "position": "QB",
            "handedness": "",
            "image_url": null,
            "updated_at": "2026-04-28T12:00:00Z",
            "season": 2025,
            "player_type": "qb",
            "source": "nflreadpy",
            "metrics": [],
            "standard_stats": [],
            "games": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder.statScout
        let player = try decoder.decode(Player.self, from: json)
        XCTAssertEqual(player.season, 2025)
        XCTAssertEqual(player.playerType, "qb")
        XCTAssertEqual(player.source, "nflreadpy")
        XCTAssertEqual(player.seasonPhase, .regular)
    }

    func testPlayerComparisonDoesNotCrossSidesOfBall() {
        let quarterback = Player(
            playerId: 1, name: "Quarterback", team: "KC", position: "QB",
            handedness: "", updatedAt: Date(), playerType: "qb",
            metrics: [], standardStats: [], games: []
        )
        let receiver = Player(
            playerId: 2, name: "Receiver", team: "KC", position: "WR",
            handedness: "", updatedAt: Date(), playerType: "wr",
            metrics: [], standardStats: [], games: []
        )
        let defender = Player(
            playerId: 3, name: "Defender", team: "DEN", position: "LB",
            handedness: "", updatedAt: Date(), playerType: "def",
            metrics: [], standardStats: [], games: []
        )

        XCTAssertTrue(quarterback.canCompareHeadToHead(with: receiver))
        XCTAssertTrue(defender.canCompareHeadToHead(with: defender))
        XCTAssertFalse(quarterback.canCompareHeadToHead(with: defender))
    }

    func testInitialsHandleSuffixes() {
        let witt = Player(playerId: 1, name: "Michael Pittman Jr.", team: "IND", position: "WR", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(witt.initials, "MP")

        let harris = Player(playerId: 2, name: "Odell Beckham Jr.", team: "MIA", position: "WR", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(harris.initials, "OB")

        let third = Player(playerId: 3, name: "Robert Griffin III", team: "WAS", position: "QB", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(third.initials, "RG")
    }

    func testInitialsStandardNames() {
        let mahomes = Player(playerId: 1, name: "Patrick Mahomes", team: "KC", position: "QB", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(mahomes.initials, "PM")

        let chase = Player(playerId: 2, name: "Ja'Marr Chase", team: "CIN", position: "WR", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(chase.initials, "JC")

        let single = Player(playerId: 3, name: "Cher", team: "KC", position: "QB", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(single.initials, "C")
    }

    func testWeeklyDeltaSumsRecentGamesOnly() {
        let now = Date()
        let player = Player(
            playerId: 1, name: "Test", team: "KC", position: "QB",
            handedness: "",
            updatedAt: now, metrics: [], standardStats: [],
            games: [
                GameTrend(id: "recent-up", date: now.addingTimeInterval(-24 * 3600), opponent: "BUF", summary: "", percentileDelta: 5, keyMetric: "Pass Yds"),
                GameTrend(id: "recent-down", date: now.addingTimeInterval(-2 * 24 * 3600), opponent: "DEN", summary: "", percentileDelta: -2, keyMetric: "EPA/Play"),
                GameTrend(id: "old", date: now.addingTimeInterval(-8 * 24 * 3600), opponent: "LV", summary: "", percentileDelta: 20, keyMetric: "Rating")
            ]
        )

        XCTAssertEqual(player.weeklyDelta, 3)
    }

    @MainActor
    func testRawNumericStripsThousandsSeparators() {
        XCTAssertEqual(DashboardViewModel.rawNumeric("4,918")!, 4918, accuracy: 0.001)
        XCTAssertEqual(DashboardViewModel.rawNumeric("68.3%")!, 68.3, accuracy: 0.001)
    }

    func testDisplayPositionFallsBackToPlayerType() {
        let tbd = Player(playerId: 1, name: "Test", team: "KC", position: "TBD", handedness: "", updatedAt: Date(), playerType: "def", metrics: [], standardStats: [], games: [])
        XCTAssertEqual(tbd.displayPosition, "DEF")
    }
}


final class FootballMetricRegistryTests: XCTestCase {
    func testAdvancedAndTraditionalClassification() {
        let epa = Metric(id: "epa", label: "EPA/Play", value: "0.18", percentile: 90, category: .passing)
        let yards = Metric(id: "yards", label: "Pass Yds", value: "4,000", percentile: 85, category: .passing)

        XCTAssertEqual(FootballMetricRegistry.kind(for: epa), .advanced)
        XCTAssertEqual(FootballMetricRegistry.kind(for: yards), .traditional)
    }

    /// Defence used to be traditional-only, and this test asserted that. It now
    /// asserts the opposite, because PFR's advanced defensive table (2018+) is
    /// merged in: pressure generated and what the defender allowed in coverage.
    func testDefenseHasAdvancedDefinitions() {
        let defenseDefinitions = FootballMetricRegistry.definitions.filter { $0.positions.contains(.defense) }
        XCTAssertFalse(defenseDefinitions.isEmpty)
        XCTAssertTrue(defenseDefinitions.contains { $0.kind == .advanced })
        XCTAssertTrue(defenseDefinitions.contains { $0.kind == .traditional })
    }

    /// Coverage metrics describe what a defender gave up, so every one of them
    /// has to rank ascending. Getting this backwards would put the worst corner
    /// in the league at the top of the board.
    func testCoverageMetricsAreLowerIsBetter() {
        for label in ["Cmp% Allowed", "Yds/Tgt Allowed", "Rating Allowed", "Missed Tkl%"] {
            let definition = FootballMetricRegistry.definition(for: label, category: .defense)
            XCTAssertNotNil(definition, "missing \(label)")
            XCTAssertEqual(definition?.higherIsBetter, false, "\(label) should rank lower-is-better")
        }
        // Pass-rush counting stats go the other way.
        for label in ["Pressures", "Hurries", "QB KD"] {
            XCTAssertEqual(
                FootballMetricRegistry.definition(for: label, category: .defense)?.higherIsBetter,
                true,
                "\(label) should rank higher-is-better"
            )
        }
    }

    /// Advanced rows must sort above traditional ones inside Defense, the same
    /// as every other category.
    func testDefenseAdvancedMetricsLeadDisplayOrder() {
        let order = MetricCategory.defense.metricPriorityOrder
        guard let firstTraditional = order.firstIndex(of: "Tackles"),
              let lastAdvanced = order.firstIndex(of: "Missed Tkl%") else {
            return XCTFail("expected both advanced and traditional defence metrics")
        }
        XCTAssertLessThan(lastAdvanced, firstTraditional)
    }

    func testPositionHeadlinePreferences() {
        XCTAssertEqual(PlayerPositionGroup.qb.preferredAdvancedMetrics.first, "EPA/Play")
        XCTAssertEqual(PlayerPositionGroup.rb.preferredAdvancedMetrics.first, "EPA/Rush")
        XCTAssertEqual(PlayerPositionGroup.wr.preferredAdvancedMetrics.first, "EPA/Tgt")
    }

    @MainActor
    func testLowerIsBetterUsesRegistry() {
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "INT%", category: .passing))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Fumble%", category: .rushing))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "EPA/Play", category: .passing))
    }

    func testUnknownMetricIsPreserved() {
        let unknown = Metric(id: "unknown", label: "New Metric", value: "1.0", percentile: 50, category: .passing)
        XCTAssertEqual(FootballMetricRegistry.kind(for: unknown), .advanced)
        XCTAssertTrue(FootballMetricRegistry.isSupported(unknown, by: .qb))
        XCTAssertEqual(FootballMetricRegistry.sorted([unknown]), [unknown])
    }
}
