import XCTest
@testable import Gridiron_StatScout

/// Regular-season and playoff games must never end up in the same window.
///
/// `player_game_logs` has always carried `season_type`, and nothing read it.
/// Playoff games are the newest rows a season has, so a date-descending "last
/// five games" for any club that reached January was mostly playoff football
/// whichever phase the user had selected - and a Playoffs board, which has at
/// most four games to work with, quietly topped itself up with December.
final class GameLogPhaseTests: XCTestCase {
    private func log(
        date: String,
        seasonType: String?,
        yards: Double
    ) throws -> PlayerGameLog {
        var payload: [String: Any] = [
            "player_id": 7,
            "season": 2025,
            "game_date": date,
            "player_type": "qb",
            "plays": 30,
            "touches": 20,
            "metrics": ["passing_yards": yards],
        ]
        if let seasonType { payload["season_type"] = seasonType }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(PlayerGameLog.self, from: data)
    }

    func testSeasonPhaseIsDecodedFromSeasonType() throws {
        XCTAssertEqual(try log(date: "2026-01-04", seasonType: "REG", yards: 200).seasonPhase, .regular)
        XCTAssertEqual(try log(date: "2026-02-08", seasonType: "POST", yards: 300).seasonPhase, .playoffs)
    }

    /// A row with no phase is a regular-season row, so the fixtures that predate
    /// the column keep decoding.
    func testMissingSeasonTypeDefaultsToRegular() throws {
        XCTAssertEqual(try log(date: "2025-12-07", seasonType: nil, yards: 250).seasonPhase, .regular)
    }

    /// The shape of the bug: the three newest games of a 2025 season are all
    /// playoff games, so a phase-blind "last 3" window under a Regular Season
    /// heading was entirely postseason.
    func testAPhaseBlindWindowWouldBeAllPlayoffs() throws {
        let logs = [
            try log(date: "2026-02-08", seasonType: "POST", yards: 300),
            try log(date: "2026-01-25", seasonType: "POST", yards: 280),
            try log(date: "2026-01-18", seasonType: "POST", yards: 260),
            try log(date: "2026-01-04", seasonType: "REG", yards: 240),
            try log(date: "2025-12-25", seasonType: "REG", yards: 220),
        ]

        let newestThree = logs.sorted { $0.gameDate > $1.gameDate }.prefix(3)
        XCTAssertTrue(newestThree.allSatisfy { $0.seasonPhase == .playoffs })

        let regularOnly = logs
            .filter { $0.seasonPhase == .regular }
            .sorted { $0.gameDate > $1.gameDate }
        XCTAssertEqual(regularOnly.count, 2)
        let window = RecentFormWindow.build(label: "Last 3", span: 3, logs: regularOnly)
        XCTAssertEqual(window.metrics["passing_yards"], 460)
    }
}
