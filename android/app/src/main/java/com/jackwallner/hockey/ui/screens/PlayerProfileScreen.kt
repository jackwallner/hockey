package com.jackwallner.hockey.ui.screens

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricCoverage
import com.jackwallner.hockey.model.MetricFamily
import com.jackwallner.hockey.model.MetricKind
import com.jackwallner.hockey.model.MetricWeight
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandardStatSemantics
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.metricNumericValue
import com.jackwallner.hockey.model.swiftRoundDouble
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.DataFreshnessView
import com.jackwallner.hockey.ui.components.DualMetricBar
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.RinkMenu
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.RinkSubSectionBar
import com.jackwallner.hockey.ui.components.RinkTopBar
import com.jackwallner.hockey.ui.components.InfoNote
import com.jackwallner.hockey.ui.components.MenuItem
import com.jackwallner.hockey.ui.components.MenuSection
import com.jackwallner.hockey.ui.components.MetricBar
import com.jackwallner.hockey.ui.components.PlayerIdentityStrip
import com.jackwallner.hockey.ui.components.RefreshableBox
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatGlossaryLink
import com.jackwallner.hockey.ui.components.StatScoutSheet
import com.jackwallner.hockey.ui.components.TextAction
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.nav.rememberRetained
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlinx.coroutines.launch

enum class FormDisplayMode(val label: String) { SEASON("Season"), RECENT("Recent"), BOTH("Both") }

enum class PlayerStatTab(val label: String) { ADVANCED("Advanced"), STANDARD("Standard"), YEAR_COMPARE("Year Compare") }

/** Resolves the row for the season and phase the route carries, as iOS `PlayerProfileDestination` does. */
@Composable
fun PlayerProfileRoute(player: Player) {
    val vm = LocalGraph.current.dashboard
    val history = vm.playerHistories[player.playerId].orEmpty()
    val seasonPlayer = history.firstOrNull { it.season == player.season && it.seasonPhase == player.seasonPhase } ?: player
    PlayerProfileScreen(seasonPlayer, history, vm)
}

/** Profile state that must survive pushing a drill-down on top of the page. */
@Stable
private class ProfileState {
    var selectedTab by mutableStateOf(PlayerStatTab.ADVANCED)
    var selectedSeason by mutableStateOf<Int?>(null)
    var formMode by mutableStateOf(FormDisplayMode.SEASON)
    var recentWindowWeeks by mutableStateOf(4)
    var standardMode by mutableStateOf(FormDisplayMode.SEASON)
    var standardWindow by mutableStateOf(RecentWindow.FOUR)
    var recentLogs by mutableStateOf<List<PlayerGameLog>>(emptyList())
    var recentLogsKey by mutableStateOf<String?>(null)
    var recentLoading by mutableStateOf(false)
    var recentLoadingKey: String? = null
    var recentLoadError by mutableStateOf<String?>(null)
    var countedOpen = false
}

