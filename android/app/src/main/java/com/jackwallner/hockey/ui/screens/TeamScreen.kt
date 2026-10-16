package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.leagueTeamAbbreviations
import com.jackwallner.hockey.model.searchMatches
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.ChipButton
import com.jackwallner.hockey.ui.components.ChipTrailing
import com.jackwallner.hockey.ui.components.DataFreshnessView
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkChip
import com.jackwallner.hockey.ui.components.RinkMenu
import com.jackwallner.hockey.ui.components.RinkNavPill
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.RinkTabs
import com.jackwallner.hockey.ui.components.RinkTopBar
import com.jackwallner.hockey.ui.components.LeaderboardTableHeader
import com.jackwallner.hockey.ui.components.LeaderboardTableRow
import com.jackwallner.hockey.ui.components.MenuItem
import com.jackwallner.hockey.ui.components.MenuSection
import com.jackwallner.hockey.ui.components.SearchField
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SeasonPhasePicker
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatGlossaryLink
import com.jackwallner.hockey.ui.components.TextAction
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType

private enum class TeamTab(val raw: String) { ADVANCED("Advanced"), STANDARD("Standard"), ROSTER("Roster") }

private enum class RosterMode(val raw: String) { SEASON("Season"), RECENT("Recent") }

private fun priorityMetrics(category: MetricCategory): List<String> = when (category) {
    MetricCategory.SCORING -> listOf("P", "G", "A", "P/60")
    MetricCategory.SHOT_QUALITY -> listOf("ixG", "GAx", "ixG/60", "Shots/60")
    MetricCategory.PLAY_DRIVING -> listOf("xGF%", "Rel xGF%", "CF%", "Hits")
    MetricCategory.GOALTENDING -> listOf("GSAx", "SV%", "GAA")
}

