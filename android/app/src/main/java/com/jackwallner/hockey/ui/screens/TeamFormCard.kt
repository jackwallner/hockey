package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.DataFreshnessStatus
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.MetricKind
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.BlurGateUnlock
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.DualMetricBar
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.RinkSubSectionBar
import com.jackwallner.hockey.ui.components.InlineLoadError
import com.jackwallner.hockey.ui.components.MetricBar
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.nav.rememberRetained
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Fetches a club's game logs: (team, season, phase, since). */
typealias TeamGameLogFetcher = suspend (String, Int, SeasonPhase, Instant) -> List<PlayerGameLog>

private enum class FormMode(val raw: String) {
    SEASON("Season"), RECENT("Recent"), BOTH("Both");

    val usesRecent: Boolean get() = this != SEASON
}

/**
 * Team "percentile rankings" card, the team-level analogue of the player
 * profile's percentile card. Aggregates the roster into one synthetic
 * "team-as-a-player" and renders its profile as percentile bars on the league
 * ruler, with a Season / Recent toggle that mirrors the player page.
 *
 * Season is the mean of every roster metric for the active cohort (forwards,
 * defensemen or goalies), placed on the league curve; tapping a bar opens that
 * metric's leaderboard. Recent is the rate metrics rebuilt over the last
 * 2 / 4 / 8 weeks of game logs, StatScout+ only, with the standard blur and
 * call to action.
 *
 * @param supportsRecent false on a season with no per-game history, where Recent and Both are hidden.
 */
