package com.jackwallner.hockey.data

import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.StatScoutSeason

/** Where a pitch came from: the paywall's icon, headline and impression id. */
sealed class PaywallTrigger(
    val icon: String,
    val title: String,
    val subtitle: String,
    val paywallImpressionId: String,
) {
    data object PastSeason : PaywallTrigger(
        "calendar.badge.clock", "Unlock Past Seasons",
        "Track how every player ranked since 2008-09, plus the year-over-year trends behind today's leaders.",
        "statscout_paywall_past_season",
    )

    /** A specific locked year: naming it converts better than a generic pitch. */
    data class LockedSeason(val year: Int) : PaywallTrigger(
        "calendar.badge.clock", if (StatScoutSeason.isAllTime(year)) "Unlock All Time" else "Unlock ${SeasonLabel.display(year)}",
        "See every player's ${SeasonLabel.display(year)} percentile rankings, and how they stack up against any other season.",
        "statscout_paywall_locked_season",
    )

    data object YearCompare : PaywallTrigger(
        "arrow.left.arrow.right.circle.fill", "Year-over-Year Comparison",
        "Compare any player's percentile rankings across any two seasons. See what changed, what held, and where they're headed.",
        "statscout_paywall_year_compare",
    )

    data object PlayerComparison : PaywallTrigger(
        "person.2.fill", "Player Comparison",
        "Stack any two players head-to-head across every NHL metric: ixG, GAx, xGF%, GSAx and more.",
        "statscout_paywall_player_comparison",
    )

    data object Onboarding : PaywallTrigger("crown.fill", "Scout Like a GM", FULL_PICTURE, "statscout_paywall_onboarding")
    data object Activation : PaywallTrigger("crown.fill", "Get the Full Picture", FULL_PICTURE, "statscout_paywall_activation")
    data object Upgrade : PaywallTrigger("crown.fill", "Scout Every Player", FULL_PICTURE, "statscout_paywall_upgrade")

    data object PastSeasonsLoad : PaywallTrigger(
        "clock.arrow.circlepath", "Load Past Seasons",
        "Load historical data to explore past seasons, year-over-year trends, and more.",
        "statscout_paywall_past_seasons_load",
    )

    data object TeamView : PaywallTrigger(
        "shield.lefthalf.filled", "Team Insights",
        "Advanced and standard stats for every club, a roster you can rank by any metric over any window, and side-by-side comparisons for every squad.",
        "statscout_paywall_team_view",
    )

    data object Winback : PaywallTrigger(
        "arrow.counterclockwise.circle.fill", "Welcome Back",
        "Your StatScout+ access has lapsed. Pick it back up to get the Trends board, recent form, head-to-head matchups, and every past season.",
        "statscout_paywall_winback",
    )

    /** Soft half-sheet pitch on a free user's first player open. */
    data object PlayerScouting : PaywallTrigger(
        "binoculars.fill", "Full Player Scouting",
        "Last 2 / 4 / 8 week form, head-to-head matchups, every roster. The full picture, not just season totals.",
        "statscout_paywall_player_scouting",
    )

    data object RecentForm : PaywallTrigger(
        "flame.fill", "Recent Form",
        "Every player's last 2 / 4 / 8 week form. Catch hot streaks and slumps before the season totals catch up.",
        "statscout_paywall_recent_form",
    )

    data object BestWorst : PaywallTrigger(
        "arrow.up.arrow.down", "Best & Worst",
        "The league leader and the league trailer on every NHL metric, side by side, in one board.",
        "statscout_paywall_best_worst",
    )

    data object AdvancedBoxScore : PaywallTrigger(
        "hockey.puck.fill", "Advanced Box Scores",
        "Every player in every game: expected goals, high-danger chances and the xG race, beside the box score.",
        "statscout_paywall_advanced_box_score",
    )

    /** What the subscription opens, kept in step with the app. */
    val features: List<Pair<String, String>> get() = PRO_FEATURES

    companion object {
        private const val FULL_PICTURE =
            "The Trends board, recent form, head-to-head matchups, and every season back to 2008-09. The full NHL picture on every player."

        val PRO_FEATURES = listOf(
            "flame.fill" to "The Trends board: who's heating up and cooling off, league-wide",
            "chart.bar.fill" to "Last 2 / 4 / 8 week form on any player, team or leaderboard",
            "person.2.fill" to "Head-to-head: any two players, every metric",
            "shield.lefthalf.filled" to "Team scouting: advanced and standard, season or recent",
            "hockey.puck.fill" to "Every player's line in every box score: ixG, GAx and goalie GSAx",
            "calendar.badge.clock" to "Every season back to 2008-09 plus year\u2011over\u2011year trends",
        )
    }
}

/** Session cap so a contextual paywall can't be re-presented endlessly. Resets on relaunch. */
class PaywallGate {
    private val presented = HashMap<String, Int>()

    fun shouldPresent(trigger: PaywallTrigger): Boolean = (presented[key(trigger)] ?: 0) < MAX_PER_TRIGGER

    fun markPresented(trigger: PaywallTrigger) {
        presented[key(trigger)] = (presented[key(trigger)] ?: 0) + 1
    }

    private fun key(trigger: PaywallTrigger): String = trigger.toString()

    private companion object {
        const val MAX_PER_TRIGGER = 2
    }
}
