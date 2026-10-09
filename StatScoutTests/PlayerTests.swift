import XCTest
@testable import Hockey_StatScout

final class PlayerTests: XCTestCase {
    func testOverallPercentileDoubleAverage() {
        let metrics = [
            Metric(id: "m1", label: "G", value: "1", percentile: 75, category: .scoring),
            Metric(id: "m2", label: "A", value: "2", percentile: 76, category: .scoring),
            Metric(id: "m3", label: "P", value: "3", percentile: 77, category: .scoring)
        ]
        let player = Player(
            playerId: 1, name: "Test", team: "SEA", position: "C",
            handedness: "",
            updatedAt: Date(), metrics: metrics, standardStats: [], games: []
        )
        XCTAssertEqual(player.overallPercentile, 76) // 76.0
    }

    func testShareSummaryIncludesTopSignal() {
        let metric = Metric(id: "m1", label: "ixG", value: "31.4", percentile: 100, category: .shotQuality)
        let player = Player(
            playerId: 1, name: "Connor Vale", team: "SEA", position: "C",
            handedness: "",
            updatedAt: Date(), metrics: [metric], standardStats: [], games: []
        )
        let summary = player.shareSummary
        XCTAssertTrue(summary.contains("Connor Vale"))
        XCTAssertTrue(summary.contains("ixG"))
        XCTAssertTrue(summary.contains("100th"))
    }

    func testMultiCategoryOverallUsesBestCategoryAverage() {
        // A scoring winger who is a mediocre driver carries both Scoring and
        // Play Driving metrics. The headline number reflects the best
        // category, not a blended average.
        let metrics = [
            Metric(id: "s1", label: "P/60", value: "3.1", percentile: 95, category: .scoring),
            Metric(id: "s2", label: "Primary P", value: "40", percentile: 95, category: .scoring),
            Metric(id: "d1", label: "xGF%", value: "47.0%", percentile: 30, category: .playDriving),
            Metric(id: "d2", label: "CF%", value: "46.0%", percentile: 30, category: .playDriving)
        ]
        let player = Player(
            playerId: 1, name: "Dual Threat", team: "BUF", position: "LW",
            handedness: "",
            updatedAt: Date(), playerType: "f",
            metrics: metrics, standardStats: [], games: []
        )
        XCTAssertEqual(player.overallPercentile, 95)
    }

