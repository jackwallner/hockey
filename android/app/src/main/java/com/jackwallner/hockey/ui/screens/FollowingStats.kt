package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.FanStatsSelection
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.TrendSide
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.RinkMenu
import com.jackwallner.hockey.ui.components.RinkInlinePill
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkTopBar
import com.jackwallner.hockey.ui.components.MenuItem
import com.jackwallner.hockey.ui.components.MenuSection
import com.jackwallner.hockey.ui.components.PlayerHeadshot
import com.jackwallner.hockey.ui.components.RefreshableBox
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatScoutSheet
import com.jackwallner.hockey.ui.components.TeamColorDot
import com.jackwallner.hockey.ui.components.TextAction
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import com.jackwallner.hockey.ui.components.CrownYellow

/** Your team and the players you follow, in the selected season and phase. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FollowingStatsView(vm: DashboardViewModel) {
    val favorites = LocalGraph.current.favorites
    val navigator = LocalNavigator.current
    var showingPlayers by remember { mutableStateOf(false) }
    val players = FanStatsSelection.players(favorites.playerIds, vm.seasonPlayers, vm.selectedSeason, vm.selectedPhase)
    val missing = favorites.playerIds.toSet().size - players.size
    RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 12.dp), contentPadding = bottomBarPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Spacer(Modifier.height(0.dp)) }
            val team = favorites.team
            if (team != null && !StatScoutSeason.isAllTime(vm.selectedSeason)) item {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(RinkPalette.surface)
                        .clickable { navigator.push(Route.Team(team)) }.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TeamColorDot(team, 12.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("YOUR TEAM", style = RinkType.micro, color = RinkPalette.inkSecondary)
                        Text(teamFullName(team), style = RinkType.bodyBold, color = RinkPalette.ink)
                    }
                    SfIcon("chevron.right", 18.dp, RinkPalette.inkTertiary)
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Your players", style = RinkType.cardTitle, color = RinkPalette.ink, modifier = Modifier.weight(1f))
                    TextAction(if (players.isEmpty()) "Follow players" else "Manage", RinkType.smallBold, RinkPalette.turf, { showingPlayers = true })
                }
            }
            if (favorites.playerIds.isEmpty()) item {
                EmptyState(
                    "Keep your players close",
                    "star",
                    "Follow your favorites for their season stats and a shortcut to every profile. Following is\u00A0free.",
                    actionTitle = "Choose players",
                ) { showingPlayers = true }
            }
            itemsIndexed(players, key = { _, p -> p.playerId }) { _, player ->
                var menu by remember { mutableStateOf(false) }
                Box {
                    PlayerCard(player, Modifier.combinedClickable(onClick = { navigator.push(Route.PlayerProfile(player)) }, onLongClick = { menu = true }))
                    DropdownMenu(menu, { menu = false }, containerColor = RinkPalette.surface) {
                        DropdownMenuItem(
                            text = { Text("Unfollow ${player.name}", style = RinkType.body, color = RinkPalette.ink) },
                            leadingIcon = { SfIcon("star.slash", 18.dp, RinkPalette.inkSecondary) },
                            onClick = {
                                menu = false
                                favorites.toggleFavorite(player.playerId)
                            },
                        )
                    }
                }
            }
            if (missing > 0) item {
                Text(
                    "$missing followed ${if (missing == 1) "player has" else "players have"} no published stats for this season and phase yet. They stay on your list.",
                    style = RinkType.small,
                    color = RinkPalette.inkSecondary,
                )
            }
        }
    }
    StatScoutSheet(showingPlayers, { showingPlayers = false }) { FollowPlayersSheet(vm) { showingPlayers = false } }
}

@Composable
private fun PlayerCard(player: Player, modifier: Modifier) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(RinkPalette.surface).then(modifier).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            PlayerHeadshot(player.team, player.initials, 36.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(player.name, style = RinkType.bodyBold, color = RinkPalette.ink)
                Text("${displayTeamAbbr(player.team)} · ${player.displayPosition}", style = RinkType.small, color = RinkPalette.inkSecondary)
            }
            SfIcon("chevron.right", 18.dp, RinkPalette.inkTertiary)
        }
        val stats = FanStatsSelection.summary(player)
        if (stats.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                stats.forEach { stat ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(stat.value, style = RinkType.statMed, color = RinkPalette.turf)
                        Text(stat.label, style = RinkType.small, color = RinkPalette.inkSecondary)
                    }
                }
                // Three-stat lines (goalies) keep the same four columns as skaters,
                // so the numbers line up from card to card.
                repeat(maxOf(0, 4 - stats.size)) { Spacer(Modifier.weight(1f)) }
            }
        } else {
            Text("Open profile for available metrics", style = RinkType.small, color = RinkPalette.inkSecondary)
        }
    }
}

/** Pick the players you follow, in bulk. Free: following is what makes the app yours. */
@Composable
fun FollowPlayersSheet(vm: DashboardViewModel, side: TrendSide = TrendSide.FORWARD, onDone: () -> Unit) {
    val favorites = LocalGraph.current.favorites
    val haptic = rememberHaptic()
    var searchText by remember { mutableStateOf("") }
    var listSide by remember { mutableStateOf(side) }
    val all = vm.players(vm.selectedSeason)
    // Ordered by when they were followed, matching the Trends board.
    val followed = favorites.playerIds.mapNotNull { id -> all.firstOrNull { it.playerId == id } }
    val query = searchText.trim().lowercase()
    val candidates = all.filter { (it.playerType ?: "") == listSide.playerType }
        .filter { query.isEmpty() || it.name.lowercase().contains(query) || it.team.lowercase().contains(query) }
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    @Composable
    fun FollowRow(player: Player, index: Int) {
        val following = favorites.isFavorite(player.playerId)
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                .clickable {
                    favorites.toggleFavorite(player.playerId)
                    haptic()
                }
                .semantics { contentDescription = if (following) "Unfollow ${player.name}" else "Follow ${player.name}" }
                .padding(horizontal = RinkGeo.padInline),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlayerHeadshot(player.team, player.initials, 34.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(player.name, style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1)
                Text("${player.team} · ${player.displayPosition}", style = RinkType.micro, color = RinkPalette.inkTertiary)
            }
            SfIcon(if (following) "star.fill" else "star", 20.dp, if (following) CrownYellow else RinkPalette.inkTertiary)
        }
    }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(title = "Follow Players", trailing = { TextAction("Done", RinkType.smallBold, androidx.compose.ui.graphics.Color.White, onDone) })
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
            item {
                Row(
                    Modifier.padding(12.dp).fillMaxWidth().height(44.dp).clip(CircleShape).background(RinkPalette.surface)
                        .border(0.5.dp, RinkPalette.hairline, CircleShape).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SfIcon("magnifyingglass", 16.dp, RinkPalette.inkTertiary)
                    Box(Modifier.weight(1f)) {
                        if (searchText.isEmpty()) Text("Search players", style = RinkType.body, color = RinkPalette.inkTertiary)
                        BasicTextField(
                            searchText, { searchText = it }, singleLine = true,
                            textStyle = RinkType.body.copy(color = RinkPalette.ink),
                            cursorBrush = SolidColor(RinkPalette.turf),
                            modifier = Modifier.fillMaxWidth().testTag("followSearch"),
                        )
                    }
                    if (searchText.isNotEmpty()) SfIcon("xmark.circle.fill", 18.dp, RinkPalette.inkTertiary, Modifier.clickable { searchText = "" })
                }
            }
            // Always present, even at zero, so the list below never jumps under the next tap.
            item {
                Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().rinkCard()) {
                    RinkSectionBar("FOLLOWING (${followed.size})")
                    if (followed.isEmpty()) {
                        Box(Modifier.fillMaxWidth().height(RinkGeo.rowHeight), contentAlignment = Alignment.Center) {
                            Text("Nobody yet. Tap a star to follow.", style = RinkType.small, color = RinkPalette.inkSecondary)
                        }
                    } else followed.forEachIndexed { i, p -> FollowRow(p, i) }
                }
            }
            item {
                Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().rinkCard()) {
                    Box(Modifier.padding(12.dp)) {
                        RinkMenu(listOf(MenuSection(null, TrendSide.entries.map { option ->
                            MenuItem(option.label, checked = option == listSide) { listSide = option }
                        }))) { open -> RinkInlinePill(listSide.label, open, icon = "person.fill") }
                    }
                    if (candidates.isEmpty()) {
                        Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                            Text("No players match “$searchText”.", style = RinkType.small, color = RinkPalette.inkSecondary)
                        }
                    } else candidates.forEachIndexed { i, p -> FollowRow(p, i) }
                }
            }
            item { Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) }
        }
    }
}
