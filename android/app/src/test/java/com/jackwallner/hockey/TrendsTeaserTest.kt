package com.jackwallner.hockey

import com.jackwallner.hockey.ui.screens.stableSeed
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The blurred board behind the Trends paywall has to redraw when the controls
 * move. Row one is the real league leader; everything under it is invented and
 * seeded. A seed that fails to reshuffle shows eighteen identical rows after a
 * window change, which advertises that they are fake. These pin both halves of
 * the fix: the seed's position in the string and the hash's avalanche.
 */
class TrendsTeaserTest {
    /** Stand-ins for the roster the teaser draws from; NHL ids are close to sequential within a draft class. */
    private val playerIds = (0 until 60).map { "80${78000 + it * 37}" }

    private fun teaserOrder(seed: String, count: Int = 18): List<String> =
        playerIds.map { it to stableSeed("$seed-$it") }.sortedBy { it.second }.take(count).map { it.first }

    /** The window is the last component of the seed and the one that reproduced the bug. */
    @Test
    fun changingTheWindowRedrawsTheBoardUnderTheBlur() {
        val orders = listOf("2", "4", "8").map { teaserOrder("points_per_60-false-$it-2026-REG") }
        for ((a, b) in listOf(0 to 1, 1 to 2, 0 to 2)) {
            assertNotEquals("The window changed and the teaser did not", orders[a], orders[b])
            val shared = orders[a].take(5).toSet().intersect(orders[b].take(5).toSet())
            assertTrue("The top of the teaser barely moved between windows: $shared", shared.size <= 2)
        }
    }

    /** Every other control on the screen feeds the same seed. */
    @Test
    fun everyTrendsControlRedrawsTheBoard() {
        val baseline = teaserOrder("points_per_60-false-2-2026-REG")
        val variants = listOf(
            "ixg_per_60-false-2-2026-REG", // metric
            "points_per_60-true-2-2026-REG", // cooling off
            "points_per_60-false-2-2025-REG", // season
            "points_per_60-false-2-2026-POST", // phase
        )
        for (variant in variants) assertNotEquals("$variant left the teaser unchanged", baseline, teaserOrder(variant))
    }

    /** A one-character change anywhere in the string has to move the hash, not nudge it. */
    @Test
    fun oneCharacterChangesTheWholeSeed() {
        val a = stableSeed("points_per_60-false-2-2026-REG-8078000")
        val b = stableSeed("points_per_60-false-4-2026-REG-8078000")
        assertNotEquals(a, b)
        assertTrue("Seeds $a and $b are adjacent, so sorting by them preserves the old order", abs(a - b) > 1_000)
    }

    @Test
    fun theSameSeedAlwaysProducesTheSameBoard() {
        val seed = "points_per_60-false-2-2026-REG"
        assertEquals(teaserOrder(seed), teaserOrder(seed))
        assertEquals(stableSeed("8078000"), stableSeed("8078000"))
    }

    /** Used as an array index and a modulus, so it can never be negative. */
    @Test
    fun seedsAreAlwaysUsableAsAnIndex() {
        for (id in playerIds) {
            val seed = stableSeed("points_per_60-false-2-2026-REG-$id")
            assertTrue(seed >= 0)
            assertTrue(seed < 100_003)
        }
    }

    /** Identical to iOS (FNV-1a plus a murmur3 finalizer), so the same controls draw the same teaser. Expected values computed from the Swift algorithm. */
    @Test
    fun seedMatchesTheIosHash() {
        assertEquals(4741, stableSeed("8078000"))
        assertEquals(54278, stableSeed("points_per_60-false-2-2026-REG"))
        assertEquals(42059, stableSeed("points_per_60-false-2-2026-REG-8078000"))
    }
}
