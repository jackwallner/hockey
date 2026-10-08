import XCTest
@testable import Gridiron_StatScout

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
        let selected = player(1, stats: [StandardStat(id: "yards", label: "Pass Yds", value: "280")])
        XCTAssertEqual(FanStatsSelection.summary(for: selected).map(\.label), ["Pass Yds"])
        XCTAssertTrue(FanStatsSelection.summary(for: player(2)).isEmpty)
    }

    private func player(
        _ id: Int, season: Int = 2026, phase: SeasonPhase = .regular,
        stats: [StandardStat] = []
    ) -> Player {
        Player(
            playerId: id, name: "Player \(id)", team: "SEA", position: "QB",
            handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
            seasonPhase: phase, playerType: "qb", metrics: [], standardStats: stats, games: []
        )
    }
}
