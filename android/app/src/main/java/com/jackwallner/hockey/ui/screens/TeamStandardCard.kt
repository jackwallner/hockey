package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.RecentFormWindow
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.BlurGateUnlock
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.RinkSubSectionBar
import com.jackwallner.hockey.ui.components.InlineLoadError
import com.jackwallner.hockey.ui.components.MetricBar
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.TrendArrow
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.statDisplayLabel
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.rememberRetained
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.text.NumberFormat
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * The traditional line for a whole club, percentile-mapped against the other 31.
 *
 * The percentile card next to it answers "how good is this group"; this
 * answers "what actually happened". The ruler here is the league's thirty-two
 * clubs, not its several hundred players: a team's .915 save percentage means
 * nothing against individual goalies' spread, and everything against the other
 * clubs'.
 *
 * @param players the roster for this team and season.
 * @param leaguePlayers every player in the season, used to build the thirty-two team lines.
 * @param seasonPhase see [TeamRankingsCard].
 * @param fetchTeamGameLogs fetches (team, season, phase, since) game logs.
 * @param supportsRecent false on a historical season, where the Recent control is hidden.
 */
@Composable
fun TeamStandardCard(
    team: String,
    season: Int,
    players: List<Player>,
    leaguePlayers: List<Player>,
    fetchTeamGameLogs: TeamGameLogFetcher?,
    onUpgradeTap: () -> Unit,
    seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    supportsRecent: Boolean = true,
) {
    val isPro = LocalGraph.current.subscriptions.isPro
    val scope = rememberCoroutineScope()
    var side by rememberSaveable { mutableStateOf(PlayerPositionGroup.FORWARD) }
    var showingRecent by rememberSaveable { mutableStateOf(false) }
    var windowWeeks by rememberSaveable { mutableStateOf(4) }
    var logs by rememberRetained("teamStandard.logs") { mutableStateOf<List<PlayerGameLog>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }

    // What the card actually renders. The toggle survives a season change (it is
    // view state, the season is a parameter), so a user who turned Recent on for
    // the live season and then walked back to 2018 would otherwise sit in front
    // of a permanently empty window.
    val isRecent = showingRecent && supportsRecent
    val line = StandardLines(team, side, players, leaguePlayers, logs, windowWeeks)

    suspend fun load() {
        val fetch = fetchTeamGameLogs ?: return
        if (!isPro) return
        loading = true
        loadError = null
        try {
            // Wide enough to cover the longest window, then trimmed to the
            // trailing weeks. Anchored to the season's own end, not to today.
            logs = fetch(team, season, seasonPhase, StatScoutSeason.gameLogWindowStart(season))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            loadError = "Couldn't load team form. Pull to refresh."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(team, season, seasonPhase, isRecent, isPro) {
        if (isRecent && isPro) load()
    }

    Column(Modifier.fillMaxWidth().rinkCard().testTag("teamStandardCard")) {
        RinkSectionBar("TEAM STANDARD STATS")

        GamesTeamsUi.PickerRow(
            groups = listOfNotNull(
                PlayerPositionGroup.entries.size to {
                    RinkSegmented(PlayerPositionGroup.entries.map { Segment(it, it.pickerLabel) }, side, { side = it })
                },
                if (supportsRecent) 2 to {
                    RinkSegmented(
                        listOf(Segment(false, "Season"), Segment(true, "Recent", isLocked = !isPro)),
                        showingRecent, { showingRecent = it },
                        onLockedTap = { onUpgradeTap() },
                    )
                } else null,
            ),
            modifier = Modifier.background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline, vertical = 8.dp),
        )

        if (isRecent) {
            RinkSegmented(
                RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                line.window,
                { windowWeeks = it.value },
                Modifier.background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline).padding(bottom = 8.dp),
            )
        }

        if (isRecent) RecentContent(line, isPro, loading, loadError) { scope.launch { load() } }
        else SeasonContent(line)
    }
}

