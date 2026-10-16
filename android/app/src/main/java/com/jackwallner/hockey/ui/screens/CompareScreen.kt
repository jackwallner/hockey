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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.HomeTopBar
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.BlurGateUnlock
import com.jackwallner.hockey.ui.components.ChipButton
import com.jackwallner.hockey.ui.components.ChipTrailing
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkChip
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkTopBar
import com.jackwallner.hockey.ui.components.PlayerHeadshot
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.RefreshableBox
import com.jackwallner.hockey.ui.components.SearchField
import com.jackwallner.hockey.ui.components.SeasonPhaseMenu
import com.jackwallner.hockey.ui.components.SeasonPhasePicker
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatScoutSheet
import com.jackwallner.hockey.ui.components.TextAction
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.gateBlur
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.nav.rememberRetained
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import com.jackwallner.hockey.ui.theme.TeamColor

private enum class PickerTarget { PLAYER_A, PLAYER_B, YEAR_PLAYER, TEAM_A, TEAM_B }

@Stable
private class CompareState(vm: DashboardViewModel) {
    var playerA by mutableStateOf<Player?>(null)
    var playerB by mutableStateOf<Player?>(null)
    var seasonA by mutableStateOf(vm.selectedSeason)
    var seasonB by mutableStateOf(vm.selectedSeason)
    var phaseA by mutableStateOf(vm.selectedPhase)
    var phaseB by mutableStateOf(vm.selectedPhase)
    var yearPhase by mutableStateOf(vm.selectedPhase)
    var teamA by mutableStateOf<String?>(null)
    var teamB by mutableStateOf<String?>(null)
    var teamSeasonA by mutableStateOf(vm.selectedSeason)
    var teamSeasonB by mutableStateOf(vm.selectedSeason)
    var teamPhaseA by mutableStateOf(vm.selectedPhase)
    var teamPhaseB by mutableStateOf(vm.selectedPhase)
}

private fun resolved(vm: DashboardViewModel, player: Player?, season: Int, phase: SeasonPhase): Player? {
    player ?: return null
    if (player.season == season && player.seasonPhase == phase) return player
    return vm.playerHistories[player.playerId]?.firstOrNull { it.season == season && it.seasonPhase == phase }
}

/**
 * The Compare tab and the home of the players you follow. Following is free;
 * only the comparison cards below it are behind StatScout+.
 */
