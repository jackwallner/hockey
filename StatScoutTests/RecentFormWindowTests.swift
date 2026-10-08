import XCTest
@testable import Gridiron_StatScout

/// What "the last N games" adds up to on a player page.
final class RecentFormWindowTests: XCTestCase {
    private func log(
        date: String,
        plays: Int = 30,
        touches: Int = 20,
        metrics: [String: Double?]
    ) throws -> PlayerGameLog {
        var payload: [String: Any] = [
            "player_id": 1,
            "season": 2025,
            "game_date": date,
            "player_type": "def",
            "plays": plays,
            "touches": touches,
        ]
        payload["metrics"] = metrics.mapValues { $0 as Any? ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(PlayerGameLog.self, from: data)
    }

    /// The weekly feed publishes solo tackles and assists as separate columns and
    /// has no combined one, but every board in the app says "Tackles" and means
    /// the total. The window derives it, so a defender's Recent card has a
    /// Tackles bar at all - it had none, because the lookup asked for a key that
    /// never existed.
    func testCombinedTacklesAreDerivedFromSoloAndAssists() throws {
        let logs = [
            try log(date: "2025-11-02", metrics: ["def_tackles_solo": 5, "def_tackle_assists": 2]),
            try log(date: "2025-11-09", metrics: ["def_tackles_solo": 3, "def_tackle_assists": 1]),
        ]
        let window = RecentFormWindow.build(label: "Last 2", span: 2, logs: logs)
        XCTAssertEqual(window.metrics["tackles"], 11)
    }

    /// A player who only ever recorded assists still gets a total rather than
    /// nothing, and one who recorded neither gets no key at all (so the row
    /// falls back to the season value instead of claiming a real zero).
    func testTacklesKeyIsAbsentWhenNeitherColumnHasData() throws {
        let logs = [try log(date: "2025-11-02", metrics: ["passing_yards": 300])]
        let window = RecentFormWindow.build(label: "Last 1", span: 1, logs: logs)
        XCTAssertNil(window.metrics["tackles"])

        let assistsOnly = [try log(date: "2025-11-02", metrics: ["def_tackle_assists": 4])]
        XCTAssertEqual(
            RecentFormWindow.build(label: "Last 1", span: 1, logs: assistsOnly).metrics["tackles"],
            4
        )
    }

    /// Counting stats sum; the window's own game count is what was supplied, not
    /// what was asked for. A three-game window over two played games is two
    /// games' worth of numbers, which is exactly why the page counts a player's
    /// games rather than the league's weeks.
    func testWindowSumsCountingStatsOverTheGamesSupplied() throws {
        let logs = [
            try log(date: "2025-11-02", plays: 30, touches: 20, metrics: ["rushing_yards": 88, "rushing_tds": 1]),
            try log(date: "2025-11-09", plays: 18, touches: 14, metrics: ["rushing_yards": 42, "rushing_tds": 0]),
        ]
        let window = RecentFormWindow.build(label: "Last 3", span: 3, logs: logs)
        XCTAssertEqual(window.games, 2)
        XCTAssertEqual(window.span, 3)
        XCTAssertEqual(window.plays, 48)
        XCTAssertEqual(window.touches, 34)
        XCTAssertEqual(window.metrics["rushing_yards"], 130)
        XCTAssertEqual(window.metrics["rushing_tds"], 1)
    }
}
