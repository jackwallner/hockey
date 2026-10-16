package com.jackwallner.hockey.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.KeyValueStore
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricCoverage
import com.jackwallner.hockey.model.LeagueConference
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.competitionRanks
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.metricValue
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.HomeTopBar
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.SeasonPhaseNavPill
import com.jackwallner.hockey.ui.components.BlurGateUnlock
import com.jackwallner.hockey.ui.components.ChipButton
import com.jackwallner.hockey.ui.components.ChipTrailing
import com.jackwallner.hockey.ui.components.DataFreshnessView
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkChip
import com.jackwallner.hockey.ui.components.RinkMenu
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.PositionTabs
import com.jackwallner.hockey.ui.components.InfoNote
import com.jackwallner.hockey.ui.components.LeaderboardTableHeader
import com.jackwallner.hockey.ui.components.LeaderboardTableRow
import com.jackwallner.hockey.ui.components.LoadingCard
import com.jackwallner.hockey.ui.components.LoadingStatusBar
import com.jackwallner.hockey.ui.components.MenuItem
import com.jackwallner.hockey.ui.components.MenuSection
import com.jackwallner.hockey.ui.components.RefreshableBox
import com.jackwallner.hockey.ui.components.SearchField
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.SortDirectionButton
import com.jackwallner.hockey.ui.components.StatOption
import com.jackwallner.hockey.ui.components.StatPickerMenu
import com.jackwallner.hockey.ui.components.TextAction
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.cardSlice
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
import kotlinx.coroutines.launch

/** Which league-wide board the Stats tab is drawing. */
enum class StatsBoard { ADVANCED, STANDARD, BEST_WORST }

/** Traditional production stats offered for each position group. */
/** Traditional production stats offered for each position group: the `standard_stats` labels in the hockey contract. */
object StandardStatCatalog {
    fun stats(position: PlayerPositionGroup): List<String> = when (position) {
        PlayerPositionGroup.FORWARD, PlayerPositionGroup.DEFENSE ->
            listOf("P", "G", "A", "+/-", "PIM", "PPG", "PPP", "SHG", "GWG", "SOG", "Sh%", "TOI/GP", "Hits", "Blk", "FO%", "GP")
        PlayerPositionGroup.GOALIE -> listOf("SV%", "GAA", "W", "L", "OT", "SO", "SV", "SA", "GS", "GP")
    }

    /** Stats where a lower number is the better one. */
    private val LOWER_IS_BETTER = setOf("GAA", "PIM", "L", "OT")

    @Suppress("UNUSED_PARAMETER")
    fun defaultDescending(stat: String, position: PlayerPositionGroup): Boolean = stat !in LOWER_IS_BETTER

    fun defaultStat(position: PlayerPositionGroup): String = stats(position).firstOrNull() ?: "GP"

    /** A stat picked on purpose follows to any position that offers it; a default does not. */
    fun stat(current: String, from: PlayerPositionGroup, to: PlayerPositionGroup): String =
        if (current != defaultStat(from) && current in stats(to)) current else defaultStat(to)
}

/** The Stats tab's shared board state, kept across pushes like iOS `@State`. */
@Stable
class StatsBoardState(private val defaults: KeyValueStore) {
    private var boardState by mutableStateOf(
        StatsBoard.entries.firstOrNull { it.name == defaults.getString(BOARD_KEY) } ?: StatsBoard.STANDARD,
    )
    var board: StatsBoard
        get() = boardState
        set(value) {
            boardState = value
            defaults.putString(BOARD_KEY, value.name)
        }
    var standardStat by mutableStateOf(StandardStatCatalog.defaultStat(PlayerPositionGroup.FORWARD))
    var standardSortDescending by mutableStateOf(true)
    /** Set when a cohort with no advanced line pushed the board to Standard, so leaving it puts Advanced back. */
    var fellBackFromAdvanced by mutableStateOf(false)

    private companion object {
        const val BOARD_KEY = "stats.board"
    }
}

