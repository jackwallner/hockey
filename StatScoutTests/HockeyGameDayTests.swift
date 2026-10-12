import XCTest
@testable import Hockey_StatScout

/// Live scores, overtime labels and the scoring summary: the parts of a game a
/// hockey fan reads first.
final class HockeyGameDayTests: XCTestCase {
    private func final(phase: SeasonPhase = .regular, overtime: Bool, period: String?, away: Int = 3, home: Int = 2) -> Game {
        Game(id: "g", season: 2026, seasonPhase: phase, gameType: phase == .regular ? "REG" : "R1", week: 1,
             kickoff: Date(timeIntervalSince1970: 1_791_000_000), awayTeam: "EDM", homeTeam: "SJS",
             awayScore: away, homeScore: home, overtime: overtime, finalPeriod: period)
    }

    func testFinalLabelsNameTheExtraPeriod() {
        XCTAssertEqual(final(overtime: false, period: nil).finalLabel, "Final")
        XCTAssertEqual(final(overtime: true, period: "SO").finalLabel, "Final/SO")
        XCTAssertEqual(final(overtime: true, period: nil).finalLabel, "Final/OT", "rows synced before the column read OT")
        XCTAssertEqual(final(phase: .playoffs, overtime: true, period: "2OT").finalLabel, "Final/2OT")
        XCTAssertEqual(final(overtime: true, period: "SO").resultLine(for: "SJS"), "L 2-3 SO")
    }

    func testOnlyARegularSeasonOvertimeLossIsAnOTL() {
        XCTAssertEqual(final(overtime: true, period: "OT").result(for: "SJS"), "OTL")
        XCTAssertEqual(final(phase: .playoffs, overtime: true, period: "OT").result(for: "SJS"), "L")
    }

