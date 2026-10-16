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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.DashboardViewModel
import com.jackwallner.hockey.model.DateText
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameBoxScore
import com.jackwallner.hockey.model.GameStatus
import com.jackwallner.hockey.model.GameDay
import com.jackwallner.hockey.model.SeasonLabel
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.ChipTrailing
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.RinkChip
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.PushedScreen
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
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/**
 * A team's game tonight, on its team page: the latest result or the next puck
 * drop. It sits above the roster cards so the first thing a team page says is
 * what happened on the ice. Under it: follow the club, open its schedule.
 */
@Composable
fun TeamGameCard(viewModel: DashboardViewModel = LocalGraph.current.dashboard, team: String) {
    val navigator = LocalNavigator.current
    if (viewModel.currentGameDay == null) return
    val game = viewModel.currentGame(team)
    // Keeps the running score fresh while the club's game is on.
    LaunchedEffect(game?.id) {
        while (true) {
            val current = viewModel.currentGame(team) ?: break
            val status = current.status()
            if (status != GameStatus.IN_PROGRESS && status != GameStatus.AWAITING_SCORE) break
            viewModel.refreshLiveScores()
            delay(30_000)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (game != null) {
            GameShell(
                heading(viewModel, team, game),
                Modifier.clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) }.testTag("teamGame"),
            ) {
                TeamColorDot(game.opponent(team), 10.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FitText(
                        "${game.matchupLabel(team)} · ${teamFullName(game.opponent(team))}",
                        RinkType.bodyBold, RinkPalette.ink, minScale = 0.85f,
                    )
                    Text(gameDetail(viewModel, game), style = RinkType.micro, color = RinkPalette.inkTertiary)
                }
                val line = game.resultLine(team)
                val live = viewModel.liveScore(game)
                if (line != null) {
                    Text(line, style = RinkType.statMed, color = GamesTeamsUi.resultColor(game.result(team)))
                } else if (live != null) {
                    Text("${live.score(game.isHome(team))}-${live.score(!game.isHome(team))}", style = RinkType.statMed, color = RinkPalette.ink)
                }
                SfIcon("chevron.right", 14.dp, RinkPalette.inkTertiary)
            }
        }
        TeamActions(team)
    }
}

/** "TONIGHT · 3-1-0 · 2ND PACIFIC", "LAST GAME · ..." or "NEXT GAME · ...": the record, then the division place. */
private fun heading(viewModel: DashboardViewModel, team: String, game: Game): String {
    val isToday = GameDay.day(game) == LocalDate.now()
    val label = if (isToday) {
        if (game.isFinal) "Today" else "Tonight"
    } else {
        if (game.isFinal) "Last game" else "Next game"
    }
    return listOfNotNull(label, viewModel.record(team), viewModel.divisionStanding(team)).joinToString(" · ").uppercase()
}

@Composable
private fun TeamActions(team: String) {
    val favorites = LocalGraph.current.favorites
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val abbr = normalizedTeamAbbreviation(team)
    val following = favorites.isFavoriteTeam(abbr)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        ChipLink(
            hint = if (following) "Stops pinning this team's games" else "Pins this team's games at the top of Games",
            modifier = Modifier.testTag("followTeam"),
            onClick = {
                favorites.setFavoriteTeam(if (following) null else abbr)
                haptic()
            },
        ) {
            RinkChip(
                title = if (following) "Your team" else "Follow team",
                icon = if (following) "star.fill" else "star",
                isActive = following,
            )
        }
        ChipLink(hint = "Opens the schedule", modifier = Modifier.testTag("teamSchedule"), onClick = { navigator.push(Route.TeamSchedule(abbr)) }) {
            RinkChip(title = "Schedule", icon = "calendar", trailing = ChipTrailing.None)
        }
    }
}

