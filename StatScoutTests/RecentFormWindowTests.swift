import XCTest
@testable import Hockey_StatScout

/// What "the last N weeks" adds up to on a player page.
final class RecentFormWindowTests: XCTestCase {
    private func log(
        date: String,
        type: String = "f",
        plays: Int = 20,
        touches: Int = 7,
        metrics: [String: Double?]
    ) throws -> PlayerGameLog {
        var payload: [String: Any] = [
            "player_id": 1,
            "season": 2026,
            "game_date": date,
            "player_type": type,
            "plays": plays,
            "touches": touches,
        ]
        payload["metrics"] = metrics.mapValues { $0 as Any? ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(PlayerGameLog.self, from: data)
    }

    /// Counting stats sum; the window's own game count is what was supplied, not
    /// what was asked for. A four-week window over two played games is two
    /// games' worth of numbers, which is exactly why the page counts a player's
    /// games alongside the weeks.
    func testWindowSumsCountingStatsOverTheGamesSupplied() throws {
        let logs = [
            try log(date: "2026-10-14", plays: 21, touches: 8, metrics: ["goals": 1, "assists": 1, "ixg": 0.6]),
            try log(date: "2026-10-16", plays: 18, touches: 5, metrics: ["goals": 0, "assists": 2, "ixg": 0.4]),
        ]
        let window = RecentFormWindow.build(label: "Last 4 weeks", span: 4, logs: logs)
        XCTAssertEqual(window.games, 2)
        XCTAssertEqual(window.span, 4)
        XCTAssertEqual(window.plays, 39)
        XCTAssertEqual(window.touches, 13)
        XCTAssertEqual(window.metrics["goals"], 1)
        XCTAssertEqual(window.metrics["assists"], 3)
        XCTAssertEqual(try XCTUnwrap(window.metrics["ixg"]), 1.0, accuracy: 0.0001)
    }

    /// A stat with no data in any game gets no key at all, so the row falls
    /// back to the season value instead of claiming a real zero.
    func testNullMetricsAreAbsentNotZero() throws {
        let logs = [try log(date: "2026-10-14", metrics: ["goals": 1, "primary_assists": nil])]
        let window = RecentFormWindow.build(label: "Last 2 weeks", span: 2, logs: logs)
        XCTAssertEqual(window.metrics["goals"], 1)
        XCTAssertNil(window.metrics["primary_assists"])
    }

    func testSkaterRatesAreRebuiltFromSummedCounts() throws {
        // 2 hours of ice time: 6 points, 5.0 ixG, 20 shots attempted, 4 goals on 20 SOG.
        let logs = [
            try log(date: "2026-10-14", metrics: ["points": 4, "ixg": 3.0, "shot_attempts": 12, "goals": 3, "shots_on_goal": 10, "toi_seconds": 3_600]),
            try log(date: "2026-10-16", metrics: ["points": 2, "ixg": 2.0, "shot_attempts": 8, "goals": 1, "shots_on_goal": 10, "toi_seconds": 3_600]),
        ]
        let window = RecentFormWindow.build(label: "Last 2 weeks", span: 2, logs: logs)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "P/60")), 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "ixG/60")), 2.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "Shots/60")), 10, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "Sh%")), 20, accuracy: 0.0001)
        // Counting stats and on-ice shares have no windowed rate.
        XCTAssertNil(window.value(forSeasonLabel: "G"))
        XCTAssertNil(window.value(forSeasonLabel: "xGF%"))
    }

    func testGoalieRatesAreRebuiltFromSummedCounts() throws {
        let logs = [
            try log(date: "2026-10-14", type: "g", metrics: ["saves": 28, "shots_against": 30, "goals_against": 2, "xga": 2.5, "hd_shots_against": 8, "hd_goals_against": 1, "toi_seconds": 3_600]),
            try log(date: "2026-10-16", type: "g", metrics: ["saves": 22, "shots_against": 25, "goals_against": 3, "xga": 2.0, "hd_shots_against": 4, "hd_goals_against": 1, "toi_seconds": 3_600]),
        ]
        let window = RecentFormWindow.build(label: "Last 2 weeks", span: 2, logs: logs)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "SV%")), 50.0 / 55.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "GAA")), 2.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "GSAx/60")), (4.5 - 5.0) / 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(window.value(forSeasonLabel: "HD SV%")), 1 - 2.0 / 12.0, accuracy: 0.0001)
    }

    /// No ice time, no per-60 rate.
    func testRatesNeedADenominator() throws {
        let logs = [try log(date: "2026-10-14", metrics: ["points": 2])]
        let window = RecentFormWindow.build(label: "Last 2 weeks", span: 2, logs: logs)
        XCTAssertNil(window.value(forSeasonLabel: "P/60"))
        XCTAssertNil(window.value(forSeasonLabel: "Sh%"))
        XCTAssertNil(window.value(forSeasonLabel: "SV%"))
    }

    func testWindowsAnchorOnTheNewestGameAndCountWholeWeeks() throws {
        let logs = [
            try log(date: "2026-11-20", metrics: ["goals": 1]),
            try log(date: "2026-11-10", metrics: ["goals": 1]),
            try log(date: "2026-11-02", metrics: ["goals": 1]),
            try log(date: "2026-10-12", metrics: ["goals": 1]),
        ]
        XCTAssertEqual(RecentFormWindow.logs(logs, weeks: 2).count, 2)
        XCTAssertEqual(RecentFormWindow.logs(logs, weeks: 4).count, 3)
        XCTAssertEqual(RecentFormWindow.logs(logs, weeks: 8).count, 4)
        XCTAssertTrue(RecentFormWindow.logs([], weeks: 4).isEmpty)
        XCTAssertEqual(RecentFormWindow.logs(logs, weeks: 8).map(\.gameDate), logs.map(\.gameDate), "newest first")
    }

    func testWindowChoicesAreTwoFourEightWeeks() {
        XCTAssertEqual(RecentWindow.allCases.map(\.rawValue), [2, 4, 8])
        XCTAssertEqual(TrendWindow.allCases.map(\.rawValue), [2, 4, 8])
        XCTAssertEqual(RecentFormWindow.windows.map(\.span), [2, 4, 8])
        XCTAssertEqual(RecentWindow.four.label, "Last 4 weeks")
        XCTAssertEqual(RecentWindow.four.shortLabel, "4W")
        XCTAssertEqual(TrendWindow.eight.segmentLabel, "8 weeks")
    }

    func testRecentWindowCaptionNamesTheGamesInHand() {
        XCTAssertEqual(RecentFormWindow.caption(games: 1, span: 2), "1 game")
        XCTAssertEqual(RecentFormWindow.caption(games: 3, span: 4), "3 games")
        XCTAssertEqual(RecentFormWindow.caption(games: 9, span: 8), "9 games")
    }

    func testBarsOnTheRecentCardDifferForGoalies() {
        XCTAssertEqual(RecentFormWindow.recentLabels(goalie: false), ["P/60", "ixG/60", "Shots/60", "Sh%"])
        XCTAssertEqual(RecentFormWindow.recentLabels(goalie: true), ["SV%", "GSAx/60", "GAA", "HD SV%"])
    }

    // MARK: - Metric keys and formatting

    func testRecentMetricKeysMapSeasonLabelsToTheRollup() {
        XCTAssertEqual(RecentMetricKey.key(for: "P/60"), "points_per_60")
        XCTAssertEqual(RecentMetricKey.key(for: "ixG"), "ixg")
        XCTAssertEqual(RecentMetricKey.key(for: "GAx"), "gax")
        XCTAssertEqual(RecentMetricKey.key(for: "GSAx/60"), "gsax_per_60")
        XCTAssertEqual(RecentMetricKey.key(for: "SV%"), "sv_pct")
        XCTAssertEqual(RecentMetricKey.key(for: "GA"), "goals_against")
        // On-ice shares have no per-game feed, so they get no recent bar.
        XCTAssertNil(RecentMetricKey.key(for: "xGF%"))
        XCTAssertNil(RecentMetricKey.key(for: "CF%"))
        XCTAssertNil(RecentMetricKey.key(for: "Made Up"))
    }

    func testSavePercentageReadsAsThreeDecimalsWithNoLeadingZero() {
        XCTAssertEqual(RecentMetricKey.savePercentage(0.915), ".915")
        XCTAssertEqual(RecentMetricKey.savePercentage(91.5), ".915")
        XCTAssertEqual(RecentMetricKey.savePercentage(1.0), "1.000")
        XCTAssertEqual(RecentMetricKey.format(0.9071, label: "SV%"), ".907")
        XCTAssertEqual(RecentMetricKey.format(0.842, label: "HD SV%"), ".842")
    }

    func testRecentValuesFormatLikeThePlayerPage() {
        XCTAssertEqual(RecentMetricKey.format(3.1234, label: "P/60"), "3.12")
        XCTAssertEqual(RecentMetricKey.format(5.26, label: "ixG"), "5.3")
        XCTAssertEqual(RecentMetricKey.format(-1.24, label: "GSAx"), "-1.2")
        XCTAssertEqual(RecentMetricKey.format(54.24, label: "xGF%"), "54.2%")
        XCTAssertEqual(RecentMetricKey.format(2.0, label: "GAA"), "2.00")
        XCTAssertEqual(RecentMetricKey.format(1_234, label: "Saves"), "1,234")
        XCTAssertTrue(RecentMetricKey.lowerIsBetter("GAA"))
        XCTAssertTrue(RecentMetricKey.lowerIsBetter("Giveaways"))
        XCTAssertFalse(RecentMetricKey.lowerIsBetter("ixG"))
    }

    func testTrendMetricsFormatTheirOwnDecimals() {
        let svPct = TrendMetric.goalieStandard.first { $0.label == "SV%" }
        XCTAssertEqual(svPct?.format(0.915), ".915")
        let ixg = TrendMetric.skaterStandard.first { $0.label == "ixG" }
        XCTAssertEqual(ixg?.format(4.26), "4.3")
        let shootingPct = TrendMetric.skaterAdvanced.first { $0.label == "Sh%" }
        XCTAssertEqual(shootingPct?.format(12.34), "12.3%")
        XCTAssertEqual(TrendSide.allCases.map(\.shortLabel), ["F", "D", "G"])
        XCTAssertEqual(TrendMetric.list(for: .goalie, mode: .advanced).first?.label, "GSAx")
        XCTAssertEqual(TrendMetric.list(for: .forward, mode: .standard).first?.label, "P")
    }
}
