package com.jackwallner.hockey

import com.jackwallner.hockey.data.PlayerSnapshotValidator
import com.jackwallner.hockey.data.TwoTierPlayerCache
import com.jackwallner.hockey.data.toJson
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.ui.nav.Route
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonArray
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regressions for the three context bugs found in the 1.2.1 audit: an
 * unprovenanced current-season cache surviving an upgrade, a team page whose
 * roster ignored its own season picker, and drill-down routes that dropped
 * the phase they were opened from.
 */
class UpgradeContextTest {
    private val directory: File = Files.createTempDirectory("upgrade-context").toFile()
    private val current = StatScoutSeason.current

    @After
    fun cleanUp() {
        directory.deleteRecursively()
    }

    private fun cache() = TwoTierPlayerCache(directory) { null }

    private fun players(
        teams: List<String>, count: Int, season: Int = current, phase: SeasonPhase = SeasonPhase.REGULAR, idOffset: Int = 0,
    ): List<Player> = (0 until count).map { index ->
        testPlayer(
            id = idOffset + index, name = "Player ${idOffset + index}", team = teams[index % teams.size],
            season = season, phase = phase, type = listOf("f", "d", "g")[index % 3],
            updatedAt = Instant.EPOCH,
            metrics = listOf(
                metric("P/60", "2.1", 50, MetricCategory.SCORING, id = "scoring"),
                metric("ixG", "3.1", 50, MetricCategory.SHOT_QUALITY, id = "shots"),
                metric("GSAx", "+1.2", 50, MetricCategory.GOALTENDING, id = "goalie"),
            ),
        )
    }

    private fun writeWithoutProvenance(rows: List<Player>): File {
        directory.mkdirs()
        val file = File(directory, "players-current.json")
        file.writeText(buildJsonArray { rows.forEach { add(it.toJson()) } }.toString())
        return file
    }

    /**
     * The shape of the artifact 1.2 shipped: a real server export, but only the
     * teams that had played by then. It passes `isCompleteCurrent` by design, so
     * the validator can never be what separates it from a full snapshot.
     */
    @Test
    fun pre122CacheWithoutProvenanceIsDiscardedOnUpgrade() {
        val openingWeek = players(listOf("VAN", "EDM", "SEA", "CGY"), 110)
        assertTrue(
            "The 1.2 artifact has to clear the opening-week rule, or this test isn't reproducing the bug",
            PlayerSnapshotValidator.isCompleteCurrent(openingWeek),
        )
        val file = writeWithoutProvenance(openingWeek)

        assertTrue("A snapshot of unknown origin must never populate the current board", cache().loadCurrentPlayers().isEmpty())
        assertFalse("The discarded snapshot should be removed, not re-read on every launch", file.exists())
    }

    @Test
    fun snapshotSavedByThisBuildIsTrustedOnReload() {
        val cache = cache()
        cache.saveCurrentPlayers(players(listOf("SEA", "EDM"), 30))

        assertEquals(30, cache.loadCurrentPlayers().size)
        assertTrue(File(directory, "players-current-provenance.json").exists())
        // Still trusted on a second read: the marker is not consumed.
        assertEquals(30, cache().loadCurrentPlayers().size)
    }

    @Test
    fun discardedSnapshotIsReplacedByTheNextServerSave() {
        writeWithoutProvenance(players(listOf("VAN", "EDM", "SEA", "CGY"), 110))

        val cache = cache()
        assertTrue(cache.loadCurrentPlayers().isEmpty())

        cache.saveCurrentPlayers(players(listOf("SEA", "EDM", "BOS", "BUF"), 40))
        assertEquals(40, cache.loadCurrentPlayers().size)
    }

    @Test
    fun teamRosterFollowsSelectedSeasonAndPhase() = runTest {
        val seaThisYear = players(listOf("SEA"), 5, current)
        val seaLastYear = players(listOf("SEA"), 3, current - 1, idOffset = 100)
        val seaPlayoffs = players(listOf("SEA"), 2, current - 1, SeasonPhase.PLAYOFFS, idOffset = 200)
        val vm = dashboard(MockProvider(seaThisYear + seaLastYear + seaPlayoffs))
        vm.load()

        vm.selectedSeason = current
        vm.selectedPhase = SeasonPhase.REGULAR
        assertEquals(5, vm.players("SEA").size)

        // The team page derives its roster from exactly this call, so moving
        // the page's picker has to move the rows underneath it.
        vm.selectedSeason = current - 1
        assertEquals(3, vm.players("SEA").size)

        vm.selectedPhase = SeasonPhase.PLAYOFFS
        assertEquals(2, vm.players("SEA").size)
    }

    @Test
    fun playersForSeasonHonoursAnExplicitPhase() = runTest {
        val regular = players(listOf("SEA", "EDM"), 6, current - 1)
        val playoffs = players(listOf("SEA", "EDM"), 2, current - 1, SeasonPhase.PLAYOFFS, idOffset = 50)
        val vm = dashboard(MockProvider(regular + playoffs))
        vm.load()
        vm.selectedPhase = SeasonPhase.REGULAR

        // A route opened from a playoff profile resolves against its own phase,
        // not whichever one the tab happens to be sitting on.
        assertEquals(2, vm.players(current - 1, SeasonPhase.PLAYOFFS).size)
        assertEquals(6, vm.players(current - 1, SeasonPhase.REGULAR).size)
    }

    @Test
    fun routesCarrySeasonAndPhase() {
        val metric = Route.Metric("ixG", MetricCategory.SHOT_QUALITY, 2024, SeasonPhase.PLAYOFFS)
        assertEquals(2024, metric.season)
        assertEquals(SeasonPhase.PLAYOFFS, metric.phase)

        val standard = Route.StandardStat("SOG", PlayerPositionGroup.FORWARD, 2024, SeasonPhase.PLAYOFFS)
        assertEquals(2024, standard.season)
        assertEquals(SeasonPhase.PLAYOFFS, standard.phase)

        // Two routes to the same stat in the same year but different halves of
        // it are different destinations, or the stack coalesces them.
        assertNotEquals(metric, Route.Metric("ixG", MetricCategory.SHOT_QUALITY, 2024, SeasonPhase.REGULAR))
    }
}
