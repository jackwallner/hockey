import XCTest
@testable import Gridiron_StatScout

@MainActor
final class StatDirectionTests: XCTestCase {
    private func player(
        _ id: Int,
        _ name: String,
        value: String,
        percentile: Int,
        label: String = "EPA/Play",
        category: MetricCategory = .passing
    ) -> Player {
        Player(
            playerId: id,
            name: name,
            team: "BUF",
            position: "QB",
            handedness: "",
            updatedAt: Date(),
            season: 2025,
            playerType: "qb",
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

    func testFootballLowerIsBetterMetrics() {
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "INT%", category: .passing))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Sack%", category: .passing))
        XCTAssertTrue(DashboardViewModel.lowerIsBetter(label: "Fumble%", category: .rushing))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "EPA/Play", category: .passing))
        XCTAssertFalse(DashboardViewModel.lowerIsBetter(label: "Tackles", category: .defense))
    }

    func testBlankValuesRankByPercentileInsteadOfLast() {
        let players = [
            player(1, "Printable but poor", value: "0.01", percentile: 5),
            player(2, "Blank but elite", value: "", percentile: 99),
            player(3, "Blank and poor", value: "", percentile: 2),
        ]
        let ranked = players.sorted(
            by: DashboardViewModel.metricComparator(
                label: "EPA/Play",
                category: .passing,
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
                label: "EPA/Play",
                category: .passing,
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
            value: "62.0%",
            percentile: 40,
            label: "Cmp%"
        )
        for descending in [true, false] {
            let ranked = [lacksMetric, hasMetric].sorted(
                by: DashboardViewModel.metricComparator(
                    label: "EPA/Play",
                    category: .passing,
                    descending: descending
                )
            )
            XCTAssertEqual(ranked.last?.name, "Lacks it")
        }
    }
}
