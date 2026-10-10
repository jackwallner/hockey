import XCTest
@testable import Hockey_StatScout

final class DashboardViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
    }
    @MainActor
    func testAllMetricsKeyCollision() async throws {
        let players: [Player] = [
            Player(
                playerId: 1, name: "A", team: "SEA", position: "C", handedness: "",
                updatedAt: Date(), season: StatScoutSeason.current, playerType: "f",
                metrics: [
                    Metric(id: "m1", label: "xGA/60", value: "2.41", percentile: 90, category: .playDriving)
                ],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "EDM", position: "G", handedness: "",
                updatedAt: Date(), season: StatScoutSeason.current, playerType: "g",
                metrics: [
                    Metric(id: "m2", label: "xGA/60", value: "2.80", percentile: 85, category: .goaltending)
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
        XCTAssertEqual(Set(all.map(\.category)), [.playDriving, .goaltending])
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
        XCTAssertEqual(teamFullName("SEA"), "Seattle Kraken")
        XCTAssertEqual(teamFullName("TBL"), "Tampa Bay Lightning")
        XCTAssertEqual(teamFullName("VGK"), "Vegas Golden Knights")
        XCTAssertEqual(teamFullName("Unknown"), "Unknown")
        XCTAssertEqual(teamNickname("TOR"), "Maple Leafs")
        XCTAssertEqual(teamNickname("TBL"), "Lightning")
    }

    @MainActor
    func testPlayersForTeamMatchesAliases() async {
        let players = [
            Player(
                playerId: 1, name: "A", team: "Seattle Kraken", position: "C", handedness: "",
                updatedAt: Date(), season: 2025,
                metrics: [],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "B", team: "LV", position: "L", handedness: "",
                updatedAt: Date(), season: 2025,
                metrics: [],
                standardStats: [],
                games: []
            )
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2025
        await vm.load()

        XCTAssertEqual(vm.players(forTeam: "SEA").map { $0.playerId }, [1])
        XCTAssertEqual(vm.players(forTeam: "VGK").map { $0.playerId }, [2])
    }

    @MainActor
    func testConferenceFilterScopesPlayersTeamsAndMetrics() async {
        let players = [
            Player(
                playerId: 1, name: "East Player", team: "BOS", position: "C", handedness: "",
                updatedAt: Date(), season: 2025, playerType: "f",
                metrics: [Metric(id: "east", label: "ixG", value: "28.0", percentile: 90, category: .shotQuality)],
                standardStats: [],
                games: []
            ),
            Player(
                playerId: 2, name: "West Player", team: "SEA", position: "C", handedness: "",
                updatedAt: Date(), season: 2025, playerType: "f",
                metrics: [Metric(id: "west", label: "GAx", value: "+3.1", percentile: 80, category: .shotQuality)],
                standardStats: [],
                games: []
            ),
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2025
        await vm.load()

        vm.selectedConference = .east
        vm.searchText = "Boston"
        XCTAssertEqual(vm.filteredPlayers.map(\.name), ["East Player"])
        XCTAssertEqual(vm.searchedTeams, ["BOS"])
        XCTAssertEqual(vm.allMetrics.map(\.label), ["ixG"])

        vm.selectedConference = .west
        vm.searchText = "Seattle"
        XCTAssertEqual(vm.filteredPlayers.map(\.name), ["West Player"])
        XCTAssertEqual(vm.searchedTeams, ["SEA"])
        XCTAssertEqual(vm.allMetrics.map(\.label), ["GAx"])
    }

    func testConferencesAndDivisionsPartitionTheLeague() {
        XCTAssertEqual(leagueTeamAbbreviations.count, 32)
        XCTAssertEqual(LeagueDivision.allCases.count, 4)
        let divisionTeams = LeagueDivision.allCases.flatMap(\.teams)
        XCTAssertEqual(Set(divisionTeams), Set(leagueTeamAbbreviations))
        XCTAssertEqual(divisionTeams.count, 32)
        XCTAssertEqual(LeagueDivision.division(of: "Seattle Kraken"), .pacific)
        XCTAssertEqual(LeagueDivision.pacific.conference, .west)
        XCTAssertEqual(LeagueDivision.division(of: "TBL"), .atlantic)
        XCTAssertTrue(LeagueConference.east.contains(team: "NYR"))
        XCTAssertFalse(LeagueConference.east.contains(team: "SEA"))
        XCTAssertTrue(LeagueConference.all.contains(team: "SEA"))
    }

    @MainActor
    func testTeamCountsPopulatedAfterLoad() async {
        let players = [
            Player(playerId: 1, name: "A", team: "SEA", position: "C", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 2, name: "B", team: "SEA", position: "D", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []),
            Player(playerId: 3, name: "C", team: "VAN", position: "G", handedness: "", updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: [])
        ]
        let vm = DashboardViewModel(provider: MockProvider(players: players))
        vm.selectedSeason = 2025
        await vm.load()
        XCTAssertEqual(vm.teamCounts["SEA"], 2)
        XCTAssertEqual(vm.teamCounts["VAN"], 1)
    }

    @MainActor
    func testPartialRefreshPreservesCompleteCache() async {
        let cached = makeCompleteCurrentPlayers()
        let partial = Array(cached.prefix(5))
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = DashboardViewModel(provider: MockProvider(players: partial), cache: cache)

        await vm.load()

        XCTAssertEqual(vm.seasonPlayers.count, cached.count)
        XCTAssertEqual(vm.teamsWithData.count, leagueTeamAbbreviations.count)
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
            Player(playerId: 99, name: "Cached", team: "SEA", position: "C", handedness: "", updatedAt: Date(), metrics: [], standardStats: [], games: [])
        ]
        let cache = InMemoryPlayerCache(seed: cached)
        let vm = DashboardViewModel(provider: MockProvider(error: URLError(.notConnectedToInternet)), cache: cache)
        await vm.load()
        XCTAssertEqual(vm.players.map { $0.id }, ["99-0-REG"], "Cached players should be shown even when refresh fails")
    }

    @MainActor
    func testSortLabelReflectsCategory() async {
        // Forwards with an ixG metric
        let forwards = [
            Player(playerId: 1, name: "A", team: "SEA", position: "C", handedness: "", updatedAt: Date(), season: StatScoutSeason.current, playerType: "f", source: "moneypuck",
                   metrics: [Metric(id: "m1", label: "ixG", value: "31.4", percentile: 90, category: .shotQuality)], standardStats: [], games: [])
        ]

        let vm = DashboardViewModel(provider: MockProvider(players: forwards))
        await vm.load()
        _ = vm.leaderboard  // Trigger computation of sort metric

        // Default cohort is forwards, which lead with ixG.
        XCTAssertEqual(vm.sortLabel, "ixG")

        // Test with goalies
        let goalies = [
            Player(playerId: 2, name: "B", team: "EDM", position: "G", handedness: "", updatedAt: Date(), season: StatScoutSeason.current, playerType: "g", source: "moneypuck",
                   metrics: [Metric(id: "m1", label: "GSAx", value: "+14.2", percentile: 95, category: .goaltending)], standardStats: [], games: [])
        ]
        let vmGoalies = DashboardViewModel(provider: MockProvider(players: goalies))
        await vmGoalies.load()
        vmGoalies.selectedCategory = .goaltending
        _ = vmGoalies.leaderboard  // Trigger computation
        XCTAssertEqual(vmGoalies.selectedPosition, .goalie)
        XCTAssertEqual(vmGoalies.sortLabel, "GSAx")

        // Test empty data falls back to the default label.
        let vmEmpty = DashboardViewModel(provider: MockProvider(players: []))
        await vmEmpty.load()
        vmEmpty.selectedCategory = .scoring
        _ = vmEmpty.leaderboard  // Trigger computation
        XCTAssertEqual(vmEmpty.sortLabel, "Top Metric")

        // Test nil category leaves the cohort alone
        let vmNil = DashboardViewModel(provider: MockProvider(players: forwards))
        await vmNil.load()
        vmNil.selectedCategory = nil
        _ = vmNil.leaderboard
        XCTAssertEqual(vmNil.sortLabel, "ixG")
    }

    @MainActor
    func testCohortSortUsesAvailableMetrics() async {
        let defenseman = Player(
            playerId: 1, name: "Test D", team: "SEA", position: "D",
            handedness: "", updatedAt: Date(), season: StatScoutSeason.current, playerType: "d", source: "moneypuck",
            metrics: [
                Metric(id: "m1", label: "Blocks", value: "150", percentile: 85, category: .playDriving),
                Metric(id: "m2", label: "Hits", value: "90", percentile: 70, category: .playDriving)
            ],
            standardStats: [],
            games: []
        )

        let vm = DashboardViewModel(provider: MockProvider(players: [defenseman]))
        await vm.load()
        vm.selectedPosition = .defense

        // Should find the defenseman in the filtered list
        XCTAssertEqual(vm.filteredPlayers.count, 1)
        // None of the defense headline metrics exist, so it falls to the first available one.
        XCTAssertEqual(vm.sortLabel, "Blocks")
        XCTAssertEqual(vm.leaderboard.first?.playerId, 1)
        // Skaters never show on the goalie board.
        vm.selectedPosition = .goalie
        XCTAssertTrue(vm.filteredPlayers.isEmpty)
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
    /// would otherwise bury "All Time" below 2008.
    private var expectedSeasons: [Int] {
        [StatScoutSeason.allTime]
            + Array(StatScoutSeason.earliest...StatScoutSeason.current).reversed()
    }

    @MainActor
    func testAvailableSeasonsIncludes2008ThroughCurrentPlusAllTime() async {
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
    /// The model: the live season is free and the default for
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

    /// Opening night: two teams have played. The live season is still the default,
    /// for Pro too, and its thin board is what shows.
    @MainActor
    func testAThinLiveSeasonIsStillTheDefault() async {
        let lastSeason = makeCompleteSeasonPlayers(season: StatScoutSeason.current - 1, namePrefix: "LastYear")
        let opener = makeCompleteCurrentPlayers(namePrefix: "Opener").filter { ["EDM", "SEA"].contains($0.team) }
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
            playerId: 1, name: "Starter", team: "BOS", position: "C", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: "f",
            metrics: [Metric(id: "s", label: "ixG", value: "10.0", percentile: 60, category: .shotQuality, qualified: true)],
            standardStats: [], games: []
        )
        let backup = Player(
            playerId: 2, name: "Backup", team: "SEA", position: "C", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: "f",
            metrics: [Metric(id: "b", label: "ixG", value: "1.9", percentile: 99, category: .shotQuality, qualified: false)],
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
        [{"id":"a","label":"ixG","value":"3.1","percentile":50,"category":"Shot Quality","qualified":false},
         {"id":"b","label":"ixG","value":"4.2","percentile":60,"category":"Shot Quality"}]
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
    /// The per-game tables hold the live season and the one before it (2025-26
    /// onward); `player_snapshots` carries everything back to 2008-09, which is
    /// why season boards reach further than form boards do. Moving this
    /// constant down without ingesting the per-game tables first puts an empty
    /// year in the Trends menu.
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
    /// it - so the first tap on any past season, and on "All Time" most
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

    /// The sentinel must never reach the UI as "0", and a real season always
    /// reads as the two years the NHL season spans.
    func testSeasonLabelRendersSentinelAsAllTime() {
        XCTAssertEqual(SeasonLabel.display(StatScoutSeason.allTime), "All Time")
        XCTAssertEqual(SeasonLabel.display(2024), "2024-25")
        XCTAssertEqual(
            SeasonLabel.display(StatScoutSeason.allTime, phase: .regular),
            "All Time"
        )
        XCTAssertEqual(SeasonLabel.display(2024, phase: .playoffs), "2024-25 Playoffs")
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
            playerId: 1, name: "Player 2025", team: "SEA", position: "C", handedness: "L",
            updatedAt: Date(), season: 2025, metrics: [], standardStats: [], games: []
        )
        let player2024 = Player(
            playerId: 2, name: "Player 2024", team: "BOS", position: "C", handedness: "R",
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
            playerId: 1, name: "Player 2025", team: "SEA", position: "C", handedness: "L",
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
            playerId: 1, name: "Last Season", team: "SEA", position: "C", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current - 1, metrics: [], standardStats: [], games: []
        )
        let vm = DashboardViewModel(provider: MockProvider(players: [lastSeason]))
        vm.isPro = true
        await vm.load()
        XCTAssertEqual(vm.selectedSeason, StatScoutSeason.current)
    }

    func testSeasonIndicatorHasNoGroupingAndShowsBothYears() {
        let formatted = SeasonLabel.display(2026)
        XCTAssertEqual(formatted, "2026-27")
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
        let teams = leagueTeamAbbreviations
        let types = ["f", "d", "g"]
        return teams.enumerated().map { index, team in
            let type = types[index % types.count]
            let position = type == "g" ? "G" : type == "d" ? "D" : "C"
            let metric: (label: String, category: MetricCategory) = switch type {
            case "f": ("ixG", .shotQuality)
            case "d": ("xGF%", .playDriving)
            default: ("GSAx", .goaltending)
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
                standardStats: [StandardStat(id: "games-\(index)", label: "GP", value: "1")],
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
        return (players ?? []).filter { ($0.season ?? 0) < StatScoutSeason.current }
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
