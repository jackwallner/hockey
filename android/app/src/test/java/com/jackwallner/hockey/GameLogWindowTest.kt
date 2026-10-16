package com.jackwallner.hockey

import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.StatScoutSeason
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where a team card's rolling game-log window starts. It used to be measured
 * back from today, so from July until the October opener every Recent control
 * on a team page found nothing for a season the app still showed totals for.
 */
class GameLogWindowTest {
    private val zone: ZoneId = ZoneId.systemDefault()

    private fun date(year: Int, month: Int, day: Int): Instant = LocalDate.of(year, month, day).atStartOfDay(zone).toInstant()

    private fun minusDays(instant: Instant, days: Long): Instant = instant.atZone(zone).minusDays(days).toInstant()

    /** Mid-season the newest game is the one just played, so the window tracks the live date. */
    @Test
    fun duringTheSeasonTheWindowIsAnchoredToToday() {
        val now = date(2026, 1, 15)
        assertEquals(minusDays(now, 120), StatScoutSeason.gameLogWindowStart(2025, 120, now))
    }

    /** August 2026 is two months past the 2025-26 season's last game; anchored to the season's end it reaches March. */
    @Test
    fun afterTheSeasonTheWindowIsAnchoredToTheSeasonsEnd() {
        val now = date(2026, 8, 17)
        val start = StatScoutSeason.gameLogWindowStart(2025, 120, now)
        assertTrue(start < now)
        assertEquals(minusDays(date(2026, 7, 1), 120), start)
        // It has to reach the last regular-season game, in mid-April.
        assertTrue(start < date(2026, 4, 17))
    }

    @Test
    fun aPastSeasonNeverDependsOnTheCurrentDate() {
        val early = StatScoutSeason.gameLogWindowStart(2022, now = date(2026, 8, 17))
        val late = StatScoutSeason.gameLogWindowStart(2022, now = date(2030, 1, 1))
        assertEquals(early, late)
        assertTrue(early < date(2023, 6, 1))
    }

    /** Wide enough to slice the longest window (8 weeks) out of, with room for a long road trip. */
    @Test
    fun windowSpansEnoughWeeksForTheLongestSlice() {
        val start = StatScoutSeason.gameLogWindowStart(2025, now = date(2026, 8, 17))
        val weeks = ChronoUnit.DAYS.between(start.atZone(zone), date(2026, 7, 1).atZone(zone)) / 7
        assertTrue(weeks >= RecentWindow.EIGHT.value)
    }
}
