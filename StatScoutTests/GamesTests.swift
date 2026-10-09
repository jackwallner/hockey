import XCTest
@testable import Hockey_StatScout

final class GamesTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// A moment in the phone's own calendar, which is what GameDay groups by.
    private func local(_ month: Int, _ day: Int, _ hour: Int = 19, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func game(_ id: String, kickoff: Date, away: String = "SEA", home: String = "EDM",
                      awayScore: Int? = nil, homeScore: Int? = nil, overtime: Bool = false) -> Game {
        Game(id: id, season: 2026, week: 1, kickoff: kickoff, awayTeam: away, homeTeam: home,
             awayScore: awayScore, homeScore: homeScore, overtime: overtime)
    }

    func testDecodesPublishedRow() throws {
        let json = """
        [{"game_id":"2026020012","season":2026,"season_type":"REG","game_type":"REG","week":1,
          "game_date":"2026-10-08","kickoff_at":"2026-10-09T02:00:00+00:00","away_team":"SEA","home_team":"EDM",
          "away_score":3,"home_score":4,"overtime":true,"stadium":"Rogers Place","synced_at":"2026-10-09T05:37:56.93+00:00"}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.statScout.decode([Game].self, from: json)
        let game = try XCTUnwrap(decoded.first)
        XCTAssertTrue(game.isFinal)
        XCTAssertEqual(game.resultLine(for: "EDM"), "W 4-3 OT")
        XCTAssertEqual(game.resultLine(for: "SEA"), "L 3-4 OT")
        XCTAssertEqual(game.result(for: "EDM"), "W")
        XCTAssertEqual(game.result(for: "SEA"), "OTL", "an overtime loss keeps its own word for the standings")
        XCTAssertEqual(game.matchupLabel(for: "SEA"), "at EDM")
        XCTAssertEqual(game.matchupLabel(for: "EDM"), "vs SEA")
        XCTAssertEqual(game.kickoff, date("2026-10-09T02:00:00Z"))
        XCTAssertEqual(game.roundLabel, "Regular Season")
    }

    func testRegulationLossIsAPlainLoss() {
        let final = game("a", kickoff: date("2026-10-09T02:00:00Z"), awayScore: 1, homeScore: 5)
        XCTAssertEqual(final.result(for: "SEA"), "L")
        XCTAssertEqual(final.resultLine(for: "SEA"), "L 1-5")
        XCTAssertNil(game("b", kickoff: date("2026-10-09T02:00:00Z")).result(for: "SEA"))
    }

    func testPlayoffRoundsGetTheirOwnNames() {
        XCTAssertEqual(GameDay.roundLabel(gameType: "R1"), "Round 1")
        XCTAssertEqual(GameDay.roundLabel(gameType: "R2"), "Round 2")
        XCTAssertEqual(GameDay.roundLabel(gameType: "CF"), "Conference Final")
        XCTAssertEqual(GameDay.roundLabel(gameType: "SCF"), "Stanley Cup Final")
        XCTAssertEqual(GameDay.roundLabel(gameType: "REG"), "Regular Season")
    }

    func testStatusWithoutLiveScores() {
        let upcoming = game("a", kickoff: date("2026-10-09T02:00:00Z"))
        XCTAssertEqual(upcoming.status(now: date("2026-10-09T01:00:00Z")), .upcoming)
        XCTAssertEqual(upcoming.status(now: date("2026-10-09T04:00:00Z")), .inProgress)
        XCTAssertEqual(upcoming.status(now: date("2026-10-09T06:00:00Z")), .awaitingScore)
        let final = game("b", kickoff: date("2026-10-09T02:00:00Z"), awayScore: 3, homeScore: 1)
        XCTAssertEqual(final.status(now: date("2026-10-09T04:00:00Z")), .final)
    }

    // MARK: - Game days

    func testDayLabelsAreRelativeNearTodayAndDatedFartherOut() {
        let now = local(10, 8, 12)
        func label(_ month: Int, _ day: Int) -> String {
            GameDay(date: calendar.startOfDay(for: local(month, day)), phase: .regular).label(now: now)
        }
        XCTAssertEqual(label(10, 8), "Today")
        XCTAssertEqual(label(10, 7), "Yesterday")
        XCTAssertEqual(label(10, 9), "Tomorrow")
        let dated = label(10, 14)
        XCTAssertTrue(dated.contains("Oct"), dated)
        XCTAssertTrue(dated.contains("14"), dated)
        XCTAssertFalse(dated.contains("Week"), dated)
    }

    func testGamesGroupByDateNotByWeek() {
        let games = [
            game("a", kickoff: local(10, 8, 19)),
            game("b", kickoff: local(10, 8, 22), away: "VAN", home: "LAK"),
            game("c", kickoff: local(10, 10, 19)),
            game("d", kickoff: local(10, 7, 19)),
        ]
        let days = GameDay.days(in: games)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days.map(\.date), days.map(\.date).sorted())
        let oct8 = days[1]
        XCTAssertEqual(Set(oct8.games(from: games).map(\.id)), ["a", "b"])
        XCTAssertEqual(days[0].games(from: games).map(\.id), ["d"])
    }

    func testPlayoffGamesOnTheSameNightAreTheirOwnDay() {
        let regular = game("r", kickoff: local(4, 15, 19))
        let playoff = Game(id: "p", season: 2026, seasonPhase: .playoffs, gameType: "R1", week: 28,
                           kickoff: local(4, 15, 19), awayTeam: "SEA", homeTeam: "EDM")
        let days = GameDay.days(in: [regular, playoff])
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(playoff.roundLabel, "Round 1")
    }

    func testCurrentDayHoldsYesterdayUntilAfternoonIfNothingHasStarted() {
        let games = [
            game("y", kickoff: local(10, 7, 19)),
            game("t", kickoff: local(10, 8, 19)),
            game("n", kickoff: local(10, 10, 19)),
        ]
        func day(_ now: Date) -> Date? { GameDay.current(in: games, now: now)?.date }
        let oct7 = calendar.startOfDay(for: local(10, 7))
        let oct8 = calendar.startOfDay(for: local(10, 8))
        let oct10 = calendar.startOfDay(for: local(10, 10))

        // Morning of Oct 8, nothing started: last night's finals are the story.
        XCTAssertEqual(day(local(10, 8, 9)), oct7)
        // Afternoon: tonight's slate takes over.
        XCTAssertEqual(day(local(10, 8, 15)), oct8)
        // Puck drop has passed, whatever the hour.
        XCTAssertEqual(day(local(10, 8, 19) + 600), oct8)
        // No games today: the most recent day with games.
        XCTAssertEqual(day(local(10, 9, 12)), oct8)
        // Before the season: the first night. After it: the last.
        XCTAssertEqual(day(local(9, 1, 12)), oct7)
        XCTAssertEqual(day(local(11, 1, 12)), oct10)
        XCTAssertNil(GameDay.current(in: [], now: local(10, 8)))
    }

    @MainActor
    func testTeamRecordCountsRegularSeasonFinalsThroughAGame() async {
        let g1 = game("g1", kickoff: date("2026-10-09T02:00:00Z"), away: "SEA", home: "EDM", awayScore: 3, homeScore: 4)
        let g2 = game("g2", kickoff: date("2026-10-11T02:00:00Z"), away: "VAN", home: "SEA", awayScore: 2, homeScore: 3, overtime: true)
        let g3 = game("g3", kickoff: date("2026-10-13T02:00:00Z"), away: "SEA", home: "CGY", awayScore: 2, homeScore: 3, overtime: true)
        let g4 = game("g4", kickoff: date("2026-10-15T02:00:00Z"), away: "SEA", home: "LAK")
        let model = DashboardViewModel(provider: GamesProvider(games: [g4, g1, g3, g2]))
        await model.loadGames(force: true)
        XCTAssertEqual(model.record(forTeam: "SEA"), "1-1-1")
        XCTAssertEqual(model.record(forTeam: "SEA", through: g1), "0-1-0")
        XCTAssertEqual(model.record(forTeam: "VAN"), "0-0-1")
        XCTAssertEqual(model.record(forTeam: "EDM"), "1-0-0")
        XCTAssertNil(model.record(forTeam: "LAK"))
        XCTAssertEqual(model.schedule(forTeam: "SEA").map(\.id), ["g1", "g2", "g3", "g4"])
    }

    func testSlateOrderPutsLiveFirstThenFinalsThenUpcoming() {
        let now = date("2026-10-09T04:00:00Z")
        let slate = Game.slateOrder([
            game("late", kickoff: date("2026-10-09T05:00:00Z")),
            game("final", kickoff: date("2026-10-09T01:00:00Z"), awayScore: 1, homeScore: 2),
            game("live", kickoff: date("2026-10-09T02:00:00Z")),
        ], now: now)
        XCTAssertEqual(slate.map(\.id), ["live", "final", "late"])
    }

    // MARK: - Box score

    func testBoxScoreSummariesReadSkaterAndGoalieLines() throws {
        let json = """
        [{"player_id":1,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-10-08","player_type":"f","team":"SEA",
          "metrics":{"goals":1,"assists":1,"points":2,"shots_on_goal":4,"shot_attempts":7,"ixg":0.62,"toi_seconds":1182}},
         {"player_id":2,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-10-08","player_type":"f","team":"SEA",
          "metrics":{"goals":0,"assists":0,"shots_on_goal":2,"toi_seconds":900}},
         {"player_id":3,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-10-08","player_type":"g","team":"EDM",
          "metrics":{"shots_against":30,"saves":28,"goals_against":2,"xga":2.41,"toi_seconds":3600}}]
        """.data(using: .utf8)!
        let logs = try JSONDecoder.statScout.decode([PlayerGameLog].self, from: json)
        XCTAssertEqual(logs.first?.gameId, "g")
        let box = GameBoxScore(logs: logs)
        XCTAssertFalse(box.isEmpty)
        XCTAssertEqual(box.lines(for: "SEA").count, 2)
        XCTAssertEqual(box.lines(for: "EDM").map(\.playerId), [3])

        let scorer = try XCTUnwrap(box.lines.first { $0.playerId == 1 })
        XCTAssertEqual(GameBoxScore.summary(scorer), "1 G, 1 A, 4 SOG, 0.62 ixG, 19:42 TOI")
        let quiet = try XCTUnwrap(box.lines.first { $0.playerId == 2 })
        XCTAssertEqual(GameBoxScore.summary(quiet), "0 P, 2 SOG, 15:00 TOI")
        let goalie = try XCTUnwrap(box.lines.first { $0.playerId == 3 })
        XCTAssertTrue(goalie.isGoalie)
        XCTAssertEqual(GameBoxScore.summary(goalie), "28 saves on 30 shots, 2 GA, 2.41 xGA")
    }

    // MARK: - Game detail

    func testGameDetailDecodesTheXGRaceAndPlayerLines() throws {
        let json = """
        [{"game_id":"2026020012","away_team":"SEA","home_team":"EDM",
          "team_stats":{"away":{"xg":{"value":2.41,"pct":71},"sog":28,"hd_chances":null},
                        "home":{"xg":{"value":3.07,"pct":88},"sog":33}},
          "players":[{"role":"skater","player_id":11,"name":"A. Winger","team":"SEA","position":"L","toi":1182,
                      "goals":1,"assists":0,"points":1,"sog":4,"shot_attempts":7,"hd_shots":2,
                      "ixg":{"value":0.62,"pct":84},"gax":{"value":0.38,"pct":70},"ixg_per_60":{"value":1.9,"pct":null}},
                     {"role":"skater","player_id":12,"name":"B. Center","team":"SEA","position":"C","toi":1260,
                      "goals":0,"assists":1,"points":1,"sog":5,"ixg":{"value":0.91,"pct":93}},
                     {"role":"goalie","player_id":31,"name":"C. Keeper","team":"EDM","position":"G","toi":3600,
                      "shots_against":28,"saves":26,"goals_against":2,
                      "xga":{"value":2.41,"pct":40},"gsax":{"value":0.41,"pct":58},"sv_pct":{"value":0.929,"pct":66}},
                     {"role":"kicker","player_id":1,"team":"SEA"}],
          "win_probability":[[0,0,0,0,0],[600,0.31,0.12,0,0],[3600,2.41,3.07,3,4]],
          "big_plays":[{"period":2,"clock":"12:34","team":"EDM","description":"Snap shot, slot, rebound","xg":0.44,
                        "result":"GOAL","player_id":99,"shooter":"D. Sniper"}]}]
        """.data(using: .utf8)!
        let detail = try XCTUnwrap(JSONDecoder.statScout.decode([GameDetail].self, from: json).first)
        XCTAssertEqual(detail.stats(for: "SEA")["xg"]?.value, 2.41)
        XCTAssertEqual(detail.stats(for: "EDM")["xg"]?.percentile, 88)
        XCTAssertEqual(detail.stats(for: "EDM")["sog"]?.value, 33)
        XCTAssertNil(detail.stats(for: "EDM")["sog"]?.percentile)
        XCTAssertNil(detail.away["hd_chances"], "a null team stat is dropped, not decoded as zero")

        XCTAssertEqual(detail.players.count, 3, "an unknown role is dropped")
        XCTAssertEqual(detail.players(.skater).map(\.playerId), [12, 11], "skaters rank by ixG")
        XCTAssertEqual(detail.players(.skater, team: "SEA").count, 2)
        XCTAssertTrue(detail.players(.skater, team: "EDM").isEmpty)
        let winger = try XCTUnwrap(detail.players.first { $0.playerId == 11 })
        XCTAssertEqual(winger.toiLabel, "19:42")
        XCTAssertNil(winger.ixgPer60?.percentile)
        let goalie = try XCTUnwrap(detail.players(.goalie).first)
        XCTAssertEqual(goalie.svPct?.value, 0.929)
        XCTAssertEqual(goalie.gsax?.value, 0.41)

        XCTAssertEqual(detail.xgRace.count, 3)
        let last = try XCTUnwrap(detail.xgRace.last)
        XCTAssertEqual(last.elapsed, 3600)
        XCTAssertEqual(last.awayXG, 2.41)
        XCTAssertEqual(last.homeXG, 3.07)
        XCTAssertEqual(last.awayGoals, 3)
        XCTAssertEqual(last.homeGoals, 4)

        let play = try XCTUnwrap(detail.bigPlays.first)
        XCTAssertTrue(play.isGoal)
        XCTAssertEqual(play.clock, "12:34")
        XCTAssertEqual(play.shooter, "D. Sniper")
    }

    func testRecentFormWindowLabelIsADateRange() throws {
        let json = """
        {"player_id":1,"season":2026,"player_type":"f","window_weeks":2,"as_of":"2026-10-07","games":1,"plays":18,
         "metrics":{},"prior_metrics":{},"delta":{}}
        """.data(using: .utf8)!
        let form = try JSONDecoder.statScout.decode(RecentForm.self, from: json)
        let label = try XCTUnwrap(form.weekRangeLabel)
        XCTAssertEqual(label, "Sep 24 - Oct 7")
        XCTAssertFalse(label.contains("Week"))
        XCTAssertTrue(form.isSmallSample)
        XCTAssertTrue(form.isSmallSample(minimumGames: 2))
        XCTAssertTrue(form.isSmallSample(minimumGames: 1), "18 minutes is under the skater floor")
    }

    func testRecentFormWithoutAnAnchorHasNoRangeLabel() throws {
        let json = """
        {"player_id":1,"season":2026,"player_type":"g","window_weeks":4,"games":3,"plays":180,
         "metrics":{"sv_pct":0.915},"prior_metrics":{},"delta":{}}
        """.data(using: .utf8)!
        let form = try JSONDecoder.statScout.decode(RecentForm.self, from: json)
        XCTAssertNil(form.weekRangeLabel)
        XCTAssertFalse(form.isSmallSample)
        XCTAssertEqual(form.metrics["sv_pct"], 0.915)
    }

    func testFreshnessReportsAdvancedPending() throws {
        let json = """
        {"status":"degraded","refresh_id":"r","max_game_date":"2026-10-08","max_week":1,
         "observed_games":10,"expected_games":10,"shots_status":"pending","summary_status":"ready"}
        """.data(using: .utf8)!
        let freshness = try JSONDecoder.statScout.decode(DataFreshness.self, from: json)
        XCTAssertTrue(freshness.isAdvancedPending)
        let roundTrip = try JSONDecoder.statScout.decode(
            DataFreshness.self,
            from: JSONEncoder.statScout.encode(freshness.replacing(isCached: true))
        )
        XCTAssertEqual(roundTrip.shotsStatus, "pending")
        XCTAssertEqual(roundTrip.summaryStatus, "ready")
    }
}

private struct GamesProvider: StatcastProviding {
    let games: [Game]
    func fetchGames(season: Int) async throws -> [Game] { games }
    func fetchPlayers() async throws -> [Player] { [] }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Date) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}
