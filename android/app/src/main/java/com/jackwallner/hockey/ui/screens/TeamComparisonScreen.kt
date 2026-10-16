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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricKind
import com.jackwallner.hockey.model.MetricValueFormat
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.RosterAggregate
import com.jackwallner.hockey.model.StandingsRow
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.TeamSeasonSummary
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.SearchField
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.TextAction
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import com.jackwallner.hockey.ui.theme.TeamColor
import java.text.NumberFormat
import java.util.Locale

/**
 * The team chooser sheet for Compare: every club alphabetically, with search.
 *
 * Present it inside a full-height `StatScoutSheet`; it calls [onDismiss] and
 * then [onSelect] when a club is tapped, and [onDismiss] alone from Cancel.
 */
@Composable
fun CompareTeamPicker(teams: List<String>, onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    var searchText by rememberSaveable { mutableStateOf("") }
    val filteredTeams = remember(teams, searchText) {
        val sorted = teams.sortedBy { teamFullName(it) }
        if (searchText.isEmpty()) sorted
        else sorted.filter { it.contains(searchText, ignoreCase = true) || teamFullName(it).contains(searchText, ignoreCase = true) }
    }
    Column(Modifier.fillMaxSize().background(RinkPalette.canvas)) {
        Box(Modifier.fillMaxWidth().height(52.dp)) {
            TextAction("Cancel", RinkType.body, RinkPalette.turf, onDismiss, Modifier.align(Alignment.CenterStart).padding(start = 4.dp).testTag("pickerCancel"))
            Text("Select Team", style = RinkType.cardTitle, color = RinkPalette.ink, modifier = Modifier.align(Alignment.Center))
        }
        SearchField(searchText, { searchText = it }, Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp), prompt = "Search teams")
        LazyColumn(Modifier.fillMaxSize()) {
            items(filteredTeams, key = { it }) { team ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp)
                        .background(RinkPalette.surface)
                        .bottomHairline(RinkPalette.divider)
                        .clickable {
                            onDismiss()
                            onSelect(team)
                        }
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .testTag("pickTeam_$team"),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
                        Text(displayTeamAbbr(team), style = RinkType.micro, color = Color.White)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(teamFullName(team), style = RinkType.bodyBold, color = RinkPalette.ink)
                        Text(displayTeamAbbr(team), style = RinkType.small, color = RinkPalette.inkTertiary)
                    }
                }
            }
        }
    }
}

private data class StatRow(
    val id: String,
    val label: String,
    val aText: String,
    val bText: String,
    /** Comparison values, sign-flipped for lower-is-better metrics so the trophy always goes to the greater number. Null means "show the value, don't declare a winner". */
    val aValue: Double?,
    val bValue: Double?,
)

private data class StatGroup(val title: String, val rows: List<StatRow>)

/**
 * Roster aggregates that are context rather than a verdict. None today: every
 * hockey metric pools into a number where more (or less, per the registry) is
 * better. Kept so a future share metric can opt out of the trophy.
 */
private val DESCRIPTIVE_ONLY_LABELS = RosterAggregate.descriptiveOnlyLabels

/** A club's own live regular season: its standings line, season summary and power rating. */
private data class ClubSeason(val standing: StandingsRow?, val summary: TeamSeasonSummary?, val rating: TeamRating?)

/**
 * Two clubs side by side: advanced rows from `metrics`, standard rows from
 * `standard_stats`, interleaved category by category. Each club carries its own
 * season and phase, as on the Compare tab.
 */
