package com.jackwallner.hockey

import com.jackwallner.hockey.model.DataCoverage
import com.jackwallner.hockey.model.DataFreshness
import com.jackwallner.hockey.model.DataFreshnessStatus
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.ui.components.shortAge
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DataFreshnessTest {
    @Test
    fun productionStatusDecodesCoverageAndPendingEnrichment() {
        val json = """
            {"status":"degraded","refresh_id":"v2","source_published_at":"2026-09-12T12:00:00Z",
             "published_at":"2026-09-12T12:05:00Z","last_checked_at":"2026-09-12T12:10:00Z",
             "max_game_date":"2026-09-10","max_week":1,"observed_games":2,"expected_games":2,"season_type":"REG"}
        """.trimIndent()
        val status = DataFreshness.fromJson(Json.parseToJsonElement(json) as JsonObject)
        assertEquals(DataFreshnessStatus.PARTIAL, status.status)
        assertEquals("v2", status.revision)
        assertEquals(1, status.coverage?.week)
        assertEquals(2, status.coverage?.gamesIncluded)
        assertNotEquals(status.sourcePublishedAt, status.checkedAt)
    }

    @Test
    fun publishedCoreRevisionIsAdoptedWithAdvancedMetricsPending() = runTest {
        val vm = dashboard(RevisionProvider(listOf("v1", "v1"), DataFreshnessStatus.PARTIAL))
        vm.load()
        assertEquals("v1", vm.freshnessRevision)
        assertEquals(DataFreshnessStatus.PARTIAL, vm.freshnessStatus)
        assertEquals(2, vm.dataCoverage?.gamesIncluded)
    }

    @Test
    fun revisionChangeDuringFetchDoesNotAdoptMixedData() = runTest {
        val vm = dashboard(RevisionProvider(listOf("v1", "v2")))
        vm.load()
        assertNull(vm.freshnessRevision)
        assertTrue(vm.players.isEmpty())
        assertNull(vm.freshnessForDisplay?.coverage)
    }

    @Test
    fun failedFirstStatusReadStillShowsPlayers() = runTest {
        val vm = dashboard(RevisionProvider(listOf("v1", "v1"), failFirstCheck = true))
        vm.load()
        assertFalse(vm.players.isEmpty())
    }

    @Test
    fun equivalentRefreshRequestsShareOnePlayerFetch() = runTest {
        val provider = RevisionProvider(listOf("v1", "v1"))
        val vm = dashboard(provider)
        val first = async { vm.load() }
        val second = async { vm.load() }
        first.await()
        second.await()
        assertEquals(1, provider.playerFetches)
    }
}

private class RevisionProvider(
    private val revisions: List<String>,
    private val status: DataFreshnessStatus = DataFreshnessStatus.READY,
    private val failFirstCheck: Boolean = false,
) : MockProvider() {
    private var checks = 0
    var playerFetches = 0
        private set

    override suspend fun fetchDataFreshness(season: Int): DataFreshness? {
        if (failFirstCheck && checks == 0) {
            checks += 1
            throw IOException("offline")
        }
        val revision = revisions[minOf(checks, revisions.size - 1)]
        checks += 1
        return DataFreshness(
            status = status, revision = revision,
            coverage = DataCoverage(Instant.ofEpochSecond(1000), 1, SeasonPhase.REGULAR, 2, 2),
        )
    }

    override suspend fun fetchCurrentPlayers(): List<Player> {
        playerFetches += 1
        delay(20)
        return listOf(
            testPlayer(name = "Fixture", team = "SEA", season = StatScoutSeason.current, type = "f", updatedAt = Instant.ofEpochSecond(1000)),
        )
    }
}

class DataFreshnessCaptionTest {
    @Test
    fun shortAgeStaysCompact() {
        val now = Instant.ofEpochSecond(1_800_000_000)
        assertEquals("just now", shortAge(now.plusSeconds(5), now))
        assertEquals("just now", shortAge(now.minusSeconds(59), now))
        assertEquals("10m ago", shortAge(now.minusSeconds(600), now))
        assertEquals("2h ago", shortAge(now.minusSeconds(7_200), now))
    }
}
