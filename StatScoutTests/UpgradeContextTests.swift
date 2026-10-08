import XCTest
@testable import Gridiron_StatScout

/// Regressions for the three context bugs found in the 1.2.1 audit: an
/// unprovenanced current-season cache surviving an upgrade, a team page whose
/// roster ignored its own season picker, and drill-down routes that dropped the
/// phase they were opened from.
final class UpgradeContextTests: XCTestCase {

    // MARK: - Current-season cache provenance

    /// The exact shape of the artifact 1.2 shipped and wrote to this path: a
    /// real server export, but only the teams that had played by then. It
    /// passes `isCompleteCurrent`, by design, so the validator can never be
    /// what separates it from a full snapshot.
    func testPre122CacheWithoutProvenanceIsDiscardedOnUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let openingWeek = players(teams: ["LA", "NE", "SEA", "SF"], count: 110)
        XCTAssertTrue(
            PlayerSnapshotValidator.isCompleteCurrent(openingWeek),
            "The 1.2 artifact has to clear the opening-week rule, or this test isn't reproducing the bug"
        )

        // Written the way 1.2 wrote it: rows only, no marker beside them.
        let file = directory.appending(path: "players-current.json")
        try JSONEncoder.statScout.encode(openingWeek).write(to: file)

        let cache = TwoTierPlayerCache(directory: directory)
        XCTAssertTrue(
            try cache.loadCurrentPlayers().isEmpty,
            "A snapshot of unknown origin must never populate the current board"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "The discarded snapshot should be removed, not re-read on every launch"
        )
    }

    func testSnapshotSavedByThisBuildIsTrustedOnReload() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = TwoTierPlayerCache(directory: directory)
        try cache.savePlayers(players(teams: ["SEA", "NE"], count: 30))

        XCTAssertEqual(try cache.loadCurrentPlayers().count, 30)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.appending(path: "players-current-provenance.json").path)
        )
        // Still trusted on a second read: the marker is not consumed.
        XCTAssertEqual(try TwoTierPlayerCache(directory: directory).loadCurrentPlayers().count, 30)
    }

    func testDiscardedSnapshotIsReplacedByTheNextServerSave() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.statScout
            .encode(players(teams: ["LA", "NE", "SEA", "SF"], count: 110))
            .write(to: directory.appending(path: "players-current.json"))

        let cache = TwoTierPlayerCache(directory: directory)
        XCTAssertTrue(try cache.loadCurrentPlayers().isEmpty)

        try cache.savePlayers(players(teams: ["SEA", "NE", "KC", "BUF"], count: 40))
        XCTAssertEqual(try cache.loadCurrentPlayers().count, 40)
    }

    // MARK: - Team page follows its own season picker

    @MainActor
    func testTeamRosterFollowsSelectedSeasonAndPhase() async {
        let seaThisYear = players(teams: ["SEA"], count: 5, season: StatScoutSeason.current)
        let seaLastYear = players(teams: ["SEA"], count: 3, season: StatScoutSeason.current - 1, idOffset: 100)
        let seaPlayoffs = players(
            teams: ["SEA"], count: 2, season: StatScoutSeason.current - 1,
            phase: .playoffs, idOffset: 200
        )
        let vm = DashboardViewModel(provider: MockProvider(players: seaThisYear + seaLastYear + seaPlayoffs))
        await vm.load()

        vm.selectedSeason = StatScoutSeason.current
        vm.selectedPhase = .regular
        XCTAssertEqual(vm.players(forTeam: "SEA").count, 5)

        // TeamView derives its roster from exactly this call, so moving the
        // page's picker has to move the rows underneath it.
        vm.selectedSeason = StatScoutSeason.current - 1
        XCTAssertEqual(vm.players(forTeam: "SEA").count, 3)

        vm.selectedPhase = .playoffs
        XCTAssertEqual(vm.players(forTeam: "SEA").count, 2)
    }

    // MARK: - Drill-down routes carry their phase

    @MainActor
    func testPlayersForSeasonHonoursAnExplicitPhase() async {
        let regular = players(teams: ["SEA", "NE"], count: 6, season: StatScoutSeason.current - 1)
        let playoffs = players(
            teams: ["SEA", "NE"], count: 2, season: StatScoutSeason.current - 1,
            phase: .playoffs, idOffset: 50
        )
        let vm = DashboardViewModel(provider: MockProvider(players: regular + playoffs))
        await vm.load()
        vm.selectedPhase = .regular

        // A route opened from a playoff profile resolves against its own phase,
        // not whichever one the tab happens to be sitting on.
        XCTAssertEqual(vm.players(forSeason: StatScoutSeason.current - 1, phase: .playoffs).count, 2)
        XCTAssertEqual(vm.players(forSeason: StatScoutSeason.current - 1, phase: .regular).count, 6)
    }

    func testRoutesCarrySeasonAndPhase() {
        let metric = MetricRoute(label: "EPA/Play", category: .passing, season: 2024, phase: .playoffs)
        XCTAssertEqual(metric.season, 2024)
        XCTAssertEqual(metric.phase, .playoffs)

        let standard = StandardStatRoute(stat: "Pass Yds", category: .passing, season: 2024, phase: .playoffs)
        XCTAssertEqual(standard.season, 2024)
        XCTAssertEqual(standard.phase, .playoffs)

        // Two routes to the same stat in the same year but different halves of
        // it are different destinations, or the stack coalesces them.
        XCTAssertNotEqual(
            metric,
            MetricRoute(label: "EPA/Play", category: .passing, season: 2024, phase: .regular)
        )
    }

    // MARK: - Helpers

    private func players(
        teams: [String],
        count: Int,
        season: Int = StatScoutSeason.current,
        phase: SeasonPhase = .regular,
        idOffset: Int = 0
    ) -> [Player] {
        (0..<count).map { index in
            Player(
                playerId: idOffset + index, name: "Player \(idOffset + index)",
                team: teams[index % teams.count], position: "QB",
                handedness: "", updatedAt: Date(timeIntervalSince1970: 0), season: season,
                seasonPhase: phase,
                playerType: ["qb", "rb", "wr", "te", "def"][index % 5],
                metrics: [
                    Metric(id: "pass", label: "EPA/Play", value: "0.1", percentile: 50, category: .passing),
                    Metric(id: "rush", label: "EPA/Rush", value: "0.1", percentile: 50, category: .rushing),
                    Metric(id: "rec", label: "EPA/Tgt", value: "0.1", percentile: 50, category: .receiving),
                ],
                standardStats: [], games: []
            )
        }
    }
}
