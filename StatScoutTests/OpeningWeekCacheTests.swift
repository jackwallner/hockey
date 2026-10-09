import XCTest
@testable import Hockey_StatScout

final class OpeningWeekCacheTests: XCTestCase {
    func testCompleteOpeningGameIsCacheableBeforeFullSlate() {
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteCurrent(players()))
    }

    func testOnlyOneTeamIsNotACompleteOpeningGame() {
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(oneTeam: true)))
    }

    func testOpeningGameStillRequiresEveryCohort() {
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(players().filter { $0.playerType != "g" }))
    }

    func testLastYearsOpeningGameIsNotCurrentData() {
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(season: StatScoutSeason.current - 1)))
    }

    func testExpiredSavedSnapshotIsKeptAndNotRestamped() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TwoTierPlayerCache(directory: directory)
        try cache.savePlayers(players())
        let file = directory.appending(path: "players-current.json")
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: weekAgo], ofItemAtPath: file.path)

        XCTAssertEqual(try cache.loadCurrentPlayers().count, 30)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(modified?.timeIntervalSince1970 ?? 0, weekAgo.timeIntervalSince1970, accuracy: 1)
    }

    func testNoSavedSnapshotServesNoCurrentPlayers() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(try TwoTierPlayerCache(directory: directory).loadCurrentPlayers().isEmpty)
    }

    private func players(oneTeam: Bool = false, season: Int = StatScoutSeason.current) -> [Player] {
        (0..<30).map { index in
            Player(
                playerId: index, name: "Player \(index)",
                team: oneTeam || index < 15 ? "SEA" : "EDM", position: "C",
                handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
                playerType: ["f", "d", "g"][index % 3],
                metrics: [
                    Metric(id: "scoring", label: "P/60", value: "2.1", percentile: 50, category: .scoring),
                    Metric(id: "shots", label: "ixG", value: "3.1", percentile: 50, category: .shotQuality),
                    Metric(id: "goalie", label: "GSAx", value: "+1.2", percentile: 50, category: .goaltending),
                ],
                standardStats: [], games: []
            )
        }
    }
}