@Composable
fun PlayerProfileScreen(player: Player, history: List<Player>, vm: DashboardViewModel) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val favorites = graph.favorites
    val actions = LocalAppActions.current
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val scope = rememberCoroutineScope()
    val state = rememberRetained("profile-${player.id}") { ProfileState() }
    var showPercentileInfo by remember { mutableStateOf(false) }
    var showingPlayerPicker by remember { mutableStateOf(false) }
    val isPro = store.isPro

    val phaseHistory = history.filter { it.seasonPhase == player.seasonPhase }
    val activeSeason = state.selectedSeason ?: player.season
    val displayed = activeSeason?.let { s -> phaseHistory.firstOrNull { it.season == s } } ?: player
    val activePhase = player.seasonPhase
    val seasonLabel = activeSeason?.let { SeasonLabel.display(it, player.seasonPhase) } ?: "-"
    val recentFormSeasons = vm.recentFormSeasons
    val supportsRecentForm = (activeSeason ?: vm.freeSeason) in recentFormSeasons
    val allPlayers = remember(player.season, activePhase, vm.playerHistories) { vm.players(player.season ?: vm.selectedSeason, activePhase) }
    // Every percentile and comparison is measured against the season on screen, not the one the page opened in.
    val cohort = remember(activeSeason, allPlayers, vm.playerHistories) {
        if (activeSeason == null || activeSeason == player.season) allPlayers
        else vm.players(activeSeason, activePhase).ifEmpty { allPlayers }
    }
    // Window curves from the player's own cohort: forwards, defensemen or goalies.
    val curves = remember(cohort, displayed.positionGroup) {
        val goalie = displayed.isGoalie
        LeaguePercentileCurves(
            cohort.filter { it.positionGroup == displayed.positionGroup },
            if (goalie) listOf(MetricCategory.GOALTENDING) else listOf(MetricCategory.SCORING, MetricCategory.SHOT_QUALITY),
            RecentFormWindow.recentLabels(goalie),
        )
    }
    val liveProfile = vm.profile(displayed)
    val effectiveForm = if (supportsRecentForm) state.formMode else FormDisplayMode.SEASON
    val effectiveStandard = if (isPro && supportsRecentForm) state.standardMode else FormDisplayMode.SEASON

    // First-impression pitch from the second profile open; a positive moment from the third.
    LaunchedEffect(Unit) {
        if (state.countedOpen) return@LaunchedEffect
        state.countedOpen = true
        val opens = graph.defaults.getInt(PROFILE_OPEN_COUNT) + 1
        graph.defaults.putInt(PROFILE_OPEN_COUNT, opens)
        if (!store.isPro && opens >= 2 && graph.paywallGate.shouldPresent(PaywallTrigger.PlayerScouting)) {
            actions.openTrialPitch(PaywallTrigger.PlayerScouting)
        } else if (opens >= 3) {
            actions.positiveMoment()
        }
    }

    suspend fun loadRecentLogs() {
        val season = activeSeason ?: return
        if (!store.isPro) return
        // The phase belongs in the key: a regular season and its playoffs are two sets of games.
        val key = "${player.playerId}-$season-${activePhase.raw}-${vm.freshnessRevision ?: "none"}"
        if (state.recentLogsKey == key && state.recentLogs.isNotEmpty()) return
        if (state.recentLoadingKey == key) return
        state.recentLoadingKey = key
        state.recentLoading = true
        state.recentLoadError = null
        try {
            val logs = vm.fetchGameLogs(player.playerId, season, activePhase)
            if (state.recentLoadingKey != key) return
            state.recentLogs = logs
            state.recentLogsKey = key
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            if (state.recentLoadingKey != key) return
            if (state.recentLogs.isEmpty() || state.recentLogsKey != key) {
                state.recentLogs = emptyList()
                state.recentLogsKey = null
                state.recentLoadError = "Couldn't load recent games. Check your connection and try again."
            }
        }
        state.recentLoadingKey = null
        state.recentLoading = false
    }

    LaunchedEffect(effectiveForm, state.recentWindowWeeks, activeSeason, isPro, vm.freshnessRevision) {
        if (isPro && effectiveForm != FormDisplayMode.SEASON) loadRecentLogs()
    }
    LaunchedEffect(effectiveStandard, state.standardWindow, activeSeason, isPro, vm.freshnessRevision) {
        if (isPro && effectiveStandard != FormDisplayMode.SEASON) loadRecentLogs()
    }

    val comparable = remember(cohort, displayed) {
        val myType = displayed.playerType?.lowercase()
        val mine = displayed.overallPercentile
        cohort.filter { it.playerId != player.playerId && (myType == null || it.playerType?.lowercase() == myType) }
            .sortedBy { abs(it.overallPercentile - mine) }
    }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(
            title = player.name,
            onBack = { navigator.pop() },
            trailing = {
                val isFavorite = favorites.isFavorite(player.playerId)
                Box(
                    Modifier.size(44.dp).clip(CircleShape).clickable {
                        favorites.toggleFavorite(player.playerId)
                        haptic()
                    }.semantics { contentDescription = if (isFavorite) "Unfollow ${player.name}" else "Follow ${player.name}" }.testTag("favoriteButton"),
                    contentAlignment = Alignment.Center,
                ) { SfIcon(if (isFavorite) "star.fill" else "star", 22.dp, if (isFavorite) CrownYellow else Color.White) }
                Box(
                    Modifier.size(44.dp).clip(CircleShape).clickable {
                        if (store.isPro) showingPlayerPicker = true else actions.openTrialPitch(PaywallTrigger.PlayerComparison)
                    }.semantics { contentDescription = "Compare with another player" }.testTag("compareButton"),
                    contentAlignment = Alignment.Center,
                ) { SfIcon("person.2.fill", 22.dp, Color.White) }
            },
        )
        RefreshableBox({
            vm.load()
            state.recentLogsKey = null
            if (store.isPro && (effectiveForm != FormDisplayMode.SEASON || effectiveStandard != FormDisplayMode.SEASON)) loadRecentLogs()
        }, Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottomBarPadding())) {
                PlayerIdentityStrip(displayed, profile = liveProfile)
                DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 6.dp), season = activeSeason ?: player.season, phase = activePhase)
                val season = activeSeason ?: player.season
                if (season != null && season in recentFormSeasons) {
                    Box(Modifier.padding(horizontal = 12.dp)) { PlayerLastGameCard(viewModel = vm, player = displayed, season = season, phase = activePhase) }
                }
                Row(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PlayerStatTab.entries.forEach { tab ->
                        val selected = state.selectedTab == tab
                        Box(
                            Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(RinkGeo.radiusCard))
                                .background(if (selected) RinkPalette.turf else RinkPalette.surface)
                                .clickable {
                                    state.selectedTab = tab
                                    if (tab == PlayerStatTab.YEAR_COMPARE && store.isPro && !vm.hasLoadedHistorical && !vm.isHistoricalLoading) {
                                        scope.launch { vm.loadHistoricalIfNeeded() }
                                    }
                                    haptic()
                                }
                                .testTag("profileTab_${tab.label}"),
                            contentAlignment = Alignment.Center,
                        ) { Text(tab.label, style = RinkType.bodyBold, color = if (selected) Color.White else RinkPalette.ink) }
                    }
                }

                val seasonMenu = @Composable {
                    val seasons = (phaseHistory.mapNotNull { it.season } + listOfNotNull(player.season)).distinct().sortedDescending()
                    if (seasons.size > 1) {
                        RinkMenu(listOf(MenuSection(null, seasons.map { s ->
                            val locked = s != vm.freeSeason && !store.isPro
                            MenuItem(SeasonLabel.display(s), checked = !locked && s == activeSeason, locked = locked) {
                                if (locked) actions.openTrialPitch(PaywallTrigger.PastSeason) else state.selectedSeason = s
                            }
                        }))) { open ->
                            Row(
                                Modifier.heightIn(min = 28.dp).clickable(onClick = open).semantics { contentDescription = "Season, $seasonLabel" },
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(seasonLabel, style = RinkType.micro, color = RinkPalette.inkSecondary, maxLines = 1)
                                SfIcon("chevron.down", 11.dp, RinkPalette.inkSecondary)
                            }
                        }
                    } else Text(seasonLabel, style = RinkType.micro, color = RinkPalette.inkSecondary, maxLines = 1)
                }

                when (state.selectedTab) {
                    PlayerStatTab.ADVANCED -> Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        PercentileCard(
                            displayed = displayed,
                            seasonLabel = seasonLabel,
                            seasonMenu = seasonMenu,
                            onInfo = { showPercentileInfo = true },
                            isPro = isPro,
                            supportsRecent = supportsRecentForm,
                            state = state,
                            effectiveForm = effectiveForm,
                            curves = curves,
                            cohort = cohort,
                            freshnessStatus = vm.freshnessStatus,
                            onMetric = { m -> navigator.push(Route.Metric(m.label, m.category, activeSeason, activePhase, player.positionGroup)) },
                        )
                        pendingNote(displayed, vm)?.let { InfoNote(it, Modifier.padding(horizontal = 0.dp)) }
                        if (!isPro) {
                            RecentFormCard(
                                player = player,
                                season = activeSeason ?: player.season ?: java.time.LocalDate.now().year,
                                leaguePlayers = cohort,
                                fetchGameLogs = { id, s, ph -> vm.fetchGameLogs(id, s, ph) },
                                freshnessRevision = vm.freshnessRevision,
                                freshnessStatus = vm.freshnessStatus,
                            )
                            ProUpsellCard(player.name) { actions.openTrialPitch(store.defaultUpgradeTrigger) }
                        }
                    }
                    PlayerStatTab.STANDARD -> Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        StandardStatsCard(
                            displayed = displayed,
                            cohort = cohort,
                            seasonMenu = seasonMenu,
                            supportsRecent = supportsRecentForm,
                            isPro = isPro,
                            state = state,
                            effectiveMode = effectiveStandard,
                            onLockedTap = { actions.openTrialPitch(PaywallTrigger.RecentForm) },
                            onStat = { label -> navigator.push(Route.StandardStat(label, displayed.positionGroup, activeSeason, activePhase)) },
                        )
                        if (season != null && season in recentFormSeasons) {
                            PlayerGameLogCard(viewModel = vm, player = displayed, season = season, phase = activePhase)
                        }
                    }
                    PlayerStatTab.YEAR_COMPARE -> when {
                        !isPro -> YearComparePreview(player.name)
                        vm.isHistoricalLoading -> HistoricalLoadingCard(vm.loadingMessage, vm.loadingProgress)
                        !vm.hasLoadedHistorical -> LoadHistoryCard { scope.launch { vm.loadHistoricalIfNeeded() } }
                        phaseHistory.size < 2 -> Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().rinkCard().padding(vertical = 24.dp)) {
                            EmptyState("Not enough history", "calendar.badge.clock", "${player.name} doesn't have multiple seasons of data to compare.")
                        }
                        else -> YearComparisonView(phaseHistory)
                    }
                }
                Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { StatGlossaryLink() }
            }
        }
    }

    StatScoutSheet(showPercentileInfo, { showPercentileInfo = false }) { PercentileInfoSheet { showPercentileInfo = false } }
    StatScoutSheet(showingPlayerPicker, { showingPlayerPicker = false }) {
        PlayerPickerSheet(comparable, "Compare With", onCancel = { showingPlayerPicker = false }) { selected ->
            showingPlayerPicker = false
            navigator.push(Route.Comparison(displayed, selected))
        }
    }
}