/** One club's page: tonight's game, the season at a glance, then Advanced, Standard and Roster tabs. */
@Composable
fun TeamScreen(abbr: String) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val isPro = graph.subscriptions.isPro
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val haptic = rememberHaptic()

    var selectedTab by rememberSaveable { mutableStateOf(TeamTab.ADVANCED) }
    var searchText by rememberSaveable { mutableStateOf("") }
    var isSearching by rememberSaveable { mutableStateOf(false) }
    // Default to Scoring so the roster always shows a meaningful sort metric.
    var selectedCategory by rememberSaveable { mutableStateOf<MetricCategory?>(MetricCategory.SCORING) }
    var sortDescending by rememberSaveable { mutableStateOf(true) }
    var lastDefaultedSortKey by rememberSaveable { mutableStateOf<String?>(null) }
    var rosterSide by rememberSaveable { mutableStateOf(PlayerPositionGroup.FORWARD) }
    var qualifierLevel by rememberSaveable { mutableStateOf(DashboardViewModel.QualifierLevel.ALL) }
    var rosterMode by rememberSaveable { mutableStateOf(RosterMode.SEASON) }
    var rosterWindow by rememberSaveable { mutableStateOf(RecentWindow.FOUR) }
    var userSortLabel by rememberSaveable { mutableStateOf<String?>(null) }

    // The roster for the season and phase that are selected right now, so the
    // nav-bar picker moves the rows, cards, category filters and sort metrics
    // together instead of leaving the page on the season it was opened in.
    val players = vm.players(abbr)
    val displaySeason = vm.selectedSeason
    val leaguePlayers = vm.seasonPlayers
    val displayPhase = vm.selectedPhase

    // Recent form exists for the live season only: the rolling windows and the
    // per-game logs behind them are no longer kept for finished seasons, so every
    // Recent control on this screen is hidden (not locked) on a historical one.
    val supportsRecent = vm.supportsRecentForm(displaySeason)
    val isRosterRecent = rosterMode == RosterMode.RECENT && isPro && supportsRecent

    val availableSortLabels: List<String> = selectedCategory?.let { category ->
        val present = players.flatMap { p -> p.metrics.filter { it.category == category }.map { it.label } }.toSet()
        val ordered = category.metricPriorityOrder.filter { it in present }
        ordered + (present - category.metricPriorityOrder.toSet()).sorted()
    } ?: emptyList()

    val sortMetric: Pair<String, MetricCategory>? = selectedCategory?.let { category ->
        val user = userSortLabel
        if (user != null && user in availableSortLabels) return@let user to category
        priorityMetrics(category).firstOrNull { label ->
            players.any { p -> p.metrics.any { it.label == label && it.category == category } }
        }?.let { it to category }
    }
    val sortLabel = if (selectedCategory == null) "Overall" else sortMetric?.first ?: "Top Category"

    // "All" is the whole roster at once, so no one metric means the same thing
    // down the column; each row would show its own overall percentile instead.
    val rowLabel = sortMetric?.first
    val rowCategory = sortMetric?.second

    fun recentFormFor(player: Player) = vm.recentForm(player.playerId, rosterWindow)
    val recentKey = sortMetric?.first?.let { RecentMetricKey.key(it) }
    fun recentValue(player: Player): Double? = recentKey?.let { recentFormFor(player)?.metrics?.get(it) }
    fun recentDelta(player: Player): Double? = recentKey?.let { recentFormFor(player)?.delta?.get(it) }
    fun recentValueText(player: Player): String {
        val label = sortMetric?.first ?: return "-"
        val value = recentValue(player) ?: return "-"
        return RecentMetricKey.format(value, label)
    }
    val hasRecentData = vm.recentFormByWindow[rosterWindow.value] != null

    fun fallbackPercentile(player: Player): Int =
        selectedCategory?.let { player.percentile(it) } ?: player.overallPercentile

    fun isQualified(player: Player): Boolean = when (qualifierLevel) {
        DashboardViewModel.QualifierLevel.ALL -> true
        DashboardViewModel.QualifierLevel.QUALIFIED -> DashboardViewModel.hasQualifyingMetric(player, selectedCategory)
    }

    val filteredPlayers: List<Player> = run {
        val bySearch = if (searchText.isEmpty()) players else players.filter {
            it.name.searchMatches(searchText) || it.displayPosition.searchMatches(searchText)
        }
        val bySide = bySearch.filter { it.positionGroup == rosterSide }
        val byCategory = bySide.filter { player -> selectedCategory == null || player.metrics.any { it.category == selectedCategory } }
        val byQualifier = byCategory.filter { isQualified(it) }
        when {
            isRosterRecent && sortMetric != null -> byQualifier.filter { recentValue(it) != null }.sortedWith { a, b ->
                val first = recentValue(a) ?: 0.0
                val second = recentValue(b) ?: 0.0
                if (sortDescending) second.compareTo(first) else first.compareTo(second)
            }
            sortMetric == null -> byQualifier.sortedWith { a, b ->
                if (sortDescending) fallbackPercentile(b).compareTo(fallbackPercentile(a)) else fallbackPercentile(a).compareTo(fallbackPercentile(b))
            }
            else -> byQualifier.sortedWith(DashboardViewModel.metricComparator(sortMetric.first, sortMetric.second, sortDescending))
        }
    }

    // Season changes through the nav-bar menu rotate the roster data beneath us,
    // and a playoff roster carries a different set of metrics than the regular
    // season's: re-default the sort direction so the chip never displays a
    // metric the new data doesn't have.
    val sortKey = sortMetric?.let { "${it.second.raw}|${it.first}" } ?: "-"
    LaunchedEffect(sortKey) {
        if (sortKey != lastDefaultedSortKey) {
            lastDefaultedSortKey = sortKey
            sortDescending = DashboardViewModel.defaultSortDescending(sortMetric?.first, sortMetric?.second)
        }
    }

    LaunchedEffect(rosterMode, rosterWindow, displaySeason, displayPhase, isPro, vm.freshnessRevision ?: "none") {
        if (isRosterRecent) vm.loadRecentFormIfNeeded(rosterWindow)
    }

    val fetchTeamGameLogs: TeamGameLogFetcher = { team, season, phase, since -> vm.fetchTeamGameLogs(team, season, phase, since) }
    val openTeamPitch = { actions.openTrialPitch(PaywallTrigger.TeamView) }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(
            onBack = { navigator.pop() },
            leading = { TeamSwitcher(abbr) },
            trailing = {
                SeasonPhasePicker(
                    // A single team page, so no All Time: a career row can't be attributed to one franchise.
                    seasons = vm.seasonsExcludingAllTime,
                    selectedSeason = vm.selectedSeason,
                    selectedPhase = vm.selectedPhase,
                    isSeasonLocked = vm::isSeasonLocked,
                    onSelectSeason = { season ->
                        if (vm.isSeasonLocked(season)) actions.openTrialPitch(PaywallTrigger.LockedSeason(season)) else vm.selectSeason(season)
                    },
                    onSelectPhase = { vm.selectedPhase = it },
                ) { open ->
                    // No glyph and the short year alone: the team name is long ("Jacksonville
                    // Jaguars"), and spelling the phase out as well would crowd the bar.
                    RinkNavPill(
                        title = SeasonLabel.display(vm.selectedSeason) + if (vm.selectedPhase == SeasonPhase.PLAYOFFS) " · Playoffs" else "",
                        onClick = open,
                        description = "Season and season type, ${SeasonLabel.display(vm.selectedSeason)}, ${vm.selectedPhase.label}",
                    )
                }
            },
        )
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 10.dp), season = displaySeason, phase = displayPhase)
                if (displaySeason == vm.freeSeason) {
                    Box(Modifier.padding(horizontal = 12.dp).padding(top = 10.dp)) { TeamGameCard(vm, abbr) }
                    if (displayPhase == SeasonPhase.REGULAR) {
                        Box(Modifier.padding(horizontal = 12.dp).padding(top = 10.dp)) { TeamSeasonGlance(vm, abbr) }
                    }
                }
                TabSelector(selectedTab, Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { selectedTab = it }

                when (selectedTab) {
                    TeamTab.ADVANCED -> Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        TeamRankingsCard(
                            team = abbr,
                            season = displaySeason,
                            players = players,
                            leaguePlayers = leaguePlayers,
                            fetchTeamGameLogs = fetchTeamGameLogs,
                            // Explicit tap, always answer it; the gate only caps automatic pop-ups.
                            onUpgradeTap = openTeamPitch,
                            seasonPhase = displayPhase,
                            freshnessRevision = vm.freshnessRevision,
                            freshnessStatus = vm.freshnessStatus,
                            supportsRecent = supportsRecent,
                        )
                    }
                    TeamTab.STANDARD -> Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) {
                        TeamStandardCard(
                            team = abbr,
                            season = displaySeason,
                            players = players,
                            leaguePlayers = leaguePlayers,
                            fetchTeamGameLogs = fetchTeamGameLogs,
                            onUpgradeTap = openTeamPitch,
                            seasonPhase = displayPhase,
                            supportsRecent = supportsRecent,
                        )
                    }
                    TeamTab.ROSTER -> Column {
                        GamesTeamsUi.PickerRow(
                            groups = listOfNotNull(
                                PlayerPositionGroup.entries.size to {
                                    RinkSegmented(
                                        PlayerPositionGroup.entries.map { Segment(it, it.pickerLabel) },
                                        rosterSide,
                                        { side ->
                                            rosterSide = side
                                            selectedCategory = side.categories[0]
                                            userSortLabel = null
                                        },
                                    )
                                },
                                if (supportsRecent) RosterMode.entries.size to {
                                    RinkSegmented(
                                        RosterMode.entries.map { Segment(it, it.raw, isLocked = !isPro && it == RosterMode.RECENT) },
                                        rosterMode,
                                        { rosterMode = it },
                                        onLockedTap = { actions.openTrialPitch(PaywallTrigger.RecentForm) },
                                    )
                                } else null,
                            ),
                            modifier = Modifier.padding(horizontal = 12.dp).padding(top = 12.dp),
                        )

                        if (isRosterRecent) {
                            RinkSegmented(
                                RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                                rosterWindow,
                                { rosterWindow = it },
                                Modifier.padding(horizontal = 12.dp).padding(top = 8.dp),
                            )
                        }

                        if (rosterSide.categories.size > 1) {
                            RinkTabs(
                                tabs = rosterSide.categories.map { it.raw },
                                selected = (selectedCategory ?: rosterSide.categories[0]).raw,
                                onSelect = { raw ->
                                    selectedCategory = MetricCategory.entries.firstOrNull { it.raw == raw }
                                    userSortLabel = null
                                },
                                modifier = Modifier.padding(horizontal = 12.dp).padding(top = 8.dp),
                            )
                        }

                        if (players.isNotEmpty()) {
                            SortControlsRow(
                                sortLabel = sortLabel,
                                sortDescending = sortDescending,
                                searchActive = isSearching || searchText.isNotEmpty(),
                                qualifierLevel = qualifierLevel,
                                sortLabels = availableSortLabels,
                                currentSortLabel = sortMetric?.first,
                                onFlip = {
                                    sortDescending = !sortDescending
                                    haptic()
                                },
                                onToggleSearch = {
                                    isSearching = !isSearching
                                    if (!isSearching) searchText = ""
                                    haptic()
                                },
                                onPickLabel = {
                                    userSortLabel = it
                                    haptic()
                                },
                                onPickQualifier = {
                                    qualifierLevel = it
                                    haptic()
                                },
                                onDirection = { sortDescending = it },
                            )
                            if (isSearching || searchText.isNotEmpty()) {
                                Row(
                                    Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 8.dp),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    SearchField(searchText, { searchText = it }, Modifier.weight(1f), focusOnAppear = true)
                                    TextAction("Cancel", RinkType.small, RinkPalette.turf, {
                                        isSearching = false
                                        searchText = ""
                                    })
                                }
                            }
                        }

                        RosterSection(
                            abbr = abbr,
                            season = displaySeason,
                            players = players,
                            isHistoryLoading = vm.isHistoricalLoading,
                            filteredPlayers = filteredPlayers,
                            noCategoryMatch = searchText.isEmpty() && selectedCategory != null,
                            isRosterRecent = isRosterRecent,
                            hasRecentData = hasRecentData,
                            rosterWindow = rosterWindow,
                            sortLabel = sortLabel,
                            sortDescending = sortDescending,
                            sortLabels = availableSortLabels,
                            rowLabel = rowLabel,
                            rowCategory = rowCategory,
                            onToggleDirection = {
                                sortDescending = !sortDescending
                                haptic()
                            },
                            onPickLabel = { userSortLabel = it },
                            recentDelta = ::recentDelta,
                            recentValueText = ::recentValueText,
                        )
                    }
                }

                Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { StatGlossaryLink() }
                // Lets content scroll under the floating tab bar.
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/**
 * The team name in the bar doubles as a switcher menu: tap to jump to any other
 * team without popping back to the Teams list.
 */
