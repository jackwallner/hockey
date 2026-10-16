package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameProjection
import com.jackwallner.hockey.model.GameStatus
import com.jackwallner.hockey.model.GameDay
import com.jackwallner.hockey.model.GameXG
import com.jackwallner.hockey.model.LiveScore
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.teamNickname
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.HomeTopBar
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.CrownYellow
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.TeamColorDot
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.bottomHairline
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.components.rememberHaptic
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The night's slate: who played whom, the finals, what is on next.
 *
 * This is the fan-first front door. Scores, schedule and box scores are free
 * for everyone; the analysis layers stay where they were.
 */
@Composable
fun GamesScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val favorites = graph.favorites
    var selectedDayId by rememberSaveable { mutableStateOf<String?>(null) }

    val days = GameDay.days(vm.games)
    val selectedDay = days.firstOrNull { it.id == selectedDayId } ?: vm.currentGameDay
    val slate = selectedDay?.let { Game.slateOrder(it.games(vm.games)) } ?: emptyList()
    val caption = dayCaption(selectedDay, slate)
    val favoriteGame = favorites.team?.let { team -> slate.firstOrNull { it.involves(team) } }

    Column(Modifier.fillMaxSize()) {
        HomeTopBar("Games · ${SeasonLabel.display(vm.freeSeason)}")
        GamesTeamsUi.RefreshBox(onRefresh = { vm.loadGames(force = true) }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                if (vm.games.isEmpty()) {
                    EmptyState()
                } else {
                    DaySelector(days, selectedDay?.id, Modifier.padding(top = 10.dp)) { selectedDayId = it }
                    caption?.let {
                        Text(
                            it,
                            style = RinkType.micro,
                            color = RinkPalette.inkTertiary,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp),
                        )
                    }
                    SlateContent(slate, favoriteGame)
                }
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }

    // Re-reads the schedule while this tab is on screen: every two minutes while
    // a game is under way or a final is still waiting on its stats, every ten
    // otherwise. The backend itself only updates every fifteen minutes on a game
    // day. Running scores come from the NHL scoreboard every thirty seconds while a game is on.
    LaunchedEffect(isActive) {
        if (!isActive) return@LaunchedEffect
        var lastSchedule = Instant.EPOCH
        while (true) {
            val now = Instant.now()
            if (java.time.Duration.between(lastSchedule, now).seconds >= 115) {
                vm.loadGames()
                lastSchedule = now
            }
            val live = vm.games.any { it.status(now) == GameStatus.IN_PROGRESS || it.status(now) == GameStatus.AWAITING_SCORE }
            vm.refreshLiveScores(now)
            val busy = live || vm.games.any { game ->
                val kickoff = game.kickoff
                game.status(now) == GameStatus.FINAL && kickoff != null && !vm.hasStats(game) &&
                    java.time.Duration.between(kickoff, now).seconds < 12 * 3_600
            }
            delay(if (live) 30_000L else if (busy) 120_000L else 600_000L)
        }
    }
}

/** "Tuesday, Oct 7 · 8 games · Round 1" in the playoffs, so the slate and the Stats caption are plainly two different things. */
private fun dayCaption(day: GameDay?, slate: List<Game>): String? {
    day ?: return null
    val count = if (slate.size == 1) "1 game" else "${slate.size} games"
    val round = if (day.phase == SeasonPhase.PLAYOFFS) slate.firstOrNull()?.let { " · ${it.roundLabel}" } ?: "" else ""
    return "${DateTimeFormatter.ofPattern("EEEE, MMM d", Locale.US).format(day.date)} · $count$round"
}

