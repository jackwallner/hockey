package com.jackwallner.hockey

import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.MetricAggregation
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricValueFormat
import com.jackwallner.hockey.model.MetricWeight
import com.jackwallner.hockey.model.StandardStat
import com.jackwallner.hockey.model.metricNumericValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Roster-pooling rules the team comparison relies on. A rate is weighted by the
 * volume it was measured over, so a two-game cameo cannot outrank an 80-game season.
 */
class MetricAggregationTest {
    private fun aggregation(label: String, category: MetricCategory) = HockeyMetricRegistry.aggregation(label, category)

    private fun player(standard: List<StandardStat>, type: String = "f") =
        testPlayer(position = if (type == "g") "G" else "C", season = 2026, type = type, standard = standard)

    @Test
    fun scoringRatesWeightByIceTimeAndCountsAdd() {
        assertEquals(MetricAggregation.Weighted(MetricWeight.ICE_TIME), aggregation("P/60", MetricCategory.SCORING))
        assertEquals(MetricAggregation.Weighted(MetricWeight.SHOTS_ON_GOAL), aggregation("Sh%", MetricCategory.SCORING))
        // Volume stats still add up.
        assertEquals(MetricAggregation.Sum, aggregation("G", MetricCategory.SCORING))
        assertEquals(MetricAggregation.Sum, aggregation("SOG", MetricCategory.SCORING))
    }

    @Test
    fun shotQualityTotalsSumAndRatesWeight() {
        assertEquals(MetricAggregation.Sum, aggregation("ixG", MetricCategory.SHOT_QUALITY))
        assertEquals(MetricAggregation.Sum, aggregation("GAx", MetricCategory.SHOT_QUALITY))
        assertEquals(MetricAggregation.Weighted(MetricWeight.ICE_TIME), aggregation("ixG/60", MetricCategory.SHOT_QUALITY))
        assertEquals(MetricAggregation.Weighted(MetricWeight.SHOT_ATTEMPTS), aggregation("xG/Shot", MetricCategory.SHOT_QUALITY))
    }

    @Test
    fun playDrivingSharesWeightByIceTimeWhileCountsAdd() {
        // A roster's on-ice shares are an average over the minutes played.
        for (label in listOf("xGF%", "CF%", "xGA/60")) {
            assertEquals(label, MetricAggregation.Weighted(MetricWeight.ICE_TIME), aggregation(label, MetricCategory.PLAY_DRIVING))
        }
        for (label in listOf("Blocks", "Hits", "Takeaways", "Giveaways")) {
            assertEquals(label, MetricAggregation.Sum, aggregation(label, MetricCategory.PLAY_DRIVING))
        }
    }

    @Test
    fun goaltendingRatesWeightByShotsAgainstOrIceTime() {
        assertEquals(MetricAggregation.Weighted(MetricWeight.SHOTS_AGAINST), aggregation("SV%", MetricCategory.GOALTENDING))
        assertEquals(MetricAggregation.Weighted(MetricWeight.SHOTS_AGAINST), aggregation("HD SV%", MetricCategory.GOALTENDING))
        assertEquals(MetricAggregation.Weighted(MetricWeight.ICE_TIME), aggregation("GAA", MetricCategory.GOALTENDING))
        assertEquals(MetricAggregation.Weighted(MetricWeight.ICE_TIME), aggregation("GSAx/60", MetricCategory.GOALTENDING))
        assertEquals(MetricAggregation.Sum, aggregation("GSAx", MetricCategory.GOALTENDING))
        assertEquals(MetricAggregation.Sum, aggregation("W", MetricCategory.GOALTENDING))
    }

    /** "19:42" per game times 40 games. */
    @Test
    fun iceTimeWeightIsTimeOnIcePerGameTimesGamesPlayed() {
        val p = player(listOf(std("GP", "40"), std("TOI/GP", "19:42")))
        assertEquals(19.7 * 40, MetricWeight.ICE_TIME.value(p)!!, 0.001)
    }

    /** A goalie line carries no TOI/GP, so it weights by games played. */
    @Test
    fun goalieIceTimeWeightFallsBackToGames() {
        assertEquals(52.0, MetricWeight.ICE_TIME.value(player(listOf(std("GP", "52"), std("GS", "50")), "g")))
    }

    @Test
    fun shotsAgainstWeightReadsTheSAColumn() {
        assertEquals(1312.0, MetricWeight.SHOTS_AGAINST.value(player(listOf(std("SA", "1,312")), "g")))
    }

