package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.DateText
import com.jackwallner.hockey.model.GameDay
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.TrendMetric
import com.jackwallner.hockey.model.TrendSide
import com.jackwallner.hockey.model.TrendWindow
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.ui.HomeTopBar
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.SeasonPhaseNavPillFor
import com.jackwallner.hockey.ui.components.BlurGateUnlock
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.DataFreshnessView
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.RinkTabs
import com.jackwallner.hockey.ui.components.PlayerHeadshot
import com.jackwallner.hockey.ui.components.RefreshableBox
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatOption
import com.jackwallner.hockey.ui.components.StatPickerMenu
import com.jackwallner.hockey.ui.components.TrendArrow
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.cardSlice
import com.jackwallner.hockey.ui.components.gateBlur
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.launch

/**
 * League-wide recent form, ranked by change rather than by level: THEN to NOW
 * and the delta. Free users see the real leader, then the wall.
 */
@Composable
fun TrendsScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    var showingCold by remember { mutableStateOf(false) }
    var side by remember { mutableStateOf(TrendSide.FORWARD) }
    var metric by remember { mutableStateOf(TrendMetric.skaterAdvanced[0]) }
    // A recent-seasons board: it opens on the live season whatever Stats points at.
    var selectedSeason by remember { mutableStateOf(vm.recentFormSeason) }
    var selectedPhase by remember { mutableStateOf(vm.selectedPhase) }

    LaunchedEffect(side) { metric = (TrendMetric.advanced(side) + TrendMetric.standard(side))[0] }
    LaunchedEffect(vm.recentFormSeason) { selectedSeason = vm.recentFormSeason }
    LaunchedEffect(isActive, vm.recentWindow, selectedSeason, selectedPhase, vm.freshnessRevision) {
        if (isActive) vm.loadRecentFormIfNeeded(season = selectedSeason, phase = selectedPhase)
    }

    val forms = vm.recentFormRows(vm.recentWindow, side.playerType, selectedSeason, selectedPhase)
    val roster = remember(vm.playerHistories, selectedSeason, selectedPhase) {
        vm.players(selectedSeason, selectedPhase).associateBy { it.playerId }
    }
    // Opening night of the season and phase on the board, from the live schedule; null for an older season.
    val openingDay: Instant? = if (selectedSeason != vm.freeSeason) null else vm.games
        .filter { it.seasonPhase == selectedPhase }
        .minOfOrNull { GameDay.day(it) }
        ?.atStartOfDay(ZoneId.systemDefault())?.toInstant()
    // Falling numbers are the improvement for goals against average.
    fun improvement(form: RecentForm): Double? = form.delta[metric.key]?.let { if (metric.lowerIsBetter) -it else it }
    // No prior window yet anywhere on the board: rank the current window by level instead.
    val isEarlySeason = forms.isNotEmpty() && forms.none { it.priorMetrics[metric.key] != null }
    val earlyRanked = forms.filter { it.metrics[metric.key] != null && !it.isSmallSample(1) }
        .sortedWith { a, b ->
            val x = a.metrics[metric.key] ?: 0.0
            val y = b.metrics[metric.key] ?: 0.0
            if (metric.lowerIsBetter) x.compareTo(y) else y.compareTo(x)
        }
    val earlyTitle = "${side.label.uppercase()} · ${(forms.firstNotNullOfOrNull { it.weekRangeLabel(openingDay) } ?: "This season").uppercase()} LEADERS"
    // Only movement in the board's direction is listed, so Heating up never ends in a run of fallers.
    val ranked = forms.filter { form ->
        val change = improvement(form)
        !form.isSmallSample && change != null && (if (showingCold) change < 0 else change > 0)
    }
        .sortedWith { a, b ->
            val x = improvement(a) ?: 0.0
            val y = improvement(b) ?: 0.0
            if (showingCold) x.compareTo(y) else y.compareTo(x)
        }
    val boardTitle = "${side.label.uppercase()} · ${if (showingCold) "COOLING OFF" else "HEATING UP"}"
    val through = vm.recentFormAsOf(vm.recentWindow, selectedSeason, selectedPhase)?.let { "Through ${DateText.gameDay(it)}" }

    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        HomeTopBar(leading = {
            // Two seasons, not the full menu: older ones have no recent-form rows to rank.
            SeasonPhaseNavPillFor(
                seasons = vm.recentFormSeasons,
                selectedSeason = selectedSeason,
                selectedPhase = selectedPhase,
                onSelectSeason = { season ->
                    if (vm.supportsRecentForm(season)) {
                        if (vm.isSeasonLocked(season)) actions.openTrialPitch(PaywallTrigger.LockedSeason(season)) else selectedSeason = season
                    }
                },
                onSelectPhase = { selectedPhase = it },
            )
        })
        val header = @Composable {
            Column {
                RinkTabs(
                    TrendSide.entries.map { it.label },
                    side.label,
                    { label -> TrendSide.entries.firstOrNull { it.label == label }?.let { side = it } },
                    Modifier.padding(top = 8.dp).semantics { contentDescription = "Position" },
                )
                Column(Modifier.padding(horizontal = 12.dp).padding(top = RinkGeo.controlRowGap - 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StatPickerMenu(
                            activeLabel = metric.label,
                            advanced = TrendMetric.advanced(side).map { StatOption(it.key, it.label, it.key == metric.key) },
                            standard = TrendMetric.standard(side).map { StatOption(it.key, it.label, it.key == metric.key) },
                            onSelectAdvanced = { o -> TrendMetric.advanced(side).firstOrNull { it.key == o.id }?.let { metric = it } },
                            onSelectStandard = { o -> TrendMetric.standard(side).firstOrNull { it.key == o.id }?.let { metric = it } },
                        )
                        Spacer(Modifier.weight(1f))
                        through?.let { Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary) }
                    }
                    if (!isEarlySeason) {
                        RinkSegmented(
                            listOf(Segment(false, "Heating up", icon = "flame.fill"), Segment(true, "Cooling off", icon = "snowflake")),
                            showingCold,
                            { showingCold = it },
                            selectedFill = { if (it) RinkPalette.performanceLow else RinkPalette.performanceHigh },
                        )
                    }
                    RinkSegmented(TrendWindow.entries.map { Segment(it, it.segmentLabel) }, vm.recentWindow, { vm.recentWindow = it })
                    Text(
                        if (isEarlySeason) "Too early for movement: a ${vm.recentWindow.value}-week comparison needs ${vm.recentWindow.value * 2} weeks of games. Until then, the best of the season so far."
                        else "Weeks of games, compared with the same span before them. Players inactive for the current span are excluded.",
                        style = RinkType.micro,
                        color = RinkPalette.inkTertiary,
                    )
                }
            }
        }

        if (store.isPro) {
            // Rows scroll under this block; the rule says where it ends.
            Box(Modifier.fillMaxWidth().bottomHairline(RinkPalette.divider).padding(bottom = 8.dp)) { header() }
            RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
                    item { DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 6.dp), season = selectedSeason, phase = selectedPhase) }
                    when {
                        vm.isRecentFormLoading && forms.isEmpty() -> item {
                            Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = RinkPalette.inkTertiary) }
                        }
                        vm.recentFormError != null && forms.isEmpty() -> item {
                            val scope = rememberCoroutineScope()
                            EmptyState("Couldn't load recent form", "exclamationmark.triangle", vm.recentFormError, Modifier.padding(vertical = 16.dp), "Try Again") {
                                scope.launch { vm.reloadRecentForm(season = selectedSeason, phase = selectedPhase) }
                            }
                        }
                        isEarlySeason && earlyRanked.isNotEmpty() -> {
                            item { Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).cardSlice(true, false)) { RinkSectionBar(earlyTitle) } }
                            val rows = earlyRanked.take(50)
                            itemsIndexed(rows, key = { _, f -> f.id }) { index, form ->
                                Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == rows.lastIndex)) {
                                    EarlyRow(form, index + 1, index, metric, roster[form.playerId])
                                }
                            }
                        }
                        ranked.isEmpty() -> item {
                            EmptyState(
                                "No movement to rank yet",
                                "chart.line.flattrend.xyaxis",
                                if (forms.any { it.priorMetrics[metric.key] != null }) "Nobody's ${metric.label} is ${if (showingCold) "falling" else "rising"} over this window. Try another stat or window."
                                else "${metric.label} doesn't have a prior window to compare against yet. Try another stat or a shorter window.",
                                Modifier.padding(vertical = 16.dp),
                            )
                        }
                        else -> {
                            item { Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).cardSlice(true, false)) { RinkSectionBar(boardTitle) } }
                            val rows = ranked.take(50)
                            itemsIndexed(rows, key = { _, f -> f.id }) { index, form ->
                                Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == rows.lastIndex)) {
                                    MoveRow(form, index + 1, index, metric, roster[form.playerId], openingDay)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 6.dp), season = selectedSeason, phase = selectedPhase)
            header()
            // The locked board does not scroll: there is nothing below the fold to scroll to. It ends
            // above the floating tab bar (78 dp with its margin), or "See all plans" sits under it on 16:9 phones.
            Column(Modifier.weight(1f).padding(horizontal = 12.dp).padding(top = 12.dp).padding(bottom = bottomBarPadding(88.dp).calculateBottomPadding()).fillMaxWidth().rinkCard()) {
                RinkSectionBar(if (isEarlySeason) earlyTitle else boardTitle)
                when {
                    isEarlySeason && earlyRanked.isNotEmpty() -> earlyRanked.first().let { EarlyRow(it, 1, 0, metric, roster[it.playerId]) }
                    ranked.isNotEmpty() -> ranked.first().let { MoveRow(it, 1, 0, metric, roster[it.playerId], openingDay) }
                    else -> Row(
                        Modifier.fillMaxWidth().height(RinkGeo.rowHeight).background(RinkPalette.surface).bottomHairline().padding(horizontal = RinkGeo.padInline),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (vm.isRecentFormLoading) CircularProgressIndicator(Modifier.size(14.dp), color = RinkPalette.inkTertiary, strokeWidth = 2.dp)
                        Text(if (vm.isRecentFormLoading) "Loading the board…" else "No movement to rank yet", style = RinkType.small, color = RinkPalette.inkTertiary)
                    }
                }
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().clipToBounds()) {
                    // Everything under row one is invented: blur is not a security boundary.
                    Column(Modifier.gateBlur()) {
                        teaserRows(vm, metric, showingCold, selectedSeason, selectedPhase, side).drop(1).forEachIndexed { index, teaser ->
                            TeaserRowView(teaser, index + 1, metric, vm.recentWindow.value)
                        }
                    }
                    BlurGateUnlock(
                        if (isEarlySeason) "See the full board: every player's last ${vm.recentWindow.value} weeks at every position, with movement once two windows of games exist"
                        else "See the full board: every position ranked by how far they've moved",
                        PaywallTrigger.RecentForm,
                        // Natural height, pinned to the bottom: on a short screen the fade clips at the
                        // top, never the CTA, disclosure or "See all plans" at the bottom.
                        Modifier.align(Alignment.BottomCenter).wrapContentHeight(Alignment.Bottom, unbounded = true),
                        compact = maxHeight < 260.dp,
                    )
                }
            }
        }
    }
}

