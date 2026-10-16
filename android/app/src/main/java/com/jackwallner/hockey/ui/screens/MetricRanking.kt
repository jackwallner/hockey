package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.competitionRanks
import com.jackwallner.hockey.model.metricValue
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.LeaderboardTableHeader
import com.jackwallner.hockey.ui.components.LeaderboardTableRow
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.cardSlice
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType

/** One metric's league ranking, for the season and phase the drill-down carries. */
@Composable
fun MetricRankingRoute(route: Route.Metric) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val season = route.season ?: vm.selectedSeason
    val phase = route.phase ?: vm.selectedPhase
    val label = route.label
    val category = route.category
    var descending by rememberSaveable { mutableStateOf(DashboardViewModel.defaultSortDescending(label, category)) }
    var position by rememberSaveable { mutableStateOf(route.position) }
    val players = vm.players(season, phase)
    fun hasMetric(player: Player) = player.metrics.any { it.label == label && it.category == category }
    // The cohorts that carry this metric, in Forwards / Defensemen / Goalies order.
    val cohorts = players.filter(::hasMetric).map { it.positionGroup }.toSet().let { groups -> PlayerPositionGroup.entries.filter { it in groups } }
    // Percentiles only compare within a cohort, so the board ranks one at a time.
    val activeCohort = position?.takeIf { it in cohorts } ?: cohorts.firstOrNull()
    fun isSmallSample(player: Player): Boolean {
        val metric = player.metrics.firstOrNull { it.label == label && it.category == category } ?: return false
        return !vm.isQualified(player, metric)
    }
    val sorted = players.filter { hasMetric(it) && it.positionGroup == activeCohort }
        .sortedWith(DashboardViewModel.metricComparator(label, category, descending))
    // Same rule as the Stats board: small samples stay listed, below.
    val ranked = sorted.filterNot(::isSmallSample) + sorted.filter(::isSmallSample)

    PushedScreen("$label · ${category.raw}") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
            item { Spacer(Modifier.height(12.dp)) }
            item {
                Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, ranked.isEmpty())) {
                    // The bar draws its title in capitals, which would turn "ixG" into "IXG";
                    // the metric already leads the title and heads the column.
                    RinkSectionBar(category.raw, trailing = {
                        Text(SeasonLabel.display(season), style = RinkType.micro, color = RinkPalette.inkSecondary)
                        Row(
                            Modifier.padding(start = 12.dp).heightIn(min = 28.dp).clickable {
                                descending = !descending
                                haptic()
                            },
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(label, style = RinkType.micro, color = RinkPalette.inkSecondary)
                            SfIcon(if (descending) "arrow.down" else "arrow.up", 11.dp, RinkPalette.inkSecondary)
                        }
                    })
                }
            }
            if (cohorts.size > 1) {
                item {
                    Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, false).padding(horizontal = RinkGeo.padInline, vertical = 10.dp)) {
                        RinkSegmented(cohorts.map { Segment<PlayerPositionGroup?>(it, it.displayName) }, activeCohort, { position = it })
                    }
                }
            }
            if (ranked.isEmpty()) {
                item {
                    Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true).padding(vertical = 12.dp)) {
                        EmptyState("No rankings found", "chart.bar", "No players have the $label metric for this season.")
                    }
                }
            } else {
                item { Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, false)) { LeaderboardTableHeader(descending, label) { descending = !descending } } }
                val ranks = competitionRanks(ranked.map { metricValue(it, label, category) })
                itemsIndexed(ranked, key = { _, p -> p.id }) { index, player ->
                    Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == ranked.lastIndex)) {
                        LeaderboardTableRow(
                            rank = ranks[index],
                            player = player,
                            stripe = index,
                            metricLabel = label,
                            metricCategory = category,
                            volume = vm.volumeCaption(player, category),
                            isSmallSample = isSmallSample(player),
                        ) { navigator.push(Route.PlayerProfile(player)) }
                    }
                }
            }
        }
    }
}
