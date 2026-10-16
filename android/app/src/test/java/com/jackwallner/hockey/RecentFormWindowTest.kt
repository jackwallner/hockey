package com.jackwallner.hockey

import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.TrendMetric
import com.jackwallner.hockey.model.TrendSide
import com.jackwallner.hockey.model.TrendStatMode
import com.jackwallner.hockey.model.TrendWindow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What "the last N weeks" adds up to on a player page. */
class RecentFormWindowTest {
    private fun log(date: String, type: String = "f", plays: Int = 20, touches: Int = 7, metrics: String): PlayerGameLog {
        val json = """{"player_id":1,"season":2026,"game_date":"$date","player_type":"$type","plays":$plays,"touches":$touches,"metrics":$metrics}"""
        return PlayerGameLog.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    /** A four-week window over two played games is two games' worth of numbers. */
    @Test
    fun windowSumsCountingStatsOverTheGamesSupplied() {
        val logs = listOf(
            log("2026-10-14", plays = 21, touches = 8, metrics = """{"goals":1,"assists":1,"ixg":0.6}"""),
            log("2026-10-16", plays = 18, touches = 5, metrics = """{"goals":0,"assists":2,"ixg":0.4}"""),
        )
        val window = RecentFormWindow.build("Last 4 weeks", 4, logs)
        assertEquals(2, window.games)
        assertEquals(4, window.span)
        assertEquals(39, window.plays)
        assertEquals(13, window.touches)
        assertEquals(1.0, window.metrics["goals"]!!, 0.0)
        assertEquals(3.0, window.metrics["assists"]!!, 0.0)
        assertEquals(1.0, window.metrics["ixg"]!!, 0.0001)
    }

    /** A stat with no data in any game gets no key, so the row falls back to the season value. */
    @Test
    fun nullMetricsAreAbsentNotZero() {
        val window = RecentFormWindow.build("Last 2 weeks", 2, listOf(log("2026-10-14", metrics = """{"goals":1,"primary_assists":null}""")))
        assertEquals(1.0, window.metrics["goals"]!!, 0.0)
        assertNull(window.metrics["primary_assists"])
    }

    @Test
    fun skaterRatesAreRebuiltFromSummedCounts() {
        // 2 hours of ice time: 6 points, 5.0 ixG, 20 shots attempted, 4 goals on 20 SOG.
        val logs = listOf(
            log("2026-10-14", metrics = """{"points":4,"ixg":3.0,"shot_attempts":12,"goals":3,"shots_on_goal":10,"toi_seconds":3600}"""),
            log("2026-10-16", metrics = """{"points":2,"ixg":2.0,"shot_attempts":8,"goals":1,"shots_on_goal":10,"toi_seconds":3600}"""),
        )
        val window = RecentFormWindow.build("Last 2 weeks", 2, logs)
        assertEquals(3.0, window.value("P/60")!!, 0.0001)
        assertEquals(2.5, window.value("ixG/60")!!, 0.0001)
        assertEquals(10.0, window.value("Shots/60")!!, 0.0001)
        assertEquals(20.0, window.value("Sh%")!!, 0.0001)
        // Counting stats and on-ice shares have no windowed rate.
        assertNull(window.value("G"))
        assertNull(window.value("xGF%"))
    }

    @Test
    fun goalieRatesAreRebuiltFromSummedCounts() {
        val logs = listOf(
            log("2026-10-14", "g", metrics = """{"saves":28,"shots_against":30,"goals_against":2,"xga":2.5,"hd_shots_against":8,"hd_goals_against":1,"toi_seconds":3600}"""),
            log("2026-10-16", "g", metrics = """{"saves":22,"shots_against":25,"goals_against":3,"xga":2.0,"hd_shots_against":4,"hd_goals_against":1,"toi_seconds":3600}"""),
        )
        val window = RecentFormWindow.build("Last 2 weeks", 2, logs)
        assertEquals(50.0 / 55.0, window.value("SV%")!!, 0.0001)
        assertEquals(2.5, window.value("GAA")!!, 0.0001)
        assertEquals((4.5 - 5.0) / 2, window.value("GSAx/60")!!, 0.0001)
        assertEquals(1 - 2.0 / 12.0, window.value("HD SV%")!!, 0.0001)
    }

    /** No ice time, no per-60 rate. */
    @Test
    fun ratesNeedADenominator() {
        val window = RecentFormWindow.build("Last 2 weeks", 2, listOf(log("2026-10-14", metrics = """{"points":2}""")))
        assertNull(window.value("P/60"))
        assertNull(window.value("Sh%"))
        assertNull(window.value("SV%"))
    }

    @Test
    fun windowsAnchorOnTheNewestGameAndCountWholeWeeks() {
        val logs = listOf(
            log("2026-11-20", metrics = """{"goals":1}"""),
            log("2026-11-10", metrics = """{"goals":1}"""),
            log("2026-11-02", metrics = """{"goals":1}"""),
            log("2026-10-12", metrics = """{"goals":1}"""),
        )
        assertEquals(2, RecentFormWindow.logs(logs, 2).size)
        assertEquals(3, RecentFormWindow.logs(logs, 4).size)
        assertEquals(4, RecentFormWindow.logs(logs, 8).size)
        assertTrue(RecentFormWindow.logs(emptyList(), 4).isEmpty())
        assertEquals("newest first", logs.map { it.gameDate }, RecentFormWindow.logs(logs, 8).map { it.gameDate })
    }

    @Test
    fun windowChoicesAreTwoFourEightWeeks() {
        assertEquals(listOf(2, 4, 8), RecentWindow.entries.map { it.value })
        assertEquals(listOf(2, 4, 8), TrendWindow.entries.map { it.value })
        assertEquals(listOf(2, 4, 8), RecentFormWindow.windows.map { it.second })
        assertEquals("Last 4 weeks", RecentWindow.FOUR.label)
        assertEquals("4W", RecentWindow.FOUR.shortLabel)
        assertEquals("8 weeks", TrendWindow.EIGHT.segmentLabel)
    }

    @Test
    fun recentWindowCaptionNamesTheGamesInHand() {
        assertEquals("1 game", RecentFormWindow.caption(1, 2))
        assertEquals("3 games", RecentFormWindow.caption(3, 4))
        assertEquals("9 games", RecentFormWindow.caption(9, 8))
    }

    @Test
    fun barsOnTheRecentCardDifferForGoalies() {
        assertEquals(listOf("P/60", "ixG/60", "Shots/60", "Sh%"), RecentFormWindow.recentLabels(false))
        assertEquals(listOf("SV%", "GSAx/60", "GAA", "HD SV%"), RecentFormWindow.recentLabels(true))
    }

    @Test
    fun recentMetricKeysMapSeasonLabelsToTheRollup() {
        assertEquals("points_per_60", RecentMetricKey.key("P/60"))
        assertEquals("ixg", RecentMetricKey.key("ixG"))
        assertEquals("gax", RecentMetricKey.key("GAx"))
        assertEquals("gsax_per_60", RecentMetricKey.key("GSAx/60"))
        assertEquals("sv_pct", RecentMetricKey.key("SV%"))
        assertEquals("goals_against", RecentMetricKey.key("GA"))
        // On-ice shares have no per-game feed, so they get no recent bar.
        assertNull(RecentMetricKey.key("xGF%"))
        assertNull(RecentMetricKey.key("CF%"))
        assertNull(RecentMetricKey.key("Made Up"))
    }

    @Test
    fun savePercentageReadsAsThreeDecimalsWithNoLeadingZero() {
        assertEquals(".915", RecentMetricKey.savePercentage(0.915))
        assertEquals(".915", RecentMetricKey.savePercentage(91.5))
        assertEquals("1.000", RecentMetricKey.savePercentage(1.0))
        assertEquals(".907", RecentMetricKey.format(0.9071, "SV%"))
        assertEquals(".842", RecentMetricKey.format(0.842, "HD SV%"))
    }

    @Test
    fun recentValuesFormatLikeThePlayerPage() {
        assertEquals("3.12", RecentMetricKey.format(3.1234, "P/60"))
        assertEquals("5.3", RecentMetricKey.format(5.26, "ixG"))
        assertEquals("-1.2", RecentMetricKey.format(-1.24, "GSAx"))
        assertEquals("54.2%", RecentMetricKey.format(54.24, "xGF%"))
        assertEquals("2.00", RecentMetricKey.format(2.0, "GAA"))
        assertEquals("1,234", RecentMetricKey.format(1_234.0, "Saves"))
        assertTrue(RecentMetricKey.lowerIsBetter("GAA"))
        assertTrue(RecentMetricKey.lowerIsBetter("Giveaways"))
        assertFalse(RecentMetricKey.lowerIsBetter("ixG"))
    }

    @Test
    fun trendMetricsFormatTheirOwnDecimals() {
        assertEquals(".915", TrendMetric.goalieStandard.first { it.label == "SV%" }.format(0.915))
        assertEquals("4.3", TrendMetric.skaterStandard.first { it.label == "ixG" }.format(4.26))
        assertEquals("12.3%", TrendMetric.skaterAdvanced.first { it.label == "Sh%" }.format(12.34))
        assertEquals(listOf("F", "D", "G"), TrendSide.entries.map { it.shortLabel })
        assertEquals("GSAx", TrendMetric.list(TrendSide.GOALIE, TrendStatMode.ADVANCED).first().label)
        assertEquals("P", TrendMetric.list(TrendSide.FORWARD, TrendStatMode.STANDARD).first().label)
    }
}