/** A level, not a change: the value and the volume behind it. */
@Composable
private fun EarlyRow(form: RecentForm, rank: Int, index: Int, metric: TrendMetric, player: Player?) {
    val navigator = LocalNavigator.current
    val value = form.metrics[metric.key]?.let(metric::format) ?: "-"
    Row(
        Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt).bottomHairline()
            .then(if (player != null) Modifier.combinedClickable(onClick = { navigator.push(Route.PlayerProfile(player)) }) else Modifier)
            .padding(horizontal = RinkGeo.padInline)
            .clearAndSetSemantics { contentDescription = "$rank. ${player?.name ?: "Player"}, ${metric.label} $value, ${volumeText(form)}" },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("$rank", style = RinkType.statSmall, color = RinkPalette.inkSecondary, modifier = Modifier.width(26.dp))
        PlayerHeadshot(player?.team ?: form.team ?: "", player?.initials ?: "-", 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(player?.name ?: "Player ${form.playerId}", style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1)
            Text("${displayTeamAbbr(player?.team ?: form.team ?: "")} · ${volumeText(form)}", style = RinkType.micro, color = RinkPalette.inkTertiary, maxLines = 1)
        }
        Text(value, style = RinkType.statMed, color = RinkPalette.turf, modifier = Modifier.width(72.dp), textAlign = TextAlign.End)
    }
}