@Composable
fun TeamRankingsCard(
    team: String,
    season: Int,
    players: List<Player>,
    leaguePlayers: List<Player>,
    fetchTeamGameLogs: TeamGameLogFetcher?,
    onUpgradeTap: () -> Unit,
    seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    freshnessRevision: String? = null,
    freshnessStatus: DataFreshnessStatus? = null,
    supportsRecent: Boolean = true,
) {
    val isPro = LocalGraph.current.subscriptions.isPro
    val scope = rememberCoroutineScope()
    var side by rememberSaveable { mutableStateOf(PlayerPositionGroup.FORWARD) }
    var mode by rememberSaveable { mutableStateOf(FormMode.SEASON) }
    var windowWeeks by rememberSaveable { mutableStateOf(4) }
    var logs by rememberRetained("teamForm.logs") { mutableStateOf<List<PlayerGameLog>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }

    val curves = remember(leaguePlayers, players, side, freshnessRevision) {
        val rosterLabels = players.flatMap { p -> p.metrics.map { it.label } }
        val recentLabels = side.categories.flatMap { it.metricPriorityOrder }
        LeaguePercentileCurves(
            leaguePlayers.filter { it.positionGroup == side },
            side.categories,
            (rosterLabels + recentLabels).distinct(),
        )
    }

    // The mode actually rendered: a season with no per-game history would
    // otherwise sit in front of a permanently empty window.
    val effectiveMode = if (supportsRecent) mode else FormMode.SEASON

    suspend fun load() {
        // Free users see a static teaser, never real team game logs.
        val fetch = fetchTeamGameLogs ?: return
        if (!isPro) return
        loading = true
        loadError = null
        try {
            // Pull a wide window (the last ~120 days of the season) so the client
            // can slice the most recent 2 / 4 / 8 weeks out of it. Anchored to the
            // season's own end, not to today.
            logs = fetch(team, season, seasonPhase, StatScoutSeason.gameLogWindowStart(season))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            loadError = "Couldn't load team form. Check your connection and try again."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(team, season, seasonPhase, effectiveMode, isPro, freshnessRevision ?: "none") {
        if (effectiveMode.usesRecent && isPro) load()
    }

    val form = FormData(side, players, curves, logs, windowWeeks, season)

    Column(Modifier.fillMaxWidth().rinkCard().testTag("teamRankingsCard")) {
        RinkSectionBar("TEAM ADVANCED STATS", trailing = if (isPro) null else ({ ProBadge() }))

        // Six capsules on one line squeezed "Forwards" against its own edges,
        // so the position and the mode each get a full-width row.
        Column(
            Modifier.fillMaxWidth().background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            RinkSegmented(PlayerPositionGroup.entries.map { Segment(it, it.pickerLabel) }, side, { side = it })
            if (supportsRecent) {
                RinkSegmented(
                    FormMode.entries.map { Segment(it, it.raw, isLocked = !isPro && it != FormMode.SEASON) },
                    mode, { mode = it },
                    onLockedTap = { onUpgradeTap() },
                )
            }
        }

        if (effectiveMode.usesRecent) {
            RinkSegmented(
                RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                RecentWindow.of(windowWeeks) ?: RecentWindow.FOUR,
                { windowWeeks = it.value },
                Modifier.background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline).padding(bottom = 8.dp),
            )
        }

        when (effectiveMode) {
            FormMode.SEASON -> SeasonBars(form, players.isEmpty())
            FormMode.RECENT -> RecentSection(form, isPro, loading, loadError, freshnessStatus) { scope.launch { load() } }
            FormMode.BOTH -> BothSection(form, loading, loadError) { scope.launch { load() } }
        }
    }
}

/** The pieces of derived state the sections share. */
private class FormData(
    val side: PlayerPositionGroup,
    val players: List<Player>,
    val curves: LeaguePercentileCurves,
    val logs: List<PlayerGameLog>,
    val windowWeeks: Int,
    val season: Int,
) {
    /** Smallest team-window ice time (minutes) we'll treat as trustworthy. */
    val smallSampleMinutesThreshold = 200

    /**
     * One bar per roster metric: the roster mean placed on the league curve.
     * Each keeps its own category so the leaderboard link routes correctly.
     */
    val seasonRows: List<Metric> by lazy { aggregateSeasonRows() }

    val sideLogs: List<PlayerGameLog> by lazy {
        val onSide = logs.filter { it.playerType.lowercase() == side.raw.lowercase() }
        RecentFormWindow.logs(onSide, windowWeeks)
    }

    val recentWindow: RecentFormWindow? by lazy {
        if (sideLogs.isEmpty()) null else RecentFormWindow.build("Last $windowWeeks weeks", windowWeeks, sideLogs)
    }

    /** Distinct game dates in the window: the club's games, not player rows. */
    val teamGames: Int get() = sideLogs.map { it.gameDate.atZone(ZoneId.systemDefault()).toLocalDate() }.toSet().size

    private fun aggregateSeasonRows(): List<Metric> {
        val cats = side.categories
        val pool = players.filter { it.positionGroup == side }
        if (pool.isEmpty()) return emptyList()

        // Ordered (label, category) pairs present on the roster.
        val pairs = mutableListOf<Pair<String, MetricCategory>>()
        val seen = HashSet<String>()
        for (cat in cats) {
            val present = pool.flatMap { p -> p.metrics.filter { it.category == cat }.map { it.label } }.toSet()
            // Advanced only: a roster mean of goals or hits ("1.2 G") reads as
            // nothing, and the Standard tab carries the counting stats.
            for (label in cat.metricPriorityOrder) {
                if (label !in present) continue
                if (HockeyMetricRegistry.definition(label, cat)?.kind == MetricKind.TRADITIONAL) continue
                if (seen.add(label)) pairs += label to cat
            }
        }

        return pairs.mapNotNull { (label, category) ->
            val values = pool.mapNotNull { player ->
                player.metrics.firstOrNull { it.label == label && it.category == category }?.let { DashboardViewModel.rawNumeric(it.value) }
            }
            if (values.isEmpty()) return@mapNotNull null
            val avg = values.sum() / values.size
            val pct = curves.curve(label)?.percentile(avg) ?: return@mapNotNull null
            Metric(label = label, value = formattedValue(avg, label), percentile = pct, category = category, id = "teamavg-$label")
        }
    }

    private fun formattedValue(v: Double, label: String): String = when {
        label.endsWith("SV%") -> RecentMetricKey.savePercentage(v)
        label.endsWith("%") -> String.format(Locale.US, "%.1f%%", v)
        abs(v) >= 100 -> String.format(Locale.US, "%.0f", v)
        else -> String.format(Locale.US, "%.${maxOf(RecentMetricKey.decimals(label), 1)}f", v)
    }

    /** The metric category a season label belongs to. */
    private fun categoryFor(label: String): MetricCategory {
        for (cat in side.categories) if (label in cat.metricPriorityOrder) return cat
        return side.primaryCategory
    }

    /** The recent-window bar for a season label, or null when the window cannot rebuild it. */
    fun recentMetric(label: String, window: RecentFormWindow): Metric? {
        val v = window.value(label) ?: return null
        val pct = curves.curve(label)?.percentile(v) ?: return null
        return Metric(
            label = label,
            value = RecentMetricKey.format(v, label),
            percentile = pct,
            category = categoryFor(label),
            id = "team-recent-$label",
        )
    }

    /**
     * Recent mode mirrors the season list: every season aggregate bar is shown.
     * Metrics the window can rebuild render the recent value (re-placed on the
     * league curve); the rest fall back to their season aggregate bar.
     */
    fun recentDisplayRows(window: RecentFormWindow): List<Metric> = seasonRows.map { recentMetric(it.label, window) ?: it }
}

@Composable
private fun ProBadge() {
    Row(
        Modifier.clip(CircleShape).background(CrownYellow).padding(horizontal = 7.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfIcon("crown.fill", 11.dp, RinkPalette.midnight)
        Text("STATSCOUT+", style = RinkType.micro.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = RinkPalette.midnight)
    }
}

// MARK: - Season

@Composable
private fun SeasonBars(form: FormData, rosterEmpty: Boolean) {
    val navigator = LocalNavigator.current
    val rows = form.seasonRows
    if (rows.isEmpty()) {
        EmptyAggregate(
            if (rosterEmpty) "No games played yet this season" else "Not enough ${form.side.displayName.lowercase()} data to aggregate",
        )
        return
    }
    RinkSubSectionBar(form.side.displayName.uppercase())
    Column {
        rows.forEachIndexed { index, metric ->
            BarRow(
                metric, index,
                Modifier.clickable(onClickLabel = "See the league leaderboard for ${metric.label}") {
                    navigator.push(Route.Metric(metric.label, metric.category))
                },
            )
        }
    }
    Text(
        "${if (form.season >= StatScoutSeason.current) "Season to date" else "Full season"}, averaged across the ${form.side.displayName.lowercase()} on the roster",
        style = RinkType.micro,
        color = RinkPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padCard, vertical = 10.dp),
    )
}

@Composable
private fun BarRow(metric: Metric, index: Int, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxWidth()
            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padCard, vertical = 12.dp),
    ) { MetricBar(metric) }
}