/** A chip with a 48dp touch target and an accessibility action label. */
@Composable
private fun ChipLink(hint: String, onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier.heightIn(min = 44.dp).clip(CircleShape).clickable(onClickLabel = hint, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

private fun gameDetail(viewModel: DashboardViewModel, game: Game): String = when (game.status()) {
    GameStatus.FINAL -> if (viewModel.hasStats(game)) "Final · box score" else "Final · stats arriving"
    GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> viewModel.liveScore(game)?.let { "Live · ${it.clockLabel}" } ?: "In progress"
    GameStatus.UPCOMING -> "${game.dayLabel()}, ${game.kickoff?.let { GamesTeamsUi.shortTime(it) } ?: "time TBD"}"
}

@Composable
private fun GameShell(
    heading: String,
    modifier: Modifier = Modifier,
    content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit,
) {
    Column(
        modifier.fillMaxWidth().rinkCard().padding(horizontal = RinkGeo.padInline, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(heading, style = RinkType.micro, color = RinkPalette.inkSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically, content = content)
    }
}

/** One club's season: every game, the opponent, the result or the puck drop. */
@Composable
fun TeamScheduleScreen(team: String) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val games = vm.schedule(team)
    // The regular season in date order, then the playoff rounds.
    val entries = games.sortedWith(compareBy<Game>({ if (it.seasonPhase == SeasonPhase.REGULAR) 0 else 1 }, { it.sortInstant }))
    LaunchedEffect(Unit) { vm.loadGames() }
    PushedScreen(teamFullName(team)) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard()) {
                RinkSectionBar("${SeasonLabel.display(vm.freeSeason)} schedule", trailing = vm.record(team)?.let { record ->
                    { Text(record, style = RinkType.statSmall, color = RinkPalette.inkSecondary) }
                })
                entries.forEachIndexed { index, game ->
                    val background = if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt
                    ScheduleRow(
                        game, team, index + 1,
                        Modifier.background(background).clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) },
                    )
                }
                if (games.isEmpty()) {
                    Text(
                        if (vm.isGamesLoading) "Loading schedule" else "Schedule not published yet",
                        style = RinkType.small,
                        color = RinkPalette.inkTertiary,
                        modifier = Modifier.align(Alignment.CenterHorizontally).padding(vertical = 32.dp),
                    )
                }
            }
            Spacer(Modifier.padding(bottomBarPadding()))
        }
    }
}

@Composable
private fun ScheduleRow(game: Game, team: String, number: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padInline).testTag("scheduleRow"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            if (game.seasonPhase == SeasonPhase.REGULAR) "$number" else game.gameType,
            style = RinkType.statSmall,
            color = RinkPalette.inkTertiary,
            modifier = Modifier.width(30.dp),
        )
        TeamColorDot(game.opponent(team), 10.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(
                "${game.matchupLabel(team)} · ${teamFullName(game.opponent(team))}",
                RinkType.bodyBold, RinkPalette.ink, minScale = 0.85f,
            )
            Text(game.dayLabel(), style = RinkType.micro, color = RinkPalette.inkTertiary)
        }
        val line = game.resultLine(team)
        if (line != null) {
            Text(line, style = RinkType.statMed, color = GamesTeamsUi.resultColor(game.result(team)))
        } else {
            Text(
                if (game.status() == GameStatus.UPCOMING) game.kickoff?.let { GamesTeamsUi.shortTime(it) } ?: "TBD" else "In progress",
                style = RinkType.small,
                color = RinkPalette.inkSecondary,
            )
        }
        SfIcon("chevron.right", 14.dp, RinkPalette.inkTertiary)
    }
}

/**
 * A player's most recent game on his profile: opponent, result, his line, and
 * a way into the box score. Free, and real: the one-game answer to "how did he
 * look?" that the recent-form cards can't give until there are several games.
 *
 * @param viewModel the shared dashboard model, for the schedule and game logs.
 * @param player the player whose latest game is shown.
 * @param season the season the profile is reading.
 * @param phase the season type the profile is reading.
 */
@Composable
fun PlayerLastGameCard(
    viewModel: DashboardViewModel = LocalGraph.current.dashboard,
    player: Player,
    season: Int,
    phase: SeasonPhase,
) {
    val navigator = LocalNavigator.current
    var log by remember { mutableStateOf<PlayerGameLog?>(null) }
    var loadedKey by remember { mutableStateOf<String?>(null) }
    val key = "${player.playerId}-$season-${phase.raw}-${viewModel.freshnessRevision ?: "none"}"

    LaunchedEffect(key) {
        if (loadedKey == key) return@LaunchedEffect
        try {
            val logs = viewModel.fetchGameLogs(player.playerId, season, phase)
            log = logs.maxByOrNull { it.gameDate }
            loadedKey = key
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            loadedKey = null
        }
    }

    val current = log ?: return
    val game = current.gameId?.let { viewModel.game(it) }
    val team = current.team ?: player.team
    val line = GameBoxScore(listOf(current)).lines[0]
    val summary = GameBoxScore.summary(line)
    Column(
        Modifier.padding(top = 10.dp).fillMaxWidth().rinkCard()
            .then(
                if (game != null) Modifier.clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) }
                else Modifier,
            )
            .padding(horizontal = RinkGeo.padInline, vertical = 10.dp)
            .testTag("lastGameCard"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            val title = if (game != null) "Last game · ${game.roundLabel}" else "Last game · ${DateText.gameDay(current.gameDate)}"
            Text(title.uppercase(), style = RinkType.micro, color = RinkPalette.inkSecondary, modifier = Modifier.weight(1f))
            if (game != null) {
                Text("Box score", style = RinkType.micro, color = RinkPalette.turf)
                SfIcon("chevron.right", 12.dp, RinkPalette.turf)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val matchup = if (game != null) "${game.matchupLabel(team)} · ${game.dayLabel()}" else "vs ${displayTeamAbbr(current.opponent ?: "")}"
            Text(matchup, style = RinkType.bodyBold, color = RinkPalette.ink, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            game?.resultLine(team)?.let {
                Text(it, style = RinkType.statSmall, color = GamesTeamsUi.resultColor(game.result(team)))
            }
        }
        if (summary.isNotEmpty()) {
            Text(summary, style = RinkType.small.copy(fontFeatureSettings = "tnum"), color = RinkPalette.inkSecondary)
        }
    }
}

