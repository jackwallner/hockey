package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.DataFreshnessStatus
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.metricNumericValue
import com.jackwallner.hockey.model.swiftRoundDouble
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.BlurGateUnlock
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.InlineLoadError
import com.jackwallner.hockey.ui.components.MetricBar
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.gateBlur
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/**
 * Maps a raw value onto the league's season percentile scale by interpolating
 * the feed's own (value, percentile) pairs, so a recent-window bar sits on the
 * same ruler as the season bar. Direction lives in the points themselves.
 */
class LeaguePercentileCurve private constructor(private val points: List<Pair<Double, Double>>) {
    fun percentile(v: Double): Int {
        if (v <= points.first().first) return clamp(points.first().second)
        if (v >= points.last().first) return clamp(points.last().second)
        for (i in 1 until points.size) {
            if (v <= points[i].first) {
                val (v0, p0) = points[i - 1]
                val (v1, p1) = points[i]
                val t = if (v1 == v0) 0.0 else (v - v0) / (v1 - v0)
                return clamp(p0 + t * (p1 - p0))
            }
        }
        return clamp(points.last().second)
    }

    private fun clamp(p: Double): Int = swiftRoundDouble(p).toInt().coerceIn(1, 100)

    companion object {
        /** Two points are enough to interpolate, and two is what an opening week provides. */
        fun of(raw: List<Pair<Double, Double>>): LeaguePercentileCurve? {
            val sorted = raw.sortedBy { it.first }
            return if (sorted.size >= 2) LeaguePercentileCurve(sorted) else null
        }
    }
}

/** Per-metric curves for one population, keyed by season metric label. */
class LeaguePercentileCurves(players: List<Player>, categories: List<MetricCategory>, labels: List<String>) {
    private val byLabel: Map<String, LeaguePercentileCurve>

    init {
        val pool = players.filter { p -> categories.any { p.matchesPlayerType(it) } }
        byLabel = labels.mapNotNull { label ->
            val pts = pool.mapNotNull { p ->
                val m = p.metrics.firstOrNull { it.label == label && it.category in categories } ?: return@mapNotNull null
                val v = metricNumericValue(m.value) ?: return@mapNotNull null
                v to m.percentile.toDouble()
            }
            LeaguePercentileCurve.of(pts)?.let { label to it }
        }.toMap()
    }

    fun curve(label: String): LeaguePercentileCurve? = byLabel[label]
}

/** The empty-window line shared by the profile's recent cards. */
fun recentEmptyText(status: DataFreshnessStatus?, windowWeeks: Int): String = when (status) {
    DataFreshnessStatus.PENDING, DataFreshnessStatus.PARTIAL, DataFreshnessStatus.CHECKING -> "Recent game data is still arriving"
    DataFreshnessStatus.OFFLINE, DataFreshnessStatus.FAILED -> "Recent game data is unavailable right now"
    else -> "No games in the last $windowWeeks weeks"
}

/**
 * Last 2 / 4 / 8 week form for one player. Free users see a blurred static
 * teaser with no game-log fetch; StatScout+ loads the logs once and windows them locally.
 */
