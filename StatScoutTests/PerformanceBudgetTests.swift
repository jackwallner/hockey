import XCTest
@testable import Hockey_StatScout

/// Time budgets for the paths a Pro user hits on open and while scrolling,
/// against a worst-case history built in code: every season since 2008, about
/// 1,000 regular-season and 170 playoff players each, plus the career rollup.
/// That is more rows than the bundled plist carries, so a pass here is a pass
/// on the real thing with room to spare.
///
/// Guards the board stutter that BoardPerformanceTests was written for (every
/// read rescanned every row of every season). Budgets are about five times
/// the time measured on the simulator (floored at 0.5 s), so a loaded machine
/// does not trip them but an accidental rescan per read does.
final class PerformanceBudgetTests: XCTestCase {
    private static let teams = [
        "ANA", "BOS", "BUF", "CGY", "CAR", "CHI", "COL", "CBJ", "DAL", "DET", "EDM", "FLA",
        "LAK", "MIN", "MTL", "NSH", "NJD", "NYI", "NYR", "OTT", "PHI", "PIT", "SJS", "SEA",
        "STL", "TBL", "TOR", "UTA", "VAN", "VGK", "WSH", "WPG",
    ]
    private static let firstNames = ["Connor", "Jack", "Leon", "Nathan", "Auston", "Cale", "Quinn", "Igor", "Matthew", "Sidney"]
    private static let lastNames = (0..<60).map { "Surname\($0)" }

    /// Players per season and phase, by position.
    private static let regularCounts: [(PlayerPositionGroup, String, Int)] = [
        (.forward, "f", 600), (.defense, "d", 300), (.goalie, "g", 100),
    ]
    private static let playoffShare = 6

    /// A handful of distinct metric lists per position, shared between
    /// players, so building 20,000 rows stays well under the 2 s fixture limit.
    private static func metricVariants(for position: PlayerPositionGroup) -> [[Metric]] {
        let definitions = HockeyMetricRegistry.definitions.filter { $0.positions.contains(position) }
        return (0..<32).map { variant in
            definitions.enumerated().map { index, definition in
                let percentile = (variant * 7 + index * 13) % 100
                return Metric(
                    id: "\(definition.label)-\(variant)",
                    label: definition.label,
                    value: String(format: "%.1f", Double(percentile) / 3),
                    percentile: percentile,
                    category: definition.category,
                    qualified: variant % 5 != 0
                )
            }
        }
    }

    static func buildHistory(throughSeason last: Int) -> [Player] {
        let variants = Dictionary(uniqueKeysWithValues: PlayerPositionGroup.allCases.map { ($0, metricVariants(for: $0)) })
        let stats = (0..<6).map { StandardStat(id: "s\($0)", label: "Stat \($0)", value: "\($0 * 11)") }
        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        var players: [Player] = []
        players.reserveCapacity(60_000)
        var seasons = Array(StatScoutSeason.earliest...last)
        seasons.append(StatScoutSeason.allTime)
        for season in seasons {
            for phase in SeasonPhase.allCases {
                var base = 0
                for (group, type, count) in regularCounts {
                    let slots = phase == .regular ? count : count / playoffShare
                    for slot in 0..<slots {
                        // Spread careers: the same id recurs across seasons.
                        let id = base * 100_000 + (slot + season * 3) % (count + 40)
                        players.append(Player(
                            playerId: id,
                            name: "\(firstNames[id % firstNames.count]) \(lastNames[(id / 7) % lastNames.count])",
                            team: teams[(id + season) % teams.count],
                            position: group.rawValue,
                            handedness: "",
                            updatedAt: updated,
                            season: season,
                            seasonPhase: phase,
                            playerType: type,
                            metrics: variants[group]![(slot + season) % 32],
                            standardStats: stats,
                            games: []
                        ))
                    }
                    base += 1
                }
            }
        }
        return players
    }

    private struct HistoryProvider: StatcastProviding, @unchecked Sendable {
        let history: [Player]

        func fetchPlayers() async throws -> [Player] { history }
        func fetchHistoricalPlayers() async throws -> [Player] { history }
        func fetchCurrentPlayers() async throws -> [Player] { [] }
        func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
        func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
        func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
        func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    }

    private static let fixture: [Player] = buildHistory(throughSeason: StatScoutSeason.current - 1)