/**
 * Rate stats, rebuilt from summed counts. Averaging a roster's shooting
 * percentages would weight a fourth liner's 1-for-3 like a sniper's season;
 * summing goals and shots is exact.
 */
private val SKATER_RATES = listOf("SH%")
private val GOALIE_RATES = listOf("SV%")
private val SKATER_COUNTS = listOf("P", "G", "A", "+/-", "PIM", "PPG", "PPP", "SHG", "GWG", "SOG", "HITS", "BLK", "GP")
private val GOALIE_COUNTS = listOf("W", "L", "OT", "SO", "SV", "SA", "GP")
private val SUMMED_LABELS = (SKATER_COUNTS + GOALIE_COUNTS).toSet()

/** Lower is better: penalty minutes, and a goalie's losses. */
private val LOWER_IS_BETTER = setOf("PIM", "L", "OT")

/** Game-log key to the label it's displayed under: the rollup's own naming, so the two stay in step. */
private fun countingWindowKeys(side: PlayerPositionGroup): List<Pair<String, String>> =
    if (side == PlayerPositionGroup.GOALIE) {
        listOf("decision_win" to "W", "saves" to "SV", "shots_against" to "SA", "shutout" to "SO")
    } else {
        listOf(
            "points" to "P", "goals" to "G", "assists" to "A",
            "shots_on_goal" to "SOG", "hits" to "HITS", "blocks" to "BLK", "pim" to "PIM",
        )
    }