@Composable
private fun EmptyAggregate(text: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        SfIcon("chart.bar.xaxis", 26.dp, RinkPalette.inkTertiary)
        Text(text, style = RinkType.small, color = RinkPalette.inkSecondary)
    }
}

// MARK: - Both

@Composable
private fun BothSection(form: FormData, loading: Boolean, loadError: String?, retry: () -> Unit) {
    val seasonRows = form.seasonRows
    val window = form.recentWindow
    val recentRows = if (window == null) emptyMap() else seasonRows.mapNotNull { row ->
        form.recentMetric(row.label, window)?.let { row.label to it }
    }.toMap()
    when {
        loading -> GamesTeamsUi.InlineSpinner("Loading recent games…")
        loadError != null -> InlineLoadError(loadError, retry)
        else -> Column {
            seasonRows.forEachIndexed { index, metric ->
                Box(
                    Modifier.fillMaxWidth()
                        .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                        .bottomHairline(RinkPalette.divider)
                        .padding(horizontal = RinkGeo.padCard, vertical = 10.dp),
                ) { DualMetricBar(metric, recentRows[metric.label], "Last ${form.windowWeeks}W") }
            }
        }
    }
}

// MARK: - Recent

@Composable
private fun RecentSection(
    form: FormData,
    isPro: Boolean,
    loading: Boolean,
    loadError: String?,
    freshnessStatus: DataFreshnessStatus?,
    retry: () -> Unit,
) {
    if (isPro) {
        RecentBars(form, loading, loadError, freshnessStatus, retry)
    } else {
        Box(Modifier.fillMaxWidth()) {
            // The blurred sample is hidden from screen readers: it is illustrative, not real.
            Box(Modifier.blur(8.dp).clearAndSetSemantics { }) { RecentTeaser(form.side) }
            BlurGateUnlock(
                "See every team's last 2 / 4 / 8 week form", PaywallTrigger.TeamView,
                Modifier.align(Alignment.BottomCenter),
            )
        }
    }
}