@Composable
fun TeamComparisonScreen(route: Route.TeamComparison) {
    val vm = LocalGraph.current.dashboard
    val a = route.teamA
    val b = route.teamB
    val sA = route.seasonA
    val pA = route.phaseA
    val sB = route.seasonB
    val pB = route.phaseB
    val rosterA = vm.players(sA, pA).filter { normalizedTeamAbbreviation(it.team) == normalizedTeamAbbreviation(a) }
    val rosterB = vm.players(sB, pB).filter { normalizedTeamAbbreviation(it.team) == normalizedTeamAbbreviation(b) }
    // The club's own numbers exist only for the live regular season.
    fun clubSeason(team: String, season: Int, phase: SeasonPhase): ClubSeason? {
        if (season != vm.freeSeason || phase != SeasonPhase.REGULAR) return null
        val abbr = normalizedTeamAbbreviation(team)
        return ClubSeason(vm.standings[abbr], vm.teamSummaries[abbr], vm.teamRating(abbr))
    }
    val clubRows = clubRows(clubSeason(a, sA, pA), clubSeason(b, sB, pB))
    val groups = remember(rosterA, rosterB, clubRows) { statGroups(rosterA, rosterB, clubRows) }

    PushedScreen("Team Comparison") {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TeamHeader(a, rosterA.size, sA, pA, Modifier.weight(1f))
                SfIcon("arrow.left.arrow.right", 18.dp, RinkPalette.inkTertiary)
                TeamHeader(b, rosterB.size, sB, pB, Modifier.weight(1f))
            }

            if (groups.isEmpty()) {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(RinkGeo.radiusCard)).background(RinkPalette.surface).padding(vertical = 32.dp)) {
                    GamesTeamsUi.Unavailable("sum", "No aggregate stats", "Neither selected roster has standard stats for this context.")
                }
            } else {
                groups.forEach { group ->
                    Column(Modifier.fillMaxWidth().rinkCard().testTag("compareGroup")) {
                        RinkSectionBar(group.title)
                        group.rows.forEachIndexed { index, row -> StatRowView(row, index) }
                    }
                }
            }

            Text(
                (if (clubRows.isEmpty()) "" else "Team · This season is each club's own record and results; PP%, PK% and xGF% cover games with a shot breakdown. ") +
                    "The other sections sum the selected roster's player season lines. Traded players bring their full-season line, so those are roster aggregates rather than official team totals.",
                style = RinkType.micro,
                color = RinkPalette.inkTertiary,
            )
            Spacer(Modifier.padding(bottomBarPadding()))
        }
    }
}

/**
 * Advanced rows come from `metrics`, standard rows from `standard_stats`, so
 * they are built separately and interleaved category by category. Without the
 * advanced half the one screen that answers "which of these two teams is
 * better" couldn't reference a single advanced number.
 */
private fun statGroups(rosterA: List<Player>, rosterB: List<Player>, clubRows: List<StatRow>): List<StatGroup> =
    listOf(StatGroup("TEAM · THIS SEASON", clubRows)) + MetricCategory.entries.flatMap { category ->
        listOf(
            StatGroup(category.raw.uppercase() + " · ADVANCED", advancedRows(category, rosterA, rosterB)),
            StatGroup(category.raw.uppercase() + " · STANDARD", standardRows(category, rosterA, rosterB)),
        )
    }
        .map { group -> StatGroup(group.title, group.rows.filter { it.aText != "-" || it.bText != "-" }) }
        .filter { it.rows.isNotEmpty() }

/**
 * The club's own numbers, not roster sums: record, goals, special teams, xG share
 * and power rating. Only when both sides are the live regular season.
 */
private fun clubRows(a: ClubSeason?, b: ClubSeason?): List<StatRow> {
    if (a == null || b == null) return emptyList()
    fun percent(v: Double) = String.format(Locale.US, "%.1f", v * 100) + "%"
    fun decimal(v: Double) = String.format(Locale.US, "%.2f", v)
    fun row(label: String, x: Double?, y: Double?, higherIsBetter: Boolean = true, format: (Double) -> String): StatRow {
        val sign = if (higherIsBetter) 1.0 else -1.0
        return StatRow("club-$label", label, x?.let(format) ?: "-", y?.let(format) ?: "-", x?.times(sign), y?.times(sign))
    }
    val rows = mutableListOf<StatRow>()
    val sa = a.standing
    val sb = b.standing
    if (sa != null && sb != null) {
        rows += StatRow("club-record", "Record", sa.record, sb.record, sa.points.toDouble(), sb.points.toDouble())
        rows += row("P%", sa.winPercentage, sb.winPercentage) { RecentMetricKey.savePercentage(it) }
    }
    rows += row("GF/GP", a.summary?.goalsFor?.value, b.summary?.goalsFor?.value, format = ::decimal)
    rows += row("GA/GP", a.summary?.goalsAgainst?.value, b.summary?.goalsAgainst?.value, higherIsBetter = false, format = ::decimal)
    rows += row("PP%", a.summary?.powerPlay?.value, b.summary?.powerPlay?.value, format = ::percent)
    rows += row("PK%", a.summary?.penaltyKill?.value, b.summary?.penaltyKill?.value, format = ::percent)
    rows += row("xGF%", a.summary?.expectedGoalsShare?.value, b.summary?.expectedGoalsShare?.value, format = ::percent)
    rows += row("Power", a.rating?.rating, b.rating?.rating) { TeamRating.signed(it) }
    return rows
}

