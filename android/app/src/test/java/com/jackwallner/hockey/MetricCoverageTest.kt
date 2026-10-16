package com.jackwallner.hockey

import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricCoverage
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.StatScoutSeason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The coverage notes exist so a gap reads as a limit of the public record
 * rather than as a broken app. Every metric exists for every season from
 * 2008-09, so only the career rollup and a live season still catching up carry a note.
 */
class MetricCoverageTest {
    @Test
    fun currentSeasonHasNoCoverageCaveat() {
        assertNull(MetricCoverage.note(StatScoutSeason.current))
    }

    @Test
    fun everySeasonInRangeHasNoCoverageCaveat() {
        for (season in StatScoutSeason.EARLIEST..StatScoutSeason.current) {
            for (category in MetricCategory.entries) {
                assertNull("$season $category", MetricCoverage.note(season, category))
            }
        }
    }

    @Test
    fun allTimeExplainsItSpansEras() {
        val note = MetricCoverage.note(StatScoutSeason.ALL_TIME)
        assertNotNull(note)
        assertTrue(note!!.contains("Career"))
        assertTrue("the note names the first season in 2008-09 form", note.contains("2008-09"))
    }

    @Test
    fun pendingNoteNamesTheSourceThatIsLate() {
        assertTrue(MetricCoverage.pendingNote("pending", "ready")?.contains("MoneyPuck") == true)
        assertTrue(MetricCoverage.pendingNote("ready", "pending")?.contains("NHL") == true)
        assertNull(MetricCoverage.pendingNote("ready", "not_applicable"))
        assertNull(MetricCoverage.pendingNote(null, null))
    }

    /** Every metric reaches back to the start of the dataset, the career rollup included. */
    @Test
    fun everyMetricIsTrackedInEverySeason() {
        for (label in listOf("ixG", "GSAx", "xGF%", "P")) {
            assertTrue(MetricCoverage.isTracked(label, StatScoutSeason.EARLIEST))
            assertTrue(MetricCoverage.isTracked(label, StatScoutSeason.current))
            assertTrue(MetricCoverage.isTracked(label, StatScoutSeason.ALL_TIME))
        }
    }

    @Test
    fun datasetFloorMatchesMoneyPucksFirstSeason() {
        assertEquals(2008, StatScoutSeason.EARLIEST)
        assertEquals("2008-09", SeasonLabel.display(StatScoutSeason.EARLIEST))
    }
}
