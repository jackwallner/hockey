package com.jackwallner.hockey

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Raw captures for the Play listing, the Android side of the iOS
 * StatScoutScreenshotUITests: the debug fixture feed (invented NHL players
 * and games), Pro unlocked, the same seven screens as the App Store set.
 *
 * Excluded from `connectedDebugAndroidTest` (`notClass` in build.gradle.kts);
 * run it with `am instrument -e class com.jackwallner.hockey.StoreScreenshotTest`.
 * Files land in the app's external files dir under
 * `screens/`, named as scripts/play_screenshot_compositor.py expects.
 */
@RunWith(AndroidJUnit4::class)
class StoreScreenshotTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val skater = "Callum Therrien"
    private val goalie = "Henrik Dalgaard"
    private val comparisonPlayer = "Rasmus Holloway"
    private var scenario: ActivityScenario<MainActivity>? = null

    @After
    fun tearDown() {
        scenario?.close()
    }

    @Test
    fun capture01LeagueLeaders() {
        launch(tab = 0)
        waitForText("League leaders")
        waitForText(skater)
        waitForText("ixG", substring = true)
        capture("01_league_leaders")
    }

    @Test
    fun capture02PlayerProfile() {
        launch(tab = 0)
        openLeader(skater)
        scrollNearTop("ADVANCED PERCENTILES")
        capture("02_player_profile")
    }

    @Test
    fun capture03GoalieProfile() {
        launch(tab = 0)
        waitForText(skater)
        waitFor(hasContentDescription("Goalies"))
        compose.waitForIdle()
        node(hasContentDescription("Goalies")).performClick()
        openLeader(goalie)
        scrollNearTop("ADVANCED PERCENTILES")
        capture("03_goalie_profile")
    }

    @Test
    fun capture04Trends() {
        launch(tab = 2)
        waitForText("Heating up")
        // The fixture's leader cools off in this window, as on iOS; any ranked row proves the board loaded.
        waitFor(hasTestTag("trendRow"))
        capture("04_trends")
    }

    @Test
    fun capture05GameDetail() {
        launch(tab = 3)
        waitForText("TEAM ADVANCED STATS")
        waitForText("box score", substring = true)
        node(matcher("box score", substring = true)).performClick()
        waitForText("XG RACE", timeout = 120_000)
        capture("05_game_detail")
    }

    @Test
    fun capture06Team() {
        launch(tab = 3)
        waitForText("TEAM ADVANCED STATS")
        node(hasTestTag("teamTab_Roster")).performClick()
        waitForText(skater)
        capture("06_team")
    }

    @Test
    fun capture07Comparison() {
        launch(tab = 0)
        openLeader(skater)
        node(hasTestTag("compareButton")).performClick()
        waitFor(hasTestTag("pickerRow") and hasText(comparisonPlayer))
        node(hasTestTag("pickerRow") and hasText(comparisonPlayer)).performClick()
        waitForText("Player Comparison")
        waitForText(comparisonPlayer)
        capture("07_comparison")
    }

    // Helpers

    private fun launch(tab: Int) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("resetAll", true)
            .putExtra("uiTest", true)
            .putExtra("screenshotData", true)
            .putExtra("onboarded", true)
            .putExtra("forcePro", true)
            .putExtra("statsBoard", "ADVANCED")
            .putExtra("tab", tab)
        scenario = ActivityScenario.launch(intent)
    }

    private fun matcher(text: String, substring: Boolean = false) =
        hasText(text, substring = substring) or hasContentDescription(text, substring = substring)

    private fun waitFor(matcher: androidx.compose.ui.test.SemanticsMatcher, timeout: Long = 90_000, useUnmergedTree: Boolean = false) {
        compose.waitUntil(timeout) { compose.onAllNodes(matcher, useUnmergedTree).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun waitForText(text: String, timeout: Long = 90_000, substring: Boolean = false) = waitFor(matcher(text, substring), timeout)

    private fun node(matcher: androidx.compose.ui.test.SemanticsMatcher): SemanticsNodeInteraction = compose.onAllNodes(matcher).onFirst()

    private fun openLeader(name: String) {
        waitForText(name)
        node(matcher(name)).performClick()
        waitForText("ADVANCED PERCENTILES")
    }

    /** Slow drags, no fling, until [text] sits just under the top bar. */
    private fun scrollNearTop(text: String) {
        val target = 420f
        var last = Float.MAX_VALUE
        repeat(40) {
            val top = compose.onAllNodes(matcher(text)).fetchSemanticsNodes().firstOrNull()?.boundsInRoot?.top ?: return
            // A drag shorter than touch slop lands as a tap on whatever row is under it.
            if (top <= target + 80f || kotlin.math.abs(top - last) < 1f) return
            last = top
            val step = minOf(top - target, 500f)
            compose.onRoot().performTouchInput {
                val x = width / 2f
                swipe(androidx.compose.ui.geometry.Offset(x, height * 0.75f), androidx.compose.ui.geometry.Offset(x, height * 0.75f - step), durationMillis = 900)
            }
            compose.waitForIdle()
        }
    }

    private fun capture(name: String) {
        // A refresh spinner is an infinite animation, so idling does not wait for it.
        compose.waitUntil(180_000) {
            compose.onAllNodes(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).fetchSemanticsNodes().isEmpty()
        }
        compose.waitForIdle()
        Thread.sleep(1_500)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap: Bitmap = instrumentation.uiAutomation.takeScreenshot() ?: error("Screenshot failed for $name")
        val dir = File(instrumentation.targetContext.getExternalFilesDir(null), "screens").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