/** Single home for every league-wide statistic. */
@Composable
fun StatsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val actions = LocalAppActions.current
    val state = rememberRetained("statsBoard") { StatsBoardState(graph.defaults) }
    var showingFollowing by remember { mutableStateOf(false) }

    // Position changes: keep a chosen stat, fall back from Advanced where a cohort has none.
    var lastPosition by remember { mutableStateOf(vm.selectedPosition) }
    LaunchedEffect(vm) {
        snapshotFlow { vm.selectedPosition }.collect { next ->
            val old = lastPosition
            lastPosition = next
            if (old == next) return@collect
            val kept = StandardStatCatalog.stat(state.standardStat, old, next)
            if (kept != state.standardStat) {
                state.standardStat = kept
                state.standardSortDescending = StandardStatCatalog.defaultDescending(kept, next)
            }
            if (vm.availableAdvancedSortMetrics.isEmpty() && state.board == StatsBoard.ADVANCED) {
                state.board = StatsBoard.STANDARD
                state.fellBackFromAdvanced = true
            } else if (state.fellBackFromAdvanced && vm.availableAdvancedSortMetrics.isNotEmpty()) {
                if (state.board == StatsBoard.STANDARD) state.board = StatsBoard.ADVANCED
                state.fellBackFromAdvanced = false
            }
        }
    }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        HomeTopBar(leading = {
            SeasonPhaseNavPill(vm.availableSeasons) { actions.openTrialPitch(PaywallTrigger.LockedSeason(it)) }
        })
        if (vm.selectedSeason == vm.freeSeason && vm.selectedPhase == SeasonPhase.REGULAR) {
            DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 4.dp))
        }
        RinkSegmented(
            segments = listOf(Segment(false, "League leaders"), Segment(true, "Following", icon = "star.fill")),
            selection = showingFollowing,
            onSelect = { showingFollowing = it },
            modifier = Modifier.padding(horizontal = 12.dp),
        )
        if (showingFollowing) FollowingStatsView(vm)
        else when (state.board) {
            StatsBoard.ADVANCED -> AdvancedBoard(vm, state)
            StatsBoard.STANDARD -> StandardStatsLeadersView(
                players = vm.qualifiedSeasonPlayers.filter { it.positionGroup == vm.selectedPosition && vm.matchesBoardFilters(it) },
                selectedStat = state.standardStat,
                onSelectStat = { state.standardStat = it },
                selectedPosition = vm.selectedPosition,
                onSelectPosition = { vm.selectedPosition = it },
                sortDescending = state.standardSortDescending,
                onSortDescending = { state.standardSortDescending = it },
                boardState = state,
                viewModel = vm,
            )
            StatsBoard.BEST_WORST -> BestWorstBoard(vm, state)
        }
    }
}

@Composable
private fun BestWorstBoard(vm: DashboardViewModel, state: StatsBoardState) {
    val isPro = LocalGraph.current.subscriptions.isPro
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 4.dp)) { StatsViewMenu(vm, state) }
        if (isPro) MetricLeadersView(vm.allMetrics)
        else Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().gateBlur()) { MetricLeadersView(vm.allMetrics, interactive = false) }
            BlurGateUnlock(
                "See who leads and who trails on every metric in the league",
                PaywallTrigger.BestWorst,
                Modifier.align(Alignment.BottomCenter).padding(horizontal = 12.dp).padding(bottom = 100.dp),
            )
        }
    }
}

/** Picking a statistic also selects the vocabulary that owns it. */
@Composable
fun StatsBoardStatPicker(vm: DashboardViewModel, state: StatsBoardState) {
    val position = vm.selectedPosition
    val active = when (state.board) {
        StatsBoard.ADVANCED -> vm.currentSortMetric ?: vm.sortLabel
        StatsBoard.STANDARD -> state.standardStat
        StatsBoard.BEST_WORST -> "Best & Worst"
    }
    StatPickerMenu(
        activeLabel = active,
        advanced = vm.availableAdvancedSortMetrics.map {
            StatOption(it, it, state.board == StatsBoard.ADVANCED && it == vm.currentSortMetric)
        },
        standard = StandardStatCatalog.stats(position).map {
            StatOption(it, it, state.board == StatsBoard.STANDARD && it == state.standardStat)
        },
        onSelectAdvanced = {
            state.board = StatsBoard.ADVANCED
            vm.setUserSortMetric(it.id)
        },
        onSelectStandard = {
            state.board = StatsBoard.STANDARD
            state.standardStat = it.id
            state.standardSortDescending = StandardStatCatalog.defaultDescending(it.id, position)
        },
    )
}

