package com.jackwallner.hockey

import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.SeasonPhase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regular-season and playoff games must never end up in the same window. Playoff
 * games are the newest rows a season has, so a phase-blind "last N weeks" for a
 * club that reached the spring was mostly playoff hockey under a Regular Season heading.
 */
class GameLogPhaseTest {
    private fun log(date: String, seasonType: String?, goals: Double): PlayerGameLog {
        val phase = seasonType?.let { ""","season_type":"$it"""" } ?: ""
        val json = """{"player_id":7,"season":2025,"game_date":"$date","player_type":"f","plays":20,"touches":7,"metrics":{"goals":$goals}$phase}"""
        return PlayerGameLog.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    @Test
    fun seasonPhaseIsDecodedFromSeasonType() {
        assertEquals(SeasonPhase.REGULAR, log("2026-04-04", "REG", 1.0).seasonPhase)
        assertEquals(SeasonPhase.PLAYOFFS, log("2026-04-20", "POST", 2.0).seasonPhase)
    }

    /** A row with no phase is a regular-season row, so fixtures that predate the column keep decoding. */
    @Test
    fun missingSeasonTypeDefaultsToRegular() {
        assertEquals(SeasonPhase.REGULAR, log("2025-12-07", null, 0.0).seasonPhase)
    }

    @Test
    fun aPhaseBlindWindowWouldBeAllPlayoffs() {
        val logs = listOf(
            log("2026-05-08", "POST", 3.0),
            log("2026-05-05", "POST", 2.0),
            log("2026-05-02", "POST", 1.0),
            log("2026-04-16", "REG", 1.0),
            log("2026-04-14", "REG", 0.0),
        )

        val newestThree = logs.sortedByDescending { it.gameDate }.take(3)
        assertTrue(newestThree.all { it.seasonPhase == SeasonPhase.PLAYOFFS })

        val regularOnly = logs.filter { it.seasonPhase == SeasonPhase.REGULAR }.sortedByDescending { it.gameDate }
        assertEquals(2, regularOnly.size)
        val window = RecentFormWindow.build("Last 2 weeks", 2, regularOnly)
        assertEquals(1.0, window.metrics["goals"]!!, 0.0)
    }
}
