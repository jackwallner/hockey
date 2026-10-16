package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.model.DateText
import com.jackwallner.hockey.model.LeagueConference
import com.jackwallner.hockey.model.LeagueDivision
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.StandingsRow
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.TeamColorDot
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType

/** Division standings as their own pushed page. */
@Composable
fun StandingsScreen() {
    val vm = LocalGraph.current.dashboard
    PushedScreen("Standings") {
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
                StandingsTable()
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/** The league ranked by power rating as its own pushed page. */
@Composable
fun PowerRankingsScreen() {
    val vm = LocalGraph.current.dashboard
    PushedScreen("Power Rankings") {
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
                PowerRankingsTable()
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/** Division standings from posted finals, East then West. */
@Composable
internal fun StandingsTable() {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    if (vm.games.isEmpty()) {
        // Before the schedule lands every club would read 0-0-0, which looks like a
        // broken table rather than one on its way.
        Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (vm.isGamesLoading || vm.gamesError == null) {
                CircularProgressIndicator(color = RinkPalette.inkTertiary)
                Text("Loading standings", style = RinkType.small, color = RinkPalette.inkSecondary)
            } else {
                GamesTeamsUi.Unavailable("wifi.slash", "Couldn't load standings", "Check your connection and pull to refresh.")
            }
        }
        return
    }
    val table = remember(vm.games) { vm.standings }
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf(LeagueConference.EAST, LeagueConference.WEST).forEach { conference ->
            Text(
                conference.label.uppercase() + "ERN CONFERENCE",
                style = RinkType.micro,
                color = RinkPalette.inkSecondary,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp).padding(top = 4.dp),
            )
            LeagueDivision.entries.filter { it.conference == conference }.forEach { division ->
                val rows = StandingsRow.ordered(division.teams.mapNotNull { table[it] })
                Column(Modifier.fillMaxWidth().rinkCard().testTag("division_${division.label}")) {
                    StandingsHeader(division.label)
                    rows.forEachIndexed { index, row ->
                        StandingsLine(
                            row,
                            Modifier
                                .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                                .clickable { navigator.push(Route.Team(row.team)) },
                        )
                    }
                }
            }
        }
        Text(
            "Ordered by points, then points percentage and goal differential, not the NHL's full tiebreakers. PTS are standings points: two for a win, one for an overtime or shootout loss.",
            style = RinkType.micro,
            color = RinkPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        )
    }
}

@Composable
private fun StandingsHeader(title: String) {
    Row(
        Modifier.fillMaxWidth().height(RinkGeo.rowHeightHeader).background(RinkPalette.surfaceAlt)
            .bottomHairline(RinkPalette.divider).padding(horizontal = RinkGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FitText(title.uppercase(), RinkType.micro, RinkPalette.inkTertiary, Modifier.weight(1f), minScale = 0.6f)
        HeaderCell("GP", 26.dp)
        HeaderCell("W-L-OTL", 56.dp)
        HeaderCell("PTS", 34.dp)
        HeaderCell("P%", 36.dp)
        HeaderCell("GF", 28.dp)
        HeaderCell("GA", 28.dp)
        HeaderCell("DIFF", 40.dp)
        HeaderCell("STRK", 36.dp)
    }
}

@Composable
private fun HeaderCell(text: String, width: Dp) {
    Text(text, style = RinkType.micro, color = RinkPalette.inkTertiary, textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(width))
}

@Composable
private fun StandingsLine(row: StandingsRow, modifier: Modifier = Modifier) {
    val played = row.games > 0
    val diff = if (row.differential > 0) "+${row.differential}" else "${row.differential}"
    val diffColor = when {
        row.differential > 0 -> RinkPalette.performanceHigh
        row.differential < 0 -> RinkPalette.performanceLow
        else -> RinkPalette.inkSecondary
    }
    val description = "${teamFullName(row.team)}, ${row.games} games, ${row.record}, ${row.points} points, goal differential ${row.differential}"
    Row(
        modifier.fillMaxWidth().height(44.dp).bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padInline)
            .clearAndSetSemantics { contentDescription = description }
            .testTag("teamRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColorDot(row.team, 10.dp)
            Text(displayTeamAbbr(row.team), style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1, softWrap = false)
        }
        NumberCell("${row.games}", 26.dp, RinkPalette.inkSecondary)
        NumberCell(row.record, 56.dp, RinkPalette.ink)
        NumberCell(if (played) "${row.points}" else "-", 34.dp, RinkPalette.ink, bold = true)
        // ".625", the way points percentage is written in hockey.
        NumberCell(if (played) RecentMetricKey.savePercentage(row.winPercentage) else "-", 36.dp, RinkPalette.inkSecondary)
        NumberCell(if (played) "${row.goalsFor}" else "-", 28.dp, RinkPalette.inkSecondary)
        NumberCell(if (played) "${row.goalsAgainst}" else "-", 28.dp, RinkPalette.inkSecondary)
        NumberCell(if (played) diff else "-", 40.dp, diffColor)
        NumberCell(row.streak ?: "-", 36.dp, RinkPalette.inkSecondary)
    }
}

@Composable
private fun NumberCell(text: String, width: Dp, color: Color, bold: Boolean = false) {
    FitText(text, if (bold) RinkType.statMed else RinkType.statSmall, color, Modifier.width(width), minScale = 0.7f, textAlign = TextAlign.End)
}

/**
 * The league ranked by power rating: what a club does minus what it allows, in
 * goals per game, adjusted for who it played.
 */
@Composable
internal fun PowerRankingsTable() {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val ratings = vm.teamRatings.values.sortedBy { it.rank }
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (ratings.isEmpty()) {
            Column(Modifier.fillMaxWidth().background(RinkPalette.surface, androidx.compose.foundation.shape.RoundedCornerShape(RinkGeo.radiusCard)).padding(vertical = 32.dp)) {
                GamesTeamsUi.Unavailable("chart.bar.xaxis", "Power ratings loading", "Ratings arrive with the next update. Pull to refresh.")
            }
        } else {
            val standings = remember(vm.games) { vm.standings }
            Column(Modifier.fillMaxWidth().rinkCard()) {
                PowerHeader()
                ratings.forEachIndexed { index, rating ->
                    PowerLine(
                        rating,
                        standings[normalizedTeamAbbreviation(rating.team)]?.record,
                        Modifier
                            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                            .clickable { navigator.push(Route.Team(rating.team)) },
                    )
                }
            }
        }
        Text(
            powerFootnote(ratings, vm.dataCoverage?.asOf),
            style = RinkType.micro,
            color = RinkPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        )
    }
}

