import XCTest
@testable import Hockey_StatScout

/// Regular-season and playoff games must never end up in the same window.
///
/// `player_game_logs` carries `season_type`. Playoff games are the newest rows
/// a season has, so a date-descending "last N weeks" for any club that reached
/// the spring was mostly playoff hockey whichever phase the user had selected -
/// and a Playoffs board, which has few games to work with, quietly topped
/// itself up with regular-season games.
final class GameLogPhaseTests: XCTestCase {
    private func log(
        date: String,
        seasonType: String?,
        goals: Double
    ) throws -> PlayerGameLog {
        var payload: [String: Any] = [
            "player_id": 7,
            "season": 2025,
            "game_date": date,
            "player_type": "f",
            "plays": 20,
            "touches": 7,
            "metrics": ["goals": goals],
        ]
        if let seasonType { payload["season_type"] = seasonType }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(PlayerGameLog.self, from: data)
    }

    func testSeasonPhaseIsDecodedFromSeasonType() throws {
        XCTAssertEqual(try log(date: "2026-04-04", seasonType: "REG", goals: 1).seasonPhase, .regular)
        XCTAssertEqual(try log(date: "2026-04-20", seasonType: "POST", goals: 2).seasonPhase, .playoffs)
    }

    /// A row with no phase is a regular-season row, so the fixtures that predate
    /// the column keep decoding.
    func testMissingSeasonTypeDefaultsToRegular() throws {
        XCTAssertEqual(try log(date: "2025-12-07", seasonType: nil, goals: 0).seasonPhase, .regular)
    }

    /// The shape of the bug: the three newest games of a 2025-26 season are all
    /// playoff games, so a phase-blind "last 3" window under a Regular Season
    /// heading was entirely postseason.
    func testAPhaseBlindWindowWouldBeAllPlayoffs() throws {
        let logs = [
            try log(date: "2026-05-08", seasonType: "POST", goals: 3),
            try log(date: "2026-05-05", seasonType: "POST", goals: 2),
            try log(date: "2026-05-02", seasonType: "POST", goals: 1),
            try log(date: "2026-04-16", seasonType: "REG", goals: 1),
            try log(date: "2026-04-14", seasonType: "REG", goals: 0),
        ]

        let newestThree = logs.sorted { $0.gameDate > $1.gameDate }.prefix(3)
        XCTAssertTrue(newestThree.allSatisfy { $0.seasonPhase == .playoffs })

        let regularOnly = logs
            .filter { $0.seasonPhase == .regular }
            .sorted { $0.gameDate > $1.gameDate }
        XCTAssertEqual(regularOnly.count, 2)
        let window = RecentFormWindow.build(label: "Last 2 weeks", span: 2, logs: regularOnly)
        XCTAssertEqual(window.metrics["goals"], 1)
    }
}