/**
 * Every game this season, newest first: date, opponent, result, and the
 * player's line. The night-by-night view an 82-game sport is read in, free, and
 * the natural companion to the Pro rolling windows.
 *
 * @param viewModel the shared dashboard model, for the schedule and game logs.
 * @param player the player whose games are listed.
 * @param season the season the profile is reading.
 * @param phase the season type the profile is reading.
 */
@Composable
fun PlayerGameLogCard(
    viewModel: DashboardViewModel = LocalGraph.current.dashboard,
    player: Player,
    season: Int,
    phase: SeasonPhase,
) {
    var entries by remember { mutableStateOf<List<GameLogEntry>>(emptyList()) }
    var loadedKey by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    val key = "${player.playerId}-$season-${phase.raw}-${viewModel.freshnessRevision ?: "none"}"

    LaunchedEffect(key) {
        if (loadedKey == key) return@LaunchedEffect
        try {
            val logs = viewModel.fetchGameLogs(player.playerId, season, phase)
            entries = gameLogEntries(logs, player.team)
            loadedKey = key
            failed = false
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            failed = true
        }
    }

    Column(Modifier.fillMaxWidth().rinkCard().testTag("gameLogCard")) {
        RinkSectionBar("GAME LOG")
        if (entries.isEmpty()) {
            Text(
                if (failed) "Couldn't load games. Pull to refresh." else if (loadedKey == null) "Loading games…" else "No games yet this season.",
                style = RinkType.small,
                color = RinkPalette.inkSecondary,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(vertical = 20.dp),
            )
        } else {
            entries.forEachIndexed { index, entry ->
                GameLogRow(entry, viewModel, Modifier.background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt))
            }
        }
    }
}

/** One game in a player's log. */
private data class GameLogEntry(
    val id: String,
    val gameId: String?,
    val gameDate: java.time.Instant,
    val team: String,
    val opponent: String?,
    val summary: String,
)

/**
 * One entry per game; a player with two rows in a game (a skater who also
 * appears as a goalie, say) reads as one line.
 */
private fun gameLogEntries(logs: List<PlayerGameLog>, fallbackTeam: String): List<GameLogEntry> =
    logs.groupBy { it.gameId ?: it.gameDate.toString() }
        .map { (id, rows) ->
            val first = rows[0]
            val summary = GameBoxScore(rows).lines.map { GameBoxScore.summary(it) }.filter { it.isNotEmpty() }.joinToString(" · ")
            GameLogEntry(id, first.gameId, first.gameDate, first.team ?: fallbackTeam, first.opponent, summary)
        }
        .sortedByDescending { it.gameDate }

@Composable
private fun GameLogRow(entry: GameLogEntry, viewModel: DashboardViewModel, modifier: Modifier = Modifier) {
    val navigator = LocalNavigator.current
    val game = entry.gameId?.let { viewModel.game(it) }
    Row(
        modifier.fillMaxWidth()
            .then(if (game != null) Modifier.clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) } else Modifier)
            .bottomHairline(RinkPalette.divider)
            .padding(horizontal = RinkGeo.padInline, vertical = 10.dp)
            .testTag("gameLogRow"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            DateText.gameDay(entry.gameDate),
            style = RinkType.statSmall.copy(fontFeatureSettings = "tnum"),
            color = RinkPalette.inkTertiary,
            modifier = Modifier.width(44.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    game?.matchupLabel(entry.team) ?: "vs ${displayTeamAbbr(entry.opponent ?: "")}",
                    style = RinkType.bodyBold,
                    color = RinkPalette.ink,
                )
                game?.resultLine(entry.team)?.let {
                    Text(it, style = RinkType.statSmall, color = GamesTeamsUi.resultColor(game.result(entry.team)))
                }
            }
            Text(
                entry.summary.ifEmpty { "No box score line" },
                style = RinkType.small.copy(fontFeatureSettings = "tnum"),
                color = RinkPalette.inkSecondary,
            )
        }
    }
}
