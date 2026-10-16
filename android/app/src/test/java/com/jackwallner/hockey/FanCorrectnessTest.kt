package com.jackwallner.hockey

import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.TrendMetric
import com.jackwallner.hockey.model.TrendSide
import com.jackwallner.hockey.model.competitionRanks
import com.jackwallner.hockey.ui.theme.RinkPalette
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Numbers a hockey fan checks against the box score, on the Android-only
 * paths: windows count games rather than rows, leaderboards share ranks on a
 * tie, and the Trends board reads the rollup's own then, now and change.
 */
class FanCorrectnessTest {
    private var nextId = 1

    private fun log(date: String, team: String = "SEA", metrics: String): PlayerGameLog {
        val json = """{"player_id":${nextId++},"season":2026,"game_date":"$date","player_type":"f","team":"$team","plays":18,"touches":4,"metrics":$metrics}"""
        return PlayerGameLog.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    private fun form(metrics: String, prior: String, delta: String, type: String = "f"): RecentForm {
        val json = """{"player_id":1,"season":2026,"player_type":"$type","window_weeks":2,"games":4,"metrics":$metrics,"prior_metrics":$prior,"delta":$delta}"""
        return RecentForm.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    /** A team window has one row per player per game: its game count is its dates. */
    @Test
    fun windowCountsGamesNotRows() {
        val logs = listOf(
            log("2026-10-04", metrics = """{"goals":1}"""),
            log("2026-10-04", metrics = """{"goals":2}"""),
            log("2026-10-02", metrics = """{"goals":0}"""),
        )
        val window = RecentFormWindow.build("Last 2", 2, logs)
        assertEquals(2, window.games)
        assertEquals(3.0, window.metrics["goals"]!!, 0.0)
    }

    /** The board ranks the change the rollup published, never a re-derived one. */
    @Test
    fun trendValuesPassThroughTheRollup() {
        val pace = TrendMetric.skaterAdvanced.first { it.key == "points_per_60" }
        val values = pace.values(form("""{"points_per_60":3.1}""", """{"points_per_60":2.4}""", """{"points_per_60":0.7}"""))
        assertEquals(3.1, values.now!!, 1e-9)
        assertEquals(2.4, values.then!!, 1e-9)
        assertEquals(0.7, values.delta!!, 1e-9)
        assertEquals("3.10", pace.display(3.1))
    }

    @Test
    fun goalieTrendsReadSavePercentageTheHockeyWay() {
        val sv = TrendMetric.goalieStandard.first { it.key == "sv_pct" }
        assertEquals(".915", sv.display(0.915))
        assertTrue("goals against ranks lowest first", TrendMetric.goalieStandard.first { it.key == "gaa" }.lowerIsBetter)
        assertTrue(TrendSide.GOALIE.hasAdvancedMetrics)
        assertEquals("g", TrendSide.GOALIE.playerType)
    }

    /** Two forwards on 31 goals are not 21st and 22nd. */
    @Test
    fun tiesShareALeaderboardRank() {
        assertEquals(listOf(1, 2, 2, 4), competitionRanks(listOf(40.0, 31.0, 31.0, 20.0)))
        assertEquals(listOf(1, 2), competitionRanks(listOf(null, null)))
    }

    @Test
    fun onlyAWinReadsAsAWin() {
        assertEquals(RinkPalette.performanceHigh, RinkPalette.resultColor("W"))
        assertEquals(RinkPalette.performanceLow, RinkPalette.resultColor("L"))
        assertEquals(RinkPalette.performanceLow, RinkPalette.resultColor("OTL"))
    }
}
