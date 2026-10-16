package com.jackwallner.hockey

import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricKind
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerTest {
    @Test
    fun overallPercentileDoubleAverage() {
        val metrics = listOf(metric("G", "1", 75), metric("A", "2", 76), metric("P", "3", 77))
        assertEquals(76, testPlayer(metrics = metrics).overallPercentile)
    }

    @Test
    fun shareSummaryIncludesTopSignal() {
        val player = testPlayer(name = "Connor Vale", metrics = listOf(metric("ixG", "31.4", 100, MetricCategory.SHOT_QUALITY)))
        val summary = player.shareSummary
        assertTrue(summary.contains("Connor Vale"))
        assertTrue(summary.contains("ixG"))
        assertTrue(summary.contains("100th"))
    }

    @Test
    fun multiCategoryOverallUsesBestCategoryAverage() {
        // A scoring winger who is a mediocre driver carries both Scoring and Play
        // Driving metrics. The headline reflects the best category, not a blend.
        val metrics = listOf(
            metric("P/60", "3.1", 95, MetricCategory.SCORING),
            metric("Primary P", "40", 95, MetricCategory.SCORING),
            metric("xGF%", "47.0%", 30, MetricCategory.PLAY_DRIVING),
            metric("CF%", "46.0%", 30, MetricCategory.PLAY_DRIVING),
        )
        assertEquals(95, testPlayer(name = "Dual Threat", team = "BUF", position = "LW", type = "f", metrics = metrics).overallPercentile)
    }

    @Test
    fun playerDecodesSeasonAndPlayerType() {
        val json = """
            {
                "id": 8478402, "name": "Test", "team": "SEA", "position": "C", "handedness": "L",
                "image_url": null, "updated_at": "2026-10-08T12:00:00Z", "season": 2026,
                "player_type": "f", "source": "moneypuck",
                "metrics": [], "standard_stats": [], "games": []
            }
        """.trimIndent()
        val player = Player.fromJson(Json.parseToJsonElement(json) as JsonObject)
        assertEquals(2026, player.season)
        assertEquals("f", player.playerType)
        assertEquals("moneypuck", player.source)
        assertEquals(SeasonPhase.REGULAR, player.seasonPhase)
    }

    @Test
    fun cohortFilteringKeepsSkatersAndGoaliesApart() {
        fun player(type: String?) = testPlayer(type = type)
        for (category in listOf(MetricCategory.SCORING, MetricCategory.SHOT_QUALITY, MetricCategory.PLAY_DRIVING)) {
            assertTrue(player("f").matchesPlayerType(category))
            assertTrue(player("d").matchesPlayerType(category))
            assertFalse(player("g").matchesPlayerType(category))
        }
        assertTrue(player("g").matchesPlayerType(MetricCategory.GOALTENDING))
        assertFalse(player("f").matchesPlayerType(MetricCategory.GOALTENDING))
        assertFalse(player("d").matchesPlayerType(MetricCategory.GOALTENDING))
        // An unknown or missing cohort is never dropped.
        assertTrue(player(null).matchesPlayerType(MetricCategory.GOALTENDING))
        assertTrue(player("x").matchesPlayerType(MetricCategory.SCORING))
        assertTrue(player("f").matchesPlayerType(null))
    }

    @Test
    fun primaryCategoryFollowsTheCohort() {
        assertEquals(MetricCategory.SCORING, testPlayer(type = "f").primaryCategory)
        assertEquals(MetricCategory.PLAY_DRIVING, testPlayer(type = "d").primaryCategory)
        assertEquals(MetricCategory.GOALTENDING, testPlayer(type = "g").primaryCategory)
    }

    @Test
    fun playerComparisonDoesNotCrossSkatersAndGoalies() {
        val center = testPlayer(1, "Center", "SEA", "C", type = "f")
        val defenseman = testPlayer(2, "Defenseman", "SEA", "D", type = "d")
        val goalie = testPlayer(3, "Goalie", "EDM", "G", type = "g")

        assertTrue(center.canCompareHeadToHead(defenseman))
        assertTrue(goalie.canCompareHeadToHead(goalie))
        assertFalse(center.canCompareHeadToHead(goalie))
        assertFalse(goalie.canCompareHeadToHead(defenseman))
    }

    @Test
    fun positionGroupFallsBackToTheRawPosition() {
        fun group(position: String) = testPlayer(position = position).positionGroup
        assertEquals(PlayerPositionGroup.FORWARD, group("C"))
        assertEquals(PlayerPositionGroup.FORWARD, group("L"))
        assertEquals(PlayerPositionGroup.FORWARD, group("R"))
        assertEquals(PlayerPositionGroup.DEFENSE, group("D"))
        assertEquals(PlayerPositionGroup.GOALIE, group("G"))
    }

    @Test
    fun initialsHandleSuffixes() {
        assertEquals("MP", testPlayer(name = "Michael Pittman Jr.").initials)
        assertEquals("OB", testPlayer(name = "Odell Beckham II", position = "L").initials)
        assertEquals("RG", testPlayer(name = "Robert Griffin III", team = "WSH", position = "D").initials)
    }

    @Test
    fun initialsStandardNames() {
        assertEquals("CV", testPlayer(name = "Connor Vale", team = "EDM").initials)
        assertEquals("RO", testPlayer(name = "Ryan O'Reilly", team = "NSH").initials)
        assertEquals("C", testPlayer(name = "Cher").initials)
    }

    @Test
    fun rawNumericStripsThousandsSeparators() {
        assertEquals(1312.0, DashboardViewModel.rawNumeric("1,312")!!, 0.001)
        assertEquals(54.2, DashboardViewModel.rawNumeric("54.2%")!!, 0.001)
        assertEquals(0.915, DashboardViewModel.rawNumeric(".915")!!, 0.0001)
    }

    @Test
    fun displayPositionFallsBackToPlayerType() {
        assertEquals("D", testPlayer(position = "TBD", type = "d").displayPosition)
        assertEquals("LW", testPlayer(position = "L", type = "f").displayPosition)
    }

    @Test
    fun seasonLabelDisplaysAsTwoYearForm() {
        assertEquals("2026-27", SeasonLabel.display(2026))
        assertEquals("2008-09", SeasonLabel.display(2008))
        assertEquals("2099-00", SeasonLabel.display(2099))
        assertEquals("All Time", SeasonLabel.display(StatScoutSeason.ALL_TIME))
        assertEquals("2026-27 Regular Season", SeasonLabel.display(2026, SeasonPhase.REGULAR))
        assertEquals("2025-26 Playoffs", SeasonLabel.display(2025, SeasonPhase.PLAYOFFS))
        assertEquals("All Time", SeasonLabel.display(StatScoutSeason.ALL_TIME, SeasonPhase.PLAYOFFS))
    }
}

