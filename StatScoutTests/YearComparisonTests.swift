import XCTest
@testable import Hockey_StatScout

final class YearComparisonTests: XCTestCase {
    func testPlayerHistorySortedBySeason() {
        let players = [
            Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2024, metrics: [], standardStats: [], games: [])
        ]
        let sorted = players.sorted {
            guard let s1 = $0.season, let s2 = $1.season else { return false }
            return s1 > s2
        }
        XCTAssertEqual(sorted.map { $0.season }, [2026, 2025, 2024])
    }

    func testUniqueYearsExtracted() {
        let players = [
            Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2026, metrics: [], standardStats: [], games: [])
        ]
        let years = players.compactMap { $0.season }.uniqued().sorted(by: >)
        XCTAssertEqual(years, [2026, 2025])
    }

    func testPercentileChangeCalculation() {
        let p1 = Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2026, metrics: [
            Metric(id: "m1", label: "ixG", value: "30.0", percentile: 85, category: .shotQuality)
        ], standardStats: [], games: [])
        let p2 = Player(playerId: 1, name: "Test", team: "SEA", position: "C", handedness: "L", updatedAt: Date(), season: 2025, metrics: [
            Metric(id: "m1", label: "ixG", value: "27.8", percentile: 75, category: .shotQuality)
        ], standardStats: [], games: [])

        let change = p1.overallPercentile - p2.overallPercentile
        XCTAssertEqual(change, 10)
    }

    func testMetricComparisonLogic() {
        let metrics1 = [
            Metric(id: "m1", label: "ixG", value: "30.0", percentile: 85, category: .shotQuality),
            Metric(id: "m2", label: "GAx", value: "+3.0", percentile: 70, category: .shotQuality)
        ]
        let metrics2 = [
            Metric(id: "m1", label: "ixG", value: "27.8", percentile: 75, category: .shotQuality),
            Metric(id: "m2", label: "GAx", value: "+3.8", percentile: 80, category: .shotQuality)
        ]

        let dict1 = Dictionary(grouping: metrics1) { $0.label }
        let dict2 = Dictionary(grouping: metrics2) { $0.label }

        let allLabels = Set(dict1.keys).union(dict2.keys)
        var changes: [String: Int] = [:]

        for label in allLabels {
            if let m1 = dict1[label]?.first, let m2 = dict2[label]?.first {
                changes[label] = m1.percentile - m2.percentile
            }
        }

        XCTAssertEqual(changes["ixG"], 10)
        XCTAssertEqual(changes["GAx"], -10)
    }

    func testNoOverlappingMetricsReturnsEmptyComparison() {
        // Test the new functionality: when two years have no overlapping metrics
        let metrics2026 = [
            Metric(id: "m1", label: "ixG", value: "30.0", percentile: 85, category: .shotQuality)
        ]
        let metrics2025 = [
            Metric(id: "m2", label: "GAx", value: "+3.8", percentile: 80, category: .shotQuality)
        ]

        let dict1 = Dictionary(grouping: metrics2026) { $0.label }
        let dict2 = Dictionary(grouping: metrics2025) { $0.label }

        let allLabels = Set(dict1.keys).union(dict2.keys)
        var comparisons: [(label: String, change: Int)] = []

        for label in allLabels {
            // Only add comparison if metric exists in BOTH years
            if let m1 = dict1[label]?.first, let m2 = dict2[label]?.first {
                comparisons.append((label: label, change: m1.percentile - m2.percentile))
            }
        }

        // Should be empty since no metrics overlap
        XCTAssertTrue(comparisons.isEmpty, "Comparisons should be empty when no metrics overlap")
    }

    func testPartialOverlappingMetrics() {
        // Test when some metrics overlap but not all
        let metrics2026 = [
            Metric(id: "m1", label: "ixG", value: "30.0", percentile: 85, category: .shotQuality),
            Metric(id: "m2", label: "GAx", value: "+3.0", percentile: 70, category: .shotQuality)
        ]
        let metrics2025 = [
            Metric(id: "m1", label: "ixG", value: "27.8", percentile: 75, category: .shotQuality),
            Metric(id: "m3", label: "ixG/60", value: "1.10", percentile: 60, category: .shotQuality)
        ]

        let dict1 = Dictionary(grouping: metrics2026) { $0.label }
        let dict2 = Dictionary(grouping: metrics2025) { $0.label }

        let allLabels = Set(dict1.keys).union(dict2.keys)
        var comparisons: [(label: String, change: Int)] = []

        for label in allLabels {
            if let m1 = dict1[label]?.first, let m2 = dict2[label]?.first {
                comparisons.append((label: label, change: m1.percentile - m2.percentile))
            }
        }

        // Only ixG should be compared since it's the only overlapping metric
        XCTAssertEqual(comparisons.count, 1)
        XCTAssertEqual(comparisons.first?.label, "ixG")
        XCTAssertEqual(comparisons.first?.change, 10)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
