import XCTest
@testable import Hockey_StatScout

@MainActor
final class StatDirectionTests: XCTestCase {
    private func player(
        _ id: Int,
        _ name: String,
        value: String,
        percentile: Int,
        label: String = "ixG",
        category: MetricCategory = .shotQuality
    ) -> Player {
        Player(
            playerId: id,
            name: name,
            team: "BUF",
            position: "C",
            handedness: "",
            updatedAt: Date(),
            season: 2026,
            playerType: "f",
            metrics: [
                Metric(
                    id: "m\(id)",
                    label: label,
                    value: value,
                    percentile: percentile,
                    category: category
                )
            ],
            standardStats: [],
            games: []
        )
    }

    func testHockeyLowerIsBetterMetrics() {
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "xGA/60", category: .playDriving))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Giveaways", category: .playDriving))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "GAA", category: .goaltending))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Rebound%", category: .goaltending))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "ixG", category: .shotQuality))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "Blocks", category: .playDriving))
        // The same label is workload for a goalie: more is not worse.
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "xGA/60", category: .goaltending))
    }

    func testBlankValuesRankByPercentileInsteadOfLast() {
        let players = [
            player(1, "Printable but poor", value: "0.01", percentile: 5),
            player(2, "Blank but elite", value: "", percentile: 99),
            player(3, "Blank and poor", value: "", percentile: 2),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(
                label: "ixG",
                category: .shotQuality,
                descending: true
            )
        )
        XCTAssertEqual(
            ranked.map(\.name),
            ["Blank but elite", "Printable but poor", "Blank and poor"]
        )
    }

    func testEqualPercentilesBreakTiesOnValue() {
        let players = [
            player(1, "Lower value", value: "0.12", percentile: 80),
            player(2, "Higher value", value: "0.21", percentile: 80),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(
                label: "ixG",
                category: .shotQuality,
                descending: true
            )
        )
        XCTAssertEqual(ranked.map(\.name), ["Higher value", "Lower value"])
    }

    func testMissingMetricSortsLastInBothDirections() {
        let hasMetric = player(1, "Has it", value: "0.12", percentile: 50)
        let lacksMetric = player(
            2,
            "Lacks it",
            value: "11.0%",
            percentile: 40,
            label: "Sh%",
            category: .scoring
        )
        for descending in [true, false] {
            let ranked = [lacksMetric, hasMetric].sorted(
                by: DashboardViewModel.metricComparator(
                    label: "ixG",
                    category: .shotQuality,
                    descending: descending
                )
            )
            XCTAssertEqual(ranked.last?.name, "Lacks it")
        }
    }
}
