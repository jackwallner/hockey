import XCTest
@testable import Gridiron_StatScout

final class DashboardViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
    }
    @MainActor
    func testAllMetricsKeyCollision() async throws {
        let players: [Player] = [
            Player(
                playerId: 1, name: "A", team: "KC", position: "QB", handedness: "",
                updatedAt: Date(), season: StatScoutSeason.current, playerType: "qb",
                metrics: [
                    Metric(id: "m1", label: "TD", value: "26", percentile: 90, category: .passing)
                ],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "PHI", position: "RB", handedness: "",
                updatedAt: Date(), season: StatScoutSeason.current, playerType: "rb",
                metrics: [
                    Metric(id: "m2", label: "TD", value: "13", percentile: 85, category: .rushing)
                ],
                standardStats: [],
                games: []
            )
        ]
        let provider = MockProvider(players: players)
        let vm = DashboardViewModel(provider: provider)
        await vm.load()
        let all = vm.allMetrics
        XCTAssertEqual(all.count, 2, "Same label in different categories should produce 2 entries")
    }

    @MainActor
    func testLoadDistinguishesErrors() async {
        let decoderProvider = MockProvider(error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")))
        let vm1 = DashboardViewModel(provider: decoderProvider)
        await vm1.load()
        XCTAssertTrue(vm1.errorMessage?.contains("format changed") == true)

        let urlProvider = MockProvider(error: URLError(.notConnectedToInternet))
        let vm2 = DashboardViewModel(provider: urlProvider)
        await vm2.load()
        XCTAssertTrue(vm2.errorMessage?.contains("connection") == true)
    }

    @MainActor
    func testLastUpdatedReturnsNilWhenEmpty() {
        let vm = DashboardViewModel(provider: MockProvider(players: []))
        XCTAssertNil(vm.lastUpdated)
    }

    @MainActor
    func testTeamFullNameReturnsCorrectFullName() {
        // Test the teamFullName helper function directly
        XCTAssertEqual(teamFullName("KC"), "Kansas City Chiefs")
        XCTAssertEqual(teamFullName("SF"), "San Francisco 49ers")
        XCTAssertEqual(teamFullName("PHI"), "Philadelphia Eagles")
        XCTAssertEqual(teamFullName("Unknown"), "Unknown")
    }

    @MainActor
    func testPlayersForTeamMatchesAliases() async {
        let players = [
            Player(
                playerId: 1, name: "A", team: "Kansas City Chiefs", position: "QB", handedness: "",
                updatedAt: Date(), season: 2025,
                metrics: [],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "OAK", position: "WR", handedness: "",
                updatedAt: Date(), season: 2025,
                metrics: [],
                standardStats: [],
                games: []
            )
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2025
        await vm.load()

        XCTAssertEqual(vm.players(forTeam: "KC").map { $0.playerId }, [1])
        XCTAssertEqual(vm.players(forTeam: "LV").map { $0.playerId }, [2])
    }

    @MainActor
    func testConferenceFilterScopesPlayersTeamsAndMetrics() async {
        let players = [
            Player(
                playerId: 1, name: "AFC Player", team: "KC", position: "QB", handedness: "",
                updatedAt: Date(), season: 2025, playerType: "qb",
                metrics: [Metric(id: "afc", label: "Pass Yds", value: "4,000", percentile: 90, category: .passing)],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "NFC Player", team: "PHI", position: "QB", handedness: "",
                updatedAt: Date(), season: 2025, playerType: "qb",
                metrics: [Metric(id: "nfc", label: "CPOE", value: "5.1", percentile: 80, category: .passing)],
                standardStats: [],
                games: []
            ),
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2025
        await vm.load()

        vm.selectedConference = .afc
        vm.searchText = "Kansas"
        XCTAssertEqual(vm.filteredPlayers.map(\.name), ["AFC Player"])
        XCTAssertEqual(vm.searchedTeams, ["KC"])
        XCTAssertEqual(vm.allMetrics.map(\.label), ["Pass Yds"])

        vm.selectedConference = .nfc
        vm.searchText = "Philadelphia"
        XCTAssertEqual(vm.filteredPlayers.map(\.name), ["NFC Player"])
        XCTAssertEqual(vm.searchedTeams, ["PHI"])
        XCTAssertEqual(vm.allMetrics.map(\.label), ["CPOE"])
    }

    @MainActor
    func testTeamCountsPopulatedAfterLoad() async {
        let players = [
            Player(playerId: 1, name: "A", team: "KC", position: "QB", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 2, name: "B", team: "KC", position: "RB", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 3, name: "C", team: "SF", position: "WR", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: [])
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2025
        await vm.load()
        XCTAssertEqual(vm.teamCounts["KC"], 2)
        XCTAssertEqual(vm.teamCounts["SF"], 1)
    }

    @MainActor
    func testPartialRefreshPreservesCompleteCache() async {
        let cached = makeCompleteCurrentPlayers()
        let partial = Array(cached.prefix(5))
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = DashboardViewModel(provider: MockProvider(players: partial), cache: cache)

        await vm.load()

        XCTAssertEqual(vm.seasonPlayers.count, cached.count)
        XCTAssertEqual(vm.teamsWithData.count, 32)
        XCTAssertTrue(vm.lastFetchFailed)
        XCTAssertEqual(cache.savedPlayers.count, cached.count)
    }

    @MainActor
    func testCompleteRefreshReplacesCurrentCache() async {
        let refreshed = makeCompleteCurrentPlayers(namePrefix: "Fresh")
        let cache = InMemoryPlayerCache(seed: makeCompleteCurrentPlayers())
        let vm = DashboardViewModel(provider: MockProvider(players: refreshed), cache: cache)

        await vm.load()

        XCTAssertEqual(vm.seasonPlayers.count, refreshed.count)
        XCTAssertTrue(vm.seasonPlayers.allSatisfy { $0.name.hasPrefix("Fresh") })
        XCTAssertEqual(cache.savedPlayers.count, refreshed.count)
    }

    @MainActor
    func testCacheHydratesPlayersBeforeFetch() async {
        let cached = [
            Player(playerId: 99, name: "Cached", team: "KC", position: "QB", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        ]
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = DashboardViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)), cache: cache)
        await vm.load()
        XCTAssertEqual(vm.players.map { $0.id }, ["99-0-REG"], "Cached players should be shown even when refresh fails")
    }

    @MainActor
    func testSortLabelReflectsCategory() async {
        // Passers with a Pass Yds metric
        let passers = [
            Player(playerId: 1, name: "A", team: "KC", position: "QB", handedness: "", updatedAt: Date(), season: StatScoutSeason.current, playerType: "qb", source: "nflreadpy",
                   metrics: [Metric(id: "m1", label: "Pass Yds", value: "4,000", percentile: 90, category: .passing)], standardStats: [], games: [])
        ]

        let vm = DashboardViewModel(provider: MockProvider(players: passers))
        await vm.load()
        _ = vm.leaderboard  // Trigger computation of sort metric

        // Default category is passing, should find Pass Yds in data
        XCTAssertEqual(vm.sortLabel, "Pass Yds")

        // Test with rushers
        let rushers = [
            Player(playerId: 2, name: "B", team: "PHI", position: "RB", handedness: "", updatedAt: Date(), season: StatScoutSeason.current, playerType: "rb", source: "nflreadpy",
                   metrics: [Metric(id: "m1", label: "Rush Yds", value: "1,500", percentile: 85, category: .rushing)], standardStats: [], games: [])
        ]
        let vmRushing = DashboardViewModel(provider: MockProvider(players: rushers))
        await vmRushing.load()
        vmRushing.selectedCategory = .rushing
        _ = vmRushing.leaderboard  // Trigger computation
        XCTAssertEqual(vmRushing.sortLabel, "Rush Yds")

        // Test empty data falls back to the default label. The NFL redesign
        // renamed this from "Top Category" to "Top Metric"; the fixture never
        // followed.
        let vmEmpty = DashboardViewModel(provider: MockProvider(players: []))
        await vmEmpty.load()
        vmEmpty.selectedCategory = .passing
        _ = vmEmpty.leaderboard  // Trigger computation
        XCTAssertEqual(vmEmpty.sortLabel, "Top Metric")

        // Test nil category shows the default label
        let vmNil = DashboardViewModel(provider: MockProvider(players: passers))
        await vmNil.load()
        vmNil.selectedCategory = nil
        _ = vmNil.leaderboard
        XCTAssertEqual(vmNil.sortLabel, "Pass Yds")
    }

    @MainActor
    func testRushingSortUsesAvailableMetrics() async {
        let back = Player(
            playerId: 1, name: "Test RB", team: "PHI", position: "RB",
            handedness: "", updatedAt: Date(), season: StatScoutSeason.current, playerType: "rb", source: "nflreadpy",
            metrics: [
                Metric(id: "m1", label: "Rush Yds", value: "1,500", percentile: 85, category: .rushing),
                Metric(id: "m2", label: "Y/C", value: "5.2", percentile: 70, category: .rushing)
            ],
            standardStats: [],
            games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [back]))
        await vm.load()
        vm.selectedCategory = .rushing

        // Should find the back in filtered list
        XCTAssertEqual(vm.filteredPlayers.count, 1)
        // Should sort by Rush Yds since that's the first available priority metric
        XCTAssertEqual(vm.leaderboard.first?.playerId, 1)
    }

    @MainActor
    func testHistoricalArchiveRequiresEverySupportedSeason() async {
        let complete = makeCompleteHistoricalPlayers()
        XCTAssertTrue(PlayerSnapshotValidator.isCompleteHistorical(complete))

        let missing2015 = complete.filter { $0.season != StatScoutSeason.earliest }
        XCTAssertFalse(PlayerSnapshotValidator.isCompleteHistorical(missing2015))
    }

    /// The career rollup leads the menu, then real years newest-first. It sits at
    /// the top rather than sorting into place because its sentinel is 0, which
    /// would otherwise bury "All Time" below 2000.
    private var expectedSeasons: [Int] {
        [StatScoutSeason.allTime]
            + Array(StatScoutSeason.earliest...StatScoutSeason.current).reversed()
    }

    @MainActor
    func testAvailableSeasonsIncludes2000ThroughCurrentPlusAllTime() async {
        let players = makeCompleteHistoricalPlayers() + makeCompleteCurrentPlayers()
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.isPro = true

        await vm.load()

        XCTAssertEqual(vm.availableSeasons, expectedSeasons)
        XCTAssertEqual(vm.availableSeasons.first, StatScoutSeason.allTime)
    }

    @MainActor
    func testAvailableSeasonsIncludesLockedHistoryBeforeHistoryLoads() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertEqual(vm.availableSeasons, expectedSeasons)
        XCTAssertTrue(vm.isSeasonLocked(StatScoutSeason.current - 1))
    }

    /// All Time is Pro, like every season other than the current one.
    @MainActor
    func testAllTimeIsLockedForFreeUsers() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        vm.isPro = false
        XCTAssertTrue(vm.isSeasonLocked(StatScoutSeason.allTime))
        vm.isPro = true
        XCTAssertFalse(vm.isSeasonLocked(StatScoutSeason.allTime))
    }

    /// The free season is the calendar's season, even before its data lands.
    ///
    /// Baseball StatScout's model: the live season is free and the default for
    /// everyone from the day it starts; every earlier season is StatScout+. It
    /// used to trail the data, which kept 2025 free and 2026 hidden after the
    /// 2026 opener had been played.
    @MainActor
    func testFreeSeasonIsTheCalendarSeasonEvenBeforeItsDataLands() async {
        let stale = makeCompleteSeasonPlayers(
            season: StatScoutSeason.current - 1,
            namePrefix: "LastYear"
        )
        let vm = DashboardViewModel(provider: MockProvider(players: stale))

        await vm.load()

        XCTAssertEqual(vm.freeSeason, StatScoutSeason.current)
        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.current)
        XCTAssertTrue(vm.isSeasonLocked(StatScoutSeason.current - 1))
        XCTAssertTrue(vm.availableSeasons.contains(StatScoutSeason.current))
    }

    /// Week 1: two teams have played. The live season is still the default,
    /// for Pro too, and its thin board is what shows.
    @MainActor
    func testAThinLiveSeasonIsStillTheDefault() async {
        let lastSeason = makeCompleteSeasonPlayers(season: StatScoutSeason.current - 1, namePrefix: "LastYear")
        let opener = makeCompleteCurrentPlayers(namePrefix: "Opener").filter { ["NE", "SEA"].contains($0.team) }
        let vm = DashboardViewModel(provider: MockProvider(players: lastSeason + opener))
        vm.isPro = true

        await vm.load()

        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.current)
        XCTAssertFalse(vm.isSeasonLocked(StatScoutSeason.current))
        XCTAssertTrue(vm.players.contains { $0.season == StatScoutSeason.current })
    }

    /// The live season ships players under the bar. All Players (the default)
    /// keeps them dimmed below qualified players; Qualified hides them.
    @MainActor
    func testQualifiedFilterHonoursTheLiveSeasonFlag() async {
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
        defer { UserDefaults.standard.removeObject(forKey: "stats.qualifier") }
        let starter = Player(
            playerId: 1, name: "Starter", team: "NE", position: "QB", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: "qb",
            metrics: [Metric(id: "s", label: "EPA/Play", value: "0.10", percentile: 60, category: .passing, qualified: true)],
            standardStats: [], games: []
        )
        let backup = Player(
            playerId: 2, name: "Backup", team: "SEA", position: "QB", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: "qb",
            metrics: [Metric(id: "b", label: "EPA/Play", value: "0.90", percentile: 99, category: .passing, qualified: false)],
            standardStats: [], games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [starter, backup]))
        await vm.load()

        XCTAssertEqual(vm.qualifierLevel, .all)
        // The backup's 99th percentile outranks the starter, but a small
        // sample never tops a board.
        XCTAssertEqual(vm.leaderboard.map(\.name), ["Starter", "Backup"])
        vm.qualifierLevel = .qualified
        XCTAssertEqual(vm.leaderboard.map(\.name), ["Starter"])
        XCTAssertEqual(DashboardViewModel(provider: MockProvider(players: [])).qualifierLevel, .qualified, "the choice persists")
    }

    func testMetricDecodesWithAndWithoutTheQualifiedFlag() throws {
        let json = #"""
        [{"id":"a","label":"EPA/Play","value":"0.1","percentile":50,"category":"Passing","qualified":false},
         {"id":"b","label":"EPA/Play","value":"0.2","percentile":60,"category":"Passing"}]
        """#
        let metrics = try JSONDecoder().decode([Metric].self, from: Data(json.utf8))
        XCTAssertEqual(metrics.map(\.qualified), [false, nil])
    }

    /// Recent form covers the live season and the one before it.
    ///
    /// Last season keeps its form board on purpose: pinning this to the live
    /// season alone meant Trends went blank every September for the year people
    /// were still reading about. Asserted as rules rather than as literal years
    /// because both ends move - the live season rolls over on its own, and the
    /// floor is wherever the per-game purge left the rollup table.
    @MainActor
    func testRecentFormCoversTheLiveSeasonAndTheOneBefore() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertEqual(vm.recentFormSeason, StatScoutSeason.current)
        XCTAssertEqual(vm.recentFormSeasons.first, vm.freeSeason, "Newest first")
        XCTAssertLessThanOrEqual(vm.recentFormSeasons.count, 2)
        XCTAssertEqual(vm.recentFormSeasons, vm.recentFormSeasons.sorted(by: >))
        XCTAssertTrue(vm.supportsRecentForm(vm.freeSeason))
        for season in vm.recentFormSeasons {
            XCTAssertTrue(vm.supportsRecentForm(season))
        }
        XCTAssertFalse(vm.supportsRecentForm(StatScoutSeason.allTime))
    }

    /// Never offer a season the rollup table no longer holds.
    ///
    /// The per-game tables were purged back to `earliestRecentForm`, so
    /// "the one before the live season" has to stop there. It didn't, and the
    /// Trends menu gained an entry whose board could only ever come back empty.
    @MainActor
    func testRecentFormNeverOffersAPurgedSeason() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        for season in vm.recentFormSeasons {
            XCTAssertGreaterThanOrEqual(season, StatScoutSeason.earliestRecentForm)
        }
        XCTAssertFalse(vm.supportsRecentForm(StatScoutSeason.earliestRecentForm - 1))
    }

    /// The floor is a fact about the database, not a preference.
    ///
    /// Verified against the live Football project on 2026-08-07:
    /// `player_game_logs` and `player_recent_form` hold 2025 and nothing else
    /// (16,745 and 3,607 rows; 2024 and earlier return zero). `player_snapshots`
    /// still carries 2024 and back, which is why season boards reach further
    /// than form boards do. Moving this constant down without re-ingesting the
    /// per-game tables first puts an empty year in the Trends menu.
    func testRecentFormFloorMatchesTheSeasonsTheRollupStillHolds() {
        XCTAssertEqual(StatScoutSeason.earliestRecentForm, 2025)
        XCTAssertLessThanOrEqual(
            StatScoutSeason.earliestRecentForm,
            StatScoutSeason.current,
            "The floor can never sit above the live season, or Recent Form vanishes entirely"
        )
    }

    /// Kickoff, end to end: once the new season's rows land, it is the free
    /// season and last season is Pro. Written in terms of `current` rather than
    /// literal years because it has to survive the calendar rolling.
    @MainActor
    func testTheAppMovesToTheNewSeasonTheDayItsDataLands() async {
        let lastSeason = StatScoutSeason.current - 1
        let lastSeasonRows = makeCompleteSeasonPlayers(season: lastSeason, namePrefix: "LastYear")

        // Kickoff night: the ingest writes the new season, the next fetch sees it.
        let postKickoff = DashboardViewModel(
            provider: MockProvider(players: lastSeasonRows + makeCompleteCurrentPlayers())
        )
        await postKickoff.load()

        XCTAssertEqual(postKickoff.freeSeason, StatScoutSeason.current, "and moves on by itself once rows land")
        XCTAssertFalse(postKickoff.isSeasonLocked(StatScoutSeason.current))
        XCTAssertTrue(postKickoff.isSeasonLocked(lastSeason), "last season becomes Pro, not gone")
        XCTAssertTrue(postKickoff.availableSeasons.contains(lastSeason))

        // Recent Form follows the live season and keeps the one before it, as
        // far back as the rollup table still reaches.
        XCTAssertEqual(postKickoff.recentFormSeasons.first, StatScoutSeason.current)
        XCTAssertEqual(
            postKickoff.recentFormSeasons,
            [StatScoutSeason.current, lastSeason].filter { $0 >= StatScoutSeason.earliestRecentForm }
        )
    }

    /// With the live season present, nothing changes: the free season is it.
    @MainActor
    func testFreeSeasonIsTheCurrentSeasonOnceItHasData() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertEqual(vm.freeSeason, StatScoutSeason.current)
        XCTAssertFalse(vm.isSeasonLocked(StatScoutSeason.current))
    }

    /// Picking a past season fetches that season.
    ///
    /// History is decoded on demand, and nothing in the nav bar used to ask for
    /// it - so the first tap on any past season, and on "All since 2000" most
    /// visibly since it is the first row of the menu, landed on an empty board.
    @MainActor
    func testSelectingAPastSeasonLoadsTheHistoryItNeeds() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        vm.isPro = true
        await vm.load()
        XCTAssertFalse(vm.hasLoadedHistorical, "History should still be unfetched after a plain load")

        vm.selectSeason(StatScoutSeason.allTime)

        // The header moves on the tap; the rows arrive behind it.
        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.allTime)
        XCTAssertNotNil(vm.seasonLoadTask, "Choosing a past season should start the history load")
        await vm.seasonLoadTask?.value
    }

    /// The live season needs no extra fetch, so it must not start one.
    @MainActor
    func testSelectingTheFreeSeasonDoesNotRefetchHistory() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))
        await vm.load()

        vm.selectSeason(vm.freeSeason)

        XCTAssertNil(vm.seasonLoadTask)
    }

    /// Trends ranks rolling week windows, so a career has nothing to rank.
    @MainActor
    func testTrendsSeasonListExcludesAllTime() async {
        let vm = DashboardViewModel(provider: MockProvider(players: makeCompleteCurrentPlayers()))

        await vm.load()

        XCTAssertFalse(vm.seasonsExcludingAllTime.contains(StatScoutSeason.allTime))
        XCTAssertEqual(vm.seasonsExcludingAllTime.count, vm.availableSeasons.count - 1)
    }

    /// The sentinel must never reach the UI as "0", and it must name its own
    /// start date rather than claiming every season ever played.
    func testSeasonLabelRendersSentinelAsAllSinceEarliest() {
        XCTAssertEqual(SeasonLabel.text(StatScoutSeason.allTime), "All since 2000")
        XCTAssertEqual(SeasonLabel.text(2024), "2024")
        XCTAssertEqual(
            SeasonLabel.text(StatScoutSeason.allTime, phase: .regular),
            "All since 2000 · Regular Season"
        )
        XCTAssertEqual(SeasonLabel.text(2024, phase: .playoffs), "2024 Playoffs")
    }

    /// One name for the phase everywhere. The nav pill used to get a bare
    /// "Regular", which reads as an adjective describing the year beside it.
    func testSeasonPhaseAlwaysReadsAsAFullName() {
        XCTAssertEqual(SeasonPhase.regular.label, "Regular Season")
        XCTAssertEqual(SeasonPhase.playoffs.label, "Playoffs")
    }

    @MainActor
    func testSeasonPlayersReturnsPlayersForSelectedSeason() async {
        // Create players with different seasons
        let player2025 = Player(
            playerId: 1, name: "Player 2025", team: "NYY", position: "RF", handedness: "R/R",
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )
        let player2024 = Player(
            playerId: 2, name: "Player 2024", team: "BOS", position: "1B", handedness: "L/R",
            updatedAt: Date(), season: 2024, metrics: [], standardStats: [], games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [player2025, player2024]))
        await vm.load()

        // Set season to 2025
        vm.selectedSeason = 2025
        XCTAssertEqual(vm.seasonPlayers.count, 1)
        XCTAssertEqual(vm.seasonPlayers.first?.playerId, 1)

        // Set season to 2024
        vm.selectedSeason = 2024
        XCTAssertEqual(vm.seasonPlayers.count, 1)
        XCTAssertEqual(vm.seasonPlayers.first?.playerId, 2)
    }

    @MainActor
    func testSeasonPlayersIsEmptyWhenSeasonHasNoData() async {
        // Players only have 2025 data
        let player2025 = Player(
            playerId: 1, name: "Player 2025", team: "NYY", position: "RF", handedness: "R/R",
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [player2025]))
        await vm.load()

        // Select 2024 which has no data - should report empty (no stale fallback).
        vm.selectedSeason = 2024
        XCTAssertTrue(vm.seasonPlayers.isEmpty)
    }

    @MainActor
    func testLoadNeverSnapsAwayFromTheLiveSeason() async {
        let lastSeason = Player(
            playerId: 1, name: "Last Season", team: "KC", position: "QB", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current - 1, metrics: [], standardStats: [], games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [lastSeason]))
        vm.isPro = true
        await vm.load()
        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.current)
    }

    @MainActor
    func testSeasonIndicatorCanBeFormatted() async {
        // Test that season can be displayed correctly (no commas, just the year)
        let season: Int = 2026

        // Swift string interpolation should not add commas
        let formatted = "\(season)"
        XCTAssertEqual(formatted, "2026")
        XCTAssertFalse(formatted.contains(","), "Season should not contain comma separators")
    }

    private func makeCompleteHistoricalPlayers() -> [Player] {
        (StatScoutSeason.earliest..<StatScoutSeason.current).flatMap { season in
            makeCompleteSeasonPlayers(season: season, namePrefix: "Historical")
        }
    }

    private func makeCompleteCurrentPlayers(namePrefix: String = "Cached") -> [Player] {
        makeCompleteSeasonPlayers(season: StatScoutSeason.current, namePrefix: namePrefix)
    }

    private func makeCompleteSeasonPlayers(season: Int, namePrefix: String) -> [Player] {
        let teams = nflTeamAbbreviations
        let types = ["qb", "rb", "wr", "te", "def"]
        return teams.enumerated().map { index, team in
            let type = types[index % types.count]
            let position = type == "def" ? "LB" : type.uppercased()
            let metric: (label: String, category: MetricCategory) = switch type {
            case "qb": ("EPA/Play", .passing)
            case "rb": ("EPA/Rush", .rushing)
            case "wr", "te": ("EPA/Tgt", .receiving)
            default: ("Tackles", .defense)
            }
            return Player(
                playerId: 10_000 + index,
                name: "\(namePrefix) \(team)",
                team: team,
                position: position,
                handedness: "",
                updatedAt: Date(),
                season: season,
                playerType: type,
                metrics: [Metric(id: "metric-\(index)", label: metric.label, value: "1", percentile: 50, category: metric.category)],
                standardStats: [StandardStat(id: "games-\(index)", label: "G", value: "1")],
                games: []
            )
        }
    }
}

final class InMemoryPlayerCache: PlayerCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Player]
    init(seed: [Player] = []) { self.stored = seed }
    var savedPlayers: [Player] { lock.withLock { stored } }
    func loadPlayers() throws -> [Player] { lock.withLock { stored } }
    func savePlayers(_ players: [Player]) throws { lock.withLock { stored = players } }
}

struct MockProvider: StatcastProviding, @unchecked Sendable {
    let players: [Player]?
    let error: Error?

    init(players: [Player]? = nil, error: Error? = nil) {
        self.players = players
        self.error = error
    }

    func fetchPlayers() async throws -> [Player] {
        if let error { throw error }
        return players ?? []
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        if let error { throw error }
        return (players ?? []).filter { ($0.season ?? 0) < 2025 }
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        if let error { throw error }
        return players ?? []
    }

    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        if let error { throw error }
        return []
    }

    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog] {
        if let error { throw error }
        return []
    }

    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        if let error { throw error }
        return []
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        if let error { throw error }
        return nil
    }
}
