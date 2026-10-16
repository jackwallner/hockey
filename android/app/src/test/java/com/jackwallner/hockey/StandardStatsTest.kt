package com.jackwallner.hockey

import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.StandardStatSemantics
import com.jackwallner.hockey.ui.screens.LeaguePercentileCurve
import com.jackwallner.hockey.ui.screens.StandardStatCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StandardStatsTest {
    @Test
    fun positionCatalogUsesHockeyStatLines() {
        assertEquals("P", StandardStatCatalog.defaultStat(PlayerPositionGroup.FORWARD))
        assertEquals("P", StandardStatCatalog.defaultStat(PlayerPositionGroup.DEFENSE))
        assertEquals("SV%", StandardStatCatalog.defaultStat(PlayerPositionGroup.GOALIE))
        assertTrue(StandardStatCatalog.stats(PlayerPositionGroup.FORWARD).contains("TOI/GP"))
        assertTrue(StandardStatCatalog.stats(PlayerPositionGroup.GOALIE).contains("GAA"))
        assertFalse("goalies do not score", StandardStatCatalog.stats(PlayerPositionGroup.GOALIE).contains("G"))
        assertFalse(StandardStatCatalog.stats(PlayerPositionGroup.FORWARD).contains("SV%"))
    }

    @Test
    fun walkingThePositionTabsRanksEachPositionByItsOwnDefault() {
        var stat = StandardStatCatalog.defaultStat(PlayerPositionGroup.FORWARD)
        var position = PlayerPositionGroup.FORWARD
        val walk = listOf(
            PlayerPositionGroup.DEFENSE, PlayerPositionGroup.GOALIE, PlayerPositionGroup.FORWARD,
            PlayerPositionGroup.GOALIE, PlayerPositionGroup.DEFENSE,
        )
        for (next in walk) {
            stat = StandardStatCatalog.stat(stat, position, next)
            position = next
            assertEquals(StandardStatCatalog.defaultStat(next), stat)
        }
    }

    @Test
    fun deliberatelyChosenStatFollowsToPositionsThatOfferIt() {
        assertEquals("G", StandardStatCatalog.stat("G", PlayerPositionGroup.FORWARD, PlayerPositionGroup.DEFENSE))
        assertEquals("G", StandardStatCatalog.stat("G", PlayerPositionGroup.DEFENSE, PlayerPositionGroup.FORWARD))
        // Goalies do not score: the choice falls back to their own default.
        assertEquals("SV%", StandardStatCatalog.stat("G", PlayerPositionGroup.FORWARD, PlayerPositionGroup.GOALIE))
        assertEquals("GP", StandardStatCatalog.stat("GP", PlayerPositionGroup.GOALIE, PlayerPositionGroup.FORWARD))
    }

    @Test
    fun goalsAgainstAndPenaltiesDefaultLowestFirst() {
        assertFalse(StandardStatCatalog.defaultDescending("GAA", PlayerPositionGroup.GOALIE))
        assertFalse(StandardStatCatalog.defaultDescending("PIM", PlayerPositionGroup.FORWARD))
        assertFalse(StandardStatCatalog.defaultDescending("L", PlayerPositionGroup.GOALIE))
        assertTrue(StandardStatCatalog.defaultDescending("SV%", PlayerPositionGroup.GOALIE))
        assertTrue(StandardStatCatalog.defaultDescending("P", PlayerPositionGroup.FORWARD))
    }

    @Test
    fun timeOnIceRanksByItsMinutes() {
        assertEquals(19.7, StandardStatSemantics.numericValue("TOI/GP", "19:42")!!, 0.001)
        assertEquals(54.2, StandardStatSemantics.numericValue("FO%", "54.2%")!!, 0.001)
        assertEquals(0.915, StandardStatSemantics.numericValue("SV%", ".915")!!, 0.0001)
        assertEquals(
            "a clock compares as minutes, not as the text before the colon",
            StandardStatSemantics.Winner.LEFT, StandardStatSemantics.winner("TOI/GP", "21:05", "19:42"),
        )
    }

    @Test
    fun standardComparisonRespectsDirectionAndRates() {
        assertEquals(StandardStatSemantics.Winner.LEFT, StandardStatSemantics.winner("SV%", ".915", ".907"))
        assertEquals("the lower goals-against average wins", StandardStatSemantics.Winner.LEFT, StandardStatSemantics.winner("GAA", "2.31", "2.88"))
        assertEquals(StandardStatSemantics.Winner.RIGHT, StandardStatSemantics.winner("PIM", "30", "12"))
        assertEquals(StandardStatSemantics.Winner.RIGHT, StandardStatSemantics.winner("L", "14", "9"))
        assertNull(StandardStatSemantics.winner("G", "1", "1"))
        assertNull(StandardStatSemantics.winner("G", null, "1"))
    }

    @Test
    fun everyExistingStandardStatGetsAPercentile() {
        assertEquals(50, StandardStatSemantics.percentile("TOI/GP", "19:42", listOf("19:42", "15:00", "22:30")))
        assertEquals(50, StandardStatSemantics.percentile("G", "1", emptyList()))
    }

    @Test
    fun percentileRanksAgainstWhicheverPeersHaveTheStat() {
        // Opening week: two peers, and a value that beats one of them.
        assertEquals(75, StandardStatSemantics.percentile("SOG", "8", listOf("8", "2")))
        // A cohort of one is the middle of its own distribution, never 0.
        assertEquals(50, StandardStatSemantics.percentile("SOG", "8", listOf("8")))
        // Direction still applies with a thin pool: fewer penalty minutes is better.
        val peers = listOf("0", "12")
        assertTrue(StandardStatSemantics.percentile("PIM", "0", peers) > StandardStatSemantics.percentile("PIM", "12", peers))
    }

    @Test
    fun percentileIsNeverZeroForAnExistingValue() {
        // A stat that exists always lands on a drawable 1-100 bar.
        for (value in listOf("0", "1", "250", "0.0%")) {
            val pct = StandardStatSemantics.percentile("SOG", value, listOf("0", "1", "250", "999"))
            assertTrue("$value produced $pct", pct in 1..100)
        }
    }

    /** Was null below five points, which dropped the Recent Form bar entirely on opening night. */
    @Test
    fun leagueCurveInterpolatesFromTwoPoints() {
        val curve = LeaguePercentileCurve.of(listOf(100.0 to 20.0, 300.0 to 80.0))
        assertNotNull(curve)
        assertEquals(50, curve!!.percentile(200.0))
        assertEquals(20, curve.percentile(50.0))
        assertEquals(80, curve.percentile(400.0))
        assertNull(LeaguePercentileCurve.of(listOf(100.0 to 20.0)))
    }
}
