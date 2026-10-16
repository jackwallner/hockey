package com.jackwallner.hockey.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.MetricCoverage
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandardStat
import com.jackwallner.hockey.model.StandardStatSemantics
import com.jackwallner.hockey.model.competitionRanks
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.metricNumericValue
import com.jackwallner.hockey.model.ordinal
import com.jackwallner.hockey.model.searchMatches
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.PositionTabs
import com.jackwallner.hockey.ui.components.InfoNote
import com.jackwallner.hockey.ui.components.PercentileBarMini
import com.jackwallner.hockey.ui.components.PlayerHeadshot
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.RefreshableBox
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatOption
import com.jackwallner.hockey.ui.components.StatPickerMenu
import com.jackwallner.hockey.ui.components.TeamColorDot
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.cardSlice
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType

/**
 * Traditional leaderboard with the same position tabs and control vocabulary
 * as the Advanced board. [viewModel] and [boardState] are present on the Stats
 * tab and absent on a drill-down.
 */
@Composable
fun StandardStatsLeadersView(
    players: List<Player>,
    selectedStat: String,
    onSelectStat: (String) -> Unit,
    selectedPosition: PlayerPositionGroup,
    onSelectPosition: (PlayerPositionGroup) -> Unit,
    sortDescending: Boolean,
    onSortDescending: (Boolean) -> Unit,
    boardState: StatsBoardState? = null,
    viewModel: DashboardViewModel? = null,
) {
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    var isSearching by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }

    // A stat the new position does not offer falls back to its default.
    LaunchedEffect(selectedPosition) {
        if (selectedStat !in StandardStatCatalog.stats(selectedPosition)) {
            val next = StandardStatCatalog.defaultStat(selectedPosition)
            onSelectStat(next)
            onSortDescending(StandardStatCatalog.defaultDescending(next, selectedPosition))
        }
    }

    fun standardStat(player: Player): StandardStat? = player.standardStats?.firstOrNull { it.label.equals(selectedStat, ignoreCase = true) }
    fun numericStat(player: Player): Double? = standardStat(player)?.let { StandardStatSemantics.numericValue(it.label, it.value) }
    fun games(player: Player): Double = player.standardStats?.firstOrNull { it.label == "GP" }?.value?.let(::metricNumericValue) ?: 0.0

    val filtered = players.filter { it.positionGroup == selectedPosition && numericStat(it) != null }
    val sorted = filtered.sortedWith { a, b ->
        val av = numericStat(a) ?: 0.0
        val bv = numericStat(b) ?: 0.0
        if (av != bv) (if (sortDescending) bv.compareTo(av) else av.compareTo(bv)) else games(b).compareTo(games(a))
    }
    val sampleLabel = when {
        viewModel == null -> "PLAYER"
        else -> {
            val who = if (viewModel.isRookieFilterActive) "ROOKIES" else "PLAYERS"
            if (viewModel.qualifierLevel == DashboardViewModel.QualifierLevel.QUALIFIED) "QUALIFIED $who" else "ALL $who"
        }
    }
    // The live season while the NHL summary or MoneyPuck's files are still catching up.
    val pendingNote = viewModel?.takeIf { it.selectedSeason == it.freeSeason && it.selectedPhase == SeasonPhase.REGULAR }?.let {
        MetricCoverage.pendingNote(it.dataFreshness?.shotsStatus, it.dataFreshness?.summaryStatus)
    }

    // The volume behind the headline number: games played, and for a rate stat
    // the shots behind it. A .940 save percentage means little over one start.
    fun volumeText(player: Player): String? {
        val stats = player.standardStats.orEmpty()
        fun value(label: String) = stats.firstOrNull { it.label.equals(label, ignoreCase = true) }?.value
        val stat = selectedStat.uppercase()
        if (stat in setOf("SV%", "GAA")) value("SA")?.let { return "$it SA" }
        if (stat == "SH%") value("SOG")?.let { return "$it SOG" }
        if (stat == "GP") return null
        val g = value("GP") ?: return null
        return if (g == "1") "1 game" else "$g GP"
    }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        PositionTabs(selectedPosition, onSelectPosition, Modifier.padding(top = 8.dp))
        BoardControlRow(
            picker = {
                if (boardState != null && viewModel != null) StatsBoardStatPicker(viewModel, boardState)
                else StatPickerMenu(
                    activeLabel = selectedStat,
                    standard = StandardStatCatalog.stats(selectedPosition).map { StatOption(it, it, it == selectedStat) },
                    onSelectStandard = {
                        onSelectStat(it.id)
                        onSortDescending(StandardStatCatalog.defaultDescending(it.id, selectedPosition))
                    },
                )
            },
            descending = sortDescending,
            statLabel = selectedStat,
            onToggleDirection = { onSortDescending(!sortDescending) },
            isSearchActive = isSearching,
            onToggleSearch = {
                isSearching = !isSearching
                if (!isSearching) searchText = ""
            },
            trailing = if (boardState != null && viewModel != null) ({ StatsViewMenu(viewModel, boardState) }) else null,
        )
        AnimatedVisibility(isSearching) {
            SearchRow(searchText, { searchText = it }) {
                isSearching = false
                searchText = ""
            }
        }
        RefreshableBox({ viewModel?.load() }, Modifier.fillMaxSize()) {
            val query = searchText.trim()
            val ranked = sorted.withIndex().filter { (_, p) ->
                query.isEmpty() || p.name.searchMatches(query) || p.team.searchMatches(query) || teamFullName(p.team).searchMatches(query)
            }
            val peerValues = filtered.mapNotNull { standardStat(it)?.value }
            val ranks = competitionRanks(sorted.map { numericStat(it) })
            LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
                item { Spacer(Modifier.height(8.dp)) }
                item {
                    Row(
                        Modifier.padding(horizontal = 12.dp).cardSlice(first = true, last = false).fillMaxWidth().height(RinkGeo.rowHeightHeader)
                            .background(RinkPalette.surfaceAlt).bottomHairline()
                            .clickable {
                                onSortDescending(!sortDescending)
                                haptic()
                            }
                            .padding(horizontal = RinkGeo.padInline),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("RANK", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(42.dp))
                        FitText(sampleLabel, RinkType.micro, RinkPalette.inkTertiary, Modifier.weight(1f), minScale = 0.75f)
                        Text("TEAM", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(44.dp))
                        Row(Modifier.width(100.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                            FitText(selectedStat, RinkType.micro, RinkPalette.turf, minScale = 0.7f)
                            SfIcon(if (sortDescending) "arrow.down" else "arrow.up", 10.dp, RinkPalette.turf)
                        }
                    }
                }
                when {
                    viewModel?.isLoading == true && players.isEmpty() -> item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true).fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(color = RinkPalette.inkTertiary)
                                Text("Loading player stats", style = RinkType.small, color = RinkPalette.inkSecondary)
                            }
                        }
                    }
                    sorted.isEmpty() -> item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true).padding(vertical = 24.dp)) {
                            EmptyState("No data available", "chart.bar", "No ${selectedPosition.displayName.lowercase()} have $selectedStat data for this season.")
                        }
                    }
                    else -> {
                        if (ranked.isEmpty()) item {
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true)) {
                                EmptyState("No Results for “$searchText”", "magnifyingglass", "Check the spelling or try a new search.")
                            }
                        }
                        itemsIndexed(ranked, key = { _, it -> it.value.id }) { position, (index, player) ->
                            val rank = ranks[index]
                            val stat = standardStat(player)
                            val pct = stat?.let { StandardStatSemantics.percentile(it.label, it.value, peerValues) } ?: 50
                            // A zero count has no honest rank; a skater's 0 PIM is the best line, not an absence.
                            val isZero = numericStat(player) == 0.0 && StandardStatSemantics.higherIsBetter(selectedStat)
                            val display = stat?.value ?: "-"
                            Row(
                                Modifier.padding(horizontal = 12.dp).cardSlice(false, position == ranked.lastIndex).fillMaxWidth().height(52.dp)
                                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                                    .bottomHairline()
                                    .clickable { navigator.push(Route.PlayerProfile(player)) }
                                    .padding(horizontal = RinkGeo.padInline)
                                    .testTag("standardRow"),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                // Same 42 as the header's RANK slot and the Advanced board.
                                Text("$rank", style = RinkType.statSmall, color = RinkPalette.inkSecondary, modifier = Modifier.width(42.dp))
                                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                    PlayerHeadshot(player.team, player.initials, 36.dp)
                                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        FitText(player.name, RinkType.bodyBold, RinkPalette.ink, minScale = 0.85f)
                                        Text(listOfNotNull(player.displayPosition, volumeText(player)).joinToString(" · "), style = RinkType.micro, color = RinkPalette.inkTertiary, maxLines = 1)
                                    }
                                }
                                Row(Modifier.width(44.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    TeamColorDot(player.team, 6.dp)
                                    Text(displayTeamAbbr(player.team), style = RinkType.small, color = RinkPalette.inkSecondary, maxLines = 1)
                                }
                                Row(
                                    Modifier.clearAndSetSemantics {
                                        contentDescription = if (isZero) "$selectedStat: $display, not ranked" else "$selectedStat: $display, ${pct.ordinal} percentile"
                                    },
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    if (isZero) Spacer(Modifier.width(34.dp)) else PercentileBarMini(pct, Modifier.width(34.dp))
                                    FitText(display, RinkType.statMed, if (isZero) RinkPalette.inkTertiary else RinkPalette.turf, Modifier.width(58.dp), minScale = 0.7f, textAlign = TextAlign.End)
                                }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(12.dp)) }
                pendingNote?.let { note -> item { InfoNote(note, Modifier.padding(horizontal = 4.dp)) } }
            }
        }
    }
}

/** Standalone traditional-stat drill-down reached from a player or team page. */
@Composable
fun StandardStatRoute(route: Route.StandardStat) {
    val vm = LocalGraph.current.dashboard
    val season = route.season ?: vm.selectedSeason
    val phase = route.phase ?: vm.selectedPhase
    var stat by rememberSaveable { mutableStateOf(route.stat) }
    var position by rememberSaveable { mutableStateOf(route.position) }
    var descending by rememberSaveable { mutableStateOf(StandardStatCatalog.defaultDescending(route.stat, route.position)) }
    val title = route.stat + " · " + if (phase == SeasonPhase.REGULAR) SeasonLabel.display(season) else SeasonLabel.display(season, phase)
    PushedScreen(title) {
        StandardStatsLeadersView(
            players = vm.players(season, phase),
            selectedStat = stat,
            onSelectStat = { stat = it },
            selectedPosition = position,
            onSelectPosition = { position = it },
            sortDescending = descending,
            onSortDescending = { descending = it },
        )
    }
}
