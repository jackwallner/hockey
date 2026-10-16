package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.BuildConfig
import com.jackwallner.hockey.data.StoreLinks
import com.jackwallner.hockey.model.DateText
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.searchMatches
import com.jackwallner.hockey.ui.LocalAppActions
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.EmptyState
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.Hairline
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.SearchField
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.openMail
import com.jackwallner.hockey.ui.openPlayListing
import com.jackwallner.hockey.ui.openUrl
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch

private val LONG_DATE = DateTimeFormatter.ofPattern("MMMM d, yyyy 'at' h:mm a", Locale.US)

/**
 * Settings, a place in the app rather than a modal. Rate and Send Feedback are
 * separate rows with no question in front of either: Google forbids gating the
 * Play review behind one.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showReviewerCode by remember { mutableStateOf(false) }
    val freshness = vm.freshnessForDisplay
    val coverage = freshness?.coverage ?: vm.dataCoverage
    val gamesThrough = coverage?.let { c ->
        val stamp = DateText.gameDay(c.asOf)
        if (c.phase == SeasonPhase.PLAYOFFS) "$stamp (playoffs)" else stamp
    } ?: "-"
    val checked = (freshness?.checkedAt ?: vm.lastUpdated)?.let { LONG_DATE.format(it.atZone(ZoneId.systemDefault())) } ?: "-"
    val sourcePublished = freshness?.sourcePublishedAt?.let { LONG_DATE.format(it.atZone(ZoneId.systemDefault())) }

    PushedScreen("Settings") {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 12.dp).padding(bottomBarPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Card("STATSCOUT+") {
                Row(Modifier.padding(RinkGeo.padCard), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfIcon("crown.fill", 26.dp, if (store.isPro) CrownYellow else RinkPalette.inkTertiary)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(if (store.isPro) "StatScout+ Unlocked" else "Free Version", style = RinkType.bodyBold, color = RinkPalette.ink)
                        Text(
                            if (store.isPro) "All StatScout+ features are active." else "Unlock Trends, recent form, head-to-head and every season back to 2008-09.",
                            style = RinkType.small,
                            color = RinkPalette.inkSecondary,
                        )
                    }
                    if (!store.isPro) {
                        Box(
                            Modifier.heightIn(min = 36.dp).clip(RoundedCornerShape(8.dp)).background(RinkPalette.turf)
                                .clickable { actions.openPaywall(store.defaultUpgradeTrigger) }.padding(horizontal = 12.dp, vertical = 8.dp)
                                .testTag("settingsUpgrade"),
                            contentAlignment = Alignment.Center,
                        ) { Text(if (store.isLapsed) "Renew" else store.upgradeCTALabel, style = RinkType.smallBold, color = Color.White) }
                    }
                }
                Hairline()
                LinkRow("arrow.clockwise", "Restore Purchases") { scope.launch { store.restorePurchases() } }
                store.activeProductId?.let { productId ->
                    Hairline()
                    LinkRow("slider.horizontal.3", "Manage Subscription") { context.openUrl(StoreLinks.manageSubscriptionURL(productId)) }
                }
                store.lastError?.let {
                    Hairline()
                    Text(it, style = RinkType.small, color = RinkPalette.turf, modifier = Modifier.fillMaxWidth().padding(RinkGeo.padCard))
                }
            }
            Card("REFERENCE") {
                Row(Modifier.clickable { navigator.push(Route.Glossary) }) {
                    InfoRow("text.book.closed.fill", "Stat Glossary", "Definitions and formulas for every stat in StatScout.")
                }
            }
            Card("SUPPORT & PRIVACY") {
                Row(Modifier.clickable {
                    graph.review.markOpenedWriteReview()
                    context.openPlayListing()
                }.testTag("rateRow")) { InfoRow("star.fill", "Rate StatScout", "Opens Google Play to write a review.") }
                Hairline()
                Row(Modifier.clickable {
                    graph.review.markFeedbackSent()
                    // No mail app: the support page carries the same address.
                    if (!context.openMail(StoreLinks.feedbackMail("StatScout feedback"))) context.openUrl(StoreLinks.SUPPORT_URL)
                }.testTag("feedbackRow")) { InfoRow("envelope.fill", "Send Feedback", StoreLinks.FEEDBACK_EMAIL) }
                Hairline()
                Row(Modifier.clickable { context.openUrl(StoreLinks.PRIVACY_URL) }) { InfoRow("shield.lefthalf.filled", "Privacy Policy", "No ads or tracking.") }
            }
            Card("DATA") {
                InfoRow("arrow.triangle.2.circlepath", "Data Updates", "Checks for new NHL numbers after every night's games.")
                Hairline()
                InfoRow("calendar.badge.clock", "Games Through", gamesThrough)
                Hairline()
                InfoRow("clock.arrow.circlepath", "Last Checked", checked)
                sourcePublished?.let {
                    Hairline()
                    InfoRow("cloud.sun.fill", "Source Published", it)
                }
            }
            Card("STATSCOUT") {
                Row(Modifier.padding(RinkGeo.padCard), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfIcon("hockey.puck.fill", 26.dp, RinkPalette.turf)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Hockey StatScout", style = RinkType.cardTitle, color = RinkPalette.ink)
                        Text("Every NHL skater and goalie ranked by expected goals, against their own position.", style = RinkType.small, color = RinkPalette.inkSecondary)
                    }
                }
            }
            Card("VERSION") {
                // Long press opens the private reviewer access for Google Play's review team.
                Row(
                    Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { showReviewerCode = true }).padding(RinkGeo.padCard)
                        .testTag("versionRow"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("App Version", style = RinkType.bodyBold, color = RinkPalette.ink, modifier = Modifier.weight(1f))
                    Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = RinkType.statSmall, color = RinkPalette.inkSecondary)
                }
            }
            Card("DISCLAIMER") {
                Text(
                    "Not affiliated with, endorsed by, or sponsored by the National Hockey League, its teams, the NHLPA or MoneyPuck. Expected goals and shot data from MoneyPuck.com. Team names and abbreviations are used for identification only.",
                    style = RinkType.small,
                    color = RinkPalette.inkSecondary,
                    modifier = Modifier.fillMaxWidth().padding(RinkGeo.padCard),
                )
            }
        }
    }
    if (showReviewerCode) ReviewerCodeDialog { showReviewerCode = false }
}

@Composable
private fun Card(title: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().rinkCard()) {
        RinkSectionBar(title)
        content()
    }
}

@Composable
private fun InfoRow(icon: String, title: String, subtitle: String) {
    Row(Modifier.fillMaxWidth().padding(RinkGeo.padCard), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { SfIcon(icon, 24.dp, RinkPalette.turf) }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = RinkType.bodyBold, color = RinkPalette.ink)
            Text(subtitle, style = RinkType.small, color = RinkPalette.inkSecondary)
        }
    }
}

@Composable
private fun LinkRow(icon: String, title: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onClick).padding(RinkGeo.padCard),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfIcon(icon, 14.dp, RinkPalette.linkBlue)
        Text(title, style = RinkType.smallBold, color = RinkPalette.linkBlue)
    }
}

/** Google Play reviewers reach StatScout+ without paying; only a hash of the code is in the app. */
@Composable
private fun ReviewerCodeDialog(onDismiss: () -> Unit) {
    val store = LocalGraph.current.subscriptions
    var code by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = RinkPalette.surface,
        title = { Text("Reviewer Access", style = RinkType.cardTitle, color = RinkPalette.ink) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Enter the reviewer code provided with this app's review notes.", style = RinkType.small, color = RinkPalette.inkSecondary)
                OutlinedTextField(
                    code,
                    { code = it; failed = false },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = RinkPalette.turf, cursorColor = RinkPalette.turf),
                    modifier = Modifier.testTag("reviewerCode"),
                )
                if (failed) Text("That code isn't valid.", style = RinkType.small, color = RinkPalette.performanceLow)
            }
        },
        confirmButton = {
            TextButton(onClick = { if (store.activateReviewAccess(code)) onDismiss() else failed = true }) {
                Text("Unlock", style = RinkType.bodyBold, color = RinkPalette.turf)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", style = RinkType.body, color = RinkPalette.inkSecondary) } },
    )
}