class HockeyMetricRegistryTest {
    @Test
    fun advancedAndTraditionalClassification() {
        assertEquals(MetricKind.ADVANCED, HockeyMetricRegistry.kind(metric("ixG", "31.4", 90, MetricCategory.SHOT_QUALITY)))
        assertEquals(MetricKind.TRADITIONAL, HockeyMetricRegistry.kind(metric("G", "44", 85, MetricCategory.SCORING)))
        assertEquals(MetricKind.ADVANCED, HockeyMetricRegistry.kind(metric("GSAx", "+12.3", 95, MetricCategory.GOALTENDING)))
        assertEquals(MetricKind.TRADITIONAL, HockeyMetricRegistry.kind(metric("SV%", ".915", 70, MetricCategory.GOALTENDING)))
    }

    @Test
    fun everyCohortHasAdvancedAndTraditionalDefinitions() {
        for (position in PlayerPositionGroup.entries) {
            val definitions = HockeyMetricRegistry.definitions.filter { position in it.positions }
            assertTrue("$position", definitions.isNotEmpty())
            assertTrue("$position", definitions.any { it.kind == MetricKind.ADVANCED })
            assertTrue("$position", definitions.any { it.kind == MetricKind.TRADITIONAL })
        }
    }

    @Test
    fun skaterMetricsAreNotOfferedToGoaliesAndBack() {
        val ixg = metric("ixG", "31.4", 90, MetricCategory.SHOT_QUALITY)
        val gsax = metric("GSAx", "+12.3", 95, MetricCategory.GOALTENDING)
        assertTrue(HockeyMetricRegistry.isSupported(ixg, PlayerPositionGroup.FORWARD))
        assertTrue(HockeyMetricRegistry.isSupported(ixg, PlayerPositionGroup.DEFENSE))
        assertFalse(HockeyMetricRegistry.isSupported(ixg, PlayerPositionGroup.GOALIE))
        assertTrue(HockeyMetricRegistry.isSupported(gsax, PlayerPositionGroup.GOALIE))
        assertFalse(HockeyMetricRegistry.isSupported(gsax, PlayerPositionGroup.FORWARD))
    }

    /** Getting a direction backwards would put the worst goalie in the league at the top of the board. */
    @Test
    fun lowerIsBetterMetricsRankAscending() {
        val lower = listOf(
            "xGA/60" to MetricCategory.PLAY_DRIVING, "Giveaways" to MetricCategory.PLAY_DRIVING,
            "GAA" to MetricCategory.GOALTENDING, "GA" to MetricCategory.GOALTENDING, "Rebound%" to MetricCategory.GOALTENDING,
        )
        for ((label, category) in lower) {
            val definition = HockeyMetricRegistry.definition(label, category)
            assertNotNull("missing $label", definition)
            assertFalse("$label should rank lower-is-better", definition!!.higherIsBetter)
        }
        val higher = listOf(
            "ixG" to MetricCategory.SHOT_QUALITY, "xGF%" to MetricCategory.PLAY_DRIVING, "Blocks" to MetricCategory.PLAY_DRIVING,
            "GSAx" to MetricCategory.GOALTENDING, "SV%" to MetricCategory.GOALTENDING, "HD SV%" to MetricCategory.GOALTENDING,
        )
        for ((label, category) in higher) {
            assertEquals("$label should rank higher-is-better", true, HockeyMetricRegistry.definition(label, category)?.higherIsBetter)
        }
    }