/** The derived numbers behind the card: the club's line, the league's lines and the game-log window. */
private class StandardLines(
    val team: String,
    val side: PlayerPositionGroup,
    private val players: List<Player>,
    private val leaguePlayers: List<Player>,
    private val logs: List<PlayerGameLog>,
    val windowWeeks: Int,
) {
    val rateLabels: List<String> get() = if (side == PlayerPositionGroup.GOALIE) GOALIE_RATES else SKATER_RATES
    val countingLabels: List<String> get() = if (side == PlayerPositionGroup.GOALIE) GOALIE_COUNTS else SKATER_COUNTS
    val order: List<String> get() = rateLabels + countingLabels
    val window: RecentWindow get() = RecentWindow.of(windowWeeks) ?: RecentWindow.FOUR

    val seasonLine: Map<String, Double> by lazy { teamLine(players) }

    /** The other thirty-one, plus this one: the distribution a bar is drawn against. */
    val league: List<Map<String, Double>> by lazy {
        leaguePlayers.groupBy { normalizedTeamAbbreviation(it.team) }.values.map { teamLine(it) }.filter { it.isNotEmpty() }
    }

    /**
     * One club's standard line: counting stats summed, rates rebuilt from the
     * quantity they're a rate of. The same "numerators and denominators, never
     * pre-divided rates" rule the backend rollup follows.
     */
    private fun teamLine(roster: List<Player>): Map<String, Double> {
        val pool = roster.filter { it.positionGroup == side }
        if (pool.isEmpty()) return emptyMap()
        val totals = HashMap<String, Double>()
        for (player in pool) {
            for (stat in player.standardStats.orEmpty()) {
                val label = stat.label.uppercase()
                if (label !in SUMMED_LABELS) continue
                val value = DashboardViewModel.rawNumeric(stat.value) ?: continue
                // Games played is per player, so summing it across a roster is
                // meaningless. Take the maximum, which is the club's own count.
                if (label == "GP") totals["GP"] = maxOf(totals["GP"] ?: 0.0, value)
                else totals[label] = (totals[label] ?: 0.0) + value
            }
        }
        return withDerivedRates(totals)
    }

    /** The rate stats, rebuilt from the summed counts. */
    private fun withDerivedRates(totals: Map<String, Double>): Map<String, Double> {
        val out = HashMap(totals)
        val shots = totals["SOG"]
        val goals = totals["G"]
        if (shots != null && shots > 0 && goals != null) out["SH%"] = goals / shots * 100
        val faced = totals["SA"]
        val saves = totals["SV"]
        if (faced != null && faced > 0 && saves != null) out["SV%"] = saves / faced
        return out
    }

    /**
     * Rank against whichever clubs have the stat, however few that is. A rank
     * among the clubs that have a number is the honest answer at every point in
     * the season, including opening night when only a few have played.
     */
    fun percentile(label: String, value: Double): Int {
        var values = league.mapNotNull { it[label] }
        if (values.isEmpty()) values = listOf(value)
        val below = values.count { it < value }
        val equal = values.count { it == value }
        val raw = (below + equal / 2.0) / values.size * 100
        val oriented = if (label in LOWER_IS_BETTER) 100 - raw else raw
        return Math.round(oriented).toInt().coerceIn(1, 100)
    }

    // MARK: Window

    private val sideLogsAll: List<PlayerGameLog> get() = logs.filter { it.playerType.lowercase() == side.raw.lowercase() }

    /**
     * The club's logs from the trailing weeks. The window is anchored to the last
     * date present in the data, never to today: anchoring to now would silently
     * shrink the window to nothing all summer.
     */
    private val sideLogs: List<PlayerGameLog> get() = RecentFormWindow.logs(sideLogsAll, windowWeeks)

    /**
     * True when the club's games all fall inside the window, so "last four weeks"
     * and "the season" are the same games. The comparison goes away, the window stays.
     */
    val windowIsWholeSeason: Boolean get() = sideLogs.size == sideLogsAll.size

    /** "LAST 4 WEEKS" over a club that has played for ten days is a claim about days that do not exist yet. */
    val windowTitle: String get() = if (windowIsWholeSeason) "SEASON TO DATE" else "LAST $windowWeeks WEEKS"

    /** Summed counting stats for the window, keyed by display label. */
    val windowTotals: Map<String, Double> by lazy {
        val window = sideLogs
        val totals = HashMap<String, Double>()
        for (log in window) {
            for ((key, label) in countingWindowKeys(side)) {
                log.metrics[key]?.let { totals[label] = (totals[label] ?: 0.0) + it }
            }
            log.metrics["goals"]?.let { totals["goals"] = (totals["goals"] ?: 0.0) + it }
        }
        totals
    }

    /** The rate line rebuilt from the window's sums, the same identity the backend rollup uses. */
    val windowRates: Map<String, Double> by lazy {
        val totals = windowTotals
        val out = HashMap<String, Double>()
        if (side == PlayerPositionGroup.GOALIE) {
            val faced = totals["SA"]
            val saves = totals["SV"]
            if (faced != null && faced > 0 && saves != null) out["SV%"] = saves / faced
        } else {
            val shots = totals["SOG"]
            val goals = totals["G"]
            if (shots != null && shots > 0 && goals != null) out["SH%"] = goals / shots * 100
        }
        out
    }

    fun sortedByOrder(labels: Collection<String>): List<String> =
        labels.sortedBy { order.indexOf(it).let { index -> if (index < 0) Int.MAX_VALUE else index } }

    // MARK: Teaser

    /**
     * Season line to an invented window, per side and per window length. Built
     * from this club's real season rates so the preview is the team the user is
     * looking at, and so moving the position or 2/4/8 pickers visibly redraws it.
     */
    val teaserRows: List<Triple<String, Double, Double>>
        get() {
            val labels = rateLabels.filter { seasonLine[it] != null }
            val fallback = if (side == PlayerPositionGroup.GOALIE) listOf("SV%" to 0.907) else listOf("SH%" to 9.8)
            val base = if (labels.isEmpty()) fallback else labels.take(4).map { it to (seasonLine[it] ?: 0.0) }
            return base.map { (label, season) ->
                val seed = stableSeed("$label-${side.raw}-$windowWeeks-$team")
                // Plus or minus 12% of the season figure, the size of a real few-week swing.
                val swing = season * (seed % 25 - 12) / 100
                Triple(label, season, season + swing)
            }
        }

    val teaserTotals: List<Pair<String, Int>>
        get() {
            val scale = windowWeeks / 4.0
            val base = if (side == PlayerPositionGroup.GOALIE) {
                listOf("SV" to 410, "SA" to 446, "W" to 6, "SO" to 1)
            } else {
                listOf("P" to 118, "G" to 42, "SOG" to 380, "HITS" to 190)
            }
            return base.map { (label, value) -> label to Math.round(value * scale).toInt() }
        }

    /** Deterministic across launches, unlike `hashCode`. */
    private fun stableSeed(text: String): Int =
        Math.abs(text.codePoints().toArray().fold(7) { acc, scalar -> (acc * 31 + scalar) % 100_003 })

    fun format(label: String, value: Double): String = when (label) {
        "SH%" -> String.format(Locale.US, "%.1f%%", value)
        "SV%" -> RecentMetricKey.savePercentage(value)
        else -> NumberFormat.getIntegerInstance(Locale.US).format(Math.round(value))
    }
}

