package com.jackwallner.hockey

import android.content.Intent
import com.jackwallner.hockey.data.PackageKind
import com.jackwallner.hockey.data.PeriodUnit
import com.jackwallner.hockey.data.Plan
import com.jackwallner.hockey.data.PlanPeriod

/**
 * Debug-only launch extras, the Android side of the iOS launch arguments.
 * Nothing here is compiled into a release or QA build.
 *
 *     adb shell am start -n com.jackwallner.hockey/.MainActivity \
 *         --ez resetAll true --ez onboarded true --ez forcePro true --ei tab 2
 *
 * `--ez screenshotData true` swaps in the fictional fixture feed for store captures;
 * add `--ez fixtureFresh true` for the first-run look or `--ez fixtureSlate true`
 * for a live night plus the next two days on Games.
 */
object DebugLaunchOptions {
    var launchTab: Int? = null
        private set
    var onboardingPage: Int? = null
        private set

    fun apply(graph: AppGraph, intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getBoolean("uiTest")) graph.review.isAutomationRun = true
        if (extras.getBoolean("resetAll")) graph.defaults.keys().forEach(graph.defaults::remove)
        if (extras.getBoolean("screenshotData")) {
            ScreenshotFixtureApi.fresh = extras.getBoolean("fixtureFresh")
            ScreenshotFixtureApi.slate = extras.getBoolean("fixtureSlate")
            ScreenshotFixtureApi.prepareDefaults(graph.defaults)
            graph.feedOverride = ScreenshotFixtureApi to ScreenshotFixtureApi.cache
            graph.review.isAutomationRun = true
        }
        extras.getString("statsBoard")?.let { graph.defaults.putString("stats.board", it) }
        if (extras.getBoolean("onboarded")) graph.defaults.putBoolean("hasCompletedOnboarding", true)
        // The graph outlives an activity, so a reset also clears a Pro unlock left by an earlier launch.
        if (extras.getBoolean("resetAll") || extras.containsKey("forcePro")) graph.subscriptions.forceProForDebug(extras.getBoolean("forcePro"))
        if (extras.getBoolean("previewStore")) graph.subscriptions.loadPreviewPlans(previewPlans(), history = extras.getBoolean("previewTrialUsed"))
        if (extras.containsKey("tab")) launchTab = extras.getInt("tab")
        if (extras.containsKey("onboardingPage")) onboardingPage = extras.getInt("onboardingPage")
    }

    /** The Android US ladder, so the real paywall renders without a store. */
    private fun previewPlans(): List<Plan> {
        val trial = PlanPeriod(1, PeriodUnit.WEEK)
        return listOf(
            Plan("\$rc_annual", "com.jackwallner.hockey.pro.yearly", PackageKind.YEARLY, 7_990_000, "$7.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), trial, "StatScout+ Yearly"),
            Plan("\$rc_monthly", "com.jackwallner.hockey.pro.monthly", PackageKind.MONTHLY, 1_490_000, "$1.49", "USD", PlanPeriod(1, PeriodUnit.MONTH), trial, "StatScout+ Monthly"),
            Plan("\$rc_lifetime", "com.jackwallner.hockey.pro", PackageKind.LIFETIME, 15_990_000, "$15.99", "USD", null, null, "StatScout+ Lifetime"),
        )
    }
}