@Composable
private fun TeamSwitcher(team: String) {
    val navigator = LocalNavigator.current
    val teams = leagueTeamAbbreviations.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { teamFullName(it) })
    RinkMenu(
        sections = listOf(
            MenuSection(null, teams.map { abbr -> MenuItem(teamFullName(abbr), checked = abbr == team) { navigator.push(Route.Team(abbr)) } }),
        ),
    ) { open ->
        Row(
            Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(RinkGeo.radiusCard)).clickable(onClick = open)
                .semantics { contentDescription = "Team, ${teamFullName(team)}. Switch to another team" }
                .testTag("teamSwitcher"),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FitText(teamFullName(team), RinkType.bodyBold, Color.White, Modifier.widthIn(max = 170.dp), minScale = 0.8f)
            SfIcon("chevron.down", 14.dp, Color.White.copy(alpha = 0.85f))
        }
    }
}

/**
 * Mirrors the player profile's tab selector with equal-width turf controls that
 * swap the card content below: the team's percentile profile, its traditional
 * line, and its sortable roster.
 */
@Composable
private fun TabSelector(selected: TeamTab, modifier: Modifier = Modifier, onSelect: (TeamTab) -> Unit) {
    val haptic = rememberHaptic()
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TeamTab.entries.forEach { tab ->
            val isSelected = tab == selected
            Box(
                Modifier.weight(1f).height(44.dp)
                    .clip(RoundedCornerShape(RinkGeo.radiusCard))
                    .background(if (isSelected) RinkPalette.turf else RinkPalette.surface)
                    .clickable {
                        onSelect(tab)
                        haptic()
                    }
                    .semantics {
                        this.selected = isSelected
                        role = Role.Tab
                    }
                    .testTag("teamTab_${tab.raw}"),
                contentAlignment = Alignment.Center,
            ) {
                FitText(
                    tab.raw, RinkType.smallBold, if (isSelected) Color.White else RinkPalette.ink,
                    Modifier.padding(horizontal = 4.dp), minScale = 0.85f, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
        }
    }
}

/**
 * Mirrors the Stats tab's sort UI: a chip showing the active metric (tap flips
 * direction), and a magnifying-glass toggle that expands an inline search row.
 */
@Composable
private fun SortControlsRow(
    sortLabel: String,
    sortDescending: Boolean,
    searchActive: Boolean,
    qualifierLevel: DashboardViewModel.QualifierLevel,
    sortLabels: List<String>,
    currentSortLabel: String?,
    onFlip: () -> Unit,
    onToggleSearch: () -> Unit,
    onPickLabel: (String) -> Unit,
    onPickQualifier: (DashboardViewModel.QualifierLevel) -> Unit,
    onDirection: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.heightIn(min = 44.dp).clip(CircleShape).clickable(onClick = onFlip)
                .semantics { contentDescription = "Sorted by $sortLabel, ${if (sortDescending) "highest first" else "lowest first"}. Tap to flip sort direction" }
                .testTag("sortChip"),
            contentAlignment = Alignment.Center,
        ) {
            Row(
                Modifier.height(30.dp).clip(CircleShape).background(RinkPalette.surface)
                    .border(0.5.dp, RinkPalette.hairline, CircleShape).padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(sortLabel, style = RinkType.smallBold, color = RinkPalette.ink, maxLines = 1)
                SfIcon(if (sortDescending) "arrow.down" else "arrow.up", 12.dp, RinkPalette.turf)
            }
        }
        Spacer(Modifier.weight(1f))
        Box(
            Modifier.size(44.dp).clip(CircleShape).clickable(onClick = onToggleSearch)
                .semantics { contentDescription = "Search" }.testTag("rosterSearch"),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(30.dp).clip(CircleShape)
                    .background(if (searchActive) RinkPalette.turf else RinkPalette.surface)
                    .border(0.5.dp, if (searchActive) Color.Transparent else RinkPalette.hairline, CircleShape),
                contentAlignment = Alignment.Center,
            ) { SfIcon("magnifyingglass", 16.dp, if (searchActive) Color.White else RinkPalette.inkSecondary) }
        }
        RinkMenu(
            sections = buildList {
                if (sortLabels.isNotEmpty()) {
                    add(MenuSection("Sort by", sortLabels.map { label -> MenuItem(label, checked = label == currentSortLabel) { onPickLabel(label) } }))
                }
                add(
                    MenuSection(
                        "Minimum playing time",
                        DashboardViewModel.QualifierLevel.entries.map { level ->
                            MenuItem("${level.label} · ${level.description}", checked = level == qualifierLevel) { onPickQualifier(level) }
                        },
                    ),
                )
                add(
                    MenuSection(
                        "Direction",
                        listOf(
                            MenuItem("Highest first", checked = sortDescending, icon = "arrow.down") { onDirection(true) },
                            MenuItem("Lowest first", checked = !sortDescending, icon = "arrow.up") { onDirection(false) },
                        ),
                    ),
                )
            },
        ) { open ->
            ChipButton(open, description = "Filters", modifier = Modifier.testTag("rosterFilters")) {
                RinkChip(
                    title = "Filters",
                    icon = "line.3.horizontal.decrease.circle",
                    trailing = ChipTrailing.Chevron,
                    isActive = qualifierLevel != DashboardViewModel.QualifierLevel.ALL,
                )
            }
        }
    }
}