// MARK: - Season

@Composable
private fun SeasonContent(lines: StandardLines) {
    val line = lines.seasonLine
    if (line.isEmpty()) {
        EmptyState("No standard stats for this roster")
        return
    }
    BarGroup("RATE", lines.rateLabels, lines, startIndex = 0)
    BarGroup("VOLUME", lines.countingLabels, lines, startIndex = lines.rateLabels.size)
    Text(
        "Totals add up the current roster's season lines, so a player traded at the deadline brings his whole year with him.",
        style = RinkType.micro,
        color = RinkPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padCard, vertical = 10.dp),
    )
}

@Composable
private fun BarGroup(title: String, labels: List<String>, lines: StandardLines, startIndex: Int) {
    val present = labels.filter { lines.seasonLine[it] != null }
    if (present.isEmpty()) return
    RinkSubSectionBar(title)
    present.forEachIndexed { offset, label ->
        val value = lines.seasonLine[label] ?: 0.0
        val metric = Metric(
            label = label,
            value = lines.format(label, value),
            percentile = lines.percentile(label, value),
            category = lines.side.primaryCategory,
            id = "team-std-$label",
        )
        Box(
            Modifier.fillMaxWidth()
                .background(if ((startIndex + offset) % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                .bottomHairline(RinkPalette.divider)
                .padding(horizontal = RinkGeo.padCard, vertical = 12.dp),
        ) { MetricBar(metric) }
    }
}

// MARK: - Recent

@Composable
private fun RecentContent(lines: StandardLines, isPro: Boolean, loading: Boolean, loadError: String?, retry: () -> Unit) {
    when {
        !isPro -> Box(Modifier.fillMaxWidth()) {
            // The blurred sample is hidden from screen readers: it is illustrative, not real.
            Box(Modifier.blur(8.dp).clearAndSetSemantics { }) { Teaser(lines) }
            BlurGateUnlock("See every club's last 2 / 4 / 8 weeks", PaywallTrigger.TeamView, Modifier.align(Alignment.BottomCenter))
        }
        loading -> GamesTeamsUi.InlineSpinner("Loading recent games…")
        loadError != null -> InlineLoadError(loadError, retry)
        else -> RecentTotals(lines)
    }
}

@Composable
private fun RecentTotals(lines: StandardLines) {
    val totals = lines.windowTotals
    if (totals.isEmpty()) {
        EmptyState("No ${lines.side.displayName.lowercase()} games in the last ${lines.windowWeeks} weeks")
        return
    }
    val rates = lines.windowRates
    val seasonLine = lines.seasonLine

    // Season to window, not a percentile bar. Two weeks of team shooting
    // percentage sits outside the whole spread of thirty-two season figures more
    // often than not, so a bar drawn on that ruler pins to 1 or 100 and says
    // nothing. The move against the club's own season number is the real
    // information, and it's the same framing the Trends board uses.
    if (rates.isNotEmpty()) {
        RinkSubSectionBar("RATE · ${lines.windowTitle}")
        lines.sortedByOrder(rates.keys).forEachIndexed { index, label ->
            val now = rates[label] ?: 0.0
            val then = seasonLine[label]
            val showCompare = then != null && !lines.windowIsWholeSeason
            Row(
                Modifier.fillMaxWidth().height(RinkGeo.rowHeight)
                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .bottomHairline(RinkPalette.divider)
                    .padding(horizontal = RinkGeo.padCard),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label.statDisplayLabel, style = RinkType.bodyBold, color = RinkPalette.ink, modifier = Modifier.width(68.dp))
                Text(
                    if (showCompare) "${lines.format(label, then!!)} → ${lines.format(label, now)}" else lines.format(label, now),
                    style = RinkType.small.copy(fontFeatureSettings = "tnum"),
                    color = RinkPalette.inkSecondary,
                )
                Spacer(Modifier.weight(1f))
                if (showCompare) TrendArrow(now - then!!, if (label == "SV%") 3 else 1, lowerIsBetter = label in LOWER_IS_BETTER)
            }
        }
        Text(
            if (lines.windowIsWholeSeason) "Every game this club has played so far." else "Compared with the same club's season line.",
            style = RinkType.micro,
            color = RinkPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padCard, vertical = 8.dp),
        )
    }

    // Counting stats get no bar. Two weeks of goals against thirty-two
    // season totals would sit at the first percentile for every club in the
    // league, which says nothing.
    RinkSubSectionBar("TOTALS · ${lines.windowTitle}")
    countingWindowKeys(lines.side).map { it.second }.filter { totals[it] != null }.forEachIndexed { index, label ->
        TotalRow(label.statDisplayLabel, String.format(Locale.US, "%.0f", totals[label] ?: 0.0), index)
    }
}