    func testPlayerDecodesSeasonAndPlayerType() throws {
        let json = """
        {
            "id": 8478402,
            "name": "Test",
            "team": "SEA",
            "position": "C",
            "handedness": "L",
            "image_url": null,
            "updated_at": "2026-10-08T12:00:00Z",
            "season": 2026,
            "player_type": "f",
            "source": "moneypuck",
            "metrics": [],
            "standard_stats": [],
            "games": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder.statScout
        let player = try decoder.decode(Player.self, from: json)
        XCTAssertEqual(player.season, 2026)
        XCTAssertEqual(player.playerType, "f")
        XCTAssertEqual(player.source, "moneypuck")
        XCTAssertEqual(player.seasonPhase, .regular)
    }

    func testCohortFilteringKeepsSkatersAndGoaliesApart() {
        func player(_ type: String?) -> Player {
            Player(
                playerId: 1, name: "P", team: "SEA", position: "C", handedness: "",
                updatedAt: Date(), playerType: type, metrics: [], standardStats: [], games: []
            )
        }
        for category in [MetricCategory.scoring, .shotQuality, .playDriving] {
            XCTAssertTrue(player("f").matchesPlayerType(for: category))
            XCTAssertTrue(player("d").matchesPlayerType(for: category))
            XCTAssertFalse(player("g").matchesPlayerType(for: category))
        }
        XCTAssertTrue(player("g").matchesPlayerType(for: .goaltending))
        XCTAssertFalse(player("f").matchesPlayerType(for: .goaltending))
        XCTAssertFalse(player("d").matchesPlayerType(for: .goaltending))
        // An unknown or missing cohort is never dropped.
        XCTAssertTrue(player(nil).matchesPlayerType(for: .goaltending))
        XCTAssertTrue(player("x").matchesPlayerType(for: .scoring))
        XCTAssertTrue(player("f").matchesPlayerType(for: nil))
    }

    func testPrimaryCategoryFollowsTheCohort() {
        func player(_ type: String) -> Player {
            Player(
                playerId: 1, name: "P", team: "SEA", position: "C", handedness: "",
                updatedAt: Date(), playerType: type, metrics: [], standardStats: [], games: []
            )
        }
        XCTAssertEqual(player("f").primaryCategory, .scoring)
        XCTAssertEqual(player("d").primaryCategory, .playDriving)
        XCTAssertEqual(player("g").primaryCategory, .goaltending)
    }

    func testPlayerComparisonDoesNotCrossSkatersAndGoalies() {
        let center = Player(
            playerId: 1, name: "Center", team: "SEA", position: "C",
            handedness: "L", updatedAt: Date(), playerType: "f",
            metrics: [], standardStats: [], games: []
        )
        let defenseman = Player(
            playerId: 2, name: "Defenseman", team: "SEA", position: "D",
            handedness: "R", updatedAt: Date(), playerType: "d",
            metrics: [], standardStats: [], games: []
        )
        let goalie = Player(
            playerId: 3, name: "Goalie", team: "EDM", position: "G",
            handedness: "L", updatedAt: Date(), playerType: "g",
            metrics: [], standardStats: [], games: []
        )

        XCTAssertTrue(center.canCompareHeadToHead(with: defenseman))
        XCTAssertTrue(goalie.canCompareHeadToHead(with: goalie))
        XCTAssertFalse(center.canCompareHeadToHead(with: goalie))
        XCTAssertFalse(goalie.canCompareHeadToHead(with: defenseman))
    }

    func testPositionGroupFallsBackToTheRawPosition() {
        func group(_ position: String) -> PlayerPositionGroup {
            Player(
                playerId: 1, name: "P", team: "SEA", position: position, handedness: "",
                updatedAt: Date(), metrics: [], standardStats: [], games: []
            ).positionGroup
        }
        XCTAssertEqual(group("C"), .forward)
        XCTAssertEqual(group("L"), .forward)
        XCTAssertEqual(group("R"), .forward)
        XCTAssertEqual(group("D"), .defense)
        XCTAssertEqual(group("G"), .goalie)
    }

    func testInitialsHandleSuffixes() {
        let junior = Player(playerId: 1, name: "Michael Pittman Jr.", team: "SEA", position: "C", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(junior.initials, "MP")

        let second = Player(playerId: 2, name: "Odell Beckham II", team: "SEA", position: "L", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(second.initials, "OB")

        let third = Player(playerId: 3, name: "Robert Griffin III", team: "WSH", position: "D", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(third.initials, "RG")
    }

    func testInitialsStandardNames() {
        let vale = Player(playerId: 1, name: "Connor Vale", team: "EDM", position: "C", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(vale.initials, "CV")

        let apostrophe = Player(playerId: 2, name: "Ryan O'Reilly", team: "NSH", position: "C", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(apostrophe.initials, "RO")

        let single = Player(playerId: 3, name: "Cher", team: "SEA", position: "C", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        XCTAssertEqual(single.initials, "C")
    }

    func testWeeklyDeltaSumsRecentGamesOnly() {
        let now = Date()
        let player = Player(
            playerId: 1, name: "Test", team: "SEA", position: "C",
            handedness: "",
            updatedAt: now, metrics: [], standardStats: [],
            games: [
                GameTrend(id: "recent-up", date: now.addingTimeInterval(-24 * 3600), opponent: "VAN", summary: "", percentileDelta: 5, keyMetric: "P/60"),
                GameTrend(id: "recent-down", date: now.addingTimeInterval(-2 * 24 * 3600), opponent: "CGY", summary: "", percentileDelta: -2, keyMetric: "ixG"),
                GameTrend(id: "old", date: now.addingTimeInterval(-8 * 24 * 3600), opponent: "EDM", summary: "", percentileDelta: 20, keyMetric: "GAx")
            ]
        )

        XCTAssertEqual(player.weeklyDelta, 3)
    }

    @MainActor
    func testRawNumericStripsThousandsSeparators() {
        XCTAssertEqual(DashboardViewModel.rawNumeric("1,312")!, 1312, accuracy: 0.001)
        XCTAssertEqual(DashboardViewModel.rawNumeric("54.2%")!, 54.2, accuracy: 0.001)
        XCTAssertEqual(DashboardViewModel.rawNumeric(".915")!, 0.915, accuracy: 0.0001)
    }

    func testDisplayPositionFallsBackToPlayerType() {
        let tbd = Player(playerId: 1, name: "Test", team: "SEA", position: "TBD", handedness: "", updatedAt: Date(), playerType: "d", metrics: [], standardStats: [], games: [])
        XCTAssertEqual(tbd.displayPosition, "D")
        let winger = Player(playerId: 2, name: "Test", team: "SEA", position: "L", handedness: "", updatedAt: Date(), playerType: "f", metrics: [], standardStats: [], games: [])
        XCTAssertEqual(winger.displayPosition, "LW")
    }

    func testSeasonLabelDisplaysAsTwoYearForm() {
        XCTAssertEqual(SeasonLabel.display(2026), "2026-27")
        XCTAssertEqual(SeasonLabel.display(2008), "2008-09")
        XCTAssertEqual(SeasonLabel.display(2099), "2099-00")
        XCTAssertEqual(SeasonLabel.display(StatScoutSeason.allTime), "All Time")
        XCTAssertEqual(SeasonLabel.display(2026, phase: .regular), "2026-27 regular season")
        XCTAssertEqual(SeasonLabel.display(2025, phase: .playoffs), "2025-26 playoffs")
        XCTAssertEqual(SeasonLabel.display(StatScoutSeason.allTime, phase: .playoffs), "All Time")
    }
}


final class HockeyMetricRegistryTests: XCTestCase {
    func testAdvancedAndTraditionalClassification() {
        let ixg = Metric(id: "ixg", label: "ixG", value: "31.4", percentile: 90, category: .shotQuality)
        let goals = Metric(id: "g", label: "G", value: "44", percentile: 85, category: .scoring)
        let gsax = Metric(id: "gsax", label: "GSAx", value: "+12.3", percentile: 95, category: .goaltending)
        let sv = Metric(id: "sv", label: "SV%", value: ".915", percentile: 70, category: .goaltending)

        XCTAssertEqual(HockeyMetricRegistry.kind(for: ixg), .advanced)
        XCTAssertEqual(HockeyMetricRegistry.kind(for: goals), .traditional)
        XCTAssertEqual(HockeyMetricRegistry.kind(for: gsax), .advanced)
        XCTAssertEqual(HockeyMetricRegistry.kind(for: sv), .traditional)
    }

    func testEveryCohortHasAdvancedAndTraditionalDefinitions() {
        for position in PlayerPositionGroup.allCases {
            let definitions = HockeyMetricRegistry.definitions.filter { $0.positions.contains(position) }
            XCTAssertFalse(definitions.isEmpty, "\(position)")
            XCTAssertTrue(definitions.contains { $0.kind == .advanced }, "\(position)")
            XCTAssertTrue(definitions.contains { $0.kind == .traditional }, "\(position)")
        }
    }

    func testSkaterMetricsAreNotOfferedToGoaliesAndBack() {
        let ixg = Metric(id: "ixg", label: "ixG", value: "31.4", percentile: 90, category: .shotQuality)
        let gsax = Metric(id: "gsax", label: "GSAx", value: "+12.3", percentile: 95, category: .goaltending)
        XCTAssertTrue(HockeyMetricRegistry.isSupported(ixg, by: .forward))
        XCTAssertTrue(HockeyMetricRegistry.isSupported(ixg, by: .defense))
        XCTAssertFalse(HockeyMetricRegistry.isSupported(ixg, by: .goalie))
        XCTAssertTrue(HockeyMetricRegistry.isSupported(gsax, by: .goalie))
        XCTAssertFalse(HockeyMetricRegistry.isSupported(gsax, by: .forward))
    }

    /// Metrics that count something going wrong, or a workload, rank ascending.
    /// Getting this backwards would put the worst goalie in the league at the
    /// top of the board.
    func testLowerIsBetterMetricsRankAscending() {
        let lower: [(String, MetricCategory)] = [
            ("xGA/60", .playDriving), ("Giveaways", .playDriving),
            ("GAA", .goaltending), ("GA", .goaltending), ("Rebound%", .goaltending),
        ]
        for (label, category) in lower {
            let definition = HockeyMetricRegistry.definition(for: label, category: category)
            XCTAssertNotNil(definition, "missing \(label)")
            XCTAssertEqual(definition?.higherIsBetter, false, "\(label) should rank lower-is-better")
        }
        let higher: [(String, MetricCategory)] = [
            ("ixG", .shotQuality), ("xGF%", .playDriving), ("Blocks", .playDriving),
            ("GSAx", .goaltending), ("SV%", .goaltending), ("HD SV%", .goaltending),
        ]
        for (label, category) in higher {
            XCTAssertEqual(
                HockeyMetricRegistry.definition(for: label, category: category)?.higherIsBetter,
                true,
                "\(label) should rank higher-is-better"
            )
        }
    }

    /// The same label can live in two categories with opposite readings of
    /// who it belongs to: xGA/60 is a skater's on-ice result and a goalie's
    /// workload. The registry keys on both.
    func testSharedLabelsResolveByCategory() {
        let skater = HockeyMetricRegistry.definition(for: "xGA/60", category: .playDriving)
        let goalie = HockeyMetricRegistry.definition(for: "xGA/60", category: .goaltending)
        XCTAssertEqual(skater?.higherIsBetter, false)
        XCTAssertEqual(goalie?.higherIsBetter, true)
        XCTAssertEqual(skater?.positions, [.forward, .defense])
        XCTAssertEqual(goalie?.positions, [.goalie])
    }

    /// Advanced rows must sort above traditional ones inside every category.
    func testAdvancedMetricsLeadDisplayOrder() {
        for category in MetricCategory.allCases {
            let order = category.metricPriorityOrder
            let advanced = HockeyMetricRegistry.definitions
                .filter { $0.category == category && $0.kind == .advanced }.map(\.label)
            let traditional = HockeyMetricRegistry.definitions
                .filter { $0.category == category && $0.kind == .traditional }.map(\.label)
            let lastAdvanced = advanced.compactMap { order.firstIndex(of: $0) }.max()
            let firstTraditional = traditional.compactMap { order.firstIndex(of: $0) }.min()
            guard let lastAdvanced, let firstTraditional else {
                return XCTFail("expected both advanced and traditional metrics in \(category)")
            }
            XCTAssertLessThan(lastAdvanced, firstTraditional, "\(category)")
        }
    }

    func testPositionHeadlinePreferences() {
        XCTAssertEqual(PlayerPositionGroup.forward.preferredAdvancedMetrics.first, "ixG")
        XCTAssertEqual(PlayerPositionGroup.defense.preferredAdvancedMetrics.first, "xGF%")
        XCTAssertEqual(PlayerPositionGroup.goalie.preferredAdvancedMetrics.first, "GSAx")
        XCTAssertEqual(PlayerPositionGroup.goalie.preferredTraditionalMetrics.first, "SV%")
        XCTAssertEqual(PlayerPositionGroup.forward.primaryCategory, .scoring)
        XCTAssertEqual(PlayerPositionGroup.defense.primaryCategory, .playDriving)
        XCTAssertEqual(PlayerPositionGroup.goalie.primaryCategory, .goaltending)
        XCTAssertEqual(PlayerPositionGroup.forward.categories, [.scoring, .shotQuality, .playDriving])
        XCTAssertEqual(PlayerPositionGroup.goalie.categories, [.goaltending])
    }

    @MainActor
    func testLowerIsBetterUsesRegistry() {
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "GAA", category: .goaltending))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Giveaways", category: .playDriving))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "ixG", category: .shotQuality))
        XCTAssertFalse(DashboardViewModel.defaultSortDescending(label: "GAA", category: .goaltending))
        XCTAssertTrue(DashboardViewModel.defaultSortDescending(label: "GSAx", category: .goaltending))
    }

    func testUnknownMetricIsPreserved() {
        let unknown = Metric(id: "unknown", label: "New Metric", value: "1.0", percentile: 50, category: .scoring)
        XCTAssertEqual(HockeyMetricRegistry.kind(for: unknown), .advanced)
        XCTAssertTrue(HockeyMetricRegistry.isSupported(unknown, by: .goalie))
        XCTAssertEqual(HockeyMetricRegistry.sorted([unknown]), [unknown])
    }

    func testMetricCategoryDecodesCaseInsensitively() throws {
        for rawValue in ["shot quality", "SHOT QUALITY", "Shot Quality"] {
            let json = """
            {"id":"m","label":"ixG","value":"31.4","percentile":88,"category":"\(rawValue)"}
            """.data(using: .utf8)!
            let metric = try JSONDecoder().decode(Metric.self, from: json)
            XCTAssertEqual(metric.category, .shotQuality)
        }
    }

    /// The historical bundle leaves the id out; it is rebuilt from the
    /// category and label.
    func testMetricDecodesWithoutAnId() throws {
        let json = #"{"label":"xGF%","value":"54.2%","percentile":91,"category":"Play Driving"}"#
        let metric = try JSONDecoder().decode(Metric.self, from: Data(json.utf8))
        XCTAssertEqual(metric.id, "play-driving-xGF%")
        XCTAssertEqual(metric.category, .playDriving)
        XCTAssertEqual(
            Metric.derivedID(category: .goaltending, label: "GSAx"),
            "goaltending-GSAx"
        )
    }
}