private const val PROFILE_OPEN_COUNT = "profileOpenCount"

/** The live season while MoneyPuck's files or the NHL summary are behind. */
private fun pendingNote(displayed: Player, vm: DashboardViewModel): String? {
    if (displayed.season != vm.freeSeason || displayed.seasonPhase != SeasonPhase.REGULAR) return null
    return MetricCoverage.pendingNote(vm.dataFreshness?.shotsStatus, vm.dataFreshness?.summaryStatus)
}

@Composable
private fun PercentileCard(
    displayed: Player,
    seasonLabel: String,
    seasonMenu: @Composable () -> Unit,
    onInfo: () -> Unit,
    isPro: Boolean,
    supportsRecent: Boolean,
    state: ProfileState,
    effectiveForm: FormDisplayMode,
    curves: LeaguePercentileCurves,
    cohort: List<Player>,
    freshnessStatus: com.jackwallner.hockey.model.DataFreshnessStatus,
    onMetric: (Metric) -> Unit,
) {
    val profileMetrics = displayed.metrics(MetricKind.ADVANCED)
    val grouped = profileMetrics.groupBy { HockeyMetricRegistry.definition(it.label, it.category)?.family ?: MetricFamily.PRODUCTION }
    val groups = MetricFamily.entries.mapNotNull { f -> grouped[f]?.takeIf { it.isNotEmpty() }?.let { f to HockeyMetricRegistry.sorted(it) } }
    val weeks = state.recentWindowWeeks
    val window = RecentFormWindow.logs(state.recentLogs, weeks).takeIf { it.isNotEmpty() }
        ?.let { RecentFormWindow.build("Last $weeks weeks", weeks, it) }

    // The window's rate for a season metric, rebuilt from his own game logs. Only
    // the rates in RecentFormWindow.recentLabels have one: a few weeks of a count
    // would be read against a full-season ruler, and on-ice shares have no per-game feed.
    fun recentMetric(season: Metric): Metric? {
        val w = window ?: return null
        val v = w.value(season.label) ?: return null
        val pct = curves.curve(season.label)?.percentile(v) ?: return null
        return Metric(season.label, RecentMetricKey.format(v, season.label), pct, season.category, id = "recent-${season.label}")
    }

    Column(Modifier.fillMaxWidth().rinkCard()) {
        RinkSectionBar(
            "ADVANCED PERCENTILES",
            trailing = {
                seasonMenu()
                Text(
                    "ⓘ",
                    style = RinkType.micro,
                    color = RinkPalette.linkBlue,
                    modifier = Modifier.padding(start = 4.dp).clip(CircleShape).clickable(onClick = onInfo).padding(6.dp)
                        .semantics { contentDescription = "About percentiles" },
                )
            },
        )
        if (isPro && supportsRecent) {
            Box(Modifier.fillMaxWidth().background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline, vertical = 6.dp)) {
                RinkSegmented(FormDisplayMode.entries.map { Segment(it, it.label) }, state.formMode, { state.formMode = it })
            }
        }
        if (effectiveForm != FormDisplayMode.SEASON && isPro && supportsRecent) {
            // Same inset and shade as the Season / Recent / Both row above it, so the
            // two controls read as one block.
            Box(Modifier.fillMaxWidth().background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline).padding(bottom = 10.dp)) {
                RinkSegmented(
                    RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                    RecentWindow.of(state.recentWindowWeeks) ?: RecentWindow.FOUR,
                    { state.recentWindowWeeks = it.value },
                )
            }
            when {
                state.recentLoading -> Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = RinkPalette.inkTertiary, strokeWidth = 2.dp)
                    Text("Loading recent games…", style = RinkType.small, color = RinkPalette.inkSecondary)
                }
                state.recentLoadError != null -> Text(state.recentLoadError!!, style = RinkType.small, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(16.dp))
                window == null -> Text(recentEmptyText(freshnessStatus, state.recentWindowWeeks), style = RinkType.small, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(16.dp))
            }
        }
        if (groups.isEmpty()) {
            Box(Modifier.padding(vertical = 24.dp)) {
                EmptyState("No metrics available", "chart.bar", "Percentile rankings are not available for this player in the $seasonLabel season.")
            }
        } else groups.forEach { (family, rows) ->
            if (rows.isEmpty()) return@forEach
            RinkSubSectionBar(family.label.uppercase())
            rows.forEachIndexed { index, metric ->
                val recent = recentMetric(metric)
                val bg = if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt
                val rowModifier = Modifier.fillMaxWidth().background(bg).bottomHairline()
                when (effectiveForm) {
                    FormDisplayMode.SEASON -> Box(rowModifier.clickable { onMetric(metric) }.padding(horizontal = RinkGeo.padCard, vertical = 12.dp)) { MetricBar(metric) }
                    // No window figure for this metric: fall back to the season bar so every bar still shows.
                    FormDisplayMode.RECENT -> if (recent != null) Box(rowModifier.padding(horizontal = RinkGeo.padCard, vertical = 12.dp)) { MetricBar(recent) }
                    else Box(rowModifier.clickable { onMetric(metric) }.padding(horizontal = RinkGeo.padCard, vertical = 12.dp)) { MetricBar(metric) }
                    FormDisplayMode.BOTH -> Box(rowModifier.clickable { onMetric(metric) }.padding(horizontal = RinkGeo.padCard, vertical = 12.dp)) {
                        DualMetricBar(metric, recent, "Last ${state.recentWindowWeeks}W")
                    }
                }
            }
        }
    }
}