    func testScoreboardParsesGamesUnderWay() throws {
        let json = #"""
        {"games":[
          {"id":2026020090,"gameState":"LIVE","period":2,"periodDescriptor":{"number":2,"periodType":"REG"},
           "clock":{"timeRemaining":"07:41","inIntermission":false},
           "awayTeam":{"abbrev":"EDM","score":2,"sog":17},"homeTeam":{"abbrev":"CGY","score":1,"sog":12}},
          {"id":2026020091,"gameState":"LIVE","period":1,"periodDescriptor":{"number":1,"periodType":"REG"},
           "clock":{"timeRemaining":"00:00","inIntermission":true},
           "awayTeam":{"score":0,"sog":8},"homeTeam":{"score":0,"sog":11}},
          {"id":2026020092,"gameState":"FUT","awayTeam":{},"homeTeam":{}},
          {"id":2026020093,"gameState":"OFF","period":5,"periodDescriptor":{"number":5,"periodType":"SO"},
           "awayTeam":{"score":3,"sog":30},"homeTeam":{"score":2,"sog":28}}
        ]}
        """#
        let scores = Dictionary(uniqueKeysWithValues: LiveScore.parse(Data(json.utf8)).map { ($0.gameId, $0) })
        XCTAssertEqual(scores.count, 3, "a game not yet started has no score")
        let live = try XCTUnwrap(scores["2026020090"])
        XCTAssertEqual(live.clockLabel, "2nd 7:41")
        XCTAssertEqual(live.awayScore, 2)
        XCTAssertEqual(live.homeShots, 12)
        XCTAssertTrue(live.isUnderway)
        XCTAssertEqual(scores["2026020091"]?.clockLabel, "1st INT")
        XCTAssertEqual(scores["2026020093"]?.clockLabel, "Final/SO")
        XCTAssertTrue(LiveScore.parse(Data("nonsense".utf8)).isEmpty)
    }

    func testScoreboardDateIsTheLeaguesEasternDay() throws {
        let date = try XCTUnwrap(DataFreshness.parseDate("2026-10-11"))
        XCTAssertEqual(LiveScoreClient.dateKey(date), "2026-10-11")
    }

    func testGoalLinesReadLikeAScoringSummary() throws {
        let json = #"""
        [{"period":3,"clock":"3:13","team":"EDM","description":"Slap shot","xg":0.06,"result":"GOAL",
          "player_id":1,"shooter":"Vasily Podkolzin","assists":["Connor McDavid","James van Riemsdyk"],
          "strength":"PP","score":[2,0],"goal_number":5},
         {"period":3,"clock":"5:40","team":"EDM","description":"Backhand","xg":0.1,"result":"GOAL",
          "player_id":2,"shooter":"Alex Formenton","assists":[]},
         {"period":3,"clock":"9:18","team":"EDM","description":"Wrist shot","xg":0.19,"result":"MISS",
          "player_id":3,"shooter":"Kasperi Kapanen"},
         {"period":1,"clock":"1:00","team":"EDM","description":"Wrist shot","xg":0.2,"result":"GOAL","player_id":4}]
        """#
        let plays = try JSONDecoder().decode([GameDetail.BigPlay].self, from: Data(json.utf8))
        XCTAssertEqual(plays[0].assistLine, "McDavid, van Riemsdyk")
        XCTAssertEqual(plays[0].strength, "PP")
        XCTAssertEqual(plays[0].score, [2, 0])
        XCTAssertEqual(plays[0].goalNumber, 5)
        XCTAssertEqual(plays[1].assistLine, "Unassisted")
        XCTAssertNil(plays[2].assistLine)
        XCTAssertEqual(plays[2].resultLabel, "Missed")
        XCTAssertNil(plays[3].assistLine, "older rows without assists say nothing rather than Unassisted")
        let brothers = #"[{"period":1,"clock":"16:47","team":"WSH","description":"Snap shot","xg":0.16,"result":"GOAL","assists":["Aliaksei Protas","Ilya Protas"]}]"#
        let protas = try JSONDecoder().decode([GameDetail.BigPlay].self, from: Data(brothers.utf8))
        XCTAssertEqual(protas[0].assistLine, "A. Protas, I. Protas")
    }

    func testExpectedGoalsLabelReadsAwayFirst() {
        XCTAssertEqual(GameXG(away: 2.873, home: 1.204).label, "xG 2.9-1.2")
    }

    func testSeasonSummaryAddsSpecialTeamsAndRanksTheLeague() throws {
        func game(_ id: String, _ away: String, _ home: String, _ a: Int, _ h: Int) -> Game {
            Game(id: id, season: 2026, week: 1, kickoff: Date(timeIntervalSince1970: 1_791_000_000),
                 awayTeam: away, homeTeam: home, awayScore: a, homeScore: h)
        }
        let games = [game("1", "EDM", "SJS", 3, 1), game("2", "SJS", "VAN", 2, 4)]
        let xg = [
            "1": GameXG(away: 2.0, home: 1.0, awayPowerPlayGoals: 1, awayPowerPlays: 4,
                        homePowerPlayGoals: 0, homePowerPlays: 2, awayShots: 30, homeShots: 20),
        ]
        let table = TeamSeasonSummary.build(games: games, xg: xg, teams: ["EDM", "SJS", "VAN"])
        let edm = try XCTUnwrap(table["EDM"])
        XCTAssertEqual(edm.goalsFor.value, 3)
        XCTAssertEqual(try XCTUnwrap(edm.powerPlay).value, 0.25)
        XCTAssertEqual(try XCTUnwrap(edm.penaltyKill).value, 1.0)
        XCTAssertEqual(try XCTUnwrap(edm.expectedGoalsShare).value, 2.0 / 3.0, accuracy: 0.0001)
        let sjs = try XCTUnwrap(table["SJS"])
        XCTAssertEqual(sjs.games, 2)
        XCTAssertEqual(try XCTUnwrap(sjs.penaltyKill).value, 0.75)
        XCTAssertEqual(edm.goalsAgainst.rank, 1, "fewest against ranks first")
        XCTAssertEqual(sjs.goalsAgainst.rank, 3)
        XCTAssertNil(table["VAN"]?.powerPlay, "no breakdown, no special teams")
        XCTAssertEqual(TeamSeasonSummary.ordinal(22), "22nd")
    }
}