private data class GlossaryEntry(val id: String, val label: String, val category: String, val description: String)

private val SUPPLEMENTAL = listOf(
    GlossaryEntry("general-gp", "GP", "General", "Games played."),
    GlossaryEntry("general-toi", "TOI/GP", "General", "Average ice time per game played, in minutes and seconds."),
    GlossaryEntry("general-plus-minus", "+/-", "General", "Goals for minus goals against while the player was on the ice, at even strength or shorthanded. Power-play goals do not count."),
    GlossaryEntry("general-ppp", "PPP", "General", "Power-play points: goals and assists scored with the team a man up. PPG is the goals alone."),
    GlossaryEntry("general-power", "Power Rating", "General", "Goals per game better or worse than an average team on neutral ice, from expected goals and actual goals for, minus against, adjusted for schedule. Early in the season last year's rating counts as extra games of evidence. The gap between two ratings, plus about 0.2 goals for home ice, sets each game's win chance."),
    GlossaryEntry("general-win-chance", "Win chance", "General", "How often the favourite wins a game between these two power ratings, home ice included. Hockey is close to a coin flip: 60% is a clear favourite."),
    GlossaryEntry("general-strength", "PP / SH / EN", "General", "How a goal was scored: on the power play (a man up), shorthanded (a man down) or into an empty net. A pulled goalie's extra attacker is not a power play."),
    GlossaryEntry("general-special-teams", "PP% / PK%", "General", "Power play: goals per power-play chance. Penalty kill: the share of the other team's power plays that ended without a goal."),
    GlossaryEntry("general-team-xgf", "Team xGF%", "General", "A club's share of the expected goals in its games, all situations. Above 50% means it has been creating more dangerous chances than it allows."),
    GlossaryEntry("general-rookie", "Rookie", "General", "Calder Trophy eligible, by the NHL's own rule: no more than 25 games in any earlier season, not six or more in each of two earlier seasons, and under 26 on September 15."),
    GlossaryEntry("general-streak", "STRK", "General", "The current run of results: W wins, L regulation losses, OT overtime or shootout losses."),
    GlossaryEntry("general-small-sample", "Small sample", "General", "Below the playing-time minimum for that stat, prorated by how much of the season the typical team has played. Skaters need 200 minutes over a full season, goalies 600."),
    GlossaryEntry("general-not-ranked", "Not ranked", "General", "A counting stat at zero. When most of the league has none of something, a tie at zero has no honest percentile, so the value shows and the bar does not."),
    GlossaryEntry("percentile", "Percentile", "General", "A 1\u2013100 rank among players in the same season, season type, and stat category. Higher is always better after lower-is-better stats are inverted."),
)

