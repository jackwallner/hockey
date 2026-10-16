package com.jackwallner.hockey

import android.content.Intent
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.hockey.data.TwoTierPlayerCache
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * End-to-end flows on a real device. Most run on the debug fixture feed so
 * they are deterministic; the live test hits the production Supabase feed on
 * purpose, since a mock would only prove the mock still matches.
 */
@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(fixture: Boolean = true, onboarded: Boolean = true, forcePro: Boolean = false, tab: Int = 0) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("resetAll", true)
            .putExtra("uiTest", true)
            .putExtra("screenshotData", fixture)
            .putExtra("onboarded", onboarded)
            .putExtra("forcePro", forcePro)
            .putExtra("previewStore", true)
            .putExtra("tab", tab)
        scenario = ActivityScenario.launch(intent)
    }

    @After
    fun tearDown() {
        scenario?.close()
    }

    private fun waitForText(text: String, timeout: Long = 30_000, substring: Boolean = false) {
        compose.waitUntil(timeout) {
            compose.onAllNodes(hasText(text, substring = substring) or hasContentDescription(text, substring = substring))
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun tap(text: String, substring: Boolean = false) {
        compose.onAllNodes(hasText(text, substring = substring) or hasContentDescription(text, substring = substring))
            .onFirst().performClick()
    }

    @Test
    fun firstLaunchShowsOnboarding() {
        launch(fixture = false, onboarded = false)
        waitForText("Your Pocket", substring = true)
        waitForText("Continue")
    }

    @Test
    fun leaderboardOpensAPlayerProfile() {
        launch()
        waitForText("League leaders")
        waitForText("Callum Therrien")
        tap("Callum Therrien")
        waitForText("ADVANCED PERCENTILES")
        waitForText("ixG", substring = true)
    }

    @Test
    fun freeTrendsShowTheTeaserAndPaywall() {
        launch(tab = 2)
        waitForText("Heating up")
        waitForText("See all plans")
        tap("See all plans")
        waitForText("Restore Purchases")
        waitForText("Lifetime")
    }

    @Test
    fun proYearCompareShowsBothSeasons() {
        launch(forcePro = true)
        waitForText("Callum Therrien")
        tap("Callum Therrien")
        compose.onNodeWithTag("profileTab_Year Compare").performClick()
        waitForText("SEASON TOTALS")
        waitForText("2025-26")
    }

    @Test
    fun everyTabOpens() {
        launch()
        waitForText("League leaders")
        for (tab in listOf("Games", "Trends", "Teams", "Compare", "Stats")) {
            compose.onNodeWithTag("tab_$tab").performClick()
            compose.waitForIdle()
        }
        waitForText("League leaders")
    }

    /** Rate and Send Feedback are separate rows with no question in front; support lives in feedback. */
    @Test
    fun settingsSeparatesRatingFromFeedback() {
        launch()
        waitForText("League leaders")
        compose.onNodeWithTag("settingsButton").performClick()
        compose.onNodeWithTag("rateRow").performScrollTo()
        waitForText("Rate StatScout")
        waitForText("Opens Google Play to write a review.")
        compose.onNodeWithTag("feedbackRow").performScrollTo()
        waitForText("Send Feedback")
        waitForText("jackwallner+bb@gmail.com")
        assertTrue(compose.onAllNodes(hasText("Contact Support")).fetchSemanticsNodes().isEmpty())
        assertTrue(compose.onAllNodes(hasText("Rate on Google Play")).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun bundledHistoryDecodesFromTheApk() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val cache = TwoTierPlayerCache(context.cacheDir) { context.assets.open("players-historical.bin") }
        val seasons = cache.loadHistoricalPlayers().mapNotNull { it.season }.toSet()
        assertTrue("Expected many past seasons, got $seasons", seasons.size > 10)
    }

    @Test
    fun liveFeedLoadsTheLeaderboard() {
        launch(fixture = false)
        // The Debug build parses the full feed slowly on an emulator; allow for it.
        compose.waitUntil(240_000) { compose.onAllNodesWithTag("tab_Stats").fetchSemanticsNodes().isNotEmpty() }
        compose.waitUntil(240_000) { compose.onAllNodesWithTag("standardRow").fetchSemanticsNodes().size >= 3 }
        // Real NHL rows, not the debug fixture's invented roster.
        assertTrue(compose.onAllNodes(hasText("Callum Therrien")).fetchSemanticsNodes().isEmpty())
        compose.onAllNodesWithTag("standardRow").onFirst().performClick()
        waitForText("ADVANCED PERCENTILES", timeout = 120_000)
    }
}