private fun volumeText(form: RecentForm): String {
    val games = if (form.games == 1) "1 game" else "${form.games} games"
    if (form.playerType == "g") return "$games · ${form.touches} SA"
    return "$games · ${form.plays} min"
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MoveRow(form: RecentForm, rank: Int?, index: Int, metric: TrendMetric, player: Player?, openingDay: Instant? = null) {
    val navigator = LocalNavigator.current
    val favorites = LocalGraph.current.favorites
    var menu by remember { mutableStateOf(false) }
    val delta = form.delta[metric.key] ?: 0.0
    val now = form.metrics[metric.key]
    val then = form.priorMetrics[metric.key]
    Box {
        Row(
            Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt).bottomHairline()
                .combinedClickable(onClick = { player?.let { navigator.push(Route.PlayerProfile(it)) } }, onLongClick = { menu = true })
                .padding(horizontal = RinkGeo.padInline)
                .testTag("trendRow"),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            rank?.let { Text("$it", style = RinkType.statSmall, color = RinkPalette.inkSecondary, modifier = Modifier.width(26.dp)) }
            PlayerHeadshot(player?.team ?: form.team ?: "", player?.initials ?: "-", 34.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(player?.name ?: "Player ${form.playerId}", style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1)
                    if (favorites.isFavorite(form.playerId)) SfIcon("star.fill", 11.dp, CrownYellow)
                }
                // THEN to NOW, plus the dates it covers: "Sep 24 - Oct 7" says both how long and when.
                if (then != null && now != null) {
                    FitText(
                        listOf("${metric.format(then)} → ${metric.format(now)}", form.weekRangeLabel(openingDay) ?: "${form.games} GP").joinToString(" · "),
                        RinkType.micro,
                        RinkPalette.inkTertiary,
                        minScale = 0.85f,
                    )
                }
            }
            Box(Modifier.width(56.dp), contentAlignment = Alignment.CenterEnd) { TrendArrow(delta, metric.decimals, metric.lowerIsBetter) }
        }
        DropdownMenu(menu, { menu = false }, containerColor = RinkPalette.surface) {
            val following = favorites.isFavorite(form.playerId)
            DropdownMenuItem(
                text = { Text(if (following) "Unfollow" else "Follow", style = RinkType.body, color = RinkPalette.ink) },
                leadingIcon = { SfIcon(if (following) "star.slash" else "star", 18.dp, RinkPalette.inkSecondary) },
                onClick = {
                    menu = false
                    favorites.toggleFavorite(form.playerId)
                },
            )
        }
    }
}