/**
 * Counting stats. Ranking these is honest but playing-time driven, a fourth
 * liner's 2 goals isn't a talent signal, so they're grouped apart from the rates.
 */
private val COUNTING_STATS = setOf("GP", "G", "A", "P", "+/-", "PIM", "PPG", "PPP", "SHG", "GWG", "SOG", "HITS", "BLK", "GS", "W", "L", "OT", "SO", "SA", "SV")

/**
 * Traditional stat label to its per-game log key. Rates and games played have no
 * single summed counterpart (GP is the window's own game count, read where used).
 */
private val STANDARD_RECENT_KEYS = mapOf(
    "G" to "goals", "A" to "assists", "P" to "points", "+/-" to "plus_minus",
    "PIM" to "pim", "PPG" to "pp_goals", "SOG" to "shots_on_goal",
    "HITS" to "hits", "BLK" to "blocks",
    "SA" to "shots_against", "SV" to "saves", "W" to "decision_win",
    "SO" to "shutout", "GS" to "started",
)

@Composable
private fun StandardStatsCard(
    displayed: Player,
    cohort: List<Player>,
    seasonMenu: @Composable () -> Unit,
    supportsRecent: Boolean,
    isPro: Boolean,
    state: ProfileState,
    effectiveMode: FormDisplayMode,
    onLockedTap: () -> Unit,
    onStat: (String) -> Unit,
) {
    val group = displayed.positionGroup
    fun peerValues(label: String): List<String> {
        val key = label.uppercase()
        return cohort.mapNotNull { other ->
            if (other.positionGroup != group) null else other.standardStats?.firstOrNull { it.label.uppercase() == key }?.value
        }
    }
    fun percentile(label: String, value: String) = StandardStatSemantics.percentile(label, value, peerValues(label))
    fun metrics(counting: Boolean): List<Metric> = displayed.standardStats.orEmpty()
        .filter { (it.label.uppercase() in COUNTING_STATS) == counting }
        .map { stat ->
            Metric(
                label = stat.label.uppercase(),
                value = stat.value,
                percentile = percentile(stat.label, stat.value),
                category = displayed.primaryCategory,
                // A zero count has no honest rank, except where fewer is better: a skater's 0 PIM ranks at the top.
                rankable = if (counting && StandardStatSemantics.higherIsBetter(stat.label) && metricNumericValue(stat.value) == 0.0) false else null,
                id = "std-${stat.label}",
            )
        }
    val span = state.standardWindow.value
    // This player's own games in the trailing weeks, summed: the same logs the percentile card reads.
    val window = RecentFormWindow.logs(state.recentLogs, span).takeIf { it.isNotEmpty() }?.let { RecentFormWindow.build("Last $span weeks", span, it) }
    val caption = window?.games?.let { RecentFormWindow.caption(it, span) } ?: state.standardWindow.segmentLabel
    // Peers' season values for a stat, scaled to [games] games each.
    fun pacedPeerValues(label: String, games: Int): List<String> {
        val key = label.uppercase()
        return cohort.mapNotNull { other ->
            if (other.positionGroup != group) return@mapNotNull null
            val stat = other.standardStats?.firstOrNull { it.label.uppercase() == key } ?: return@mapNotNull null
            val total = metricNumericValue(stat.value) ?: return@mapNotNull null
            val played = other.standardStats?.firstOrNull { it.label == "GP" }?.let { metricNumericValue(it.value) }?.takeIf { it > 0 } ?: return@mapNotNull null
            swiftRoundDouble(total / played * games).toInt().toString()
        }
    }
    // A few weeks of a count would sit at the bottom of a full-season ruler, so the
    // percentile compares pace: his window total against each peer's season scaled to the same games.
    fun recent(season: Metric): Metric? {
        val w = window ?: return null
        val value = if (season.label == "GP") w.games.toDouble() else {
            val key = STANDARD_RECENT_KEYS[season.label] ?: return null
            w.metrics[key] ?: return null
        }
        val text = java.text.NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong())
        val pct = StandardStatSemantics.percentile(season.label, text, pacedPeerValues(season.label, w.games))
        return Metric(season.label, text, pct, season.category, id = "std-recent-${season.label}")
    }
    fun statKey(display: String) = displayed.standardStats.orEmpty().firstOrNull { it.label.uppercase() == display }?.label ?: display

    Column(Modifier.fillMaxWidth().rinkCard()) {
        RinkSectionBar("STANDARD STATS", trailing = { seasonMenu() })
        if (supportsRecent) {
            Box(Modifier.fillMaxWidth().background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline, vertical = 6.dp)) {
                RinkSegmented(
                    FormDisplayMode.entries.map { Segment(it, it.label, isLocked = !isPro && it != FormDisplayMode.SEASON) },
                    state.standardMode,
                    { state.standardMode = it },
                    onLockedTap = { onLockedTap() },
                )
            }
            if (effectiveMode != FormDisplayMode.SEASON) {
                Box(Modifier.fillMaxWidth().background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline).padding(bottom = 4.dp)) {
                    RinkSegmented(RecentWindow.entries.map { Segment(it, it.segmentLabel) }, state.standardWindow, { state.standardWindow = it })
                }
            }
        }
        if (displayed.standardStats.isNullOrEmpty()) {
            Box(Modifier.padding(vertical = 24.dp)) { EmptyState("Standard stats unavailable", "chart.bar", "Traditional stats are not available for this player.") }
        } else {
            val rates = metrics(false)
            val counts = metrics(true)
            // Only label the two groups when there are two of them.
            val labelled = rates.isNotEmpty() && counts.isNotEmpty()
            @Composable
            fun Rows(list: List<Metric>, start: Int) {
                list.forEachIndexed { offset, metric ->
                    val r = recent(metric)
                    Box(
                        Modifier.fillMaxWidth().background(if ((start + offset) % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                            .bottomHairline().clickable { onStat(statKey(metric.label)) }
                            .padding(horizontal = RinkGeo.padCard, vertical = 12.dp),
                    ) {
                        when (effectiveMode) {
                            FormDisplayMode.SEASON -> MetricBar(metric)
                            FormDisplayMode.RECENT -> MetricBar(r ?: metric)
                            FormDisplayMode.BOTH -> DualMetricBar(metric, r, caption)
                        }
                    }
                }
            }
            if (rates.isNotEmpty()) {
                if (labelled) RinkSubSectionBar("RATE")
                Rows(rates, 0)
            }
            if (counts.isNotEmpty()) {
                if (labelled) RinkSubSectionBar("VOLUME")
                Rows(counts, rates.size)
            }
        }
    }
}

