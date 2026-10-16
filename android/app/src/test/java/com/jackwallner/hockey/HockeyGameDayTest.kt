package com.jackwallner.hockey

import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.GameXG
import com.jackwallner.hockey.model.LiveScore
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.TeamSeasonSummary
import com.jackwallner.hockey.model.parseDate
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Live scores, overtime labels and the scoring summary: the parts of a game a hockey fan reads first. */
class HockeyGameDayTest {
    private val kickoff = Instant.ofEpochSecond(1_791_000_000)

    private fun final(phase: SeasonPhase = SeasonPhase.REGULAR, overtime: Boolean, period: String?, away: Int = 3, home: Int = 2) =
        Game(
            id = "g", season = 2026, seasonPhase = phase, gameType = if (phase == SeasonPhase.REGULAR) "REG" else "R1", week = 1,
            kickoff = kickoff, awayTeam = "EDM", homeTeam = "SJS", awayScore = away, homeScore = home,
            overtime = overtime, finalPeriod = period,
        )

    private fun plays(json: String) = (Json.parseToJsonElement(json) as JsonArray).map { GameDetail.BigPlay.fromJson(it as JsonObject) }

    @Test
    fun finalLabelsNameTheExtraPeriod() {
        assertEquals("Final", final(overtime = false, period = null).finalLabel)
        assertEquals("Final/SO", final(overtime = true, period = "SO").finalLabel)
        assertEquals("rows synced before the column read OT", "Final/OT", final(overtime = true, period = null).finalLabel)
        assertEquals("Final/2OT", final(SeasonPhase.PLAYOFFS, overtime = true, period = "2OT").finalLabel)
        assertEquals("L 2-3 SO", final(overtime = true, period = "SO").resultLine("SJS"))
    }

    @Test
    fun onlyARegularSeasonOvertimeLossIsAnOTL() {
        assertEquals("OTL", final(overtime = true, period = "OT").result("SJS"))
        assertEquals("L", final(SeasonPhase.PLAYOFFS, overtime = true, period = "OT").result("SJS"))
    }

    @Test
    fun scoreboardParsesGamesUnderWay() {
        val json = """
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
        """.trimIndent()
        val scores = LiveScore.parse(json).associateBy { it.gameId }
        assertEquals("a game not yet started has no score", 3, scores.size)
        val live = scores.getValue("2026020090")
        assertEquals("2nd 7:41", live.clockLabel)
        assertEquals(2, live.awayScore)
        assertEquals(12, live.homeShots)
        assertTrue(live.isUnderway)
        assertEquals("1st INT", scores["2026020091"]?.clockLabel)
        assertEquals("Final/SO", scores["2026020093"]?.clockLabel)
        assertTrue(LiveScore.parse("nonsense").isEmpty())
    }

    @Test
    fun scoreboardDateIsTheLeaguesEasternDay() {
        val date = parseDate("2026-10-11")
        assertNotNull(date)
        assertEquals("2026-10-11", LiveScore.dateKey(date!!))
    }

    @Test
    fun goalLinesReadLikeAScoringSummary() {
        val list = plays(
            """
            [{"period":3,"clock":"3:13","team":"EDM","description":"Slap shot","xg":0.06,"result":"GOAL",
              "player_id":1,"shooter":"Vasily Podkolzin","assists":["Connor McDavid","James van Riemsdyk"],
              "strength":"PP","score":[2,0],"goal_number":5},
             {"period":3,"clock":"5:40","team":"EDM","description":"Backhand","xg":0.1,"result":"GOAL",
              "player_id":2,"shooter":"Alex Formenton","assists":[]},
             {"period":3,"clock":"9:18","team":"EDM","description":"Wrist shot","xg":0.19,"result":"MISS",
              "player_id":3,"shooter":"Kasperi Kapanen"},
             {"period":1,"clock":"1:00","team":"EDM","description":"Wrist shot","xg":0.2,"result":"GOAL","player_id":4}]
            """.trimIndent(),
        )
        assertEquals("McDavid, van Riemsdyk", list[0].assistLine)
        assertEquals("PP", list[0].strength)
        assertEquals(listOf(2, 0), list[0].score)
        assertEquals(5, list[0].goalNumber)
        assertEquals("Unassisted", list[1].assistLine)
        assertNull(list[2].assistLine)
        assertEquals("Missed", list[2].resultLabel)
        assertNull("older rows without assists say nothing rather than Unassisted", list[3].assistLine)
        val protas = plays("""[{"period":1,"clock":"16:47","team":"WSH","description":"Snap shot","xg":0.16,"result":"GOAL","assists":["Aliaksei Protas","Ilya Protas"]}]""")
        assertEquals("A. Protas, I. Protas", protas[0].assistLine)
    }

    @Test
    fun expectedGoalsLabelReadsAwayFirst() {
        assertEquals("xG 2.9-1.2", GameXG(away = 2.873, home = 1.204).label)
    }

    @Test
    fun seasonSummaryAddsSpecialTeamsAndRanksTheLeague() {
        fun game(id: String, away: String, home: String, a: Int, h: Int) =
            Game(id = id, season = 2026, week = 1, kickoff = kickoff, awayTeam = away, homeTeam = home, awayScore = a, homeScore = h)
        val games = listOf(game("1", "EDM", "SJS", 3, 1), game("2", "SJS", "VAN", 2, 4))
        val xg = mapOf(
            "1" to GameXG(
                away = 2.0, home = 1.0, awayPowerPlayGoals = 1, awayPowerPlays = 4,
                homePowerPlayGoals = 0, homePowerPlays = 2, awayShots = 30, homeShots = 20,
            ),
        )
        val table = TeamSeasonSummary.build(games, xg, listOf("EDM", "SJS", "VAN"))
        val edm = table.getValue("EDM")
        assertEquals(3.0, edm.goalsFor.value, 0.0)
        assertEquals(0.25, edm.powerPlay!!.value, 0.0)
        assertEquals(1.0, edm.penaltyKill!!.value, 0.0)
        assertEquals(2.0 / 3.0, edm.expectedGoalsShare!!.value, 0.0001)
        val sjs = table.getValue("SJS")
        assertEquals(2, sjs.games)
        assertEquals(0.75, sjs.penaltyKill!!.value, 0.0)
        assertEquals("fewest against ranks first", 1, edm.goalsAgainst.rank)
        assertEquals(3, sjs.goalsAgainst.rank)
        assertNull("no breakdown, no special teams", table["VAN"]?.powerPlay)
        assertEquals("22nd", TeamSeasonSummary.ordinal(22))
    }
}