@Composable
private fun TotalRow(label: String, value: String, index: Int) {
    Row(
        Modifier.fillMaxWidth().height(RinkGeo.rowHeight)
            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padCard),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = RinkType.bodyBold, color = RinkPalette.ink, modifier = Modifier.weight(1f))
        Text(value, style = RinkType.statSmall, color = RinkPalette.ink, textAlign = TextAlign.End)
    }
}

/**
 * Invented numbers in the real layout, so a free user can see what the window
 * actually reports rather than a padlock. It tracks the window picker, because
 * a preview that ignores the control above it looks broken.
 */
@Composable
private fun Teaser(lines: StandardLines) {
    Column {
        RinkSubSectionBar("RATE · LAST ${lines.windowWeeks} WEEKS")
        lines.teaserRows.forEachIndexed { index, (label, season, window) ->
            Row(
                Modifier.fillMaxWidth().height(RinkGeo.rowHeight)
                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .padding(horizontal = RinkGeo.padCard),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, style = RinkType.bodyBold, color = RinkPalette.ink, modifier = Modifier.width(68.dp))
                Text(
                    "${lines.format(label, season)} → ${lines.format(label, window)}",
                    style = RinkType.small.copy(fontFeatureSettings = "tnum"),
                    color = RinkPalette.inkSecondary,
                )
                Spacer(Modifier.weight(1f))
                TrendArrow(window - season, 1)
            }
        }
        RinkSubSectionBar("TOTALS · LAST ${lines.windowWeeks} WEEKS")
        lines.teaserTotals.forEachIndexed { index, (label, value) ->
            Row(
                Modifier.fillMaxWidth().height(RinkGeo.rowHeight)
                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .padding(horizontal = RinkGeo.padCard),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, style = RinkType.bodyBold, color = RinkPalette.ink, modifier = Modifier.weight(1f))
                Text("$value", style = RinkType.statSmall, color = RinkPalette.ink)
            }
        }
    }
}

@Composable
private fun EmptyState(message: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        SfIcon("list.bullet.rectangle", 26.dp, RinkPalette.inkTertiary)
        Text(message, style = RinkType.small, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center)
    }
}