/** Secondary board options: conference, rookies, qualifier, and Best & Worst. */
@Composable
fun StatsViewMenu(vm: DashboardViewModel, state: StatsBoardState) {
    val isPro = LocalGraph.current.subscriptions.isPro
    val board = state.board
    val isActive = vm.qualifierLevel != DashboardViewModel.QualifierLevel.ALL || vm.selectedConference != LeagueConference.ALL ||
        vm.isRookieFilterActive || board == StatsBoard.BEST_WORST
    val leaderboard = board != StatsBoard.BEST_WORST
    RinkMenu(
        listOfNotNull(
            MenuSection("Conference", LeagueConference.entries.map { c ->
                MenuItem(c.label, checked = c == vm.selectedConference) { vm.selectedConference = c }
            }),
            if (vm.canFilterRookies) MenuSection("Players", listOf(false, true).map { rookies ->
                MenuItem(if (rookies) "Rookies" else "Everyone", checked = rookies == vm.rookiesOnly) { vm.rookiesOnly = rookies }
            }) else null,
            MenuSection("Qualifier", DashboardViewModel.QualifierLevel.entries.map { level ->
                MenuItem("${level.label} · ${level.description}", checked = level == vm.qualifierLevel) { vm.qualifierLevel = level }
            }),
            MenuSection("Show", listOf(
                MenuItem("Leaderboard", checked = leaderboard) { if (!leaderboard) state.board = StatsBoard.ADVANCED },
                MenuItem(
                    if (isPro || board == StatsBoard.BEST_WORST) "Best & Worst" else "Best & Worst (StatScout+)",
                    checked = board == StatsBoard.BEST_WORST,
                    locked = !isPro && board != StatsBoard.BEST_WORST,
                ) { state.board = StatsBoard.BEST_WORST },
            )),
        ),
        Modifier.testTag("viewMenu"),
    ) { open ->
        ChipButton(open, description = "View options") {
            RinkChip(title = "View", icon = "slider.horizontal.3", trailing = ChipTrailing.Chevron, isActive = isActive)
        }
    }
}

/** The stat picker, direction, search toggle and View menu row every board shares. */
@Composable
fun BoardControlRow(
    picker: @Composable () -> Unit,
    descending: Boolean,
    statLabel: String,
    onToggleDirection: () -> Unit,
    isSearchActive: Boolean,
    onToggleSearch: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth().padding(top = RinkGeo.controlRowGap - 6.dp).padding(end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(start = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            picker()
            SortDirectionButton(descending, statLabel, onToggleDirection)
        }
        ChipButton(onToggleSearch, description = "Search players or teams", modifier = Modifier.testTag("searchToggle")) {
            RinkChip(icon = "magnifyingglass", isActive = isSearchActive)
        }
        trailing?.invoke()
    }
}

@Composable
fun SearchRow(text: String, onTextChange: (String) -> Unit, onCancel: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SearchField(text, onTextChange, Modifier.weight(1f), focusOnAppear = true)
        TextAction("Cancel", RinkType.small, RinkPalette.turf, onCancel)
    }
}

