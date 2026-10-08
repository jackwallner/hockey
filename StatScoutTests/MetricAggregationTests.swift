import XCTest
@testable import Gridiron_StatScout

/// Covers the roster-pooling rules the team comparison relies on. The important
/// property is that a rate is weighted by the volume it was measured over: an
/// unweighted mean lets a three-carry cameo outrank a 300-carry season, which is
/// the failure mode these tests exist to prevent.
final class MetricAggregationTests: XCTestCase {
    private func player(
        id: Int,
        metrics: [Metric],
        standard: [StandardStat]
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: "KC", position: "QB",
            handedness: "", updatedAt: Date(), season: 2025,
            metrics: metrics, standardStats: standard, games: []
        )
    }

    private func std(_ label: String, _ value: String) -> StandardStat {
        StandardStat(id: "std-\(label)", label: label, value: value)
    }

    // MARK: - Aggregation rules

    func testPassingRatesWeightByAttempts() {
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "EPA/Play", category: .passing),
            .weighted(.attempts)
        )
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "Sack%", category: .passing),
            .weighted(.attempts)
        )
        // Volume stats still add up.
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "Pass Yds", category: .passing),
            .sum
        )
    }

    func testRushingTotalsSumAndRatesWeightByCarries() {
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "RYOE", category: .rushing),
            .sum
        )
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "Rush EPA", category: .rushing),
            .sum
        )
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "EPA/Rush", category: .rushing),
            .weighted(.carries)
        )
    }

    func testTargetSharesSumWhileTargetRatesWeight() {
        // A roster's target shares are shares of one offence, so they add.
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "Target Share", category: .receiving),
            .sum
        )
        XCTAssertEqual(
            FootballMetricRegistry.aggregation(for: "EPA/Tgt", category: .receiving),
            .weighted(.targets)
        )
    }

    // MARK: - Weight extraction

    func testAttemptWeightReadsDenominatorOfCmpAtt() {
        let p = player(id: 1, metrics: [], standard: [std("Cmp/Att", "401/584")])
        XCTAssertEqual(MetricWeight.attempts.value(for: p), 584)
    }

    func testTargetWeightReadsDenominatorOfRecTgt() {
        let p = player(id: 1, metrics: [], standard: [std("Rec/Tgt", "98/141")])
        XCTAssertEqual(MetricWeight.targets.value(for: p), 141)
    }

    func testCarryWeightReadsPlainColumn() {
        let p = player(id: 1, metrics: [], standard: [std("Car", "272")])
        XCTAssertEqual(MetricWeight.carries.value(for: p), 272)
    }

    /// A player with no volume must drop out of the weighted mean rather than
    /// enter it at weight 1 - that is what would let a cameo swing a team rate.
    func testMissingWeightIsNilNotZero() {
        let p = player(id: 1, metrics: [], standard: [std("G", "17")])
        XCTAssertNil(MetricWeight.attempts.value(for: p))
        XCTAssertNil(MetricWeight.targets.value(for: p))
        XCTAssertNil(MetricWeight.carries.value(for: p))
    }

    func testZeroVolumeIsTreatedAsMissing() {
        let p = player(id: 1, metrics: [], standard: [std("Car", "0")])
        XCTAssertNil(MetricWeight.carries.value(for: p))
    }

    // MARK: - Value formatting

    func testPercentFormatIsPreserved() {
        let format = MetricValueFormat.inferred(from: ["6.2%", "4.8%"])
        XCTAssertTrue(format.isPercent)
        XCTAssertEqual(format.decimals, 1)
        XCTAssertEqual(format.string(5.5), "5.5%")
    }

    func testSignedFormatKeepsLeadingPlus() {
        let format = MetricValueFormat.inferred(from: ["+2.3", "-1.1"])
        XCTAssertTrue(format.isSigned)
        XCTAssertEqual(format.string(1.4), "+1.4")
        XCTAssertEqual(format.string(-1.4), "-1.4")
    }

    func testGroupedIntegerFormat() {
        let format = MetricValueFormat.inferred(from: ["3,322", "1,004"])
        XCTAssertTrue(format.hasGrouping)
        XCTAssertEqual(format.decimals, 0)
        XCTAssertEqual(format.string(4918), "4,918")
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
        XCTAssertEqual(format.string(0.115), "0.12")
    }

    // MARK: - Parsing

    func testNumericParsingHandlesFeedShapes() {
        XCTAssertEqual(metricNumericValue("3,322"), 3322)
        XCTAssertEqual(metricNumericValue("6.2%"), 6.2)
        XCTAssertEqual(metricNumericValue("+2.3"), 2.3)
        XCTAssertEqual(metricNumericValue("-1.4"), -1.4)
        XCTAssertEqual(metricNumericValue(".5"), 0.5)
        XCTAssertNil(metricNumericValue("-"))
    }
}