@Composable
private fun ProUpsellCard(name: String, onTap: () -> Unit) {
    val store = LocalGraph.current.subscriptions
    Column(Modifier.fillMaxWidth().rinkCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfIcon("crown.fill", 16.dp, CrownYellow)
            Text("StatScout+", style = RinkType.smallBold, color = RinkPalette.ink)
        }
        Text("Get the full scouting picture on $name.", style = RinkType.body, color = RinkPalette.ink)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(
                "chart.line.uptrend.xyaxis" to "Year-over-year trends across every metric",
                "person.2.fill" to "Head-to-head comparisons vs any player",
                "calendar.badge.clock" to "Every past season, not just this one",
                "chart.bar.fill" to "Last 2 / 4 / 8 week form on every player",
            ).forEach { (icon, text) ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { SfIcon(icon, 14.dp, RinkPalette.turf) }
                    Text(text, style = RinkType.small, color = RinkPalette.inkSecondary)
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(12.dp)).background(RinkPalette.turf).clickable(onClick = onTap),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(store.paywallBlurCTA, style = RinkType.bodyBold, color = Color.White)
            SfIcon("arrow.right", 14.dp, Color.White)
        }
        store.paywallBlurSubtext?.let { Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
    }
}

@Composable
private fun HistoricalLoadingCard(message: String, progress: Double) {
    Column(
        Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().rinkCard().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        val value = progress.coerceIn(0.0, 1.0).toFloat()
        LinearProgressIndicator(progress = { value }, color = RinkPalette.turf, trackColor = RinkPalette.surfaceSunk, modifier = Modifier.fillMaxWidth())
        Text(message, style = RinkType.bodyBold, color = RinkPalette.ink)
        Text("${(value * 100).toInt()}%", style = RinkType.micro, color = RinkPalette.inkTertiary)
    }
}