@Composable
private fun EmptyState() {
    val vm = LocalGraph.current.dashboard
    val scope = rememberCoroutineScope()
    if (vm.isGamesLoading) {
        GamesTeamsUi.Spinner("Loading games", Modifier.padding(vertical = 64.dp))
        return
    }
    val failed = vm.gamesError != null
    GamesTeamsUi.Unavailable(
        icon = if (failed) "wifi.slash" else "calendar",
        title = if (failed) "Couldn't load games" else "No games scheduled",
        description = vm.gamesError ?: "The ${SeasonLabel.display(vm.freeSeason)} schedule isn't published yet.",
        modifier = Modifier.padding(vertical = 48.dp),
    ) {
        Box(
            Modifier.heightIn(min = 44.dp).clip(CircleShape).background(RinkPalette.turf)
                .clickable { scope.launch { vm.loadGames(force = true) } }
                .testTag("gamesRetry").padding(horizontal = 18.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Try Again", style = RinkType.smallBold, color = Color.White) }
    }
}

// MARK: - Day selector

@Composable
private fun DaySelector(days: List<GameDay>, selectedId: String?, modifier: Modifier = Modifier, onSelect: (String) -> Unit) {
    val haptic = rememberHaptic()
    val listState = rememberLazyListState()
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val viewportPx = with(LocalDensity.current) { maxWidth.roundToPx() }
        val halfChipPx = with(LocalDensity.current) { 40.dp.roundToPx() }
        // Keep the chosen day centred, on arrival and whenever it changes.
        LaunchedEffect(selectedId, days.size, viewportPx) {
            val index = days.indexOfFirst { it.id == selectedId }
            if (index >= 0) listState.animateScrollToItem(index, scrollOffset = -(viewportPx / 2 - halfChipPx))
        }
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(horizontal = 12.dp),
        ) {
            itemsIndexed(days, key = { _, day -> day.id }) { _, day ->
                val isSelected = day.id == selectedId
                Box(
                    Modifier.heightIn(min = 44.dp).clip(CircleShape)
                        .clickable {
                            onSelect(day.id)
                            haptic()
                        }
                        .semantics {
                            contentDescription = DateTimeFormatter.ofPattern("EEEE, MMMM d", Locale.US).format(day.date)
                            selected = isSelected
                            role = Role.Button
                        }
                        .testTag("dayChip_${day.id}"),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.height(32.dp).clip(CircleShape)
                            .background(if (isSelected) RinkPalette.turf else RinkPalette.surface)
                            .border(0.5.dp, if (isSelected) Color.Transparent else RinkPalette.hairline, CircleShape)
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            day.label,
                            style = RinkType.smallBold,
                            color = if (isSelected) Color.White else RinkPalette.inkSecondary,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Slate

@Composable
private fun SlateContent(slate: List<Game>, favoriteGame: Game?) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val favorites = graph.favorites
    if (favoriteGame != null) GameSection("Your team", listOf(favoriteGame))
    val now = Instant.now()
    val remaining = slate.filter { it.id != favoriteGame?.id }
    val live = remaining.filter { it.status(now) == GameStatus.IN_PROGRESS || it.status(now) == GameStatus.AWAITING_SCORE }
    val finals = remaining.filter { it.status(now) == GameStatus.FINAL }
    val upcoming = remaining.filter { it.status(now) == GameStatus.UPCOMING }
    if (live.isNotEmpty()) GameSection("In progress", live)
    if (finals.isNotEmpty()) GameSection("Final", finals)
    if (upcoming.isNotEmpty()) GameSection("Upcoming", upcoming)

    if (upcoming.any { vm.projection(it) != null }) {
        Footnote(
            "Win chances come from StatScout Power Ratings: each club's expected goals and scoring against an average team, adjusted for schedule, plus a fraction of a goal for home ice. Details on the Teams tab.",
            top = 12,
        )
    }
    val anyLive = slate.any { it.status(now) == GameStatus.IN_PROGRESS || it.status(now) == GameStatus.AWAITING_SCORE }
    Footnote(
        listOfNotNull(
            if (anyLive) "Live scores update every thirty seconds." else null,
            "Expected goals and player stats usually follow the final by the next morning.",
            if (favorites.team == null) "Follow a team from its page to pin its game here." else null,
        ).joinToString(" "),
        top = 8,
    )
}

@Composable
private fun Footnote(text: String, top: Int) {
    Text(
        text,
        style = RinkType.micro,
        color = RinkPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = top.dp),
    )
}

@Composable
private fun GameSection(title: String, games: List<Game>) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val navigator = LocalNavigator.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard()) {
        RinkSectionBar(title)
        games.forEachIndexed { index, game ->
            GameRow(
                game = game,
                hasStats = vm.hasStats(game),
                highlight = graph.favorites.team,
                awayRecord = vm.record(game.awayTeam, game),
                homeRecord = vm.record(game.homeTeam, game),
                projection = vm.projection(game),
                live = vm.liveScore(game),
                xg = vm.gameXG[game.id],
                modifier = Modifier
                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) },
            )
        }
    }
}

// MARK: - Row

/**
 * Two stacked team lines with scores, and the status on the right.
 *
 * [awayRecord] and [homeRecord] are each club's record through this game: after
 * it for a final, going into it for one still to be played. [projection] is the
 * power ratings' win chance, upcoming games only; [live] the NHL scoreboard's
 * running score; [xg] each side's expected goals once the breakdown is built.
 */