/** Every advanced metric that either roster has for this category, in the registry's own display order. */
private fun advancedRows(category: MetricCategory, rosterA: List<Player>, rosterB: List<Player>): List<StatRow> {
    val labels = HockeyMetricRegistry.definitions
        .filter { it.category == category && it.kind == MetricKind.ADVANCED }
        .sortedBy { it.priority }
        .map { it.label }
    return labels.mapNotNull { label ->
        val a = aggregate(label, category, rosterA)
        val b = aggregate(label, category, rosterB)
        if (a == null && b == null) return@mapNotNull null
        val format = MetricValueFormat.inferred(
            (rosterA + rosterB).mapNotNull { player -> player.metrics.firstOrNull { it.label == label && it.category == category }?.value },
        )
        // Lower-is-better metrics (GAA, xGA/60, Giveaways) must not hand the trophy
        // to the bigger number. Flipping the sign of both sides is enough.
        val higherIsBetter = HockeyMetricRegistry.definition(label, category)?.higherIsBetter ?: true
        val sign = if (higherIsBetter) 1.0 else -1.0
        // Some aggregates would describe a roster without ranking it. Null values
        // keep the row (it is genuinely interesting context) and suppress the marker.
        val comparable = label !in DESCRIPTIVE_ONLY_LABELS
        StatRow(
            id = category.raw + "-adv-" + label,
            label = label,
            aText = a?.let { format.string(it) } ?: "-",
            bText = b?.let { format.string(it) } ?: "-",
            aValue = if (comparable) a?.times(sign) else null,
            bValue = if (comparable) b?.times(sign) else null,
        )
    }
}

/** Pools one metric across a roster using the registry's aggregation rule. */
private fun aggregate(label: String, category: MetricCategory, roster: List<Player>): Double? =
    RosterAggregate.value(label, category, roster)

private fun standardRows(category: MetricCategory, rosterA: List<Player>, rosterB: List<Player>): List<StatRow> {
    val labels = when (category) {
        MetricCategory.SCORING -> listOf("P" to true, "G" to true, "A" to true, "PPP" to true, "PIM" to false)
        MetricCategory.SHOT_QUALITY -> listOf("SOG" to true)
        MetricCategory.PLAY_DRIVING -> listOf("+/-" to true, "Hits" to true, "Blk" to true)
        MetricCategory.GOALTENDING -> listOf("W" to true, "L" to false, "OT" to false, "SO" to true, "SV" to true, "SA" to true)
    }
    return labels.map { (label, higher) -> totalRow(label, rosterA, rosterB, higher) }
}

/**
 * `higherIsBetter = false` flips which side gets the trophy. Penalty minutes
 * needed it: as a plain total it handed the marker to whichever club took more
 * penalties, which is backwards.
 */
private fun totalRow(label: String, rosterA: List<Player>, rosterB: List<Player>, higherIsBetter: Boolean = true): StatRow {
    val a = total(label, rosterA)
    val b = total(label, rosterB)
    val sign = if (higherIsBetter) 1.0 else -1.0
    return StatRow(label, label, format(a, label), format(b, label), a?.times(sign), b?.times(sign))
}

private fun total(label: String, roster: List<Player>): Double? {
    val values = roster.mapNotNull { player ->
        player.standardStats?.firstOrNull { it.label == label }?.let { DashboardViewModel.rawNumeric(it.value) }
    }
    return if (values.isEmpty()) null else values.sum()
}

private fun format(value: Double?, label: String): String {
    value ?: return "-"
    return NumberFormat.getIntegerInstance(Locale.US).format(Math.round(value))
}

@Composable
private fun TeamHeader(team: String, rosterCount: Int, season: Int, phase: SeasonPhase, modifier: Modifier = Modifier) {
    Column(
        modifier.rinkCard().padding(vertical = 14.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(58.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
            Text(displayTeamAbbr(team), style = RinkType.smallBold, color = Color.White)
        }
        FitText(teamFullName(team), RinkType.bodyBold, RinkPalette.ink, minScale = 0.7f, textAlign = TextAlign.Center)
        Text(
            "$rosterCount tracked · ${SeasonLabel.display(season)} ${phase.label}",
            style = RinkType.micro,
            color = RinkPalette.inkTertiary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun StatRowView(row: StatRow, index: Int) {
    Row(
        Modifier.fillMaxWidth().height(56.dp)
            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padInline),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StatValue(row.aText, row.aValue, row.bValue, Modifier.weight(1f))
        Text(row.label, style = RinkType.smallBold, color = RinkPalette.ink, textAlign = TextAlign.Center, modifier = Modifier.width(88.dp))
        StatValue(row.bText, row.bValue, row.aValue, Modifier.weight(1f))
    }
}

@Composable
private fun StatValue(text: String, value: Double?, other: Double?, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        if (value != null && other != null && value > other) SfIcon("trophy.fill", 13.dp, CrownYellow)
        Text(
            text,
            style = RinkType.statMed,
            color = if (text == "-") RinkPalette.inkTertiary else RinkPalette.turf,
            maxLines = 1,
        )
    }
}