@Composable
private fun LoadHistoryCard(onLoad: () -> Unit) {
    Column(
        Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().rinkCard().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SfIcon("clock.arrow.circlepath", 36.dp, RinkPalette.turf)
        Text("Load past seasons", style = RinkType.bodyBold, color = RinkPalette.ink)
        Text("Year Compare loads historical data only when you need it.", style = RinkType.body, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center)
        Box(
            Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(RinkPalette.turf).clickable(onClick = onLoad).padding(horizontal = 18.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Load History", style = RinkType.bodyBold, color = Color.White) }
    }
}

@Composable
fun PercentileInfoSheet(onDone: () -> Unit) {
    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(title = "About Percentiles", trailing = { TextAction("Done", RinkType.smallBold, Color.White, onDone) })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Percentile Rankings", style = RinkType.playerName, color = RinkPalette.ink)
            Text(
                "Percentile rankings compare a player to others at the same position. A 90th percentile means the player ranks in the top 10% of the league for that metric.",
                style = RinkType.body,
                color = RinkPalette.inkSecondary,
            )
            Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    Triple("flame.fill", "Elite (75-100): Red bars", RinkPalette.performanceHigh),
                    Triple("minus", "Average (25-75): Charcoal bars", RinkPalette.inkSecondary),
                    Triple("snowflake", "Below Average (0-25): Blue bars", RinkPalette.performanceLow),
                ).forEach { (icon, text, color) ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfIcon(icon, 16.dp, color)
                        Text(text, style = RinkType.bodyBold, color = color)
                    }
                }
            }
            Text(
                "Stats update after new source data is validated. Advanced metrics may arrive later than game totals. Not every metric is tracked for every player.",
                style = RinkType.small,
                color = RinkPalette.inkTertiary,
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}