/** The Advanced leaderboard (iOS `DashboardView`). */
@Composable
private fun AdvancedBoard(vm: DashboardViewModel, state: StatsBoardState) {
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val store = LocalGraph.current.subscriptions
    val haptic = rememberHaptic()
    var isSearching by remember { mutableStateOf(false) }
    val activeSearch = isSearching || vm.searchText.isNotEmpty()

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            if ((vm.isLoading || vm.isHistoricalLoading) && vm.players.isNotEmpty()) {
                LoadingStatusBar(vm.loadingMessage, vm.loadingProgress, Modifier.padding(top = 8.dp))
            }
            PositionTabs(vm.selectedPosition, { if (it != vm.selectedPosition) vm.selectedPosition = it }, Modifier.padding(top = 8.dp))
            if (vm.players.isNotEmpty()) {
                BoardControlRow(
                    picker = { StatsBoardStatPicker(vm, state) },
                    descending = vm.sortDescending,
                    statLabel = vm.currentSortMetric ?: vm.sortLabel,
                    onToggleDirection = vm::toggleSortDirection,
                    isSearchActive = activeSearch,
                    onToggleSearch = {
                        isSearching = !isSearching
                        if (!isSearching) vm.searchText = ""
                        haptic()
                    },
                    trailing = { StatsViewMenu(vm, state) },
                )
                AnimatedVisibility(activeSearch) {
                    SearchRow(vm.searchText, { vm.searchText = it }) {
                        isSearching = false
                        vm.searchText = ""
                    }
                }
            }
            RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
                val sort = vm.currentSortMetricForDisplay
                val leaderboard = vm.leaderboard
                val ranks = competitionRanks(
                    leaderboard.map { player ->
                        val label = sort.first
                        val category = sort.second
                        if (label == null || category == null) null else metricValue(player, label, category)
                    },
                )
                LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
                    if (vm.players.isNotEmpty() && activeSearch) item { TeamResults(vm.searchedTeams.take(3)) }
                    item { Spacer(Modifier.height(8.dp)) }
                    val status = boardStatus(vm, leaderboard.isEmpty())
                    if (status != null) {
                        item { Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, true)) { status() } }
                    } else {
                        item {
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, leaderboard.isEmpty())) {
                                LeaderboardTableHeader(vm.sortDescending, vm.currentSortMetric ?: vm.sortLabel, emptyList(), onToggleDirection = vm::toggleSortDirection)
                            }
                        }
                        itemsIndexed(leaderboard, key = { _, p -> p.id }) { index, player ->
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == leaderboard.lastIndex)) {
                                LeaderboardTableRow(
                                    rank = ranks[index],
                                    player = player,
                                    stripe = index,
                                    metricLabel = sort.first,
                                    metricCategory = sort.second,
                                    volume = vm.volumeCaption(player, sort.second),
                                    isSmallSample = isSmallSample(vm, player, sort.first, sort.second),
                                ) { navigator.push(Route.PlayerProfile(player)) }
                            }
                        }
                    }
                    if (vm.players.isNotEmpty()) {
                        item { Spacer(Modifier.height(12.dp)) }
                        coverageNoteText(vm)?.let { note -> item { InfoNote(note) } }
                        item {
                            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                if (!store.isPro) {
                                    Row(
                                        Modifier.heightIn(min = 36.dp).clip(CircleShape).background(RinkPalette.turf)
                                            .clickable { actions.openTrialPitch(store.defaultUpgradeTrigger) }.padding(horizontal = 16.dp, vertical = 8.dp),
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        SfIcon("crown.fill", 12.dp, Color.White)
                                        Text(store.upgradeCTALabel, style = RinkType.micro, color = Color.White)
                                    }
                                }
                                TextAction("About StatScout", RinkType.micro, RinkPalette.inkTertiary, { navigator.push(Route.Settings) })
                            }
                        }
                    }
                }
            }
        }
        if (vm.isLoading && vm.players.isEmpty()) {
            LoadingCard(vm.loadingMessage, vm.loadingProgress, Modifier.align(Alignment.Center))
        }
    }
}

private fun isSmallSample(vm: DashboardViewModel, player: Player, label: String?, category: MetricCategory?): Boolean {
    label ?: return false
    val metric = player.metrics.firstOrNull { it.label == label && (category == null || it.category == category) } ?: return false
    return !vm.isQualified(player, metric)
}

