package com.jackwallner.hockey

import com.jackwallner.hockey.model.DataFreshness
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameBoxScore
import com.jackwallner.hockey.model.GameDay
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.GameStatus
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.SeasonPhase
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GamesTest {
    private val zone: ZoneId = ZoneId.systemDefault()

    private fun date(iso: String): Instant = Instant.parse(iso)

    /** A moment in the phone's own calendar, which is what GameDay groups by. */
    private fun local(month: Int, day: Int, hour: Int = 19, year: Int = 2026): Instant =
        LocalDateTime.of(year, month, day, hour, 0).atZone(zone).toInstant()

    private fun day(month: Int, day: Int): LocalDate = LocalDate.of(2026, month, day)

    private fun game(
        id: String, kickoff: Instant, away: String = "SEA", home: String = "EDM",
        awayScore: Int? = null, homeScore: Int? = null, overtime: Boolean = false,
    ) = Game(
        id = id, season = 2026, week = 1, kickoff = kickoff, awayTeam = away, homeTeam = home,
        awayScore = awayScore, homeScore = homeScore, overtime = overtime,
    )

    private fun objects(json: String) = (Json.parseToJsonElement(json) as JsonArray).map { it as JsonObject }

    @Test
    fun decodesPublishedRow() {
        val json = """
            [{"game_id":"2026020012","season":2026,"season_type":"REG","game_type":"REG","week":1,
              "game_date":"2026-10-08","kickoff_at":"2026-10-09T02:00:00+00:00","away_team":"SEA","home_team":"EDM",
              "away_score":3,"home_score":4,"overtime":true,"stadium":"Rogers Place","synced_at":"2026-10-09T05:37:56.93+00:00"}]
        """.trimIndent()
        val game = Game.fromJson(objects(json).first())
        assertTrue(game.isFinal)
        assertEquals("W 4-3 OT", game.resultLine("EDM"))
        assertEquals("L 3-4 OT", game.resultLine("SEA"))
        assertEquals("W", game.result("EDM"))
        assertEquals("an overtime loss keeps its own word for the standings", "OTL", game.result("SEA"))
        assertEquals("at EDM", game.matchupLabel("SEA"))
        assertEquals("vs SEA", game.matchupLabel("EDM"))
        assertEquals(date("2026-10-09T02:00:00Z"), game.kickoff)
        assertEquals("Regular Season", game.roundLabel)
    }

    @Test
    fun regulationLossIsAPlainLoss() {
        val final = game("a", date("2026-10-09T02:00:00Z"), awayScore = 1, homeScore = 5)
        assertEquals("L", final.result("SEA"))
        assertEquals("L 1-5", final.resultLine("SEA"))
        assertNull(game("b", date("2026-10-09T02:00:00Z")).result("SEA"))
    }

    @Test
    fun playoffRoundsGetTheirOwnNames() {
        assertEquals("Round 1", GameDay.roundLabel("R1"))
        assertEquals("Round 2", GameDay.roundLabel("R2"))
        assertEquals("Conference Final", GameDay.roundLabel("CF"))
        assertEquals("Stanley Cup Final", GameDay.roundLabel("SCF"))
        assertEquals("Regular Season", GameDay.roundLabel("REG"))
    }

    @Test
    fun statusWithoutLiveScores() {
        val upcoming = game("a", date("2026-10-09T02:00:00Z"))
        assertEquals(GameStatus.UPCOMING, upcoming.status(date("2026-10-09T01:00:00Z")))
        assertEquals(GameStatus.IN_PROGRESS, upcoming.status(date("2026-10-09T04:00:00Z")))
        assertEquals(GameStatus.AWAITING_SCORE, upcoming.status(date("2026-10-09T06:00:00Z")))
        val final = game("b", date("2026-10-09T02:00:00Z"), awayScore = 3, homeScore = 1)
        assertEquals(GameStatus.FINAL, final.status(date("2026-10-09T04:00:00Z")))
    }

    @Test
    fun dayLabelsAreRelativeNearTodayAndDatedFartherOut() {
        val today = day(10, 8)
        fun label(month: Int, d: Int) = GameDay(day(month, d), SeasonPhase.REGULAR).label(today)
        assertEquals("Today", label(10, 8))
        assertEquals("Yesterday", label(10, 7))
        assertEquals("Tomorrow", label(10, 9))
        val dated = label(10, 14)
        assertTrue(dated, dated.contains("Oct"))
        assertTrue(dated, dated.contains("14"))
        assertFalse(dated, dated.contains("Week"))
    }

    @Test
    fun gamesGroupByDateNotByWeek() {
        val games = listOf(
            game("a", local(10, 8, 19)),
            game("b", local(10, 8, 22), away = "VAN", home = "LAK"),
            game("c", local(10, 10, 19)),
            game("d", local(10, 7, 19)),
        )
        val days = GameDay.days(games, zone)
        assertEquals(3, days.size)
        assertEquals(days.map { it.date }.sorted(), days.map { it.date })
        assertEquals(setOf("a", "b"), days[1].games(games, zone).map { it.id }.toSet())
        assertEquals(listOf("d"), days[0].games(games, zone).map { it.id })
    }

    @Test
    fun playoffGamesOnTheSameNightAreTheirOwnDay() {
        val regular = game("r", local(4, 15, 19))
        val playoff = Game(
            id = "p", season = 2026, seasonPhase = SeasonPhase.PLAYOFFS, gameType = "R1", week = 28,
            kickoff = local(4, 15, 19), awayTeam = "SEA", homeTeam = "EDM",
        )
        assertEquals(2, GameDay.days(listOf(regular, playoff), zone).size)
        assertEquals("Round 1", playoff.roundLabel)
    }

    @Test
    fun currentDayHoldsYesterdayUntilAfternoonIfNothingHasStarted() {
        val games = listOf(
            game("y", local(10, 7, 19)),
            game("t", local(10, 8, 19)),
            game("n", local(10, 10, 19)),
        )
        fun current(now: Instant) = GameDay.current(games, now, zone)?.date

        // Morning of Oct 8, nothing started: last night's finals are the story.
        assertEquals(day(10, 7), current(local(10, 8, 9)))
        // Afternoon: tonight's slate takes over.
        assertEquals(day(10, 8), current(local(10, 8, 15)))
        // Puck drop has passed, whatever the hour.
        assertEquals(day(10, 8), current(local(10, 8, 19).plusSeconds(600)))
        // No games today: the most recent day with games.
        assertEquals(day(10, 8), current(local(10, 9, 12)))
        // Before the season: the first night. After it: the last.
        assertEquals(day(10, 7), current(local(9, 1, 12)))
        assertEquals(day(10, 10), current(local(11, 1, 12)))
        assertNull(GameDay.current(emptyList(), local(10, 8), zone))
    }

    @Test
    fun teamRecordCountsRegularSeasonFinalsThroughAGame() = runTest {
        val g1 = game("g1", date("2026-10-09T02:00:00Z"), "SEA", "EDM", 3, 4)
        val g2 = game("g2", date("2026-10-11T02:00:00Z"), "VAN", "SEA", 2, 3, overtime = true)
        val g3 = game("g3", date("2026-10-13T02:00:00Z"), "SEA", "CGY", 2, 3, overtime = true)
        val g4 = game("g4", date("2026-10-15T02:00:00Z"), "SEA", "LAK")
        val provider = object : MockProvider() {
            override suspend fun fetchGames(season: Int) = listOf(g4, g1, g3, g2)
        }
        val model = dashboard(provider)
        model.loadGames(force = true)
        assertEquals("1-1-1", model.record("SEA"))
        assertEquals("0-1-0", model.record("SEA", g1))
        assertEquals("0-0-1", model.record("VAN"))
        assertEquals("1-0-0", model.record("EDM"))
        assertNull(model.record("LAK"))
        assertEquals(listOf("g1", "g2", "g3", "g4"), model.schedule("SEA").map { it.id })
    }

    @Test
    fun slateOrderPutsLiveFirstThenFinalsThenUpcoming() {
        val slate = Game.slateOrder(
            listOf(
                game("late", date("2026-10-09T05:00:00Z")),
                game("final", date("2026-10-09T01:00:00Z"), awayScore = 1, homeScore = 2),
                game("live", date("2026-10-09T02:00:00Z")),
            ),
            date("2026-10-09T04:00:00Z"),
        )
        assertEquals(listOf("live", "final", "late"), slate.map { it.id })
    }

    @Test
    fun boxScoreSummariesReadSkaterAndGoalieLines() {
        val json = """
            [{"player_id":1,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-10-08","player_type":"f","team":"SEA",
              "metrics":{"goals":1,"assists":1,"points":2,"shots_on_goal":4,"shot_attempts":7,"ixg":0.62,"toi_seconds":1182}},
             {"player_id":2,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-10-08","player_type":"f","team":"SEA",
              "metrics":{"goals":0,"assists":0,"shots_on_goal":2,"toi_seconds":900}},
             {"player_id":3,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-10-08","player_type":"g","team":"EDM",
              "metrics":{"shots_against":30,"saves":28,"goals_against":2,"xga":2.41,"toi_seconds":3600}}]
        """.trimIndent()
        val logs = objects(json).map { PlayerGameLog.fromJson(it) }
        assertEquals("g", logs.first().gameId)
        val box = GameBoxScore(logs)
        assertFalse(box.isEmpty)
        assertEquals(2, box.lines("SEA").size)
        assertEquals(listOf(3), box.lines("EDM").map { it.playerId })

        assertEquals("1 G, 1 A, 4 SOG, 0.62 ixG, 19:42 TOI", GameBoxScore.summary(box.lines.first { it.playerId == 1 }))
        assertEquals("0 P, 2 SOG, 15:00 TOI", GameBoxScore.summary(box.lines.first { it.playerId == 2 }))
        val goalie = box.lines.first { it.playerId == 3 }
        assertTrue(goalie.isGoalie)
        assertEquals("28 saves on 30 shots, 2 GA, 2.41 xGA", GameBoxScore.summary(goalie))
    }

    @Test
    fun gameDetailDecodesTheXGRaceAndPlayerLines() {
        val json = """
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
        """.trimIndent()
        val detail = GameDetail.fromJson(objects(json).first())
        assertEquals(2.41, detail.stats("SEA")["xg"]?.value)
        assertEquals(88, detail.stats("EDM")["xg"]?.percentile)
        assertEquals(33.0, detail.stats("EDM")["sog"]?.value)
        assertNull(detail.stats("EDM")["sog"]?.percentile)
        assertNull("a null team stat is dropped, not decoded as zero", detail.away["hd_chances"])

        assertEquals("an unknown role is dropped", 3, detail.players.size)
        assertEquals("skaters rank by ixG", listOf(12, 11), detail.players(GameDetail.Role.SKATER).map { it.playerId })
        assertEquals(2, detail.players(GameDetail.Role.SKATER, "SEA").size)
        assertTrue(detail.players(GameDetail.Role.SKATER, "EDM").isEmpty())
        val winger = detail.players.first { it.playerId == 11 }
        assertEquals("19:42", winger.toiLabel)
        assertNull(winger.ixgPer60?.percentile)
        val goalie = detail.players(GameDetail.Role.GOALIE).first()
        assertEquals(0.929, goalie.svPct?.value)
        assertEquals(0.41, goalie.gsax?.value)

        assertEquals(3, detail.xgRace.size)
        val last = detail.xgRace.last()
        assertEquals(3600.0, last.elapsed, 0.0)
        assertEquals(2.41, last.awayXG, 0.0)
        assertEquals(3.07, last.homeXG, 0.0)
        assertEquals(3, last.awayGoals)
        assertEquals(4, last.homeGoals)

        val play = detail.bigPlays.first()
        assertTrue(play.isGoal)
        assertEquals("12:34", play.clock)
        assertEquals("D. Sniper", play.shooter)
    }

    @Test
    fun recentFormWindowLabelIsADateRange() {
        val json = """
            {"player_id":1,"season":2026,"player_type":"f","window_weeks":2,"as_of":"2026-10-07","games":1,"plays":18,
             "metrics":{},"prior_metrics":{},"delta":{}}
        """.trimIndent()
        val form = RecentForm.fromJson(Json.parseToJsonElement(json) as JsonObject)
        val label = form.weekRangeLabel
        assertEquals("Sep 24 - Oct 7", label)
        assertFalse(label!!.contains("Week"))
        assertTrue(form.isSmallSample)
        assertTrue(form.isSmallSample(2))
        assertTrue("18 minutes is under the skater floor", form.isSmallSample(1))
    }

    @Test
    fun recentFormWithoutAnAnchorHasNoRangeLabel() {
        val json = """
            {"player_id":1,"season":2026,"player_type":"g","window_weeks":4,"games":3,"plays":180,
             "metrics":{"sv_pct":0.915},"prior_metrics":{},"delta":{}}
        """.trimIndent()
        val form = RecentForm.fromJson(Json.parseToJsonElement(json) as JsonObject)
        assertNull(form.weekRangeLabel)
        assertFalse(form.isSmallSample)
        assertEquals(0.915, form.metrics["sv_pct"])
    }

    @Test
    fun freshnessReportsAdvancedPending() {
        val json = """
            {"status":"degraded","refresh_id":"r","max_game_date":"2026-10-08","max_week":1,
             "observed_games":10,"expected_games":10,"shots_status":"pending","summary_status":"ready"}
        """.trimIndent()
        val freshness = DataFreshness.fromJson(Json.parseToJsonElement(json) as JsonObject)
        assertTrue(freshness.isAdvancedPending)
        val roundTrip = DataFreshness.fromJson(freshness.copy(isCached = true).toJson())
        assertEquals("pending", roundTrip.shotsStatus)
        assertEquals("ready", roundTrip.summaryStatus)
    }
}