@Composable
fun CompareScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val store = graph.subscriptions
    val favorites = graph.favorites
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val haptic = rememberHaptic()
    val state = rememberRetained("compare") { CompareState(vm) }
    var picker by remember { mutableStateOf<PickerTarget?>(null) }
    var showingFollowSheet by remember { mutableStateOf(false) }

    val resolvedA = resolved(vm, state.playerA, state.seasonA, state.phaseA)
    val resolvedB = resolved(vm, state.playerB, state.seasonB, state.phaseB)
    val canCompare = resolvedA != null && resolvedB != null && resolvedA.canCompareHeadToHead(resolvedB)
    val slotWarning = when {
        vm.isHistoricalLoading && (resolvedA == null || resolvedB == null) -> "Loading past seasons…"
        state.playerA != null && resolvedA == null -> "No ${SeasonLabel.display(state.seasonA)} ${state.phaseA.label.lowercase()} data for ${state.playerA!!.name}."
        state.playerB != null && resolvedB == null -> "No ${SeasonLabel.display(state.seasonB)} ${state.phaseB.label.lowercase()} data for ${state.playerB!!.name}."
        resolvedA != null && resolvedB != null && !resolvedA.canCompareHeadToHead(resolvedB) -> "Choose two skaters or two goalies."
        else -> null
    }
    val isSameTeam = state.teamA != null && state.teamB != null &&
        normalizedTeamAbbreviation(state.teamA!!) == normalizedTeamAbbreviation(state.teamB!!) &&
        state.teamSeasonA == state.teamSeasonB && state.teamPhaseA == state.teamPhaseB
    val canCompareTeams = state.teamA != null && state.teamB != null && !isSameTeam
    val teamWarning = if (isSameTeam) "Both sides are ${teamFullName(state.teamA!!)} in ${SeasonLabel.display(state.teamSeasonA)} ${state.teamPhaseA.label.lowercase()}. Change one side's season or season type to compare." else null
    val roster = vm.players(state.seasonA, state.phaseA)
    val followed = favorites.playerIds.mapNotNull { id -> roster.firstOrNull { it.playerId == id } }

    // Preload history once the tab is actually opened, never at launch.
    LaunchedEffect(isActive, store.isPro) {
        if (isActive && store.isPro && !vm.hasLoadedHistorical && !vm.isHistoricalLoading) vm.loadHistoricalIfNeeded()
    }
    LaunchedEffect(state.seasonA, state.phaseA, state.seasonB, state.phaseB, state.teamSeasonA, state.teamPhaseA, state.teamSeasonB, state.teamPhaseB) {
        val sel = vm.selectedSeason
        if (store.isPro && (state.seasonA != sel || state.seasonB != sel || state.teamSeasonA != sel || state.teamSeasonB != sel)) vm.loadHistoricalIfNeeded()
    }

    fun loadIntoSlot(player: Player) {
        val a = state.playerA
        val b = state.playerB
        when {
            a == null || a.playerId == player.playerId -> state.playerA = player
            b == null || b.playerId == player.playerId -> {
                if (!a.canCompareHeadToHead(player)) {
                    state.playerA = player
                    state.playerB = null
                } else state.playerB = player
            }
            else -> {
                if (!a.canCompareHeadToHead(player)) state.playerA = null
                state.playerB = player
            }
        }
    }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        HomeTopBar(title = "Compare")
        RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 12.dp)
                    .padding(bottomBarPadding(104.dp)),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                YourPlayersCard(
                    followed = followed,
                    isEmpty = favorites.playerIds.isEmpty(),
                    isPro = store.isPro,
                    inSlot = { p -> state.playerA?.playerId == p.playerId || state.playerB?.playerId == p.playerId },
                    onEdit = { showingFollowSheet = true },
                    onTap = { p ->
                        if (store.isPro) {
                            loadIntoSlot(p)
                            haptic()
                        } else navigator.push(Route.PlayerProfile(p))
                    },
                    onOpen = { p -> navigator.push(Route.PlayerProfile(p)) },
                    onUnfollow = { p -> favorites.toggleFavorite(p.playerId) },
                )
                Box {
                    // Only the comparison cards blur: following stays usable for free.
                    Column(
                        Modifier.then(if (store.isPro) Modifier else Modifier.gateBlur()),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        val locked = { actions.openTrialPitch(PaywallTrigger.PlayerComparison) }
                        Column(Modifier.fillMaxWidth().rinkCard()) {
                            RinkSectionBar("PLAYER VS PLAYER")
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    SlotColumn(vm, state.playerA, "Player A", state.seasonA, state.phaseA, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.PLAYER_A }, { state.seasonA = it }, { state.phaseA = it }, locked)
                                    Text("vs", style = RinkType.smallBold, color = RinkPalette.inkTertiary, modifier = Modifier.padding(top = 40.dp))
                                    SlotColumn(vm, state.playerB, "Player B", state.seasonB, state.phaseB, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.PLAYER_B }, { state.seasonB = it }, { state.phaseB = it }, locked)
                                }
                                slotWarning?.let { Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                                BigButton("Compare", enabled = canCompare && store.isPro, tag = "compareGo") {
                                    if (resolvedA != null && resolvedB != null) navigator.push(Route.Comparison(resolvedA, resolvedB))
                                }
                            }
                        }
                        Column(Modifier.fillMaxWidth().rinkCard()) {
                            RinkSectionBar("TEAM VS TEAM")
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    TeamSlotColumn(vm, state.teamA, "Team A", state.teamSeasonA, state.teamPhaseA, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.TEAM_A }, { state.teamSeasonA = it }, { state.teamPhaseA = it }, locked)
                                    Text("vs", style = RinkType.smallBold, color = RinkPalette.inkTertiary, modifier = Modifier.padding(top = 40.dp))
                                    TeamSlotColumn(vm, state.teamB, "Team B", state.teamSeasonB, state.teamPhaseB, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.TEAM_B }, { state.teamSeasonB = it }, { state.teamPhaseB = it }, locked)
                                }
                                teamWarning?.let { Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                                BigButton("Compare Teams", enabled = canCompareTeams && store.isPro, tag = "compareTeamsGo") {
                                    val a = state.teamA ?: return@BigButton
                                    val b = state.teamB ?: return@BigButton
                                    navigator.push(Route.TeamComparison(a, b, state.teamSeasonA, state.teamPhaseA, state.teamSeasonB, state.teamPhaseB))
                                }
                            }
                        }
                        Column(Modifier.fillMaxWidth().rinkCard()) {
                            RinkSectionBar("YEAR OVER YEAR")
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Text("Pick a player and season type to compare their aggregated stats across years.", style = RinkType.small, color = RinkPalette.inkSecondary)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    SeasonPhaseMenu(state.yearPhase, { state.yearPhase = it }) { open ->
                                        ChipButton(open, description = "Season type, ${state.yearPhase.label}") {
                                            RinkChip(title = state.yearPhase.label, icon = "hockey.puck.fill", trailing = ChipTrailing.Chevron)
                                        }
                                    }
                                    Row(
                                        Modifier.weight(1f).height(46.dp).clip(RoundedCornerShape(12.dp)).background(RinkPalette.turf)
                                            .clickable(enabled = store.isPro) { picker = PickerTarget.YEAR_PLAYER },
                                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        SfIcon("calendar.badge.clock", 16.dp, Color.White)
                                        Text("Choose a player", style = RinkType.bodyBold, color = Color.White)
                                    }
                                }
                            }
                        }
                    }
                    if (!store.isPro) {
                        BlurGateUnlock(
                            "Stack any two players, or any player against his own past seasons",
                            PaywallTrigger.PlayerComparison,
                            Modifier.align(Alignment.BottomCenter).clip(RoundedCornerShape(RinkGeo.radiusCard)),
                        )
                    }
                }
            }
        }
    }

    StatScoutSheet(showingFollowSheet, { showingFollowSheet = false }) { FollowPlayersSheet(vm) { showingFollowSheet = false } }
    StatScoutSheet(picker != null, { picker = null }) {
        when (val target = picker) {
            PickerTarget.TEAM_A, PickerTarget.TEAM_B -> {
                val season = if (target == PickerTarget.TEAM_A) state.teamSeasonA else state.teamSeasonB
                val phase = if (target == PickerTarget.TEAM_A) state.teamPhaseA else state.teamPhaseB
                // Every club with data, including the one in the other slot: a franchise against its own past.
                TeamPickerSheet(vm.players(season, phase).map { normalizedTeamAbbreviation(it.team) }.toSortedSet().toList(), { picker = null }) { team ->
                    picker = null
                    if (target == PickerTarget.TEAM_A) state.teamA = team else state.teamB = team
                }
            }
            null -> Unit
            else -> {
                val (season, phase) = when (target) {
                    PickerTarget.PLAYER_A -> state.seasonA to state.phaseA
                    PickerTarget.PLAYER_B -> state.seasonB to state.phaseB
                    else -> state.seasonA to state.yearPhase
                }
                val candidates = vm.players(season, phase).filter { c ->
                    when (target) {
                        PickerTarget.PLAYER_A -> (c.playerId != state.playerB?.playerId || season != state.seasonB || phase != state.phaseB) &&
                            (resolvedB?.canCompareHeadToHead(c) ?: true)
                        PickerTarget.PLAYER_B -> (c.playerId != state.playerA?.playerId || season != state.seasonA || phase != state.phaseA) &&
                            (resolvedA?.canCompareHeadToHead(c) ?: true)
                        else -> true
                    }
                }
                PlayerPickerSheet(candidates, "Select Player · " + SeasonLabel.display(season), season, vm.isHistoricalLoading, onCancel = { picker = null }) { selected ->
                    picker = null
                    when (target) {
                        PickerTarget.PLAYER_A -> state.playerA = selected
                        PickerTarget.PLAYER_B -> state.playerB = selected
                        else -> navigator.push(Route.YearCompareRoute(selected.playerId, selected.name, state.yearPhase))
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun YourPlayersCard(
    followed: List<Player>,
    isEmpty: Boolean,
    isPro: Boolean,
    inSlot: (Player) -> Boolean,
    onEdit: () -> Unit,
    onTap: (Player) -> Unit,
    onOpen: (Player) -> Unit,
    onUnfollow: (Player) -> Unit,
) {
    Column(Modifier.fillMaxWidth().rinkCard()) {
        RinkSectionBar("YOUR PLAYERS", trailing = {
            Row(
                Modifier.heightIn(min = 28.dp).clip(CircleShape).clickable(onClick = onEdit).padding(horizontal = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SfIcon("star", 12.dp, RinkPalette.turf)
                Text(if (isEmpty) "Add" else "Edit", style = RinkType.micro, color = RinkPalette.turf)
            }
        })
        if (followed.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(vertical = 18.dp, horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Follow players to keep them one tap from a comparison, and to spot them on the Trends board.",
                    style = RinkType.small,
                    color = RinkPalette.inkSecondary,
                    textAlign = TextAlign.Center,
                )
                Box(
                    Modifier.heightIn(min = 44.dp).clickable(onClick = onEdit),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Follow players",
                        style = RinkType.smallBold,
                        color = Color.White,
                        modifier = Modifier.clip(CircleShape).background(RinkPalette.turf).padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
        } else {
            followed.forEachIndexed { index, player ->
                var menu by remember { mutableStateOf(false) }
                Box {
                    Row(
                        Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt).bottomHairline(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            Modifier.weight(1f).fillMaxSize().combinedClickable(onClick = { onTap(player) }, onLongClick = { menu = true })
                                .padding(start = RinkGeo.padInline, end = if (isPro) 6.dp else RinkGeo.padInline)
                                .semantics { contentDescription = if (isPro) "${player.name}. Loads ${player.name} into a comparison slot" else "${player.name}. Opens ${player.name}'s stats" },
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            PlayerHeadshot(player.team, player.initials, 34.dp)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(player.name, style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1)
                                Text("${displayTeamAbbr(player.team)} · ${player.displayPosition}", style = RinkType.micro, color = RinkPalette.inkTertiary)
                            }
                            if (inSlot(player)) {
                                Text(
                                    "IN SLOT",
                                    style = RinkType.micro,
                                    color = Color.White,
                                    modifier = Modifier.clip(CircleShape).background(RinkPalette.turf).padding(horizontal = 8.dp, vertical = 4.dp),
                                )
                            } else SfIcon(if (isPro) "plus.circle" else "chevron.right", 18.dp, RinkPalette.inkTertiary)
                        }
                        if (isPro) {
                            Box(
                                Modifier.width(44.dp).fillMaxSize().clickable { onOpen(player) }.semantics { contentDescription = "Open ${player.name}'s page" },
                                contentAlignment = Alignment.Center,
                            ) { SfIcon("chevron.right", 16.dp, RinkPalette.inkTertiary) }
                        }
                    }
                    DropdownMenu(menu, { menu = false }, containerColor = RinkPalette.surface) {
                        DropdownMenuItem(
                            text = { Text("Open player page", style = RinkType.body, color = RinkPalette.ink) },
                            leadingIcon = { SfIcon("person.text.rectangle", 18.dp, RinkPalette.inkSecondary) },
                            onClick = {
                                menu = false
                                onOpen(player)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Unfollow", style = RinkType.body, color = RinkPalette.performanceLow) },
                            leadingIcon = { SfIcon("star.slash", 18.dp, RinkPalette.performanceLow) },
                            onClick = {
                                menu = false
                                onUnfollow(player)
                            },
                        )
                    }
                }
            }
            Text(
                if (isPro) "Tap a player to load them into a slot below." else "Tap a player to see their stats. Head-to-head needs StatScout+.",
                style = RinkType.micro,
                color = RinkPalette.inkTertiary,
                modifier = Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padCard, vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun BigButton(title: String, enabled: Boolean, tag: String, onClick: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(12.dp))
            .background(if (enabled) RinkPalette.turf else RinkPalette.inkTertiary)
            .clickable(enabled = enabled, onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(title, style = RinkType.bodyBold, color = Color.White) }
}

@Composable
private fun SeasonPill(
    vm: DashboardViewModel,
    seasons: List<Int>,
    season: Int,
    phase: SeasonPhase,
    label: String,
    enabled: Boolean,
    onSeason: (Int) -> Unit,
    onPhase: (SeasonPhase) -> Unit,
    onLocked: () -> Unit,
) {
    SeasonPhasePicker(
        seasons = seasons,
        selectedSeason = season,
        selectedPhase = phase,
        isSeasonLocked = vm::isSeasonLocked,
        onSelectSeason = { if (vm.isSeasonLocked(it)) onLocked() else onSeason(it) },
        onSelectPhase = onPhase,
    ) { open ->
        ChipButton(if (enabled) open else ({}), Modifier.fillMaxWidth(), description = "Season and season type for $label") {
            Row(
                Modifier.fillMaxWidth().height(32.dp).clip(CircleShape).background(RinkPalette.surface)
                    .border(0.5.dp, RinkPalette.hairline, CircleShape).padding(horizontal = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FitText("${SeasonLabel.display(season)} · ${phase.label}", RinkType.smallBold, RinkPalette.ink, Modifier.weight(1f, fill = false), minScale = 0.75f)
                SfIcon("chevron.down", 13.dp, RinkPalette.inkSecondary)
            }
        }
    }
}

@Composable
private fun SlotColumn(
    vm: DashboardViewModel,
    player: Player?,
    placeholder: String,
    season: Int,
    phase: SeasonPhase,
    modifier: Modifier,
    enabled: Boolean,
    onPickPlayer: () -> Unit,
    onPickSeason: (Int) -> Unit,
    onPickPhase: (SeasonPhase) -> Unit,
    onLocked: () -> Unit,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(RinkGeo.radiusCard)).background(RinkPalette.surfaceAlt)
                .clickable(enabled = enabled, onClick = onPickPlayer).padding(vertical = 12.dp).testTag("slot_$placeholder"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (player != null) {
                PlayerHeadshot(player.team, player.initials, 44.dp)
                FitText(player.name, RinkType.smallBold, RinkPalette.ink, minScale = 0.7f)
            } else {
                Box(Modifier.size(44.dp).clip(CircleShape).background(RinkPalette.surfaceAlt), contentAlignment = Alignment.Center) {
                    SfIcon("plus", 18.dp, RinkPalette.inkTertiary)
                }
                Text(placeholder, style = RinkType.small, color = RinkPalette.inkTertiary)
            }
        }
        SeasonPill(vm, vm.availableSeasons, season, phase, player?.name ?: placeholder, enabled, onPickSeason, onPickPhase, onLocked)
    }
}

@Composable
private fun TeamSlotColumn(
    vm: DashboardViewModel,
    team: String?,
    placeholder: String,
    season: Int,
    phase: SeasonPhase,
    modifier: Modifier,
    enabled: Boolean,
    onPickTeam: () -> Unit,
    onPickSeason: (Int) -> Unit,
    onPickPhase: (SeasonPhase) -> Unit,
    onLocked: () -> Unit,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(RinkGeo.radiusCard)).background(RinkPalette.surfaceAlt)
                .clickable(enabled = enabled, onClick = onPickTeam).padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                Modifier.size(44.dp).clip(CircleShape).background(team?.let { TeamColor.color(it) } ?: RinkPalette.surfaceAlt),
                contentAlignment = Alignment.Center,
            ) {
                if (team != null) Text(displayTeamAbbr(team), style = RinkType.smallBold, color = Color.White)
                else SfIcon("plus", 16.dp, RinkPalette.inkTertiary)
            }
            FitText(team?.let(::teamFullName) ?: placeholder, if (team == null) RinkType.small else RinkType.smallBold, if (team == null) RinkPalette.inkTertiary else RinkPalette.ink, minScale = 0.7f)
        }
        // Team-scoped, so no All Time: a career line carries the last club and would miscredit the franchise.
        SeasonPill(vm, vm.seasonsExcludingAllTime, season, phase, team ?: placeholder, enabled, onPickSeason, onPickPhase, onLocked)
    }
}

@Composable
private fun TeamPickerSheet(teams: List<String>, onCancel: () -> Unit, onSelect: (String) -> Unit) {
    var searchText by remember { mutableStateOf("") }
    val filtered = if (searchText.isEmpty()) teams else teams.filter { teamFullName(it).contains(searchText, true) || it.contains(searchText, true) }
    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(title = "Select Team", leading = { TextAction("Cancel", RinkType.body, Color.White, onCancel) })
        SearchField(searchText, { searchText = it }, Modifier.padding(12.dp), prompt = "Search teams")
        LazyColumn(Modifier.fillMaxSize()) {
            items(filtered, key = { it }) { team ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).background(RinkPalette.surface).bottomHairline().clickable { onSelect(team) }
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(32.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
                        FitText(displayTeamAbbr(team), RinkType.micro, Color.White, minScale = 0.6f)
                    }
                    Text(teamFullName(team), style = RinkType.bodyBold, color = RinkPalette.ink)
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

/** A player's seasons side by side, reached from the Compare tab. */
@Composable
fun YearCompareDestination(route: Route.YearCompareRoute) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    var current by remember { mutableStateOf(route) }
    var picking by remember { mutableStateOf(false) }
    val history = vm.playerHistories[current.playerId].orEmpty()
        .filter { it.seasonPhase == current.phase && !StatScoutSeason.isAllTime(it.season ?: 0) }
    val latest = history.maxByOrNull { it.season ?: 0 }
    PushedScreen(current.playerName) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottomBarPadding())) {
            Row(
                Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().rinkCard().padding(horizontal = RinkGeo.padInline, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (latest != null) {
                    Row(
                        Modifier.weight(1f).clickable { navigator.push(Route.PlayerProfile(latest)) },
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        PlayerHeadshot(latest.team, latest.initials, 34.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(current.playerName, style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1)
                            Text("${displayTeamAbbr(latest.team)} · ${latest.displayPosition}", style = RinkType.micro, color = RinkPalette.inkTertiary)
                        }
                    }
                } else Text(current.playerName, style = RinkType.bodyBold, color = RinkPalette.ink, modifier = Modifier.weight(1f))
                ChipButton({ picking = true }, description = "Compare a different player's seasons") {
                    RinkChip(title = "Change", icon = "arrow.triangle.2.circlepath", trailing = ChipTrailing.Chevron)
                }
            }
            if (history.size < 2) {
                EmptyState(
                    "Not enough history",
                    "calendar.badge.clock",
                    if (vm.isHistoricalLoading) "Loading past seasons for ${current.playerName}…" else "${current.playerName} doesn't have multiple seasons of data to compare.",
                    Modifier.padding(vertical = 40.dp),
                )
            } else YearComparisonView(history)
        }
    }
    StatScoutSheet(picking, { picking = false }) {
        PlayerPickerSheet(vm.players(vm.selectedSeason, current.phase), "Select Player · " + SeasonLabel.display(vm.selectedSeason), vm.selectedSeason, vm.isHistoricalLoading, onCancel = { picking = false }) { p ->
            picking = false
            current = Route.YearCompareRoute(p.playerId, p.name, current.phase)
        }
    }
}
