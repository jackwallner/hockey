package com.jackwallner.hockey.ui.screens

import androidx.compose.runtime.Composable
import com.jackwallner.hockey.ui.AppTab
import com.jackwallner.hockey.ui.nav.Route

/** The root screen of each tab. */
@Composable
fun TabRoot(tab: AppTab, isActive: Boolean) {
    when (tab) {
        AppTab.STATS -> StatsScreen()
        AppTab.GAMES -> GamesScreen(isActive)
        AppTab.TRENDS -> TrendsScreen(isActive)
        AppTab.TEAMS -> TeamsScreen(isActive)
        AppTab.COMPARE -> CompareScreen(isActive)
    }
}

/** Every pushed route, the iOS `StandardDestinations`. */
@Composable
fun Destination(route: Route) {
    when (route) {
        Route.Root -> Unit
        is Route.PlayerProfile -> PlayerProfileRoute(route.player)
        is Route.Game -> GameDetailScreen(route.gameId)
        is Route.TeamSchedule -> TeamScheduleScreen(route.team)
        is Route.Team -> TeamScreen(route.abbr)
        is Route.Metric -> MetricRankingRoute(route)
        is Route.StandardStat -> StandardStatRoute(route)
        is Route.Comparison -> PlayerComparisonScreen(route.playerA, route.playerB)
        is Route.YearCompare -> YearComparisonScreen(route.player)
        is Route.TeamComparison -> TeamComparisonScreen(route)
        is Route.YearCompareRoute -> YearCompareDestination(route)
        Route.Standings -> StandingsScreen()
        Route.PowerRankings -> PowerRankingsScreen()
        Route.Settings -> SettingsScreen()
        Route.Glossary -> StatGlossaryScreen()
        Route.FollowingStats -> FollowingStatsScreen()
        is Route.Custom -> route.content()
    }
}
