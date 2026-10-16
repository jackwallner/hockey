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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricAggregation
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandardStatSemantics
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.metricNumericValue
import com.jackwallner.hockey.model.ordinal
import com.jackwallner.hockey.model.searchMatches
import com.jackwallner.hockey.model.surname
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.ChipButton
import com.jackwallner.hockey.ui.components.ChipTrailing
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkChip
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkTopBar
import com.jackwallner.hockey.ui.components.PercentileBarMini
import com.jackwallner.hockey.ui.components.PlayerHeadshot
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.SearchField
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
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import kotlinx.coroutines.launch

/** What a comparison can switch between: seasons, rosters, and how to find a player's other seasons. */
class ComparisonCatalog(
    val seasons: List<Int> = emptyList(),
    val defaultPhase: SeasonPhase = SeasonPhase.REGULAR,
    val roster: (Int, SeasonPhase) -> List<Player> = { _, _ -> emptyList() },
    val resolve: (Player, Int, SeasonPhase) -> Player? = { p, s, ph -> p.takeIf { it.season == s && it.seasonPhase == ph } },
    val isSeasonLocked: (Int) -> Boolean = { false },
    val isLoadingHistory: () -> Boolean = { false },
    val loadHistory: (suspend () -> Unit)? = null,
) {
    companion object {
        fun of(vm: DashboardViewModel, defaultPhase: SeasonPhase? = null) = ComparisonCatalog(
            seasons = vm.availableSeasons,
            defaultPhase = defaultPhase ?: vm.selectedPhase,
            roster = { season, phase -> vm.players(season, phase).sortedBy { it.name } },
            resolve = { player, season, phase ->
                if (player.season == season && player.seasonPhase == phase) player
                else vm.playerHistories[player.playerId]?.firstOrNull { it.season == season && it.seasonPhase == phase }
            },
            isSeasonLocked = vm::isSeasonLocked,
            isLoadingHistory = { vm.isHistoricalLoading },
            loadHistory = { vm.loadHistoricalIfNeeded() },
        )
    }
}

private fun lastName(player: Player): String = player.surname

/** A tie on the number shown is a tie, whatever the percentiles say. */
internal fun metricBeats(m: Metric, other: Metric): Boolean {
    val sameShown = m.value.isNotEmpty() && other.value == m.value
    return !sameShown && m.percentile > other.percentile
}

/** Two players on every shared metric. Free users see it blurred behind "Find the Edge". */
@Composable
fun PlayerComparisonScreen(playerA: Player, playerB: Player) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val catalog = remember(playerA.seasonPhase) { ComparisonCatalog.of(vm, playerA.seasonPhase) }
    PushedScreen("Player Comparison") { PlayerComparisonView(playerA, playerB, catalog) }
}