/** The empty, error and loading states in place of the board; null when there are rows to show. */
private fun boardStatus(vm: DashboardViewModel, empty: Boolean): (@Composable () -> Unit)? {
    if (!empty) return null
    return when {
        vm.searchText.isNotEmpty() -> { { EmptyState("No players found", "magnifyingglass", "Try a different search term.", Modifier.heightIn(min = 200.dp)) } }
        vm.errorMessage != null -> {
            {
                val offline = vm.lastFailureWasConnectivity
                val scope = androidx.compose.runtime.rememberCoroutineScope()
                EmptyState(
                    if (offline) "No connection" else "Data Error",
                    if (offline) "wifi.exclamationmark" else "exclamationmark.triangle",
                    if (offline) "The current season needs a connection for its first update. Once it has loaded, your saved stats are here offline."
                    else vm.errorMessage,
                    Modifier.heightIn(min = 200.dp),
                    actionTitle = "Retry",
                ) { scope.launch { vm.load() } }
            }
        }
        vm.isHistoricalLoading -> {
            {
                Column(Modifier.fillMaxWidth().heightIn(min = 200.dp).padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator(color = RinkPalette.inkTertiary)
                    Text("Loading ${SeasonLabel.display(vm.selectedSeason)}…", style = RinkType.small, color = RinkPalette.inkSecondary)
                }
            }
        }
        !vm.isLoading -> {
            {
                val hasSeasonData = vm.seasonPlayers.isNotEmpty()
                val needsFirstConnection = !hasSeasonData && vm.selectedSeason == vm.freeSeason && vm.lastFetchFailed
                val scope = androidx.compose.runtime.rememberCoroutineScope()
                EmptyState(
                    when {
                        needsFirstConnection -> "Connect to load ${SeasonLabel.display(vm.selectedSeason)}"
                        hasSeasonData -> "No matching metrics"
                        else -> "No players yet"
                    },
                    if (needsFirstConnection) "wifi.exclamationmark" else "hockey.puck.fill",
                    when {
                        needsFirstConnection -> "The current season needs a connection for its first update. Once it has loaded, your saved stats are here offline."
                        hasSeasonData -> "No metrics are available for ${vm.selectedPosition.raw} in ${SeasonLabel.display(vm.selectedSeason)}."
                        else -> "No player data is available for the ${SeasonLabel.display(vm.selectedSeason)} season."
                    },
                    Modifier.heightIn(min = 200.dp),
                    actionTitle = if (needsFirstConnection) "Try Again" else null,
                    action = if (needsFirstConnection) ({ scope.launch { vm.load() } }) else null,
                )
            }
        }
        else -> { { Spacer(Modifier.height(200.dp)) } }
    }
}

/** Why a season (or the live season so far) shows fewer advanced metrics, and what the bars mean. */
private fun coverageNoteText(vm: DashboardViewModel): String? {
    val category = vm.selectedPosition.primaryCategory
    val isLive = vm.selectedSeason == vm.freeSeason && vm.selectedPhase == SeasonPhase.REGULAR
    val pending = if (isLive) MetricCoverage.pendingNote(vm.dataFreshness?.shotsStatus, vm.dataFreshness?.summaryStatus) else null
    val noun = vm.selectedPosition.singular.lowercase()
    val cohort = if (isLive) "every $noun with a line this season" else "every qualified $noun"
    val minimum = if (vm.qualifierLevel == DashboardViewModel.QualifierLevel.ALL) "Dimmed rows are under the playing-time minimum."
    else "Players under the playing-time minimum are hidden; View shows them."
    val legend = if (isLive) "Bars show the percentile among $cohort. $minimum" else "Bars show the percentile among $cohort."
    return listOfNotNull(MetricCoverage.note(vm.selectedSeason, category), pending, legend).joinToString(" ")
}

/** Clubs matching the search, above the player rows: "chiefs" usually means Kansas City. */
@Composable
private fun TeamResults(teams: List<String>) {
    if (teams.isEmpty()) return
    val navigator = LocalNavigator.current
    Column(Modifier.padding(horizontal = 12.dp).padding(top = 8.dp).rinkCard()) {
        teams.forEachIndexed { index, team ->
            if (index > 0) com.jackwallner.hockey.ui.components.Hairline()
            Row(
                Modifier.fillMaxWidth().heightIn(min = RinkGeo.rowHeight).clickable { navigator.push(Route.Team(team)) }
                    .padding(horizontal = RinkGeo.padCard),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(28.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
                    FitText(displayTeamAbbr(team), RinkType.micro, Color.White, minScale = 0.6f)
                }
                Text(teamFullName(team), style = RinkType.bodyBold, color = RinkPalette.ink)
                Text("TEAM PAGE", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f))
                SfIcon("chevron.right", 14.dp, RinkPalette.inkTertiary)
            }
        }
    }
}