/**
 * Static, non-fetching preview for free users: illustrative team bars in the
 * recent-form layout. No game logs are fetched (no network or battery cost) and
 * no real team data is shown, so the blur can't be read through to leak the
 * actual recent numbers.
 */
@Composable
private fun RecentTeaser(side: PlayerPositionGroup) {
    val sample = if (side == PlayerPositionGroup.GOALIE) {
        listOf(
            Metric(id = "tt_sv", label = "SV%", value = ".918", percentile = 84, category = MetricCategory.GOALTENDING),
            Metric(id = "tt_gsax", label = "GSAx/60", value = "0.21", percentile = 77, category = MetricCategory.GOALTENDING),
            Metric(id = "tt_gaa", label = "GAA", value = "2.48", percentile = 71, category = MetricCategory.GOALTENDING),
            Metric(id = "tt_hd", label = "HD SV%", value = ".842", percentile = 66, category = MetricCategory.GOALTENDING),
        )
    } else {
        listOf(
            Metric(id = "tt_p60", label = "P/60", value = "2.41", percentile = 84, category = MetricCategory.SCORING),
            Metric(id = "tt_ixg", label = "ixG/60", value = "0.88", percentile = 77, category = MetricCategory.SHOT_QUALITY),
            Metric(id = "tt_sh60", label = "Shots/60", value = "11.9", percentile = 71, category = MetricCategory.SHOT_QUALITY),
            Metric(id = "tt_shp", label = "Sh%", value = "10.4%", percentile = 66, category = MetricCategory.SCORING),
        )
    }
    Column {
        Row(Modifier.padding(RinkGeo.padInline), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SummaryStat("GP", "7")
            SummaryStat("TOI", "1,420")
            SummaryStat(if (side == PlayerPositionGroup.GOALIE) "SA" else "Shot Att", if (side == PlayerPositionGroup.GOALIE) "198" else "412")
        }
        RinkSubSectionBar(side.displayName.uppercase())
        sample.forEachIndexed { index, metric -> BarRow(metric, index) }
    }
}

@Composable
private fun RecentBars(form: FormData, loading: Boolean, loadError: String?, freshnessStatus: DataFreshnessStatus?, retry: () -> Unit) {
    val window = form.recentWindow
    when {
        loading -> GamesTeamsUi.InlineSpinner("Loading recent games…")
        loadError != null -> InlineLoadError(loadError, retry)
        window != null -> {
            RecentSummaryRow(form, window)
            val rows = form.recentDisplayRows(window)
            if (rows.isNotEmpty()) {
                RinkSubSectionBar(form.side.displayName.uppercase())
                rows.forEachIndexed { index, metric -> BarRow(metric, index) }
            }
        }
        else -> Column(
            Modifier.fillMaxWidth().padding(vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            SfIcon("calendar.badge.exclamationmark", 26.dp, RinkPalette.inkTertiary)
            Text(emptyStateText(form, freshnessStatus), style = RinkType.small, color = RinkPalette.inkSecondary)
        }
    }
}

private fun emptyStateText(form: FormData, status: DataFreshnessStatus?): String = when (status) {
    DataFreshnessStatus.PENDING, DataFreshnessStatus.PARTIAL, DataFreshnessStatus.CHECKING -> "Recent team data is still arriving"
    DataFreshnessStatus.OFFLINE, DataFreshnessStatus.FAILED -> "Recent team data is unavailable right now"
    else -> "No ${form.side.displayName.lowercase()} data in the last ${form.windowWeeks} weeks"
}

@Composable
private fun RecentSummaryRow(form: FormData, window: RecentFormWindow) {
    Row(Modifier.padding(RinkGeo.padInline), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        SummaryStat("GP", "${form.teamGames}")
        SummaryStat("TOI", java.text.NumberFormat.getIntegerInstance(Locale.US).format(window.plays))
        SummaryStat(if (form.side == PlayerPositionGroup.GOALIE) "SA" else "Shot Att", "${window.touches}")
        Box(Modifier.weight(1f))
        if (window.plays < form.smallSampleMinutesThreshold) {
            Text(
                "SMALL SAMPLE",
                style = RinkType.micro,
                color = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.clip(CircleShape).background(RinkPalette.inkTertiary).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
private fun SummaryStat(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(label, style = RinkType.micro, color = RinkPalette.inkTertiary)
        Text(value, style = RinkType.bodyBold, color = RinkPalette.ink)
    }
}