@Composable
fun PlayerComparisonView(playerA: Player, playerB: Player, catalog: ComparisonCatalog?) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val scope = rememberCoroutineScope()
    var overrideA by remember { mutableStateOf<Player?>(null) }
    var overrideB by remember { mutableStateOf<Player?>(null) }
    var picker by remember { mutableStateOf<Int?>(null) }
    var note by remember { mutableStateOf<String?>(null) }
    val a = overrideA ?: playerA
    val b = overrideB ?: playerB

    LaunchedEffect(Unit) { if (store.isPro) actions.positiveMoment() }

    fun move(target: Int, season: Int, phase: SeasonPhase) {
        val current = if (target == 0) a else b
        val resolved = catalog?.resolve?.invoke(current, season, phase)
        if (resolved != null) {
            if (target == 0) overrideA = resolved else overrideB = resolved
            note = null
        } else if (catalog != null) {
            note = if (catalog.isLoadingHistory()) "Loading past seasons…"
            else "No ${SeasonLabel.display(season)} ${phase.label.lowercase()} data for ${current.name}."
            scope.launch { catalog.loadHistory?.invoke() }
        }
        haptic()
    }

    @Composable
    fun SummaryCard(player: Player, target: Int, modifier: Modifier) {
        Column(
            modifier.rinkCard().padding(vertical = 12.dp, horizontal = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(
                Modifier.fillMaxWidth().clickable { navigator.push(Route.PlayerProfile(player)) }
                    .semantics { contentDescription = "${player.name}. Opens ${player.name}'s page" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                PlayerHeadshot(player.team, player.initials, 56.dp)
                FitText(player.name, RinkType.smallBold, RinkPalette.ink, minScale = 0.7f)
                Text("${displayTeamAbbr(player.team)} · ${player.displayPosition}", style = RinkType.micro, color = RinkPalette.inkTertiary)
            }
            if (catalog != null) {
                SeasonPhasePicker(
                    seasons = catalog.seasons,
                    selectedSeason = player.season ?: 0,
                    selectedPhase = player.seasonPhase,
                    isSeasonLocked = catalog.isSeasonLocked,
                    onSelectSeason = { season ->
                        if (catalog.isSeasonLocked(season)) actions.openTrialPitch(PaywallTrigger.PlayerComparison)
                        else move(target, season, player.seasonPhase)
                    },
                    onSelectPhase = { phase -> move(target, player.season ?: 0, phase) },
                ) { open ->
                    ChipButton(open, Modifier.fillMaxWidth(), description = "Season and season type for ${player.name}") {
                        CompressibleChip("${player.season?.let(SeasonLabel::display) ?: "-"} · ${player.seasonPhase.label}")
                    }
                }
                ChipButton({ picker = target }, description = "Change ${if (target == 0) "first" else "second"} player") {
                    RinkChip(title = "Change", icon = "arrow.triangle.2.circlepath", trailing = ChipTrailing.Chevron)
                }
            } else player.season?.let {
                Text(
                    SeasonLabel.display(it),
                    style = RinkType.micro,
                    color = Color.White,
                    modifier = Modifier.clip(CircleShape).background(RinkPalette.midnight).padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        }
    }

    val content = @Composable { interactive: Boolean ->
        val comparison = comparisonMetrics(a, b)
        val standard = standardComparisons(a, b)
        Column(
            Modifier.fillMaxSize().background(RinkPalette.canvas).verticalScroll(rememberScrollState(), enabled = interactive)
                .padding(bottomBarPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SummaryCard(a, 0, Modifier.weight(1f))
                if (catalog != null) {
                    Box(
                        Modifier.padding(top = 44.dp).size(44.dp).clip(CircleShape).clickable(enabled = interactive) {
                            val left = a
                            overrideA = b
                            overrideB = left
                            haptic()
                        }.semantics { contentDescription = "Swap sides" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            Modifier.size(32.dp).clip(CircleShape).background(RinkPalette.surface).border(0.5.dp, RinkPalette.hairline, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) { SfIcon("arrow.left.arrow.right", 15.dp, RinkPalette.inkSecondary) }
                    }
                }
                SummaryCard(b, 1, Modifier.weight(1f))
            }
            note?.let {
                Text(it, style = RinkType.micro, color = RinkPalette.turf, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp))
            }
            if (comparison.isEmpty() && standard.isEmpty()) {
                EmptyState("No comparable stats", "chart.bar", "These players don't share any standard or advanced stats.", Modifier.padding(vertical = 24.dp))
            } else {
                if (standard.isNotEmpty()) StandardCard(a, b, standard)
                MetricCategory.entries.forEach { category ->
                    val items = comparison.filter { it.second == category }
                    if (items.isNotEmpty()) CategoryCard(a, b, category, items)
                }
            }
        }
    }

    if (store.isPro) content(true)
    else Box(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        Box(Modifier.fillMaxSize().gateBlur()) { content(false) }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to RinkPalette.canvas.copy(alpha = 0.9f))))
        Column(
            Modifier.align(Alignment.BottomCenter).padding(bottomBarPadding(8.dp + 88.dp)).padding(horizontal = 12.dp)
                .shadow(12.dp, RoundedCornerShape(RinkGeo.radiusCard), ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f))
                .clip(RoundedCornerShape(RinkGeo.radiusCard)).background(RinkPalette.surface)
                .padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SfIcon("crown.fill", 26.dp, CrownYellow)
            Text("Find the Edge", style = RinkType.cardTitle, color = RinkPalette.ink)
            Text(
                "StatScout+ unlocks side-by-side player comparisons across every metric. See who leads in ixG, xGF%, GSAx, and more.",
                style = RinkType.small,
                color = RinkPalette.inkSecondary,
                textAlign = TextAlign.Center,
            )
            Box(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(RinkPalette.turf)
                    .clickable { actions.openTrialPitch(PaywallTrigger.PlayerComparison) }.testTag("compareUnlock"),
                contentAlignment = Alignment.Center,
            ) { Text(store.paywallBlurCTA, style = RinkType.bodyBold, color = Color.White) }
            store.paywallBlurSubtext?.let { Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary, textAlign = TextAlign.Center) }
        }
    }

    StatScoutSheet(picker != null && catalog != null, { picker = null }) {
        val target = picker ?: return@StatScoutSheet
        val side = if (target == 0) a else b
        val other = if (target == 0) b else a
        PlayerPickerSheet(
            players = catalog!!.roster(side.season ?: 0, side.seasonPhase).filter {
                (it.playerId != other.playerId || it.season != other.season || it.seasonPhase != other.seasonPhase) && it.canCompareHeadToHead(other)
            },
            title = side.season?.let { "Select Player · " + SeasonLabel.display(it) } ?: "Select Player",
            season = side.season,
            isLoading = catalog.isLoadingHistory(),
            onCancel = { picker = null },
        ) { selected ->
            picker = null
            note = null
            if (target == 0) overrideA = selected else overrideB = selected
        }
    }
}

