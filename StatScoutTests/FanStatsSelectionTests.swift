import XCTest
@testable import Hockey_StatScout

final class FanStatsSelectionTests: XCTestCase {
    func testFollowingDoesNotSubstitutePriorSeasonOrPostseasonStats() {
        let players = [player(1, season: 2025), player(2), player(1, phase: .playoffs)]
        let selected = FanStatsSelection.players(ids: [1, 2], from: players, season: 2026, phase: .regular)
        XCTAssertEqual(selected.map(\.playerId), [2])
    }

    func testFollowingPreservesPersonalOrderAndDeduplicates() {
        let players = [player(1), player(2), player(2), player(3)]
        let selected = FanStatsSelection.players(ids: [3, 2, 3, 99, 1], from: players, season: 2026, phase: .regular)
        XCTAssertEqual(selected.map(\.playerId), [3, 2, 1])
    }

    func testMissingSummaryStatsAreNotShownAsZero() {
        let selected = player(1, stats: [StandardStat(id: "std-G", label: "G", value: "3")])
        XCTAssertEqual(FanStatsSelection.summary(for: selected).map(\.label), ["G"])
        XCTAssertTrue(FanStatsSelection.summary(for: player(2)).isEmpty)
    }

    func testSummaryLineFollowsTheCohort() {
        let all = ["G", "A", "P", "SOG", "+/-", "Blk", "TOI/GP", "W", "GAA", "SV%"]
            .map { StandardStat(id: "std-\($0)", label: $0, value: "1") }
        XCTAssertEqual(
            FanStatsSelection.summary(for: player(1, type: "f", stats: all)).map(\.label),
            ["G", "A", "P", "SOG"]
        )
        XCTAssertEqual(
            FanStatsSelection.summary(for: player(2, type: "d", stats: all)).map(\.label),
            ["P", "+/-", "Blk", "TOI/GP"]
        )
        XCTAssertEqual(
            FanStatsSelection.summary(for: player(3, type: "g", stats: all)).map(\.label),
            ["W", "GAA", "SV%"]
        )
    }

    private func player(
        _ id: Int, type: String = "f", season: Int = 2026, phase: SeasonPhase = .regular,
        stats: [StandardStat] = []
    ) -> Player {
        Player(
            playerId: id, name: "Player \(id)", team: "SEA", position: type == "g" ? "G" : type == "d" ? "D" : "C",
            handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
            seasonPhase: phase, playerType: type, metrics: [], standardStats: stats, games: []
        )
    }
}
