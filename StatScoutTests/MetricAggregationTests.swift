import XCTest
@testable import Hockey_StatScout

/// Covers the roster-pooling rules the team comparison relies on. The important
/// property is that a rate is weighted by the volume it was measured over: an
/// unweighted mean lets a two-game cameo outrank an 80-game season, which is
/// the failure mode these tests exist to prevent.
final class MetricAggregationTests: XCTestCase {
    private func player(
        id: Int,
        metrics: [Metric],
        standard: [StandardStat],
        type: String = "f"
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: "SEA", position: type == "g" ? "G" : "C",
            handedness: "", updatedAt: Date(), season: 2026, playerType: type,
            metrics: metrics, standardStats: standard, games: []
        )
    }

    private func std(_ label: String, _ value: String) -> StandardStat {
        StandardStat(id: "std-\(label)", label: label, value: value)
    }

    // MARK: - Aggregation rules

    func testScoringRatesWeightByIceTimeAndCountsAdd() {
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "P/60", category: .scoring),
            .weighted(.iceTime)
        )
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "Sh%", category: .scoring),
            .weighted(.shotsOnGoal)
        )
        // Volume stats still add up.
        XCTAssertEqual(HockeyMetricRegistry.aggregation(for: "G", category: .scoring), .sum)
        XCTAssertEqual(HockeyMetricRegistry.aggregation(for: "SOG", category: .scoring), .sum)
    }

    func testShotQualityTotalsSumAndRatesWeight() {
        XCTAssertEqual(HockeyMetricRegistry.aggregation(for: "ixG", category: .shotQuality), .sum)
        XCTAssertEqual(HockeyMetricRegistry.aggregation(for: "GAx", category: .shotQuality), .sum)
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "ixG/60", category: .shotQuality),
            .weighted(.iceTime)
        )
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "xG/Shot", category: .shotQuality),
            .weighted(.shotAttempts)
        )
    }

    func testPlayDrivingSharesWeightByIceTimeWhileCountsAdd() {
        // A roster's on-ice shares are an average over the minutes played.
        for label in ["xGF%", "CF%", "xGA/60"] {
            XCTAssertEqual(
                HockeyMetricRegistry.aggregation(for: label, category: .playDriving),
                .weighted(.iceTime),
                label
            )
        }
        for label in ["Blocks", "Hits", "Takeaways", "Giveaways"] {
            XCTAssertEqual(
                HockeyMetricRegistry.aggregation(for: label, category: .playDriving),
                .sum,
                label
            )
        }
    }

    func testGoaltendingRatesWeightByShotsAgainstOrIceTime() {
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "SV%", category: .goaltending),
            .weighted(.shotsAgainst)
        )
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "HD SV%", category: .goaltending),
            .weighted(.shotsAgainst)
        )
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "GAA", category: .goaltending),
            .weighted(.iceTime)
        )
        XCTAssertEqual(
            HockeyMetricRegistry.aggregation(for: "GSAx/60", category: .goaltending),
            .weighted(.iceTime)
        )
        XCTAssertEqual(HockeyMetricRegistry.aggregation(for: "GSAx", category: .goaltending), .sum)
        XCTAssertEqual(HockeyMetricRegistry.aggregation(for: "W", category: .goaltending), .sum)
    }

    // MARK: - Weight extraction

    /// "19:42" per game times 40 games.
    func testIceTimeWeightIsTimeOnIcePerGameTimesGamesPlayed() throws {
        let p = player(id: 1, metrics: [], standard: [std("GP", "40"), std("TOI/GP", "19:42")])
        let minutes = try XCTUnwrap(MetricWeight.iceTime.value(for: p))
        XCTAssertEqual(minutes, 19.7 * 40, accuracy: 0.001)
    }

    /// A goalie line carries no TOI/GP, so it weights by games played.
    func testGoalieIceTimeWeightFallsBackToGames() {
        let p = player(id: 1, metrics: [], standard: [std("GP", "52"), std("GS", "50")], type: "g")
        XCTAssertEqual(MetricWeight.iceTime.value(for: p), 52)
    }

    func testShotsAgainstWeightReadsTheSAColumn() {
        let p = player(id: 1, metrics: [], standard: [std("SA", "1,312")], type: "g")
        XCTAssertEqual(MetricWeight.shotsAgainst.value(for: p), 1312)
    }

    func testShotsOnGoalWeightReadsPlainColumn() {
        let p = player(id: 1, metrics: [], standard: [std("SOG", "272")])
        XCTAssertEqual(MetricWeight.shotsOnGoal.value(for: p), 272)
    }

    func testClockMinutesParsesATimeOnIceClock() {
        XCTAssertEqual(try XCTUnwrap(MetricWeight.clockMinutes("19:42")), 19.7, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(MetricWeight.clockMinutes("0:30")), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(MetricWeight.clockMinutes("21")), 21, accuracy: 0.0001)
    }

    /// A player with no volume must drop out of the weighted mean rather than
    /// enter it at weight 1 - that is what would let a cameo swing a team rate.
    func testMissingWeightIsNilNotZero() {
        let p = player(id: 1, metrics: [], standard: [std("G", "17")])
        XCTAssertNil(MetricWeight.iceTime.value(for: p))
        XCTAssertNil(MetricWeight.shotsOnGoal.value(for: p))
        XCTAssertNil(MetricWeight.shotsAgainst.value(for: p))
    }

    func testZeroVolumeIsTreatedAsMissing() {
        let p = player(id: 1, metrics: [], standard: [std("SOG", "0")])
        XCTAssertNil(MetricWeight.shotsOnGoal.value(for: p))
    }

    func testVolumeCaptionNamesTheDenominator() {
        let skater = player(id: 1, metrics: [], standard: [
            std("GP", "10"), std("TOI/GP", "20:00"), std("SOG", "41"),
        ])
        XCTAssertEqual(skater.volumeCaption(for: .scoring), "200 min")
        XCTAssertEqual(skater.volumeCaption(for: .shotQuality), "41 SOG")
        let goalie = player(id: 2, metrics: [], standard: [std("SA", "612")], type: "g")
        XCTAssertEqual(goalie.volumeCaption(for: .goaltending), "612 SA")
        XCTAssertNil(player(id: 3, metrics: [], standard: []).volumeCaption(for: .scoring))
    }

    // MARK: - Value formatting

    func testPercentFormatIsPreserved() {
        let format = MetricValueFormat.inferred(from: ["54.2%", "48.8%"])
        XCTAssertTrue(format.isPercent)
        XCTAssertEqual(format.decimals, 1)
        XCTAssertEqual(format.string(51.5), "51.5%")
    }

    func testSignedFormatKeepsLeadingPlus() {
        let format = MetricValueFormat.inferred(from: ["+2.3", "-1.1"])
        XCTAssertTrue(format.isSigned)
        XCTAssertEqual(format.string(1.4), "+1.4")
        XCTAssertEqual(format.string(-1.4), "-1.4")
    }

    func testGroupedIntegerFormat() {
        let format = MetricValueFormat.inferred(from: ["1,322", "1,004"])
        XCTAssertTrue(format.hasGrouping)
        XCTAssertEqual(format.decimals, 0)
        XCTAssertEqual(format.string(2326), "2,326")
    }

    /// Save percentages ship as ".915" and an aggregate of them must too.
    func testSavePercentageKeepsItsLeadingDotOffTheZero() {
        let format = MetricValueFormat.inferred(from: [".915", ".907"])
        XCTAssertTrue(format.dropsLeadingZero)
        XCTAssertEqual(format.decimals, 3)
        XCTAssertEqual(format.string(0.911), ".911")
    }

    /// Mixed precision in one column should render at the finer of the two, not
    /// silently truncate the aggregate.
    func testDecimalsTakeTheMaximumSeen() {
        let format = MetricValueFormat.inferred(from: ["0.1", "0.12"])
        XCTAssertEqual(format.decimals, 2)
        XCTAssertEqual(format.string(0.155), "0.15")
    }

    func testTwoDecimalRateFormat() {
        let format = MetricValueFormat.inferred(from: ["0.05", "0.18"])
        XCTAssertFalse(format.isPercent)
        XCTAssertFalse(format.dropsLeadingZero)
        XCTAssertEqual(format.string(0.115), "0.12")
    }

    // MARK: - Parsing

    func testNumericParsingHandlesFeedShapes() {
        XCTAssertEqual(metricNumericValue("1,322"), 1322)
        XCTAssertEqual(metricNumericValue("54.2%"), 54.2)
        XCTAssertEqual(metricNumericValue("+2.3"), 2.3)
        XCTAssertEqual(metricNumericValue("-1.4"), -1.4)
        XCTAssertEqual(metricNumericValue(".5"), 0.5)
        XCTAssertEqual(metricNumericValue(".915"), 0.915)
        XCTAssertEqual(metricNumericValue("-.5"), -0.5)
        XCTAssertNil(metricNumericValue("-"))
    }
}