@Composable
fun RecentFormCard(
    player: Player,
    season: Int,
    leaguePlayers: List<Player>,
    fetchGameLogs: (suspend (Int, Int, SeasonPhase) -> List<PlayerGameLog>)?,
    freshnessRevision: String?,
    freshnessStatus: DataFreshnessStatus?,
) {
    val isPro = LocalGraph.current.subscriptions.isPro
    val scope = rememberCoroutineScope()
    var logs by remember { mutableStateOf<List<PlayerGameLog>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var windowWeeks by remember { mutableStateOf(4) }
    val isGoalie = player.isGoalie
    val curves = remember(isPro, leaguePlayers.size, player.positionGroup) {
        if (isPro) LeaguePercentileCurves(
            leaguePlayers.filter { it.positionGroup == player.positionGroup },
            if (isGoalie) listOf(MetricCategory.GOALTENDING) else listOf(MetricCategory.SCORING, MetricCategory.SHOT_QUALITY),
            RecentFormWindow.recentLabels(isGoalie),
        ) else null
    }

    suspend fun load() {
        if (!isPro || fetchGameLogs == null) return
        loading = true
        loadError = null
        try {
            logs = fetchGameLogs(player.playerId, season, player.seasonPhase)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            loadError = "Couldn't load recent games."
        }
        loading = false
    }
    LaunchedEffect(player.playerId, season, player.seasonPhase, freshnessRevision, isPro) { load() }

    val window = RecentFormWindow.logs(logs, windowWeeks).takeIf { it.isNotEmpty() }
        ?.let { RecentFormWindow.build("Last $windowWeeks weeks", windowWeeks, it) }

    Column(Modifier.fillMaxWidth().rinkCard()) {
        Column(Modifier.fillMaxWidth().background(RinkPalette.surfaceAlt).bottomHairline(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.padding(horizontal = RinkGeo.padInline).padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SfIcon("flame.fill", 14.dp, RinkPalette.turf)
                Text("RECENT FORM", style = RinkType.micro, color = RinkPalette.inkSecondary, modifier = Modifier.weight(1f))
                if (!isPro) {
                    Row(
                        Modifier.clip(CircleShape).background(CrownYellow).padding(horizontal = 7.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SfIcon("crown.fill", 10.dp, RinkPalette.midnight)
                        Text("STATSCOUT+", style = RinkType.micro.copy(fontWeight = FontWeight.Bold), color = RinkPalette.midnight)
                    }
                }
            }
            RinkSegmented(
                RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                RecentWindow.of(windowWeeks) ?: RecentWindow.FOUR,
                { windowWeeks = it.value },
                Modifier.padding(horizontal = RinkGeo.padInline).padding(bottom = 6.dp),
            )
        }
        if (isPro) {
            when {
                loading -> Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = RinkPalette.inkTertiary, strokeWidth = 2.dp)
                    Text("Loading recent games…", style = RinkType.small, color = RinkPalette.inkSecondary)
                }
                loadError != null -> InlineLoadError(loadError!!) { scope.launch { load() } }
                window != null -> StatsBody(window, isGoalie, recentRows(window, isGoalie, curves))
                else -> Column(Modifier.fillMaxWidth().padding(vertical = 22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SfIcon("calendar.badge.exclamationmark", 24.dp, RinkPalette.inkTertiary)
                    Text(recentEmptyText(freshnessStatus, windowWeeks), style = RinkType.small, color = RinkPalette.inkSecondary)
                }
            }
        } else {
            Box {
                Column(Modifier.gateBlur()) { Teaser(isGoalie) }
                BlurGateUnlock("See last 2 / 4 / 8 week form for any player", PaywallTrigger.RecentForm, Modifier.align(Alignment.BottomCenter))
            }
        }
    }
}

@Composable
private fun Teaser(isGoalie: Boolean) {
    val sample = if (isGoalie) listOf(
        Metric("SV%", ".931", 94, MetricCategory.GOALTENDING),
        Metric("GSAx/60", "0.42", 88, MetricCategory.GOALTENDING),
        Metric("GAA", "2.14", 81, MetricCategory.GOALTENDING),
        Metric("HD SV%", ".858", 76, MetricCategory.GOALTENDING),
    ) else listOf(
        Metric("P/60", "3.42", 94, MetricCategory.SCORING),
        Metric("ixG/60", "1.08", 88, MetricCategory.SHOT_QUALITY),
        Metric("Shots/60", "14.2", 81, MetricCategory.SHOT_QUALITY),
        Metric("Sh%", "14.8%", 76, MetricCategory.SCORING),
    )
    Row(Modifier.padding(RinkGeo.padInline), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Summary("GP", "7")
        Summary("TOI", if (isGoalie) "420" else "148")
        Summary(if (isGoalie) "SA" else "Shot Att", if (isGoalie) "198" else "52")
    }
    MetricBarList(sample)
}

@Composable
private fun StatsBody(w: RecentFormWindow, isGoalie: Boolean, rows: List<Metric>) {
    // Smallest ice time (minutes) worth trusting; below it the numbers show, tagged.
    val smallSampleMinutes = if (isGoalie) 100 else 60
    Row(Modifier.fillMaxWidth().padding(RinkGeo.padInline), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Summary("GP", "${w.games}")
        Summary("TOI", "${w.plays}")
        Summary(if (isGoalie) "SA" else "Shot Att", "${w.touches}")
        Spacer(Modifier.weight(1f))
        if (w.plays < smallSampleMinutes) {
            Text(
                "SMALL SAMPLE",
                style = RinkType.micro,
                color = Color.White,
                modifier = Modifier.clip(CircleShape).background(RinkPalette.inkTertiary).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
    MetricBarList(rows)
}

@Composable
fun MetricBarList(rows: List<Metric>) {
    rows.forEachIndexed { index, metric ->
        Box(
            Modifier.fillMaxWidth().background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt).bottomHairline()
                .padding(horizontal = RinkGeo.padCard, vertical = 12.dp),
        ) { MetricBar(metric) }
    }
}

@Composable
private fun Summary(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(label, style = RinkType.micro, color = RinkPalette.inkTertiary)
        Text(value, style = RinkType.bodyBold, color = RinkPalette.ink)
    }
}

/**
 * Window rates as Metrics on the league season curve, rebuilt from the window's
 * summed counts; nothing is drawn that can't be placed.
 */
private fun recentRows(w: RecentFormWindow, isGoalie: Boolean, curves: LeaguePercentileCurves?): List<Metric> =
    RecentFormWindow.recentLabels(isGoalie).mapNotNull { label ->
        val v = w.value(label) ?: return@mapNotNull null
        val pct = curves?.curve(label)?.percentile(v) ?: return@mapNotNull null
        val category = when {
            isGoalie -> MetricCategory.GOALTENDING
            label in setOf("ixG/60", "Shots/60") -> MetricCategory.SHOT_QUALITY
            else -> MetricCategory.SCORING
        }
        Metric(label, RecentMetricKey.format(v, label), pct, category, id = "recent-$label")
    }
