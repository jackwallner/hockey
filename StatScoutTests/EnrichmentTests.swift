import XCTest
@testable import Hockey_StatScout

final class EnrichmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "stats.qualifier")
    }

    private func player(
        _ id: Int,
        type: String = "f",
        team: String = "SEA",
        metrics: [Metric],
        stats: [StandardStat] = []
    ) -> Player {
        Player(
            playerId: id, name: "P\(id)", team: team,
            position: type == "g" ? "G" : type == "d" ? "D" : "C", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: type,
            metrics: metrics, standardStats: stats, games: []
        )
    }

    private func metric(_ label: String, _ value: String, _ pct: Int, _ category: MetricCategory, qualified: Bool? = nil) -> Metric {
        Metric(id: "\(label)-\(pct)-\(value)", label: label, value: value, percentile: pct, category: category, qualified: qualified)
    }

    // MARK: Unranked zero counts

    func testZeroCountingStatIsUnrankedButRatesAndNonZeroCountsAreNot() {
        XCTAssertTrue(metric("G", "0", 47, .scoring).isUnranked)
        XCTAssertTrue(metric("Takeaways", "0", 41, .playDriving).isUnranked)
        XCTAssertTrue(metric("SO", "0", 41, .goaltending).isUnranked)
        XCTAssertFalse(metric("G", "12", 80, .scoring).isUnranked)
        XCTAssertFalse(metric("P/60", "0.00", 50, .scoring).isUnranked, "a rate at zero is a real rank")
        XCTAssertFalse(metric("Sh%", "0.0%", 50, .scoring).isUnranked, "a percentage at zero is a real rank")
        XCTAssertFalse(metric("ixG", "0.0", 50, .shotQuality).isUnranked, "advanced totals keep their rank")
        var standard = metric("PIM", "0", 47, .playDriving)
        standard.rankable = false
        XCTAssertTrue(standard.isUnranked)
    }

    func testOverallPercentileLeavesUnrankedZerosOut() {
        let defenseman = player(1, type: "d", metrics: [
            metric("Blocks", "40", 20, .playDriving),
            metric("Hits", "0", 47, .playDriving),
            metric("Takeaways", "0", 41, .playDriving),
        ])
        XCTAssertEqual(defenseman.overallPercentile, 20)
        XCTAssertEqual(defenseman.headlineMetric?.label, "Blocks")
    }

    // MARK: Standings

    private func final(_ id: String, _ day: Int, _ away: String, _ home: String, _ a: Int, _ h: Int, overtime: Bool = false) -> Game {
        Game(id: id, season: 2026, week: 1,
             kickoff: Date(timeIntervalSince1970: TimeInterval(1_791_000_000 + day * 86_400)),
             awayTeam: away, homeTeam: home, awayScore: a, homeScore: h, overtime: overtime)
    }

    func testStandingsCountRecordsPointsDifferentialAndStreak() {
        let games = [
            final("1", 1, "SEA", "VAN", 4, 2),
            final("2", 2, "EDM", "SEA", 3, 2, overtime: true),
            final("3", 3, "SEA", "CGY", 1, 4),
            Game(id: "4", season: 2026, week: 1, kickoff: nil, awayTeam: "VAN", homeTeam: "SEA"),
        ]
        let table = StandingsRow.build(from: games, teams: ["SEA", "VAN", "EDM", "CGY"])
        let seattle = table["SEA"]!
        XCTAssertEqual(seattle.record, "1-1-1", "wins, losses, then overtime losses")
        XCTAssertEqual(seattle.otLosses, 1)
        XCTAssertEqual(seattle.points, 3, "two for a win, one for an overtime loss")
        XCTAssertEqual(seattle.games, 3)
        XCTAssertEqual(seattle.goalsFor, 7)
        XCTAssertEqual(seattle.goalsAgainst, 9)
        XCTAssertEqual(seattle.differential, -2)
        XCTAssertEqual(seattle.streak, "L2", "an overtime loss is a loss in the streak")
        XCTAssertEqual(table["CGY"]!.record, "1-0-0")
        XCTAssertEqual(table["CGY"]!.streak, "W1")
        XCTAssertEqual(table["EDM"]!.points, 2)
        XCTAssertEqual(table["VAN"]!.points, 0)
        XCTAssertEqual(table["VAN"]!.record, "0-1-0")
        XCTAssertEqual(
            StandingsRow.ordered(Array(table.values)).map(\.team),
            ["SEA", "CGY", "EDM", "VAN"],
            "points, then points percentage, then goal differential"
        )
    }

    func testDivisionPlaceUsesTheStandingsOrderWithinTheDivision() {
        let pacific = LeagueDivision.pacific.teams
        let games = [
            final("1", 1, "SEA", "VAN", 4, 2),
            final("2", 2, "EDM", "SEA", 3, 2, overtime: true),
            final("3", 3, "CGY", "EDM", 1, 4),
            final("4", 4, "BOS", "TOR", 3, 1),
        ]
        let table = StandingsRow.build(from: games, teams: leagueTeamAbbreviations)
        let seattle = StandingsRow.divisionPlace(of: "SEA", in: table)
        XCTAssertEqual(seattle?.place, 2, "EDM has 4 points, SEA 3, VAN and CGY none")
        XCTAssertEqual(seattle?.division, .pacific)
        XCTAssertEqual(StandingsRow.divisionPlace(of: "EDM", in: table)?.place, 1)
        XCTAssertEqual(StandingsRow.divisionPlace(of: "BOS", in: table)?.division, .atlantic)
        XCTAssertNil(StandingsRow.divisionPlace(of: "ANA", in: table), "a club that has not played has no place")
        XCTAssertNil(StandingsRow.divisionPlace(of: "ZZZ", in: table))
        XCTAssertTrue(pacific.contains("SEA"))
    }

    func testOrdinalsHandleTeensAndSuffixes() {
        let cases = [(1, "1ST"), (2, "2ND"), (3, "3RD"), (4, "4TH"), (8, "8TH"), (11, "11TH"), (12, "12TH"), (21, "21ST"), (22, "22ND")]
        for (number, text) in cases {
            XCTAssertEqual(StandingsRow.ordinal(number), text)
        }
    }

    func testStandingsLeavePlayoffGamesAndUnknownClubsOut() {
        let playoff = Game(id: "p", season: 2026, seasonPhase: .playoffs, gameType: "R1", week: 28,
                           kickoff: Date(timeIntervalSince1970: 1_791_000_000), awayTeam: "SEA", homeTeam: "EDM",
                           awayScore: 1, homeScore: 0)
        let table = StandingsRow.build(from: [playoff, final("x", 1, "SEA", "ZZZ", 2, 1)], teams: ["SEA", "EDM"])
        XCTAssertEqual(table["SEA"]!.record, "1-0-0")
        XCTAssertEqual(table["EDM"]!.games, 0)
        XCTAssertEqual(table["EDM"]!.winPercentage, 0)
        XCTAssertNil(table["ZZZ"])
        XCTAssertEqual(table["SEA"]!.winPercentage, 1.0, accuracy: 0.0001)
    }

    // MARK: Profiles, projections, ratings

    func testProfileDecodesTheFeedRow() throws {
        let json = #"""
        [{"player_id":8000001,"season":2026,"jersey":97,"birth_date":"1997-01-13","height_in":73,"weight_lb":194,
          "birthplace":"Fictionville, ON, CAN","years_exp":11,"rookie_season":2015,"draft_year":2015,"draft_round":1,
          "draft_pick":1,"draft_team":"EDM","toi_seconds":126200,"toi_per_gp":1262,"pp_toi_seconds":20000,
          "pk_toi_seconds":2000,"toi_share":0.123,"updated_at":"2026-10-08T18:54:32.1+00:00","unknown_column":1}]
        """#
        let profile = try XCTUnwrap(try JSONDecoder.statScout.decode([PlayerProfile].self, from: Data(json.utf8)).first)
        XCTAssertEqual(profile.jersey, 97)
        XCTAssertEqual(profile.sizeLabel, "6'1\", 194 lb")
        XCTAssertEqual(profile.birthplace, "Fictionville, ON, CAN")
        XCTAssertEqual(profile.draftLabel, "2015 R1 #1")
        XCTAssertEqual(profile.toiPerGameLabel, "21:02")
        XCTAssertEqual(profile.toiSeconds, 126_200)
        XCTAssertEqual(try XCTUnwrap(profile.toiShare), 0.123, accuracy: 0.0001)
        XCTAssertEqual(profile.specialTeamsLabel(games: 100), "3:20 PP · 0:20 PK")
        XCTAssertNil(profile.specialTeamsLabel(games: 0))
        let october = ISO8601DateFormatter().date(from: "2026-10-08T00:00:00Z")!
        XCTAssertEqual(profile.age(on: october), 29)
    }

    func testProfileWithOnlyTheKeyColumnsDecodesAndHidesTheRest() throws {
        let json = #"[{"player_id":8000002,"season":2026,"years_exp":2}]"#
        let profile = try XCTUnwrap(try JSONDecoder.statScout.decode([PlayerProfile].self, from: Data(json.utf8)).first)
        XCTAssertNil(profile.sizeLabel)
        XCTAssertNil(profile.toiPerGameLabel)
        XCTAssertNil(profile.age())
        XCTAssertEqual(profile.draftLabel, "Undrafted")
        XCTAssertNil(PlayerProfile(playerId: 1, season: 2026).draftLabel)
    }

    func testProjectionLabelsTheFavourite() throws {
        let json = #"[{"game_id":"g","home_margin":-0.6,"home_win_prob":0.446},{"game_id":"h","home_margin":0.1,"home_win_prob":0.51}]"#
        let rows = try JSONDecoder.statScout.decode([GameProjection].self, from: Data(json.utf8))
        XCTAssertEqual(rows[0].label(home: "EDM", away: "SEA"), "SEA by 0.6")
        XCTAssertEqual(rows[0].winProbability(for: "SEA", home: "EDM"), 0.554, accuracy: 0.0001)
        XCTAssertEqual(rows[0].winProbability(for: "EDM", home: "EDM"), 0.446, accuracy: 0.0001)
        XCTAssertEqual(rows[1].label(home: "EDM", away: "SEA"), "Toss-up")
    }

    func testTeamRatingDecodesAndSigns() throws {
        let json = #"[{"season":2026,"team":"SEA","rank":1,"games":6,"through_week":2,"rating":0.71,"offense":0.39,"defense":0.32,"schedule":-0.08,"wins":4,"losses":1,"ties":1,"points_for":22,"points_against":14,"updated_at":"2026-10-08T18:54:32+00:00"}]"#
        let rating = try XCTUnwrap(try JSONDecoder.statScout.decode([TeamRating].self, from: Data(json.utf8)).first)
        XCTAssertEqual(rating.ties, 1, "the ties column holds overtime losses")
        XCTAssertEqual(TeamRating.signed(rating.rating), "+0.7")
        XCTAssertEqual(TeamRating.signed(-0.04), "0.0")
        XCTAssertEqual(TeamRating.signed(-0.37), "-0.4")
    }

    // MARK: View model wiring

    @MainActor
    func testQualifiedBoardsHideSmallSamplesAndCarryVolume() async {
        let regular = player(1, type: "d", metrics: [metric("xGF%", "52.0%", 70, .playDriving, qualified: true)],
                             stats: [StandardStat(id: "gp", label: "GP", value: "10"),
                                     StandardStat(id: "toi", label: "TOI/GP", value: "22:00")])
        let cameo = player(2, type: "d", metrics: [metric("xGF%", "70.0%", 99, .playDriving, qualified: false)])
        let provider = EnrichedProvider(players: [regular, cameo], profiles: [])
        let vm = DashboardViewModel(provider: provider)
        await vm.load()
        vm.selectedPosition = .defense
        vm.qualifierLevel = .qualified

        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1])
        XCTAssertEqual(vm.volumeCaption(for: regular, category: .playDriving), "220 min")
        vm.qualifierLevel = .all
        XCTAssertEqual(vm.leaderboard.map(\.playerId), [1, 2], "the small sample sinks below the qualified player")
    }

    @MainActor
    func testProfilesLoadForTheLiveSeasonOnly() async {
        let skater = player(1, metrics: [metric("ixG", "5.0", 70, .shotQuality, qualified: true)])
        var live = PlayerProfile(playerId: 1, season: StatScoutSeason.current)
        live.toiPerGame = 1_200
        let stale = PlayerProfile(playerId: 1, season: StatScoutSeason.current - 1)
        let vm = DashboardViewModel(provider: EnrichedProvider(players: [skater], profiles: [live]))
        await vm.load()
        XCTAssertEqual(vm.profile(for: skater)?.toiPerGameLabel, "20:00")

        let staleVM = DashboardViewModel(provider: EnrichedProvider(players: [skater], profiles: [stale]))
        await staleVM.load()
        XCTAssertNil(staleVM.profile(for: skater), "a profile from another season is not this player's")
    }

    @MainActor
    func testQualificationIsPerMetric() async {
        let winger = player(1, metrics: [
            metric("P/60", "3.1", 90, .scoring, qualified: true),
            metric("ixG/60", "1.1", 99, .shotQuality, qualified: false),
        ])
        let vm = DashboardViewModel(provider: MockProvider(players: [winger]))
        await vm.load()
        vm.selectedPosition = .forward
        vm.qualifierLevel = .qualified
        vm.setUserSortMetric("ixG/60")
        XCTAssertTrue(vm.leaderboard.isEmpty, "qualified for P/60 is not qualified for ixG/60")
        vm.setUserSortMetric("P/60")
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
