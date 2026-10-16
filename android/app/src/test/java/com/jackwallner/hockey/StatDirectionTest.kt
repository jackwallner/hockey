package com.jackwallner.hockey

import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StatDirectionTest {
    private fun player(
        id: Int,
        name: String,
        value: String,
        percentile: Int,
        label: String = "ixG",
        category: MetricCategory = MetricCategory.SHOT_QUALITY,
    ) = testPlayer(
        id = id, name = name, team = "BUF", position = "C", type = "f",
        metrics = listOf(metric(label, value, percentile, category, id = "m$id")),
    )

    private fun ranked(players: List<Player>, descending: Boolean = true) =
        players.sortedWith(DashboardViewModel.metricComparator("ixG", MetricCategory.SHOT_QUALITY, descending))

    @Test
    fun hockeyLowerIsBetterMetrics() {
        assertTrue(DashboardViewModel.lowerIsBetter("xGA/60", MetricCategory.PLAY_DRIVING))
        assertTrue(DashboardViewModel.lowerIsBetter("Giveaways", MetricCategory.PLAY_DRIVING))
        assertTrue(DashboardViewModel.lowerIsBetter("GAA", MetricCategory.GOALTENDING))
        assertTrue(DashboardViewModel.lowerIsBetter("Rebound%", MetricCategory.GOALTENDING))
        assertFalse(DashboardViewModel.lowerIsBetter("ixG", MetricCategory.SHOT_QUALITY))
        assertFalse(DashboardViewModel.lowerIsBetter("Blocks", MetricCategory.PLAY_DRIVING))
        // The same label is workload for a goalie: more is not worse.
        assertFalse(DashboardViewModel.lowerIsBetter("xGA/60", MetricCategory.GOALTENDING))
    }

    @Test
    fun blankValuesRankByPercentileInsteadOfLast() {
        val players = listOf(
            player(1, "Printable but poor", "0.01", 5),
            player(2, "Blank but elite", "", 99),
            player(3, "Blank and poor", "", 2),
        )
        assertEquals(listOf("Blank but elite", "Printable but poor", "Blank and poor"), ranked(players).map { it.name })
    }

    @Test
    fun equalPercentilesBreakTiesOnValue() {
        val players = listOf(player(1, "Lower value", "0.12", 80), player(2, "Higher value", "0.21", 80))
        assertEquals(listOf("Higher value", "Lower value"), ranked(players).map { it.name })
    }

    @Test
    fun missingMetricSortsLastInBothDirections() {
        val hasMetric = player(1, "Has it", "0.12", 50)
        val lacksMetric = player(2, "Lacks it", "11.0%", 40, label = "Sh%", category = MetricCategory.SCORING)
        for (descending in listOf(true, false)) {
            assertEquals("Lacks it", ranked(listOf(lacksMetric, hasMetric), descending).last().name)
        }
    }
}