    @MainActor
    private func openedViewModel() async -> DashboardViewModel {
        let vm = DashboardViewModel(provider: HistoryProvider(history: Self.fixture))
        vm.isPro = true
        await vm.loadHistoricalIfNeeded()
        return vm
    }

    private func measure(_ label: String, _ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        print("PERF \(label): \(Int(elapsed * 1000)) ms")
        return elapsed
    }

    func testFixtureBuildsQuickly() {
        let start = Date()
        let rows = Self.buildHistory(throughSeason: StatScoutSeason.current - 1)
        let elapsed = Date().timeIntervalSince(start)
        print("PERF fixture build (\(rows.count) rows): \(Int(elapsed * 1000)) ms")
        XCTAssertGreaterThan(rows.count, 18_000)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// Opening a past season: group, sort and index every row, then derive
    /// the team table. The main-actor part of what the Pro user waits on.
    @MainActor
    func testIngestingFullHistoryStaysWithinBudget() async {
        let vm = DashboardViewModel(provider: HistoryProvider(history: Self.fixture))
        vm.isPro = true
        let start = Date()
        await vm.loadHistoricalIfNeeded()
        let elapsed = Date().timeIntervalSince(start)
        // Budgets below are about 5x the simulator time measured, floored at 0.5 s.
        print("PERF ingest full history: \(Int(elapsed * 1000)) ms")
        XCTAssertTrue(vm.hasLoadedHistorical)
        XCTAssertGreaterThan(vm.playerHistories.count, 900)
        XCTAssertLessThan(elapsed, 1.0)  // ingest, measured 84 ms
    }

    /// Flipping through every season on every position tab, reading what one
    /// render reads. This is the "scroll through the season menu" path.
    @MainActor
    func testSeasonAndPositionSwitchingStaysWithinBudget() async {
        let vm = await openedViewModel()
        let seasons = vm.availableSeasons
        XCTAssertGreaterThan(seasons.count, 19)
        let elapsed = measure("switch \(seasons.count) seasons x 5 positions") {
            for season in seasons {
                vm.selectSeason(season)
                for position in PlayerPositionGroup.allCases {
                    vm.selectedPosition = position
                    _ = vm.currentSortMetric
                    _ = vm.availableAdvancedSortMetrics
                    for _ in 0..<3 { _ = vm.leaderboard }
                    _ = vm.teamsWithData
                }
            }
        }
        XCTAssertFalse(vm.leaderboard.isEmpty)
        XCTAssertLessThan(elapsed, 10.0)  // 20 seasons x 5 positions, measured 1.95 s
    }

    /// Typing in search on the busiest board, then Best/Worst and the
    /// qualified list on the career rollup, the widest season there is.
    @MainActor
    func testSearchAndLeaderBoardsOnTheCareerRollupStayWithinBudget() async {
        let vm = await openedViewModel()
        vm.selectSeason(StatScoutSeason.allTime)
        vm.selectedPosition = .defense
        let typing = measure("search typing, career defense") {
            for query in ["", "c", "co", "con", "conn", "con", "co", "c", "", "surname1", ""] {
                vm.searchText = query
                _ = vm.leaderboard
                _ = vm.searchedTeams
            }
        }
        XCTAssertLessThan(typing, 0.5)  // typing, measured 97 ms

        vm.searchText = ""
        let boards = measure("best/worst + qualified, career") {
            for _ in 0..<10 {
                _ = vm.allMetrics
                _ = vm.qualifiedSeasonPlayers
            }
        }
        XCTAssertFalse(vm.allMetrics.isEmpty)
        XCTAssertLessThan(boards, 0.75)  // best/worst, measured 143 ms
    }

    /// Team pages and profiles resolve players by team and by id for every
    /// club, every time they open.
    @MainActor
    func testTeamAndProfileLookupsStayWithinBudget() async {
        let vm = await openedViewModel()
        vm.selectSeason(StatScoutSeason.current - 1)
        let ids = Array(vm.playerHistories.keys.prefix(400))
        let elapsed = measure("32 team rosters + 400 profile lookups") {
            for team in Self.teams {
                _ = vm.players(forTeam: team)
                _ = vm.teamScore(team)
            }
            for id in ids {
                _ = vm.player(id: id, season: StatScoutSeason.current - 1, phase: .regular)
            }
        }
        XCTAssertLessThan(elapsed, 3.0)  // lookups, measured 606 ms
    }
}