@Composable
fun StatGlossaryScreen() {
    val context = LocalContext.current
    var searchText by remember { mutableStateOf("") }
    val all = (SUPPLEMENTAL + HockeyMetricRegistry.definitions.map { GlossaryEntry("${it.category.raw}-${it.label}", it.label, it.category.raw, it.description) })
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.label })
    val entries = if (searchText.isEmpty()) all else all.filter {
        it.label.searchMatches(searchText) || it.category.searchMatches(searchText) || it.description.searchMatches(searchText)
    }
    val categories = (listOf("General") + MetricCategory.entries.map { it.raw }).filter { c -> entries.any { it.category == c } }
    PushedScreen("Stat Glossary") {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 12.dp).padding(bottomBarPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SearchField(searchText, { searchText = it }, prompt = "Search stats")
            Text(
                "Expected goals and shot data come from MoneyPuck. Schedules, box scores and bios come from the NHL. Percentiles are calculated separately for each season and season type. The current season ranks everyone who has played; past seasons rank qualifying players.",
                style = RinkType.small,
                color = RinkPalette.inkSecondary,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
            if (entries.isEmpty()) {
                EmptyState("No stats found", "magnifyingglass", "Nothing matches \"$searchText\". Try a stat's abbreviation, like ixG or GSAx.", Modifier.padding(vertical = 24.dp))
            } else categories.forEach { category ->
                Column(Modifier.fillMaxWidth().rinkCard()) {
                    RinkSectionBar(category.uppercase())
                    entries.filter { it.category == category }.forEachIndexed { index, entry ->
                        Column(
                            Modifier.fillMaxWidth().background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt).bottomHairline()
                                .padding(RinkGeo.padCard),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(entry.label, style = RinkType.bodyBold, color = RinkPalette.ink)
                            Text(entry.description, style = RinkType.small, color = RinkPalette.inkSecondary)
                        }
                    }
                }
            }
            Column(Modifier.fillMaxWidth().rinkCard()) {
                RinkSectionBar("SOURCES")
                listOf(
                    "MoneyPuck: expected goals and shot data" to "https://moneypuck.com/about.htm",
                    "NHL: schedules, box scores and stats" to "https://www.nhl.com/stats/",
                ).forEachIndexed { index, (title, url) ->
                    if (index > 0) Hairline()
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { context.openUrl(url) }.padding(RinkGeo.padCard),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = RinkType.small, color = RinkPalette.turf, modifier = Modifier.weight(1f))
                        SfIcon("arrow.up.right", 13.dp, RinkPalette.inkTertiary)
                    }
                }
            }
        }
    }
}

/** A build without its feed configuration says so instead of showing an empty league. */
@Composable
fun ConfigMissingScreen() {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().background(RinkPalette.canvas).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        SfIcon("exclamationmark.triangle.fill", 44.dp, RinkPalette.turf)
        Text("StatScout can't load", style = RinkType.playerName, color = RinkPalette.ink)
        Text(
            "This build is missing its data-feed configuration. Please install the latest version from Google Play or contact support.",
            style = RinkType.body,
            color = RinkPalette.inkSecondary,
            textAlign = TextAlign.Center,
        )
        Box(
            Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(RinkPalette.turf).clickable { context.openUrl(StoreLinks.SUPPORT_URL) }
                .padding(horizontal = 18.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Contact Support", style = RinkType.bodyBold, color = Color.White) }
        Spacer(Modifier.height(8.dp))
    }
}
