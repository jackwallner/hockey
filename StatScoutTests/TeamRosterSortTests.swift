import XCTest
@testable import Hockey_StatScout

/// The team roster's sort stat in Season and Recent mode.
final class TeamRosterSortTests: XCTestCase {
    private let playDriving: Set<String> = ["xGF%", "Rel xGF%", "CF%", "Hits", "Blocks"]

    /// Defensemen open on Play Driving, whose default sort is xGF%. Recent has
    /// no per-game xGF%, so ranking by it filtered every player out of the
    /// Recent roster and the page read "No players found".
    func testRecentRosterSkipsStatsWithNoPerGameFeed() {
        let labels = TeamView.rosterSortLabels(present: playDriving, category: .playDriving, recentOnly: true)
        XCTAssertFalse(labels.contains("xGF%"))
        XCTAssertFalse(labels.contains("CF%"))
        XCTAssertTrue(labels.allSatisfy { RecentMetricKey.key(for: $0) != nil })

        let label = TeamView.rosterSortLabel(userLabel: nil, available: labels, category: .playDriving)
        XCTAssertEqual(label, "Hits")
    }

    /// A season sort the user picked, xGF% say, does not survive into Recent.
    func testRecentRosterIgnoresAUserSortItCannotRank() {
        let labels = TeamView.rosterSortLabels(present: playDriving, category: .playDriving, recentOnly: true)
        let label = TeamView.rosterSortLabel(userLabel: "xGF%", available: labels, category: .playDriving)
        XCTAssertNotNil(label)
        XCTAssertNotNil(label.flatMap(RecentMetricKey.key(for:)))
    }

    /// Season mode keeps every stat and its xGF% default.
    func testSeasonRosterKeepsOnIceShares() {
        let labels = TeamView.rosterSortLabels(present: playDriving, category: .playDriving, recentOnly: false)
        XCTAssertTrue(labels.contains("xGF%"))
        XCTAssertEqual(TeamView.rosterSortLabel(userLabel: nil, available: labels, category: .playDriving), "xGF%")
        XCTAssertEqual(TeamView.rosterSortLabel(userLabel: "CF%", available: labels, category: .playDriving), "CF%")
    }
}
