package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.TeamSeasonSummary
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.util.Locale

internal data class GlanceTile(val label: String, val value: String, val rank: Int)

internal fun glanceTiles(summary: TeamSeasonSummary): List<GlanceTile> {
    fun decimal(value: Double) = String.format(Locale.US, "%.2f", value)
    fun percent(value: Double) = String.format(Locale.US, "%.1f", value * 100) + "%"
    val out = mutableListOf(
        GlanceTile("Goals for / GP", decimal(summary.goalsFor.value), summary.goalsFor.rank),
        GlanceTile("Goals against / GP", decimal(summary.goalsAgainst.value), summary.goalsAgainst.rank),
    )
    summary.powerPlay?.let { out += GlanceTile("Power play", percent(it.value), it.rank) }
    summary.penaltyKill?.let { out += GlanceTile("Penalty kill", percent(it.value), it.rank) }
    summary.expectedGoalsShare?.let { out += GlanceTile("xGF%", percent(it.value), it.rank) }
    summary.shotsFor?.let { out += GlanceTile("Shots / GP", String.format(Locale.US, "%.1f", it.value), it.rank) }
    return out
}

/**
 * The six numbers a fan checks first on a club's page, each with its league
 * rank: scoring and keeping it out, shots both ways, special teams and the
 * expected-goals share.
 */
@Composable
fun TeamSeasonGlance(viewModel: DashboardViewModel, team: String) {
    val summary = viewModel.teamSummaries[normalizedTeamAbbreviation(team)] ?: return
    val tiles = glanceTiles(summary)
    if (tiles.isEmpty()) return
    Column(Modifier.fillMaxWidth().rinkCard()) {
        RinkSectionBar("SEASON SO FAR")
        tiles.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEach { TileView(it, Modifier.weight(1f)) }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Text(
            "League rank in brackets, 1st is best. Shots, special teams and xGF% cover games with a shot breakdown.",
            style = RinkType.micro,
            color = RinkPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padCard, vertical = 8.dp),
        )
    }
}

@Composable
private fun TileView(tile: GlanceTile, modifier: Modifier = Modifier) {
    // 1st reads as the 100th percentile, 32nd as the 0th, on the app's ramp.
    val percentile = Math.round((32 - tile.rank).toDouble() / 31 * 100).toInt().coerceIn(0, 100)
    val ordinal = TeamSeasonSummary.ordinal(tile.rank)
    Column(
        modifier.padding(vertical = 10.dp).clearAndSetSemantics {
            contentDescription = "${tile.label} ${tile.value}, $ordinal in the league"
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(tile.value, style = RinkType.statMed.copy(fontFeatureSettings = "tnum"), color = RinkPalette.ink)
        FitText(tile.label, RinkType.micro, RinkPalette.inkTertiary, minScale = 0.8f, textAlign = TextAlign.Center)
        Text("($ordinal)", style = RinkType.smallBold, color = RinkPalette.textColor(percentile))
    }
}