private fun powerFootnote(ratings: List<TeamRating>, asOf: java.time.Instant?): String {
    val through = ratings.firstOrNull()?.let {
        when {
            it.throughWeek <= 0 -> "Early season: last season's ratings, regressed. "
            asOf == null -> ""
            else -> "Through ${DateText.gameDay(asOf)}. "
        }
    } ?: ""
    return through + "Goals per game better or worse than an average team on neutral ice: expected goals and actual goals for, minus against, adjusted for schedule. Early in the season last year counts as extra games of evidence. The gap between two ratings, plus about 0.2 goals for home ice, sets the win chances on the Games tab."
}

@Composable
private fun PowerHeader() {
    Row(
        Modifier.fillMaxWidth().height(RinkGeo.rowHeightHeader).background(RinkPalette.surfaceAlt)
            .bottomHairline(RinkPalette.divider).padding(horizontal = RinkGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("#", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.width(28.dp))
        Text("TEAM", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f))
        HeaderCell("OFF", 48.dp)
        HeaderCell("DEF", 48.dp)
        HeaderCell("RATING", 60.dp)
    }
}

@Composable
private fun PowerLine(rating: TeamRating, record: String?, modifier: Modifier = Modifier) {
    val description = "${rating.rank}. ${teamFullName(rating.team)}, rating ${TeamRating.signed(rating.rating)}, " +
        "offense ${TeamRating.signed(rating.offense)}, defense ${TeamRating.signed(rating.defense)}"
    Row(
        modifier.fillMaxWidth().height(RinkGeo.rowHeight).bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padInline)
            .clearAndSetSemantics { contentDescription = description }
            .testTag("powerRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("${rating.rank}", style = RinkType.statSmall, color = RinkPalette.inkSecondary, modifier = Modifier.width(28.dp))
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColorDot(rating.team, 10.dp)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                FitText(teamFullName(rating.team), RinkType.bodyBold, RinkPalette.ink, minScale = 0.8f)
                record?.let { Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary) }
            }
        }
        Text(TeamRating.signed(rating.offense), style = RinkType.statSmall, color = tint(rating.offense, 0.1), textAlign = TextAlign.End, modifier = Modifier.width(48.dp))
        Text(TeamRating.signed(rating.defense), style = RinkType.statSmall, color = tint(rating.defense, 0.1), textAlign = TextAlign.End, modifier = Modifier.width(48.dp))
        Text(TeamRating.signed(rating.rating), style = RinkType.statMed, color = tint(rating.rating, 0.2), textAlign = TextAlign.End, modifier = Modifier.width(60.dp))
    }
}

/** Ratings are goals a game: a fifth of a goal is a clearly good or bad club, a tenth on either side of the puck. */
private fun tint(value: Double, threshold: Double): Color = when {
    value >= threshold -> RinkPalette.performanceHigh
    value <= -threshold -> RinkPalette.performanceLow
    else -> RinkPalette.inkSecondary
}