/** A season pill that shrinks rather than widening a half-width column. */
@Composable
private fun CompressibleChip(title: String) {
    Row(
        Modifier.fillMaxWidth().height(32.dp).clip(CircleShape).background(RinkPalette.surface).border(0.5.dp, RinkPalette.hairline, CircleShape)
            .padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FitText(title, RinkType.smallBold, RinkPalette.ink, Modifier.weight(1f, fill = false), minScale = 0.75f)
        SfIcon("chevron.down", 13.dp, RinkPalette.inkSecondary)
    }
}

private fun comparisonMetrics(a: Player, b: Player): List<Triple<String, MetricCategory, Pair<Metric?, Metric?>>> {
    val seen = HashSet<String>()
    val result = mutableListOf<Triple<String, MetricCategory, Pair<Metric?, Metric?>>>()
    for (m in a.metrics + b.metrics) {
        if (!seen.add("${m.label}|${m.category.raw}")) continue
        val left = a.metrics.firstOrNull { it.label == m.label && it.category == m.category }
        val right = b.metrics.firstOrNull { it.label == m.label && it.category == m.category }
        result += Triple(m.label, m.category, left to right)
    }
    return result.sortedWith { x, y ->
        if (x.second == y.second) {
            if (x.second.sortMetrics(x.first, y.first)) -1 else if (x.second.sortMetrics(y.first, x.first)) 1 else 0
        } else x.second.ordinal.compareTo(y.second.ordinal)
    }
}