    @Test
    fun shotsOnGoalWeightReadsPlainColumn() {
        assertEquals(272.0, MetricWeight.SHOTS_ON_GOAL.value(player(listOf(std("SOG", "272")))))
    }

    @Test
    fun clockMinutesParsesATimeOnIceClock() {
        assertEquals(19.7, MetricWeight.clockMinutes("19:42")!!, 0.0001)
        assertEquals(0.5, MetricWeight.clockMinutes("0:30")!!, 0.0001)
        assertEquals(21.0, MetricWeight.clockMinutes("21")!!, 0.0001)
    }

    /** A player with no volume must drop out of the weighted mean rather than enter it at weight 1. */
    @Test
    fun missingWeightIsNullNotZero() {
        val p = player(listOf(std("G", "17")))
        assertNull(MetricWeight.ICE_TIME.value(p))
        assertNull(MetricWeight.SHOTS_ON_GOAL.value(p))
        assertNull(MetricWeight.SHOTS_AGAINST.value(p))
    }

    @Test
    fun zeroVolumeIsTreatedAsMissing() {
        assertNull(MetricWeight.SHOTS_ON_GOAL.value(player(listOf(std("SOG", "0")))))
    }

    @Test
    fun volumeCaptionNamesTheDenominator() {
        val skater = player(listOf(std("GP", "10"), std("TOI/GP", "20:00"), std("SOG", "41")))
        assertEquals("200 min", skater.volumeCaption(MetricCategory.SCORING))
        assertEquals("41 SOG", skater.volumeCaption(MetricCategory.SHOT_QUALITY))
        assertEquals("612 SA", player(listOf(std("SA", "612")), "g").volumeCaption(MetricCategory.GOALTENDING))
        assertNull(player(emptyList()).volumeCaption(MetricCategory.SCORING))
    }

    @Test
    fun percentFormatIsPreserved() {
        val format = MetricValueFormat.inferred(listOf("54.2%", "48.8%"))
        assertTrue(format.isPercent)
        assertEquals(1, format.decimals)
        assertEquals("51.5%", format.string(51.5))
    }

    @Test
    fun signedFormatKeepsLeadingPlus() {
        val format = MetricValueFormat.inferred(listOf("+2.3", "-1.1"))
        assertTrue(format.isSigned)
        assertEquals("+1.4", format.string(1.4))
        assertEquals("-1.4", format.string(-1.4))
    }

    @Test
    fun groupedIntegerFormat() {
        val format = MetricValueFormat.inferred(listOf("1,322", "1,004"))
        assertTrue(format.hasGrouping)
        assertEquals(0, format.decimals)
        assertEquals("2,326", format.string(2326.0))
    }

    /** Save percentages ship as ".915" and an aggregate of them must too. */
    @Test
    fun savePercentageKeepsItsLeadingDotOffTheZero() {
        val format = MetricValueFormat.inferred(listOf(".915", ".907"))
        assertTrue(format.dropsLeadingZero)
        assertEquals(3, format.decimals)
        assertEquals(".911", format.string(0.911))
    }

    /** Mixed precision in one column renders at the finer of the two. */
    @Test
    fun decimalsTakeTheMaximumSeen() {
        val format = MetricValueFormat.inferred(listOf("0.1", "0.12"))
        assertEquals(2, format.decimals)
        assertEquals("0.15", format.string(0.155))
    }

    @Test
    fun twoDecimalRateFormat() {
        val format = MetricValueFormat.inferred(listOf("0.05", "0.18"))
        assertFalse(format.isPercent)
        assertFalse(format.dropsLeadingZero)
        assertEquals("0.12", format.string(0.115))
    }

    @Test
    fun numericParsingHandlesFeedShapes() {
        assertEquals(1322.0, metricNumericValue("1,322")!!, 0.0)
        assertEquals(54.2, metricNumericValue("54.2%")!!, 0.0)
        assertEquals(2.3, metricNumericValue("+2.3")!!, 0.0)
        assertEquals(-1.4, metricNumericValue("-1.4")!!, 0.0)
        assertEquals(0.5, metricNumericValue(".5")!!, 0.0)
        assertEquals(0.915, metricNumericValue(".915")!!, 0.0)
        assertEquals(-0.5, metricNumericValue("-.5")!!, 0.0)
        assertNull(metricNumericValue("-"))
    }
}
