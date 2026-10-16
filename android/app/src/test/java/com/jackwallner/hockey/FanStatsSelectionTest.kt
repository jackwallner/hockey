package com.jackwallner.hockey

import com.jackwallner.hockey.model.FanStatsSelection
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandardStat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FanStatsSelectionTest {
    private fun player(id: Int, type: String = "f", season: Int = 2026, phase: SeasonPhase = SeasonPhase.REGULAR, stats: List<StandardStat> = emptyList()) =
        testPlayer(
            id = id, name = "Player $id", team = "SEA", position = if (type == "g") "G" else if (type == "d") "D" else "C",
            season = season, phase = phase, type = type, standard = stats,
        )

    @Test
    fun followingDoesNotSubstitutePriorSeasonOrPostseasonStats() {
        val players = listOf(player(1, season = 2025), player(2), player(1, phase = SeasonPhase.PLAYOFFS))
        val selected = FanStatsSelection.players(listOf(1, 2), players, 2026, SeasonPhase.REGULAR)
        assertEquals(listOf(2), selected.map { it.playerId })
    }

    @Test
    fun followingPreservesPersonalOrderAndDeduplicates() {
        val players = listOf(player(1), player(2), player(2), player(3))
        val selected = FanStatsSelection.players(listOf(3, 2, 3, 99, 1), players, 2026, SeasonPhase.REGULAR)
        assertEquals(listOf(3, 2, 1), selected.map { it.playerId })
    }

    @Test
    fun missingSummaryStatsAreNotShownAsZero() {
        val selected = player(1, stats = listOf(StandardStat("G", "3")))
        assertEquals(listOf("G"), FanStatsSelection.summary(selected).map { it.label })
        assertTrue(FanStatsSelection.summary(player(2)).isEmpty())
    }

    @Test
    fun summaryLineFollowsTheCohort() {
        val all = listOf("G", "A", "P", "SOG", "+/-", "Blk", "TOI/GP", "W", "GAA", "SV%").map { StandardStat(it, "1") }
        assertEquals(listOf("G", "A", "P", "SOG"), FanStatsSelection.summary(player(1, "f", stats = all)).map { it.label })
        assertEquals(listOf("P", "+/-", "Blk", "TOI/GP"), FanStatsSelection.summary(player(2, "d", stats = all)).map { it.label })
        assertEquals(listOf("W", "GAA", "SV%"), FanStatsSelection.summary(player(3, "g", stats = all)).map { it.label })
    }
}