@Composable
private fun StandardCard(a: Player, b: Player, rows: List<Triple<String, String?, String?>>) {
    Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().rinkCard()) {
        RinkSectionBar("SEASON TOTALS")
        Row(
            Modifier.fillMaxWidth().height(RinkGeo.rowHeightHeader).background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("STAT", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(82.dp))
            Text(lastName(a), style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            Text(lastName(b), style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
        }
        rows.forEachIndexed { index, (label, left, right) ->
            val winner = StandardStatSemantics.winner(label, left, right)
            val spoken = buildString {
                append("$label: ${a.name} ${left ?: "no data"}, ${b.name} ${right ?: "no data"}")
                if (winner == StandardStatSemantics.Winner.LEFT) append(", ${a.name} leads")
                if (winner == StandardStatSemantics.Winner.RIGHT) append(", ${b.name} leads")
            }
            Row(
                Modifier.fillMaxWidth().height(RinkGeo.rowHeight).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .bottomHairline().padding(horizontal = RinkGeo.padInline).clearAndSetSemantics { contentDescription = spoken },
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, style = RinkType.smallBold, color = RinkPalette.ink, modifier = Modifier.width(82.dp))
                AggregateValue(left, winner == StandardStatSemantics.Winner.LEFT, Modifier.weight(1f))
                AggregateValue(right, winner == StandardStatSemantics.Winner.RIGHT, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun AggregateValue(value: String?, isWinner: Boolean, modifier: Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        if (isWinner) SfIcon("trophy.fill", 11.dp, CrownYellow)
        Text(
            value ?: "-",
            style = RinkType.statMed,
            color = when {
                value == null -> RinkPalette.inkTertiary
                isWinner -> RinkPalette.turf
                else -> RinkPalette.inkSecondary
            },
        )
    }
}

@Composable
private fun CategoryCard(a: Player, b: Player, category: MetricCategory, items: List<Triple<String, MetricCategory, Pair<Metric?, Metric?>>>) {
    Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().rinkCard()) {
        RinkSectionBar(category.raw.uppercase())
        Row(
            Modifier.fillMaxWidth().height(RinkGeo.rowHeightHeader).background(RinkPalette.surfaceAlt).bottomHairline()
                .padding(horizontal = RinkGeo.padInline),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("METRIC", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(72.dp))
            Text(lastName(a), style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            Text(lastName(b), style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
        }
        items.forEachIndexed { index, (label, _, pair) ->
            Row(
                Modifier.fillMaxWidth().height(60.dp).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .bottomHairline().padding(horizontal = RinkGeo.padInline),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Multi-word labels wrap at a space instead of shrinking; one word shrinks to fit.
                if (label.contains(" ")) {
                    Text(label, style = RinkType.smallBold, color = RinkPalette.ink, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(72.dp))
                } else {
                    FitText(label, RinkType.smallBold, RinkPalette.ink, Modifier.width(72.dp), minScale = 0.7f)
                }
                MetricValueCell(pair.first, pair.second, Modifier.weight(1f))
                MetricValueCell(pair.second, pair.first, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MetricValueCell(metric: Metric?, other: Metric?, modifier: Modifier) {
    if (metric == null || (metric.percentile <= 0 && metric.value.isEmpty())) {
        Text("-", style = RinkType.statSmall, color = RinkPalette.inkTertiary, modifier = modifier, textAlign = TextAlign.Center)
        return
    }
    val hasValue = metric.value.isNotEmpty()
    val comparable = other?.let { it.percentile > 0 || it.value.isNotEmpty() } ?: false
    val isWinner = comparable && other != null && metricBeats(metric, other)
    Column(
        modifier.clearAndSetSemantics {
            contentDescription = if (hasValue) "${metric.value}, ${metric.percentile.ordinal} percentile" else "${metric.percentile.ordinal} percentile"
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (isWinner) SfIcon("trophy.fill", 12.dp, CrownYellow)
            FitText(if (hasValue) metric.value else "${metric.percentile}", RinkType.statMed, RinkPalette.textColor(metric.percentile), minScale = 0.7f)
        }
        Text(if (hasValue) "" else "PERCENTILE", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.height(10.dp))
        PercentileBarMini(metric.percentile, Modifier.widthIn(max = 60.dp).fillMaxWidth(), height = 5.dp)
    }
}

/** A searchable player list in a sheet; the profile's and Compare's pickers are the same control. */
@Composable
fun PlayerPickerSheet(
    players: List<Player>,
    title: String,
    season: Int? = null,
    isLoading: Boolean = false,
    onCancel: () -> Unit,
    onSelect: (Player) -> Unit,
) {
    var searchText by remember { mutableStateOf("") }
    val filtered = if (searchText.isEmpty()) players else players.filter {
        it.name.searchMatches(searchText) || it.team.searchMatches(searchText)
    }
    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        RinkTopBar(title = title, leading = { TextAction("Cancel", RinkType.body, Color.White, onCancel) })
        SearchField(searchText, { searchText = it }, Modifier.padding(12.dp), prompt = "Search players")
        if (filtered.isEmpty()) {
            EmptyState(
                if (isLoading) "Loading players…" else "No players",
                "person.slash",
                when {
                    isLoading -> "Pulling the ${season?.let(SeasonLabel::display) ?: ""} roster."
                    searchText.isNotEmpty() -> "Nobody matches “$searchText”."
                    season != null -> "No player data for the ${SeasonLabel.display(season)} season."
                    else -> null
                },
            )
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                items(filtered, key = { it.id }) { player ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 56.dp).background(RinkPalette.surface).bottomHairline()
                            .clickable { onSelect(player) }.padding(horizontal = 16.dp, vertical = 6.dp)
                            .testTag("pickerRow"),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        PlayerHeadshot(player.team, player.initials, 36.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(player.name, style = RinkType.bodyBold, color = RinkPalette.ink)
                            Text("${player.team} · ${player.displayPosition}", style = RinkType.small, color = RinkPalette.inkTertiary)
                        }
                    }
                }
                item { Spacer(Modifier.height(24.dp)) }
            }
        }
    }
}
