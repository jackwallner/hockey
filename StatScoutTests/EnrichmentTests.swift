import XCTest
@testable import Rink_StatScout

final class EnrichmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
    }

    private func player(
        _ id: Int,
        type: String = "wr",
        team: String = "SEA",
        metrics: [Metric],
        stats: [StandardStat] = []
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team, position: type.uppercased(), handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: type,
            metrics: metrics, standardStats: stats, games: []
        )
    }

    private func metric(_ label: String, _ value: String, _ pct: Int, _ category: MetricCategory, qualified: Bool? = nil) -> Metric {
        Metric(id: "\(label)-\(pct)-\(value)", label: label, value: value, percentile: pct, category: category, qualified: qualified)
    }

    // MARK: Unranked zero counts

    func testZeroCountingStatIsUnrankedButRatesAndNonZeroCountsAreNot() {
        XCTAssertTrue(metric("INT", "0", 47, .defense).isUnranked)
        XCTAssertTrue(metric("Sacks", "0.0", 41, .defense).isUnranked)
        XCTAssertFalse(metric("Sacks", "1.5", 80, .defense).isUnranked)
        XCTAssertFalse(metric("EPA/Rush", "0.00", 50, .rushing).isUnranked, "a rate at zero is a real rank")
        XCTAssertFalse(metric("Rush EPA", "0.0", 50, .rushing).isUnranked, "advanced totals keep their rank")
        var standard = metric("DEF INT", "0", 47, .defense)
        standard.rankable = false
        XCTAssertTrue(standard.isUnranked)
    }

    func testOverallPercentileLeavesUnrankedZerosOut() {
        let defender = player(1, type: "def", metrics: [
            metric("Tackles", "4", 20, .defense),
            metric("INT", "0", 47, .defense),
            metric("Sacks", "0.0", 41, .defense),
        ])
        XCTAssertEqual(defender.overallPercentile, 20)
        XCTAssertEqual(defender.headlineMetric?.label, "Tackles")
    }

    // MARK: Contract value

    func testContractValueIsProductionMinusPayWithinThePosition() {
        // Five receivers: pay ascending by id, production descending.
        let players = (1...5).map { id in
            player(id, metrics: [metric("EPA/Tgt", "0.\(id)", 100 - id * 15, .receiving, qualified: true)])
        }
        var profiles: [Int: PlayerProfile] = [:]
        for id in 1...5 {
            var profile = PlayerProfile(playerId: id, season: StatScoutSeason.current)
            profile.contractCapShare = Double(id) / 100
            profile.contractAPY = Double(id * 5)
            profiles[id] = profile
        }
        let values = ContractValue.compute(players: players, profiles: profiles) { _ in true }
        XCTAssertEqual(values.count, 5)
        XCTAssertEqual(values[1]?.payPercentile, 10)
        XCTAssertEqual(values[1]?.productionPercentile, 90)
        XCTAssertEqual(values[1]?.score, 80)
        XCTAssertEqual(values[1]?.verdict, .bargain)
        XCTAssertEqual(values[5]?.verdict, .overpaid)
        XCTAssertEqual(values[3]?.verdict, .fair)
        XCTAssertEqual(values[1]?.poolSize, 5)
    }

    func testContractValueNeedsFiveQualifiedPlayersAndSkipsDefense() {
        let players = (1...4).map { id in
            player(id, metrics: [metric("EPA/Tgt", "0.1", 50, .receiving, qualified: true)])
        } + (5...10).map { id in
            player(id, type: "def", metrics: [metric("Tackles", "\(id)", id * 9, .defense)])
        }
        var profiles: [Int: PlayerProfile] = [:]
        for id in 1...10 {
            var profile = PlayerProfile(playerId: id, season: StatScoutSeason.current)
            profile.contractCapShare = 0.01 * Double(id)
            profiles[id] = profile
        }
        XCTAssertTrue(ContractValue.compute(players: players, profiles: profiles) { _ in true }.isEmpty)
    }

    func testProductionIgnoresSmallSamplesAndUnrankedZeros() {
        let receiver = player(1, metrics: [
            metric("EPA/Tgt", "0.5", 90, .receiving, qualified: true),
            metric("Separation", "3.1", 20, .receiving, qualified: false),
            metric("Rec TD", "0", 30, .receiving, qualified: true),
            metric("Rush Yds", "40", 99, .rushing, qualified: true),
        ])
        XCTAssertEqual(ContractValue.production(for: receiver), 90)
    }

    // MARK: Standings

    func testStandingsCountRecordsDifferentialAndStreak() {
        func final(_ id: String, _ week: Int, _ away: String, _ home: String, _ a: Int, _ h: Int) -> Game {
            Game(id: id, season: 2026, week: week,
                 kickoff: Date(timeIntervalSince1970: TimeInterval(1_789_000_000 + week * 604_800)),
                 awayTeam: away, homeTeam: home, awayScore: a, homeScore: h)
        }
        let games = [
            final("1", 1, "SEA", "SF", 20, 17),
            final("2", 2, "LA", "SEA", 10, 10),
            final("3", 3, "SEA", "ARI", 7, 21),
            Game(id: "4", season: 2026, week: 4, kickoff: nil, awayTeam: "SF", homeTeam: "SEA"),
        ]
        let table = StandingsRow.build(from: games, teams: ["SEA", "SF", "LA", "ARI"])
        let seattle = table["SEA"]!
        XCTAssertEqual(seattle.record, "1-1-1")
        XCTAssertEqual(seattle.differential, 37 - 48)
        XCTAssertEqual(seattle.streak, "L1")
        XCTAssertEqual(table["ARI"]!.record, "1-0")
        XCTAssertEqual(table["ARI"]!.streak, "W1")
        XCTAssertEqual(StandingsRow.ordered(Array(table.values)).map(\.team), ["ARI", "LA", "SEA", "SF"])
    }

    // MARK: Profiles, injuries, projections

    func testProfileDecodesTheFeedRow() throws {
        let json = #"""
        [{"player_id":38543,"season":2026,"jersey":11,"birth_date":"2002-02-14","height_in":73,"weight_lb":196,
          "college":"Ohio State","years_exp":3,"draft_year":2023,"draft_round":1,"draft_pick":20,"draft_team":"SEA",
          "contract_apy":42.15,"contract_cap_pct":0.14,"contract_years":4,"contract_year_signed":2026,
          "off_snaps":150,"def_snaps":0,"off_snap_pct":0.91,"def_snap_pct":null,
          "injury_week":3,"injury_status":"Questionable","injury":"Ankle","practice_status":"Limited",
          "updated_at":"2026-09-26T18:54:32.1+00:00","unknown_column":1}]
        """#
        let profile = try XCTUnwrap(try JSONDecoder.statScout.decode([PlayerProfile].self, from: Data(json.utf8)).first)
        XCTAssertEqual(profile.sizeLabel, "6-1, 196")
        XCTAssertEqual(profile.draftLabel, "2023 R1 #20")
        XCTAssertEqual(profile.contractLabel, "$42.1M/yr")
        let september = ISO8601DateFormatter().date(from: "2026-09-26T00:00:00Z")!
        XCTAssertEqual(profile.age(on: september), 24)
        XCTAssertNil(profile.defenseSnapShare)
    }

    func testInjuryBadgeOnlyForAReportAboutAnUnplayedWeek() {
        var profile = PlayerProfile(playerId: 1, season: 2026)
        profile.injuryWeek = 3
        profile.injuryStatus = "Out"
        profile.injury = "Hamstring"
        XCTAssertEqual(InjuryReport.current(from: profile, upcomingWeek: 3)?.status, "Out")
        XCTAssertNil(InjuryReport.current(from: profile, upcomingWeek: 4), "last week's report")
        profile.injuryStatus = nil
        XCTAssertNil(InjuryReport.current(from: profile, upcomingWeek: 3), "practice-only line")
        profile.injuryStatus = "Questionable"
        XCTAssertEqual(InjuryReport.current(from: profile, upcomingWeek: 3)?.shortStatus, "Q")
    }

    func testProjectionLabelsTheFavourite() throws {
        let json = #"[{"game_id":"g","home_margin":-10.8,"home_win_prob":0.211},{"game_id":"h","home_margin":0.4,"home_win_prob":0.51}]"#
        let rows = try JSONDecoder.statScout.decode([GameProjection].self, from: Data(json.utf8))
        XCTAssertEqual(rows[0].label(home: "WAS", away: "SEA"), "SEA by 11.0")
        XCTAssertEqual(rows[0].winProbability(for: "SEA", home: "WAS"), 0.789, accuracy: 0.0001)
        XCTAssertEqual(rows[1].label(home: "WAS", away: "SEA"), "Toss-up")
    }

    func testTeamRatingDecodesAndSigns() throws {
        let json = #"[{"season":2026,"team":"SEA","rank":1,"games":2,"through_week":3,"rating":8.71,"offense":3.09,"defense":5.62,"schedule":-0.08,"prior_weight":0.714,"wins":2,"losses":0,"ties":0,"points_for":44,"points_against":17,"updated_at":"2026-09-26T18:54:32+00:00"}]"#
        let rating = try XCTUnwrap(try JSONDecoder.statScout.decode([TeamRating].self, from: Data(json.utf8)).first)
        XCTAssertEqual(TeamRating.signed(rating.rating), "+8.7")
        XCTAssertEqual(TeamRating.signed(-0.04), "0.0")
        XCTAssertEqual(TeamRating.signed(-2.37), "-2.4")
    }

    // MARK: View model wiring

    @MainActor
    func testDefendersQualifyOnSnapShareAndBoardsCarryVolume() async {
        let regular = player(1, type: "def", metrics: [metric("Tackles", "12", 90, .defense, qualified: true)],
                             stats: [StandardStat(id: "g", label: "G", value: "3")])
        let gunner = player(2, type: "def", metrics: [metric("Tackles", "2", 30, .defense, qualified: true)])
        var regularProfile = PlayerProfile(playerId: 1, season: StatScoutSeason.current)
        regularProfile.defenseSnapShare = 0.94
        regularProfile.defenseSnaps = 180
        var gunnerProfile = PlayerProfile(playerId: 2, season: StatScoutSeason.current)
        gunnerProfile.defenseSnapShare = 0.05
        gunnerProfile.defenseSnaps = 9
        let provider = EnrichedProvider(players: [regular, gunner], profiles: [regularProfile, gunnerProfile])
        let vm = DashboardViewModel(provider: provider)
        await vm.load()
        vm.selectedPosition = .defense
        vm.qualifierLevel = .qualified

        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1])
        XCTAssertEqual(vm.volumeCaption(for: regular, category: .defense), "180 snaps")
        vm.qualifierLevel = .all
        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1, 2])
    }

    @MainActor
    func testQualificationIsPerMetric() async {
        let receiver = player(1, metrics: [
            metric("EPA/Tgt", "0.5", 90, .receiving, qualified: true),
            metric("Separation", "3.1", 99, .receiving, qualified: false),
        ])
        let vm = DashboardViewModel(provider: MockProvider(players: [receiver]))
        await vm.load()
        vm.selectedPosition = .wr
        vm.qualifierLevel = .qualified
        vm.setUserSortMetric("Separation")
        XCTAssertTrue(vm.leaderboard.isEmpty, "qualified for EPA/Tgt is not qualified for Separation")
        vm.setUserSortMetric("EPA/Tgt")
        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1])
    }
}

private struct EnrichedProvider: StatcastProviding, @unchecked Sendable {
    let players: [Player]
    let profiles: [PlayerProfile]

    func fetchPlayers() async throws -> [Player] { players }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { players }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] { profiles }
}