    /** xGA/60 is a skater's on-ice result and a goalie's workload. The registry keys on both. */
    @Test
    fun sharedLabelsResolveByCategory() {
        val skater = HockeyMetricRegistry.definition("xGA/60", MetricCategory.PLAY_DRIVING)
        val goalie = HockeyMetricRegistry.definition("xGA/60", MetricCategory.GOALTENDING)
        assertEquals(false, skater?.higherIsBetter)
        assertEquals(true, goalie?.higherIsBetter)
        assertEquals(setOf(PlayerPositionGroup.FORWARD, PlayerPositionGroup.DEFENSE), skater?.positions)
        assertEquals(setOf(PlayerPositionGroup.GOALIE), goalie?.positions)
    }

    @Test
    fun advancedMetricsLeadDisplayOrder() {
        for (category in MetricCategory.entries) {
            val order = category.metricPriorityOrder
            val inCategory = HockeyMetricRegistry.definitions.filter { it.category == category }
            val lastAdvanced = inCategory.filter { it.kind == MetricKind.ADVANCED }.map { order.indexOf(it.label) }.filter { it >= 0 }.maxOrNull()
            val firstTraditional = inCategory.filter { it.kind == MetricKind.TRADITIONAL }.map { order.indexOf(it.label) }.filter { it >= 0 }.minOrNull()
            assertNotNull("advanced in $category", lastAdvanced)
            assertNotNull("traditional in $category", firstTraditional)
            assertTrue("$category", lastAdvanced!! < firstTraditional!!)
        }
    }

    @Test
    fun positionHeadlinePreferences() {
        assertEquals("ixG", PlayerPositionGroup.FORWARD.preferredAdvancedMetrics.first())
        assertEquals("xGF%", PlayerPositionGroup.DEFENSE.preferredAdvancedMetrics.first())
        assertEquals("GSAx", PlayerPositionGroup.GOALIE.preferredAdvancedMetrics.first())
        assertEquals("SV%", PlayerPositionGroup.GOALIE.preferredTraditionalMetrics.first())
        assertEquals(MetricCategory.SCORING, PlayerPositionGroup.FORWARD.primaryCategory)
        assertEquals(MetricCategory.PLAY_DRIVING, PlayerPositionGroup.DEFENSE.primaryCategory)
        assertEquals(MetricCategory.GOALTENDING, PlayerPositionGroup.GOALIE.primaryCategory)
        assertEquals(listOf(MetricCategory.SCORING, MetricCategory.SHOT_QUALITY, MetricCategory.PLAY_DRIVING), PlayerPositionGroup.FORWARD.categories)
        assertEquals(listOf(MetricCategory.GOALTENDING), PlayerPositionGroup.GOALIE.categories)
    }

    @Test
    fun lowerIsBetterUsesRegistry() {
        assertTrue(DashboardViewModel.lowerIsBetter("GAA", MetricCategory.GOALTENDING))
        assertTrue(DashboardViewModel.lowerIsBetter("Giveaways", MetricCategory.PLAY_DRIVING))
        assertFalse(DashboardViewModel.lowerIsBetter("ixG", MetricCategory.SHOT_QUALITY))
        assertFalse(DashboardViewModel.defaultSortDescending("GAA", MetricCategory.GOALTENDING))
        assertTrue(DashboardViewModel.defaultSortDescending("GSAx", MetricCategory.GOALTENDING))
    }

    @Test
    fun unknownMetricIsPreserved() {
        val unknown = metric("New Metric", "1.0", 50)
        assertEquals(MetricKind.ADVANCED, HockeyMetricRegistry.kind(unknown))
        assertTrue(HockeyMetricRegistry.isSupported(unknown, PlayerPositionGroup.GOALIE))
        assertEquals(listOf(unknown), HockeyMetricRegistry.sorted(listOf(unknown)))
    }

    @Test
    fun metricCategoryDecodesCaseInsensitively() {
        for (raw in listOf("shot quality", "SHOT QUALITY", "Shot Quality")) {
            val json = """{"id":"m","label":"ixG","value":"31.4","percentile":88,"category":"$raw"}"""
            assertEquals(MetricCategory.SHOT_QUALITY, Metric.fromJson(Json.parseToJsonElement(json) as JsonObject).category)
        }
    }

    /** The historical bundle leaves the id out; it is rebuilt from the category and label. */
    @Test
    fun metricDecodesWithoutAnId() {
        val json = """{"label":"xGF%","value":"54.2%","percentile":91,"category":"Play Driving"}"""
        val metric = Metric.fromJson(Json.parseToJsonElement(json) as JsonObject)
        assertEquals("play-driving-xGF%", metric.id)
        assertEquals(MetricCategory.PLAY_DRIVING, metric.category)
        assertEquals("goaltending-GSAx", Metric.derivedId(MetricCategory.GOALTENDING, "GSAx"))
    }
}