@Composable
private fun RosterSection(
    abbr: String,
    season: Int,
    players: List<Player>,
    isHistoryLoading: Boolean,
    filteredPlayers: List<Player>,
    noCategoryMatch: Boolean,
    isRosterRecent: Boolean,
    hasRecentData: Boolean,
    rosterWindow: RecentWindow,
    sortLabel: String,
    sortDescending: Boolean,
    sortLabels: List<String>,
    rowLabel: String?,
    rowCategory: MetricCategory?,
    onToggleDirection: () -> Unit,
    onPickLabel: (String) -> Unit,
    recentDelta: (Player) -> Double?,
    recentValueText: (Player) -> String,
) {
    val navigator = LocalNavigator.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard()) {
        when {
            players.isEmpty() && isHistoryLoading -> GamesTeamsUi.Spinner("Loading ${SeasonLabel.display(season)}", Modifier.padding(vertical = 40.dp))
            players.isEmpty() -> GamesTeamsUi.Unavailable(
                "person.2.slash", "No players tracked",
                "No players are tracked for ${teamFullName(abbr)} in ${SeasonLabel.display(season)}.",
                Modifier.padding(vertical = 48.dp),
            )
            filteredPlayers.isEmpty() -> GamesTeamsUi.Unavailable(
                "magnifyingglass", "No players found",
                if (noCategoryMatch) "No players match the selected category for this team." else "Try a different search term.",
                Modifier.padding(vertical = 48.dp),
            )
            isRosterRecent && !hasRecentData -> GamesTeamsUi.InlineSpinner("Loading the last ${rosterWindow.value} weeks…", Modifier.padding(vertical = 8.dp))
            else -> {
                LeaderboardTableHeader(
                    sortDescending = sortDescending,
                    sortLabel = if (isRosterRecent) "$sortLabel · ${rosterWindow.shortLabel}" else sortLabel,
                    metrics = sortLabels,
                    onSelectMetric = onPickLabel,
                    onToggleDirection = onToggleDirection,
                )
                filteredPlayers.forEachIndexed { index, player ->
                    LeaderboardTableRow(
                        rank = index + 1,
                        player = player,
                        metricLabel = rowLabel,
                        metricCategory = rowCategory,
                        trendDelta = if (isRosterRecent) recentDelta(player) else null,
                        trendDecimals = rowLabel?.let { RecentMetricKey.decimals(it) } ?: 3,
                        valueOverride = if (isRosterRecent) recentValueText(player) else null,
                        onClick = { navigator.push(Route.PlayerProfile(player)) },
                    )
                }
            }
        }
    }
}