@Composable
fun GameRow(
    game: Game,
    hasStats: Boolean,
    modifier: Modifier = Modifier,
    highlight: String? = null,
    awayRecord: String? = null,
    homeRecord: String? = null,
    projection: GameProjection? = null,
    live: LiveScore? = null,
    xg: GameXG? = null,
) {
    val status = game.status()
    val isLive = live?.let { !it.isFinal } ?: (status == GameStatus.IN_PROGRESS)
    Row(
        modifier
            .fillMaxWidth()
            .bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padInline, vertical = 10.dp)
            .clearAndSetSemantics { contentDescription = accessibilityText(game, status, hasStats, projection, live) }
            .testTag("gameRow"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            TeamLine(game, game.awayTeam, game.awayScore ?: live?.awayScore, status, awayRecord, highlight, live)
            TeamLine(game, game.homeTeam, game.homeScore ?: live?.homeScore, status, homeRecord, highlight, live)
        }
        Column(Modifier.width(104.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                statusTitle(game, status, live),
                style = RinkType.smallBold,
                color = if (isLive) RinkPalette.performanceLow else RinkPalette.ink,
                textAlign = TextAlign.End,
            )
            statusDetail(game, status, hasStats, projection, live, xg)?.let {
                Text(it, style = RinkType.micro, color = RinkPalette.inkTertiary, textAlign = TextAlign.End)
            }
        }
        SfIcon("chevron.right", 14.dp, RinkPalette.inkTertiary)
    }
}

@Composable
private fun TeamLine(game: Game, team: String, score: Int?, status: GameStatus, record: String?, highlight: String?, live: LiveScore?) {
    // The scoreboard can call a game final a few minutes before the schedule sync does; the loser dims either way.
    val liveFinal = live?.isFinal ?: false
    val isWinner = if (liveFinal) {
        live!!.score(game.isHome(team)) > live.score(!game.isHome(team))
    } else game.result(team) == "W"
    val dim = (status == GameStatus.FINAL || liveFinal) && !isWinner
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        TeamColorDot(team, 10.dp)
        Text(
            displayTeamAbbr(team),
            style = RinkType.bodyBold,
            color = if (dim) RinkPalette.inkTertiary else RinkPalette.ink,
            modifier = Modifier.width(40.dp),
        )
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            // The nickname, not the full name: "Seattle Kra..." was cut off beside the record in a row this narrow.
            FitText(teamNickname(team), RinkType.small, RinkPalette.inkTertiary, Modifier.weight(1f, fill = false), minScale = 0.85f)
            record?.let {
                Text(it, style = RinkType.micro.copy(fontFeatureSettings = "tnum"), color = RinkPalette.inkTertiary, maxLines = 1, softWrap = false)
            }
            if (highlight != null && normalizedTeamAbbreviation(highlight) == normalizedTeamAbbreviation(team)) {
                SfIcon("star.fill", 10.dp, CrownYellow)
            }
        }
        if (score != null) {
            Text("$score", style = RinkType.statMed, color = if (dim) RinkPalette.inkTertiary else RinkPalette.ink)
        }
    }
}

private fun statusTitle(game: Game, status: GameStatus, live: LiveScore?): String {
    live?.let { return it.clockLabel }
    return when (status) {
        GameStatus.FINAL -> game.finalLabel
        GameStatus.IN_PROGRESS -> "In progress"
        GameStatus.AWAITING_SCORE -> "Final soon"
        // The day is already the section's; the row only needs the time.
        GameStatus.UPCOMING -> game.kickoff?.let { GamesTeamsUi.shortTime(it) } ?: "Time TBD"
    }
}

private fun statusDetail(game: Game, status: GameStatus, hasStats: Boolean, projection: GameProjection?, live: LiveScore?, xg: GameXG?): String? {
    if (live != null) {
        val away = live.awayShots ?: return null
        val home = live.homeShots ?: return null
        return "Shots $away-$home"
    }
    return when (status) {
        GameStatus.FINAL -> xg?.label ?: if (hasStats) "xG arriving" else "Stats arriving"
        GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> "Score at final"
        GameStatus.UPCOMING -> projection?.label(game.homeTeam, game.awayTeam) ?: game.kickoff?.let { GamesTeamsUi.monthDay(it) }
    }
}

private fun accessibilityText(game: Game, status: GameStatus, hasStats: Boolean, projection: GameProjection?, live: LiveScore?): String {
    val away = teamFullName(game.awayTeam)
    val home = teamFullName(game.homeTeam)
    return when (status) {
        GameStatus.FINAL -> {
            val score = "$away ${game.awayScore ?: 0}, $home ${game.homeScore ?: 0}"
            "$score, ${statusTitle(game, status, live)}" + if (hasStats) "" else ", stats arriving"
        }
        GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE ->
            if (live != null) "$away ${live.awayScore}, $home ${live.homeScore}, ${live.clockLabel}" else "$away at $home, in progress"
        GameStatus.UPCOMING -> {
            val projected = projection?.let {
                val label = it.label(game.homeTeam, game.awayTeam)
                if (label == "Toss-up") ", projected a toss-up" else ", projected $label to win"
            } ?: ""
            "$away at $home, ${game.dayLabel()} at ${game.kickoff?.let { GamesTeamsUi.shortTime(it) } ?: "time TBD"}$projected"
        }
    }
}