private data class TeaserRow(val name: String, val team: String, val initials: String, val then: Double, val now: Double)

@Composable
private fun TeaserRowView(teaser: TeaserRow, index: Int, metric: TrendMetric, windowWeeks: Int) {
    Row(
        Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("${index + 1}", style = RinkType.statSmall, color = RinkPalette.inkSecondary, modifier = Modifier.width(26.dp))
        PlayerHeadshot(teaser.team, teaser.initials, 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(teaser.name, style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1)
            Text("${metric.format(teaser.then)} → ${metric.format(teaser.now)} · Last $windowWeeks weeks", style = RinkType.micro, color = RinkPalette.inkTertiary, maxLines = 1)
        }
        Box(Modifier.width(56.dp), contentAlignment = Alignment.CenterEnd) { TrendArrow(teaser.now - teaser.then, metric.decimals, metric.lowerIsBetter) }
    }
}

/**
 * The invented rows behind the gate: real faces from the group's roster, ordered
 * and valued by a seed built from every control, so the board visibly redraws
 * when a picker moves.
 */
private fun teaserRows(vm: DashboardViewModel, metric: TrendMetric, showingCold: Boolean, season: Int, phase: SeasonPhase, side: TrendSide): List<TeaserRow> {
    val count = 18
    val seed = "${metric.key}-$showingCold-${vm.recentWindow.value}-$season-${phase.raw}"
    val roster = vm.players(season).filter { (it.playerType ?: "") == side.playerType }
    val names: List<Triple<String, String, String>> = if (roster.size >= count) {
        roster.map { it to stableSeed("$seed-${it.playerId}") }.sortedBy { it.second }.take(count).map { Triple(it.first.name, it.first.team, it.first.initials) }
    } else {
        listOf(
            Triple("Player One", "SEA", "PO"), Triple("Player Two", "BOS", "PT"), Triple("Player Three", "TOR", "PT"),
            Triple("Player Four", "EDM", "PF"), Triple("Player Five", "COL", "PF"), Triple("Player Six", "NYR", "PS"),
            Triple("Player Seven", "DET", "PS"), Triple("Player Eight", "VGK", "PE"), Triple("Player Nine", "FLA", "PN"),
            Triple("Player Ten", "DAL", "PT"), Triple("Player Eleven", "CAR", "PE"), Triple("Player Twelve", "MIN", "PT"),
            Triple("Player Thirteen", "WPG", "PT"), Triple("Player Fourteen", "TBL", "PF"), Triple("Player Fifteen", "VAN", "PF"),
            Triple("Player Sixteen", "PIT", "PS"), Triple("Player Seventeen", "NJD", "PS"), Triple("Player Eighteen", "LAK", "PE"),
        ).map { it to stableSeed("$seed-${it.first}") }.sortedBy { it.second }.map { it.first }
    }
    // Centre and spread the invented values on the metric's own scale: a percentage
    // reads 9%→15%, a rate 2.4→3.6 and a save percentage .901→.926.
    val (scale, spread) = when (metric.decimals) {
        0 -> 14.0 to 8.0
        2 -> 2.4 to 1.2
        3 -> 0.905 to 0.03
        else -> if (metric.unit == "%") 10.0 to 5.0 else 1.8 to 1.2
    }
    val drift = (stableSeed(seed) % 1_000) / 1_000.0
    val base = scale * (0.9 + 0.2 * drift)
    val swing = spread * (0.85 + 0.3 * drift)
    // Cooling off inverts the movement; a lower-is-better metric inverts it again.
    val sign = if (!showingCold != metric.lowerIsBetter) 1.0 else -1.0
    return names.mapIndexed { index, who ->
        val wobble = (stableSeed("$seed-${who.first}") % 100) / 100.0 * 0.03 - 0.015
        val decay = maxOf(0.15, 1.0 - index * 0.045 + wobble)
        val move = swing * decay
        val then = base - sign * move / 2
        TeaserRow(who.first, who.second, who.third, then, then + sign * move)
    }
}

/** FNV-1a with a murmur3 finalizer, identical to iOS so the same controls draw the same teaser. */
internal fun stableSeed(text: String): Int {
    var hash = 0xcbf29ce484222325uL
    text.codePoints().forEach { cp ->
        hash = (hash xor cp.toULong()) * 0x100000001b3uL
    }
    hash = hash xor (hash shr 33)
    hash *= 0xff51afd7ed558ccduL
    hash = hash xor (hash shr 33)
    return (hash % 100_003uL).toInt()
}
