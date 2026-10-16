package com.jackwallner.hockey

import com.jackwallner.hockey.data.PlayerSnapshotValidator
import com.jackwallner.hockey.data.TwoTierPlayerCache
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.StatScoutSeason
import java.io.File
import java.nio.file.Files
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpeningWeekCacheTest {
    private val directory: File = Files.createTempDirectory("opening-week").toFile()

    @After
    fun cleanUp() {
        directory.deleteRecursively()
    }

    private fun cache() = TwoTierPlayerCache(directory) { null }

    private fun players(oneTeam: Boolean = false, season: Int = StatScoutSeason.current): List<Player> = (0 until 30).map { index ->
        testPlayer(
            id = index, name = "Player $index", team = if (oneTeam || index < 15) "SEA" else "EDM",
            season = season, type = listOf("f", "d", "g")[index % 3],
            updatedAt = Instant.EPOCH,
            metrics = listOf(
                metric("P/60", "2.1", 50, MetricCategory.SCORING, id = "scoring"),
                metric("ixG", "3.1", 50, MetricCategory.SHOT_QUALITY, id = "shots"),
                metric("GSAx", "+1.2", 50, MetricCategory.GOALTENDING, id = "goalie"),
            ),
        )
    }

    @Test
    fun completeOpeningGameIsCacheableBeforeFullSlate() {
        assertTrue(PlayerSnapshotValidator.isCompleteCurrent(players()))
    }

    @Test
    fun onlyOneTeamIsNotACompleteOpeningGame() {
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(oneTeam = true)))
    }

    @Test
    fun openingGameStillRequiresEveryCohort() {
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(players().filter { it.playerType != "g" }))
    }

    @Test
    fun lastYearsOpeningGameIsNotCurrentData() {
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(season = StatScoutSeason.current - 1)))
    }

    @Test
    fun expiredSavedSnapshotIsKeptAndNotRestamped() {
        val cache = cache()
        cache.saveCurrentPlayers(players())
        val file = File(directory, "players-current.json")
        val weekAgo = System.currentTimeMillis() - 7 * 24 * 60 * 60 * 1000L
        assertTrue(file.setLastModified(weekAgo))

        assertEquals(30, cache.loadCurrentPlayers().size)
        assertEquals(weekAgo.toDouble(), file.lastModified().toDouble(), 1000.0)
    }

    @Test
    fun noSavedSnapshotServesNoCurrentPlayers() {
        assertTrue(cache().loadCurrentPlayers().isEmpty())
    }
}
