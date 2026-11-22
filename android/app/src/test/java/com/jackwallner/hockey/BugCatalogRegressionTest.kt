package com.jackwallner.hockey

import com.jackwallner.hockey.data.PaywallImpressionGate
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.ui.screens.OnboardingFooter
import com.jackwallner.hockey.ui.screens.onboardingFooter
import java.time.Instant
import java.util.TimeZone
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Android ports of the 2026-11-20 iOS bug catalog fixes that are not view model rules. */
class BugCatalogRegressionTest {
    private fun <T> onAPhoneIn(zone: String, body: () -> T): T {
        val saved = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone(zone))
        try {
            return body()
        } finally {
            TimeZone.setDefault(saved)
        }
    }

    private fun log(date: String): PlayerGameLog {
        val json = """{"player_id":1,"season":2025,"game_date":"$date","player_type":"f","plays":20,"touches":7,"metrics":{"goals":1}}"""
        return PlayerGameLog.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    private fun form(asOf: String, weeks: Int = 2): RecentForm {
        val json = """
            {"player_id":1,"season":2026,"player_type":"f","window_weeks":$weeks,"as_of":"$asOf","games":3,"plays":80,
             "metrics":{},"prior_metrics":{},"delta":{}}
        """.trimIndent()
        return RecentForm.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    // B3: the Recent Form range reads the feed's Eastern dates on any phone.
    @Test
    fun recentFormRangeReadsTheFeedsDatesOnAnyPhone() {
        for (zone in listOf("America/Los_Angeles", "America/New_York", "Asia/Tokyo")) {
            assertEquals(zone, "Sep 24 - Oct 7", onAPhoneIn(zone) { form("2026-10-07").weekRangeLabel })
        }
    }

    // B3: opening night is the schedule's date, not the phone's local day of the first puck drop.
    @Test
    fun openingNightIsTheSchedulesEasternDate() {
        val label = onAPhoneIn("Asia/Tokyo") {
            // 7 PM Eastern on 7 October is already the 8th in Tokyo.
            val opener = Game(
                id = "1", season = 2026, week = 1, kickoff = Instant.parse("2026-10-07T23:00:00Z"),
                gameDate = Instant.parse("2026-10-07T04:00:00Z"), awayTeam = "SEA", homeTeam = "EDM",
            )
            val later = opener.copy(id = "2", kickoff = Instant.parse("2026-10-09T23:00:00Z"), gameDate = Instant.parse("2026-10-09T04:00:00Z"))
            form("2026-10-10").weekRangeLabel(RecentForm.openingDay(listOf(later, opener), SeasonPhase.REGULAR))
        }
        assertEquals("Oct 7 - Oct 10", label)
    }

    // B6: Follow Players lists every followed player, whatever season is on the board.
    @Test
    fun followPlayersListsEveryFollowedPlayerOnAnySeason() = runTest {
        val current = StatScoutSeason.current
        val veteran = testPlayer(1, "Veteran", "SEA", "C", current - 1, type = "f")
        val rookie = testPlayer(2, "Rookie", "EDM", "C", current, type = "f")
        val both = listOf(testPlayer(3, "Regular", "BOS", "C", current - 1, type = "f"), testPlayer(3, "Regular", "BOS", "C", current, type = "f"))
        val vm = dashboard(MockProvider(listOf(veteran, rookie) + both))
        vm.applyProState(true)
        vm.load()
        vm.loadHistoricalIfNeeded()

        val onLastSeason = vm.followedPlayers(listOf(2, 1, 3), current - 1)
        assertEquals("in follow order, the rookie included", listOf(2, 1, 3), onLastSeason.map { it.playerId })
        assertEquals("a player with a row in the season shows that row", current - 1, onLastSeason.last().season)
        assertEquals(listOf(2, 1, 3), vm.followedPlayers(listOf(2, 1, 3), current).map { it.playerId })
        assertTrue(vm.followedPlayers(listOf(99), current).isEmpty())
    }
}
