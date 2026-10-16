package com.jackwallner.hockey

import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.DashboardViewModel.QualifierLevel
import com.jackwallner.hockey.data.InMemoryStore
import com.jackwallner.hockey.data.PlayerSnapshotValidator
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.LeagueConference
import com.jackwallner.hockey.model.LeagueDivision
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.leagueTeamAbbreviations
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.model.teamNickname
import java.io.IOException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DashboardViewModelTest {
    private val current = StatScoutSeason.current

    private fun historicalPlayers() = (StatScoutSeason.EARLIEST until current).flatMap { completeSeasonPlayers(it, "Historical") }

    private val expectedSeasons: List<Int>
        get() = listOf(StatScoutSeason.ALL_TIME) + (StatScoutSeason.EARLIEST..current).toList().reversed()

    @Test
    fun allMetricsKeyCollision() = runTest {
        val players = listOf(
            testPlayer(1, "A", "SEA", "C", current, type = "f", metrics = listOf(metric("xGA/60", "2.41", 90, MetricCategory.PLAY_DRIVING, id = "m1"))),
            testPlayer(2, "B", "EDM", "G", current, type = "g", metrics = listOf(metric("xGA/60", "2.80", 85, MetricCategory.GOALTENDING, id = "m2"))),
        )
        val vm = dashboard(MockProvider(players))
        vm.load()
        assertEquals("Same label in different categories should produce 2 entries", 2, vm.allMetrics.size)
        assertEquals(setOf(MetricCategory.PLAY_DRIVING, MetricCategory.GOALTENDING), vm.allMetrics.map { it.category }.toSet())
    }

    @Test
    fun loadDistinguishesErrors() = runTest {
        val format = dashboard(MockProvider(error = SerializationException("bad row")))
        format.load()
        assertTrue(format.errorMessage?.contains("format changed") == true)

        val offline = dashboard(MockProvider(error = IOException("offline")))
        offline.load()
        assertTrue(offline.errorMessage?.contains("connection") == true)
    }

    @Test
    fun lastUpdatedReturnsNullWhenEmpty() = runTest {
        assertNull(dashboard(MockProvider()).lastUpdated)
    }

    @Test
    fun teamFullNameReturnsCorrectFullName() {
        assertEquals("Seattle Kraken", teamFullName("SEA"))
        assertEquals("Tampa Bay Lightning", teamFullName("TBL"))
        assertEquals("Vegas Golden Knights", teamFullName("VGK"))
        assertEquals("Unknown", teamFullName("Unknown"))
        assertEquals("Maple Leafs", teamNickname("TOR"))
        assertEquals("Lightning", teamNickname("TBL"))
    }

    @Test
    fun playersForTeamMatchesAliases() = runTest {
        val players = listOf(
            testPlayer(1, "A", "Seattle Kraken", "C", 2025),
            testPlayer(2, "B", "LV", "L", 2025),
        )
        val vm = dashboard(MockProvider(players))
        vm.selectedSeason = 2025
        vm.load()

        assertEquals(listOf(1), vm.players("SEA").map { it.playerId })
        assertEquals(listOf(2), vm.players("VGK").map { it.playerId })
    }

    @Test
    fun conferenceFilterScopesPlayersTeamsAndMetrics() = runTest {
        val players = listOf(
            testPlayer(1, "East Player", "BOS", "C", 2025, type = "f", metrics = listOf(metric("ixG", "28.0", 90, MetricCategory.SHOT_QUALITY, id = "east"))),
            testPlayer(2, "West Player", "SEA", "C", 2025, type = "f", metrics = listOf(metric("GAx", "+3.1", 80, MetricCategory.SHOT_QUALITY, id = "west"))),
        )
        val vm = dashboard(MockProvider(players))
        vm.selectedSeason = 2025
        vm.load()

        vm.selectedConference = LeagueConference.EAST
        vm.searchText = "Boston"
        assertEquals(listOf("East Player"), vm.filteredPlayers.map { it.name })
        assertEquals(listOf("BOS"), vm.searchedTeams)
        assertEquals(listOf("ixG"), vm.allMetrics.map { it.label })

        vm.selectedConference = LeagueConference.WEST
        vm.searchText = "Seattle"
        assertEquals(listOf("West Player"), vm.filteredPlayers.map { it.name })
        assertEquals(listOf("SEA"), vm.searchedTeams)
        assertEquals(listOf("GAx"), vm.allMetrics.map { it.label })
    }

    @Test
    fun conferencesAndDivisionsPartitionTheLeague() {
        assertEquals(32, leagueTeamAbbreviations.size)
        assertEquals(4, LeagueDivision.entries.size)
        val divisionTeams = LeagueDivision.entries.flatMap { it.teams }
        assertEquals(leagueTeamAbbreviations.toSet(), divisionTeams.toSet())
        assertEquals(32, divisionTeams.size)
        assertEquals(LeagueDivision.PACIFIC, LeagueDivision.of("Seattle Kraken"))
        assertEquals(LeagueConference.WEST, LeagueDivision.PACIFIC.conference)
        assertEquals(LeagueDivision.ATLANTIC, LeagueDivision.of("TBL"))
        assertTrue(LeagueConference.EAST.contains("NYR"))
        assertFalse(LeagueConference.EAST.contains("SEA"))
        assertTrue(LeagueConference.ALL.contains("SEA"))
    }

    @Test
    fun teamCountsPopulatedAfterLoad() = runTest {
        val players = listOf(
            testPlayer(1, "A", "SEA", "C", 2025),
            testPlayer(2, "B", "SEA", "D", 2025),
            testPlayer(3, "C", "VAN", "G", 2025),
        )
        val vm = dashboard(MockProvider(players))
        vm.selectedSeason = 2025
        vm.load()
        assertEquals(2, vm.teamCounts["SEA"])
        assertEquals(1, vm.teamCounts["VAN"])
    }

    @Test
    fun partialRefreshPreservesCompleteCache() = runTest {
        val cached = completeCurrentPlayers()
        val cache = InMemoryPlayerCache(cached)
        val vm = dashboard(MockProvider(cached.take(5)), cache)

        vm.load()

        assertEquals(cached.size, vm.seasonPlayers.size)
        assertEquals(leagueTeamAbbreviations.size, vm.teamsWithData.size)
        assertTrue(vm.lastFetchFailed)
        assertEquals(cached.size, cache.savedPlayers.size)
    }

    @Test
    fun completeRefreshReplacesCurrentCache() = runTest {
        val refreshed = completeCurrentPlayers("Fresh")
        val cache = InMemoryPlayerCache(completeCurrentPlayers())
        val vm = dashboard(MockProvider(refreshed), cache)

        vm.load()

        assertEquals(refreshed.size, vm.seasonPlayers.size)
        assertTrue(vm.seasonPlayers.all { it.name.startsWith("Fresh") })
        assertEquals(refreshed.size, cache.savedPlayers.size)
    }

    @Test
    fun cacheHydratesPlayersBeforeFetch() = runTest {
        val cached = listOf(testPlayer(99, "Cached", "SEA", "C", season = null))
        val vm = dashboard(MockProvider(error = IOException("offline")), InMemoryPlayerCache(cached))
        vm.load()
        assertEquals("Cached players should be shown even when refresh fails", listOf("99-0-REG"), vm.players.map { it.id })
    }

    @Test
    fun sortLabelReflectsCategory() = runTest {
        val forwards = listOf(
            testPlayer(1, "A", "SEA", "C", current, type = "f", metrics = listOf(metric("ixG", "31.4", 90, MetricCategory.SHOT_QUALITY, id = "m1"))),
        )
        val vm = dashboard(MockProvider(forwards))
        vm.load()
        // Default cohort is forwards, which lead with ixG.
        assertEquals("ixG", vm.sortLabel)

        val goalies = listOf(
            testPlayer(2, "B", "EDM", "G", current, type = "g", metrics = listOf(metric("GSAx", "+14.2", 95, MetricCategory.GOALTENDING, id = "m1"))),
        )
        val goalieBoard = dashboard(MockProvider(goalies))
        goalieBoard.load()
        goalieBoard.selectedCategory = MetricCategory.GOALTENDING
        assertEquals(PlayerPositionGroup.GOALIE, goalieBoard.selectedPosition)
        assertEquals("GSAx", goalieBoard.sortLabel)

        // Empty data falls back to the default label.
        val empty = dashboard(MockProvider())
        empty.load()
        empty.selectedCategory = MetricCategory.SCORING
        assertEquals("Top Metric", empty.sortLabel)

        // A null category leaves the cohort alone.
        val unset = dashboard(MockProvider(forwards))
        unset.load()
        unset.selectedCategory = null
        assertEquals("ixG", unset.sortLabel)
    }

    @Test
    fun cohortSortUsesAvailableMetrics() = runTest {
        val defenseman = testPlayer(
            1, "Test D", "SEA", "D", current, type = "d",
            metrics = listOf(
                metric("Blocks", "150", 85, MetricCategory.PLAY_DRIVING, id = "m1"),
                metric("Hits", "90", 70, MetricCategory.PLAY_DRIVING, id = "m2"),
            ),
        )
        val vm = dashboard(MockProvider(listOf(defenseman)))
        vm.load()
        vm.selectedPosition = PlayerPositionGroup.DEFENSE

        assertEquals(1, vm.filteredPlayers.size)
        // None of the defense headline metrics exist, so it falls to the first available one.
        assertEquals("Blocks", vm.sortLabel)
        assertEquals(1, vm.leaderboard.first().playerId)
        // Skaters never show on the goalie board.
        vm.selectedPosition = PlayerPositionGroup.GOALIE
        assertTrue(vm.filteredPlayers.isEmpty())
    }

    @Test
    fun historicalArchiveRequiresEverySupportedSeason() {
        val complete = historicalPlayers()
        assertTrue(PlayerSnapshotValidator.isCompleteHistorical(complete))

        val missingEarliest = complete.filter { it.season != StatScoutSeason.EARLIEST }
        assertFalse(PlayerSnapshotValidator.isCompleteHistorical(missingEarliest))
    }

    @Test
    fun availableSeasonsIncludes2008ThroughCurrentPlusAllTime() = runTest {
        val vm = dashboard(MockProvider(historicalPlayers() + completeCurrentPlayers()))
        vm.applyProState(true)

        vm.load()

        assertEquals(expectedSeasons, vm.availableSeasons)
        assertEquals(StatScoutSeason.ALL_TIME, vm.availableSeasons.first())
    }

    @Test
    fun availableSeasonsIncludesLockedHistoryBeforeHistoryLoads() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertEquals(expectedSeasons, vm.availableSeasons)
        assertTrue(vm.isSeasonLocked(current - 1))
    }

    /** All Time is Pro, like every season other than the current one. */
    @Test
    fun allTimeIsLockedForFreeUsers() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.applyProState(false)
        assertTrue(vm.isSeasonLocked(StatScoutSeason.ALL_TIME))
        vm.applyProState(true)
        assertFalse(vm.isSeasonLocked(StatScoutSeason.ALL_TIME))
    }

    /** The free season is the calendar's season, even before its data lands. */
    @Test
    fun freeSeasonIsTheCalendarSeasonEvenBeforeItsDataLands() = runTest {
        val vm = dashboard(MockProvider(completeSeasonPlayers(current - 1, "LastYear")))

        vm.load()

        assertEquals(current, vm.freeSeason)
        assertEquals(current, vm.selectedSeason)
        assertTrue(vm.isSeasonLocked(current - 1))
        assertTrue(vm.availableSeasons.contains(current))
    }

    /** Opening night: two teams have played. The live season is still the default, for Pro too. */
    @Test
    fun aThinLiveSeasonIsStillTheDefault() = runTest {
        val lastSeason = completeSeasonPlayers(current - 1, "LastYear")
        val opener = completeCurrentPlayers("Opener").filter { it.team in listOf("EDM", "SEA") }
        val vm = dashboard(MockProvider(lastSeason + opener))
        vm.applyProState(true)

        vm.load()

        assertEquals(current, vm.selectedSeason)
        assertFalse(vm.isSeasonLocked(current))
        assertTrue(vm.players.any { it.season == current })
    }

    /** All Players (the default) keeps small samples dimmed below qualified ones; Qualified hides them. */
    @Test
    fun qualifiedFilterHonoursTheLiveSeasonFlag() = runTest {
        val store = InMemoryStore()
        val starter = testPlayer(
            1, "Starter", "BOS", "C", current, type = "f",
            metrics = listOf(metric("ixG", "10.0", 60, MetricCategory.SHOT_QUALITY, qualified = true, id = "s")),
        )
        val backup = testPlayer(
            2, "Backup", "SEA", "C", current, type = "f",
            metrics = listOf(metric("ixG", "1.9", 99, MetricCategory.SHOT_QUALITY, qualified = false, id = "b")),
        )
        val vm = dashboard(MockProvider(listOf(starter, backup)), store = store)
        vm.load()

        assertEquals(QualifierLevel.ALL, vm.qualifierLevel)
        // The backup's 99th percentile outranks the starter, but a small sample never tops a board.
        assertEquals(listOf("Starter", "Backup"), vm.leaderboard.map { it.name })
        vm.qualifierLevel = QualifierLevel.QUALIFIED
        assertEquals(listOf("Starter"), vm.leaderboard.map { it.name })
        assertEquals("the choice persists", QualifierLevel.QUALIFIED, dashboard(MockProvider(), store = store).qualifierLevel)
    }

    @Test
    fun metricDecodesWithAndWithoutTheQualifiedFlag() {
        val json = """
            [{"id":"a","label":"ixG","value":"3.1","percentile":50,"category":"Shot Quality","qualified":false},
             {"id":"b","label":"ixG","value":"4.2","percentile":60,"category":"Shot Quality"}]
        """.trimIndent()
        val metrics = (Json.parseToJsonElement(json) as JsonArray).map { Metric.fromJson(it as JsonObject) }
        assertEquals(listOf(false, null), metrics.map { it.qualified })
    }

    /** Recent form covers the live season and the one before it, as rules rather than literal years. */
    @Test
    fun recentFormCoversTheLiveSeasonAndTheOneBefore() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertEquals(current, vm.recentFormSeason)
        assertEquals("Newest first", vm.freeSeason, vm.recentFormSeasons.first())
        assertTrue(vm.recentFormSeasons.size <= 2)
        assertEquals(vm.recentFormSeasons.sortedDescending(), vm.recentFormSeasons)
        assertTrue(vm.supportsRecentForm(vm.freeSeason))
        vm.recentFormSeasons.forEach { assertTrue(vm.supportsRecentForm(it)) }
        assertFalse(vm.supportsRecentForm(StatScoutSeason.ALL_TIME))
    }

    /** Never offer a season the rollup table no longer holds. */
    @Test
    fun recentFormNeverOffersAPurgedSeason() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        vm.recentFormSeasons.forEach { assertTrue(it >= StatScoutSeason.EARLIEST_RECENT_FORM) }
        assertFalse(vm.supportsRecentForm(StatScoutSeason.EARLIEST_RECENT_FORM - 1))
    }

    /** The floor is a fact about the database: moving it down without re-ingesting puts an empty year in Trends. */
    @Test
    fun recentFormFloorMatchesTheSeasonsTheRollupStillHolds() {
        assertEquals(2025, StatScoutSeason.EARLIEST_RECENT_FORM)
        assertTrue(
            "The floor can never sit above the live season, or Recent Form vanishes entirely",
            StatScoutSeason.EARLIEST_RECENT_FORM <= current,
        )
    }

    /** Once the new season's rows land, it is the free season and last season is Pro. */
    @Test
    fun theAppMovesToTheNewSeasonTheDayItsDataLands() = runTest {
        val lastSeason = current - 1
        val postKickoff = dashboard(MockProvider(completeSeasonPlayers(lastSeason, "LastYear") + completeCurrentPlayers()))
        postKickoff.load()

        assertEquals("and moves on by itself once rows land", current, postKickoff.freeSeason)
        assertFalse(postKickoff.isSeasonLocked(current))
        assertTrue("last season becomes Pro, not gone", postKickoff.isSeasonLocked(lastSeason))
        assertTrue(postKickoff.availableSeasons.contains(lastSeason))

        assertEquals(current, postKickoff.recentFormSeasons.first())
        assertEquals(listOf(current, lastSeason).filter { it >= StatScoutSeason.EARLIEST_RECENT_FORM }, postKickoff.recentFormSeasons)
    }

    @Test
    fun freeSeasonIsTheCurrentSeasonOnceItHasData() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertEquals(current, vm.freeSeason)
        assertFalse(vm.isSeasonLocked(current))
    }

    /** History is loaded on demand, so the first tap on a past season has to start that load. */
    @Test
    fun selectingAPastSeasonLoadsTheHistoryItNeeds() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.applyProState(true)
        vm.load()
        assertFalse("History should still be unfetched after a plain load", vm.hasLoadedHistorical)

        vm.selectSeason(StatScoutSeason.ALL_TIME)

        // The header moves on the tap; the rows arrive behind it.
        assertEquals(StatScoutSeason.ALL_TIME, vm.selectedSeason)
        assertNotNull("Choosing a past season should start the history load", vm.seasonLoadJob)
        vm.seasonLoadJob?.join()
    }

    /** The live season needs no extra fetch, so it must not start one. */
    @Test
    fun selectingTheFreeSeasonDoesNotRefetchHistory() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.load()

        vm.selectSeason(vm.freeSeason)

        assertNull(vm.seasonLoadJob)
    }

    /** Trends ranks rolling week windows, so a career has nothing to rank. */
    @Test
    fun trendsSeasonListExcludesAllTime() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertFalse(vm.seasonsExcludingAllTime.contains(StatScoutSeason.ALL_TIME))
        assertEquals(vm.availableSeasons.size - 1, vm.seasonsExcludingAllTime.size)
    }

    /** The sentinel must never reach the UI as "0", and a real season reads as the two years it spans. */
    @Test
    fun seasonLabelRendersSentinelAsAllTime() {
        assertEquals("All Time", SeasonLabel.display(StatScoutSeason.ALL_TIME))
        assertEquals("2024-25", SeasonLabel.display(2024))
        assertEquals("All Time", SeasonLabel.display(StatScoutSeason.ALL_TIME, SeasonPhase.REGULAR))
        assertEquals("2024-25 Playoffs", SeasonLabel.display(2024, SeasonPhase.PLAYOFFS))
    }

    @Test
    fun seasonIndicatorHasNoGroupingAndShowsBothYears() {
        val formatted = SeasonLabel.display(2026)
        assertEquals("2026-27", formatted)
        assertFalse("Season should not contain comma separators", formatted.contains(","))
    }

    @Test
    fun seasonPhaseAlwaysReadsAsAFullName() {
        assertEquals("Regular Season", SeasonPhase.REGULAR.label)
        assertEquals("Playoffs", SeasonPhase.PLAYOFFS.label)
    }

    @Test
    fun seasonPlayersReturnsPlayersForSelectedSeason() = runTest {
        val vm = dashboard(MockProvider(listOf(testPlayer(1, "Player 2025", "SEA", "C", 2025), testPlayer(2, "Player 2024", "BOS", "C", 2024))))
        vm.load()

        vm.selectedSeason = 2025
        assertEquals(1, vm.seasonPlayers.size)
        assertEquals(1, vm.seasonPlayers.first().playerId)

        vm.selectedSeason = 2024
        assertEquals(1, vm.seasonPlayers.size)
        assertEquals(2, vm.seasonPlayers.first().playerId)
    }

    @Test
    fun seasonPlayersIsEmptyWhenSeasonHasNoData() = runTest {
        val vm = dashboard(MockProvider(listOf(testPlayer(1, "Player 2025", "SEA", "C", 2025))))
        vm.load()

        // 2024 has no data, so it reports empty with no stale fallback.
        vm.selectedSeason = 2024
        assertTrue(vm.seasonPlayers.isEmpty())
    }

    @Test
    fun loadNeverSnapsAwayFromTheLiveSeason() = runTest {
        val vm = dashboard(MockProvider(listOf(testPlayer(1, "Last Season", "SEA", "C", current - 1))))
        vm.applyProState(true)
        vm.load()
        assertEquals(current, vm.selectedSeason)
    }
}
