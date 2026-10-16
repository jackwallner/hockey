package com.jackwallner.hockey.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.hockey.data.PaywallTrigger
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.GameProjection
import com.jackwallner.hockey.model.GameStatus
import com.jackwallner.hockey.model.RatedValue
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandingsRow
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.TeamSeasonSummary
import com.jackwallner.hockey.model.displayTeamAbbr
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.ordinal
import com.jackwallner.hockey.model.teamFullName
import com.jackwallner.hockey.ui.LocalGraph
import com.jackwallner.hockey.ui.components.FitText
import com.jackwallner.hockey.ui.components.PercentileBarMini
import com.jackwallner.hockey.ui.components.PlusCTAStyle
import com.jackwallner.hockey.ui.components.PlusDirectCTA
import com.jackwallner.hockey.ui.components.PushedScreen
import com.jackwallner.hockey.ui.components.RinkSectionBar
import com.jackwallner.hockey.ui.components.RinkSegmented
import com.jackwallner.hockey.ui.components.Segment
import com.jackwallner.hockey.ui.components.SfIcon
import com.jackwallner.hockey.ui.components.StatGlossaryLink
import com.jackwallner.hockey.ui.components.TeamColorDot
import com.jackwallner.hockey.ui.components.bottomBarPadding
import com.jackwallner.hockey.ui.components.rinkCard
import com.jackwallner.hockey.ui.nav.LocalNavigator
import com.jackwallner.hockey.ui.nav.Route
import com.jackwallner.hockey.ui.nav.rememberRetained
import com.jackwallner.hockey.ui.theme.RinkGeo
import com.jackwallner.hockey.ui.theme.RinkPalette
import com.jackwallner.hockey.ui.theme.RinkType
import com.jackwallner.hockey.ui.theme.TeamColor
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * One game: the score first, then the shot-quality story the NHL box score
 * leaves out: expected goals by side, the xG race, the chances that decided
 * it, and every skater's and goalie's line.
 */
@Composable
fun GameDetailScreen(gameId: String) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val game = vm.game(gameId)
    val scope = rememberCoroutineScope()

    // Fetched data outlives a pushed player profile, like SwiftUI view state.
    var detail by rememberRetained("detail") { mutableStateOf<GameDetail?>(null) }
    var isDetailLoading by rememberRetained("detailLoading") { mutableStateOf(false) }
    var detailFailed by rememberRetained("detailFailed") { mutableStateOf(false) }
    var linesTeam by rememberRetained("linesTeam") { mutableStateOf("") }

    /** Tracked apart from the page, so a request in flight or one that failed never reads as "not published yet". */
    suspend fun loadDetail() {
        val current = vm.game(gameId)
        if (current == null || current.status() == GameStatus.UPCOMING) return
        isDetailLoading = detail == null
        try {
            vm.fetchGameDetail(gameId)?.let { detail = it }
            detailFailed = false
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            if (detail == null) detailFailed = true
        } finally {
            isDetailLoading = false
        }
        if (linesTeam.isEmpty()) linesTeam = current.awayTeam
    }

    LaunchedEffect(Unit) { vm.loadGames() }
    // Keeps the running score fresh while the game is under way.
    LaunchedEffect(gameId) {
        while (true) {
            val current = vm.game(gameId) ?: break
            val status = current.status()
            if (status != GameStatus.IN_PROGRESS && status != GameStatus.AWAITING_SCORE) break
            vm.refreshLiveScores()
            delay(30_000)
        }
    }
    LaunchedEffect(gameId, game?.let { vm.hasStats(it) } ?: false, vm.freshnessRevision ?: "none") { loadDetail() }

    val title = game?.let { "${displayTeamAbbr(it.awayTeam)} at ${displayTeamAbbr(it.homeTeam)}" } ?: "Game"
    PushedScreen(title) {
        GamesTeamsUi.RefreshBox(onRefresh = {
            vm.loadGames(force = true)
            loadDetail()
        }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                when {
                    game != null -> {
                        Header(game)
                        DetailBody(game, detail, isDetailLoading, detailFailed, linesTeam, { linesTeam = it }) {
                            scope.launch { loadDetail() }
                        }
                    }
                    vm.isGamesLoading -> GamesTeamsUi.Spinner(modifier = Modifier.padding(vertical = 64.dp))
                    else -> GamesTeamsUi.Unavailable("calendar.badge.exclamationmark", "Game not found", modifier = Modifier.padding(vertical = 48.dp))
                }
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

// MARK: - Header

@Composable
private fun Header(game: Game) {
    val vm = LocalGraph.current.dashboard
    val status = game.status()
    val live = vm.liveScore(game)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard()
            .padding(vertical = 18.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColumn(game.awayTeam, game, "Away", Modifier.weight(1f))
            Column(
                Modifier.widthIn(min = 110.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                when {
                    game.isFinal -> ScoreLine(game.awayScore, game.result(game.awayTeam) == "W", game.homeScore, game.result(game.homeTeam) == "W")
                    live != null -> ScoreLine(live.awayScore, true, live.homeScore, true)
                    else -> Text(
                        if (status == GameStatus.UPCOMING) game.kickoffLabel() else "In progress",
                        style = RinkType.cardTitle,
                        color = if (status == GameStatus.UPCOMING) RinkPalette.ink else RinkPalette.performanceLow,
                    )
                }
                if (live != null) {
                    Text(live.clockLabel, style = RinkType.smallBold, color = if (live.isFinal) RinkPalette.ink else RinkPalette.performanceLow)
                    if (live.awayShots != null && live.homeShots != null) {
                        Text("Shots ${live.awayShots}-${live.homeShots}", style = RinkType.micro, color = RinkPalette.inkTertiary)
                    }
                } else {
                    Text(statusLine(game, status), style = RinkType.micro, color = RinkPalette.inkTertiary)
                }
            }
            TeamColumn(game.homeTeam, game, "Home", Modifier.weight(1f))
        }
        // An upcoming game already shows its date under the start time.
        Text(
            listOfNotNull(game.roundLabel, if (status == GameStatus.UPCOMING) null else game.dayLabel(), game.stadium).joinToString(" · "),
            style = RinkType.micro,
            color = RinkPalette.inkTertiary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ScoreLine(away: Int?, awayWinner: Boolean, home: Int?, homeWinner: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        ScoreText(away, awayWinner)
        Text("-", style = RinkType.statLarge, color = RinkPalette.inkTertiary)
        ScoreText(home, homeWinner)
    }
}

@Composable
private fun TeamColumn(team: String, game: Game, label: String, modifier: Modifier = Modifier) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val record = if (game.seasonPhase == SeasonPhase.REGULAR) vm.record(team, game) else null
    Column(
        modifier
            .clip(RoundedCornerShape(RinkGeo.radiusCard))
            .clickable(onClickLabel = "Opens the team") { navigator.push(Route.Team(normalizedTeamAbbreviation(team))) }
            .padding(vertical = 4.dp)
            .testTag("gameTeam_$label"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(48.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
            FitText(
                displayTeamAbbr(team), RinkType.smallBold, Color.White,
                Modifier.padding(horizontal = 4.dp), minScale = 0.7f, textAlign = TextAlign.Center,
            )
        }
        // Two lines reserved either way, so "Columbus Blue Jackets" and "Boston Bruins" keep their badges level.
        Text(teamFullName(team), style = RinkType.smallBold, color = RinkPalette.ink, textAlign = TextAlign.Center, maxLines = 2, minLines = 2)
        Text((listOf(label) + listOfNotNull(record)).joinToString(" · "), style = RinkType.micro, color = RinkPalette.inkTertiary)
    }
}

@Composable
private fun ScoreText(score: Int?, winner: Boolean) {
    Text(score?.toString() ?: "-", style = RinkType.statHero, color = if (winner) RinkPalette.ink else RinkPalette.inkTertiary)
}

private fun statusLine(game: Game, status: GameStatus): String = when (status) {
    GameStatus.FINAL -> game.finalLabel
    GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> "Score posts at the final"
    GameStatus.UPCOMING -> game.kickoff?.let { GamesTeamsUi.monthDay(it) } ?: ""
}

// MARK: - Body

/**
 * Advanced first, the way analytics box scores read: how much danger each
 * side created, how the game swung, the chances that decided it, who drove it.
 */
@Composable
private fun DetailBody(
    game: Game,
    detail: GameDetail?,
    isDetailLoading: Boolean,
    detailFailed: Boolean,
    linesTeam: String,
    onLinesTeam: (String) -> Unit,
    onRetryDetail: () -> Unit,
) {
    val vm = LocalGraph.current.dashboard
    val live = vm.liveScore(game)
    when (game.status()) {
        GameStatus.UPCOMING -> UpcomingCards(game)
        GameStatus.IN_PROGRESS -> if (live?.isFinal == true) {
            FinalDetail(game, detail, isDetailLoading, detailFailed, linesTeam, onLinesTeam, onRetryDetail)
        } else {
            Notice(
                "hockey.puck.fill",
                "Game in progress",
                if (live == null) "The score and the shot breakdown post when the game goes final."
                else "Expected goals, the xG race and every player's line post after the final, usually by the next morning.",
            )
        }
        GameStatus.FINAL, GameStatus.AWAITING_SCORE ->
            FinalDetail(game, detail, isDetailLoading, detailFailed, linesTeam, onLinesTeam, onRetryDetail)
    }
}

@Composable
private fun FinalDetail(
    game: Game,
    detail: GameDetail?,
    isDetailLoading: Boolean,
    detailFailed: Boolean,
    linesTeam: String,
    onLinesTeam: (String) -> Unit,
    onRetryDetail: () -> Unit,
) {
    when {
        detail != null -> {
            // The race chart leads: it is the one picture that says how the game went.
            if (detail.xgRace.size > 2) XGRaceCard(detail, game)
            TeamCard(detail, game)
            if (detail.bigPlays.isNotEmpty()) BigPlaysCard(detail, game)
            PlayerLines(detail, game, linesTeam, onLinesTeam)
            Footnote(
                "Percentiles rank each number against every team game (or every player game with enough volume) this season, and update as new games arrive. xG is the chance each shot becomes a goal, from MoneyPuck's model. GAx is goals minus xG; GSAx is xG faced minus goals allowed.",
            )
            Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { StatGlossaryLink() }
        }
        isDetailLoading -> GamesTeamsUi.Spinner("Loading shot breakdown", Modifier.padding(vertical = 40.dp))
        detailFailed -> Notice(
            "wifi.exclamationmark",
            "Couldn't load the shot breakdown",
            "Expected goals and the xG race didn't load. Check your connection and try again.",
            action = "Try again" to onRetryDetail,
        )
        else -> Notice(
            "chart.xyaxis.line",
            "Shot breakdown on the way",
            "Expected goals, the xG race and every player's line post once shots are published, usually within a few hours of the final.",
        )
    }
}

@Composable
private fun Footnote(text: String) {
    Text(
        text,
        style = RinkType.micro,
        color = RinkPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 12.dp),
    )
}

@Composable
private fun FootnoteRow(text: String) {
    Text(
        text,
        style = RinkType.micro,
        color = RinkPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = RinkGeo.padCard, vertical = 10.dp),
    )
}

/** A titled card: the section bar, then rows. */
@Composable
private fun CardBlock(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard()) {
        RinkSectionBar(title)
        content()
    }
}

@Composable
private fun Notice(icon: String, title: String, text: String, action: Pair<String, () -> Unit>? = null) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SfIcon(icon, 24.dp, RinkPalette.inkTertiary)
        Text(title, style = RinkType.cardTitle, color = RinkPalette.ink, textAlign = TextAlign.Center)
        Text(text, style = RinkType.small, color = RinkPalette.inkSecondary, textAlign = TextAlign.Center)
        action?.let { (label, perform) ->
            Box(
                Modifier.padding(top = 4.dp).heightIn(min = 44.dp).clip(CircleShape).background(RinkPalette.surfaceSunk)
                    .clickable(onClick = perform).padding(horizontal = 18.dp),
                contentAlignment = Alignment.Center,
            ) { Text(label, style = RinkType.smallBold, color = RinkPalette.turf) }
        }
    }
}

@Composable
private fun TeamLabel(team: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        TeamColorDot(team, 8.dp)
        Text(displayTeamAbbr(team), style = RinkType.smallBold, color = RinkPalette.ink)
    }
}

// MARK: - Team expected goals

internal enum class RateStyle {
    DECIMAL, SIGNED_DECIMAL, SHARE, COUNT;

    fun format(value: Double): String = when (this) {
        DECIMAL -> String.format(Locale.US, "%.2f", value)
        SIGNED_DECIMAL -> {
            val text = String.format(Locale.US, "%.1f", value)
            if (text.trimStart('-').all { it == '0' || it == '.' }) "0.0" else if (value > 0) "+$text" else text
        }
        // The feed ships shares either as a fraction or as a percentage.
        SHARE -> String.format(Locale.US, "%.1f", if (value <= 1.5) value * 100 else value) + "%"
        COUNT -> NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundValue(value))
    }
}

private data class TeamMetric(
    val label: String,
    val key: String,
    val style: RateStyle,
    /** Shown instead of the value when present, e.g. "1/4" on the power play. */
    val fraction: Pair<String, String>? = null,
)

private val teamMetrics = listOf(
    TeamMetric("xG", "xg", RateStyle.DECIMAL),
    TeamMetric("xG 5v5", "xg_5v5", RateStyle.DECIMAL),
    TeamMetric("xGF% 5v5", "xgf_pct_5v5", RateStyle.SHARE),
    TeamMetric("CF% 5v5", "cf_pct_5v5", RateStyle.SHARE),
    TeamMetric("High-danger chances", "hd_chances", RateStyle.COUNT),
    TeamMetric("Shots on goal", "sog", RateStyle.COUNT),
    TeamMetric("Shot attempts", "shot_attempts", RateStyle.COUNT),
    TeamMetric("Goals above expected", "gax", RateStyle.SIGNED_DECIMAL),
    TeamMetric("Power play", "pp_goals", RateStyle.COUNT, "pp_goals" to "pp_opportunities"),
    TeamMetric("Faceoff %", "faceoff_pct", RateStyle.SHARE),
    TeamMetric("Hits", "hits", RateStyle.COUNT),
    TeamMetric("Blocks", "blocks", RateStyle.COUNT),
    TeamMetric("Penalty minutes", "pim", RateStyle.COUNT),
)

@Composable
private fun TeamCard(detail: GameDetail, game: Game) {
    val away = detail.stats(game.awayTeam)
    val home = detail.stats(game.homeTeam)
    CardBlock("Expected goals") {
        Row(
            Modifier.fillMaxWidth().height(30.dp).background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padCard),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamLabel(game.awayTeam)
            Spacer(Modifier.weight(1f))
            Text("Bars: percentile vs all team games", style = RinkType.micro, color = RinkPalette.inkTertiary)
            Spacer(Modifier.weight(1f))
            TeamLabel(game.homeTeam)
        }
        teamMetrics.forEachIndexed { index, metric ->
            if (away[metric.key] != null || home[metric.key] != null) TeamRow(metric, away, home, index, game)
        }
    }
}

@Composable
private fun TeamRow(metric: TeamMetric, away: Map<String, RatedValue>, home: Map<String, RatedValue>, index: Int, game: Game) {
    fun text(side: Map<String, RatedValue>): String {
        metric.fraction?.let { (madeKey, triesKey) ->
            val made = side[madeKey]
            val tries = side[triesKey]
            if (made != null && tries != null) return "${made.value.toInt()}/${tries.value.toInt()}"
        }
        return side[metric.key]?.let { metric.style.format(it.value) } ?: "-"
    }
    val awayText = text(away)
    val homeText = text(home)
    val description = "${metric.label}: ${teamFullName(game.awayTeam)} $awayText" +
        (away[metric.key]?.percentile?.let { ", ${it.ordinal} percentile" } ?: "") + ", " +
        "${teamFullName(game.homeTeam)} $homeText" +
        (home[metric.key]?.percentile?.let { ", ${it.ordinal} percentile" } ?: "")
    Row(
        Modifier.fillMaxWidth().height(40.dp)
            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .padding(horizontal = RinkGeo.padCard)
            .clearAndSetSemantics { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RatedCell(awayText, away[metric.key]?.percentile, leading = true)
        FitText(metric.label, RinkType.small, RinkPalette.inkSecondary, Modifier.weight(1f), minScale = 0.8f, textAlign = TextAlign.Center)
        RatedCell(homeText, home[metric.key]?.percentile, leading = false)
    }
}

/** A value over a thin percentile bar, the value tinted by its rank. */
@Composable
private fun RatedCell(text: String, percentile: Int?, leading: Boolean) {
    Column(
        Modifier.width(64.dp),
        horizontalAlignment = if (leading) Alignment.Start else Alignment.End,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(text, style = RinkType.statMed, color = percentile?.let { RinkPalette.textColor(it) } ?: RinkPalette.ink, maxLines = 1)
        if (percentile != null) {
            PercentileBarMini(percentile, Modifier.width(44.dp).graphicsLayer(scaleX = if (leading) 1f else -1f), height = 4.dp)
        } else {
            Spacer(Modifier.size(width = 44.dp, height = 4.dp))
        }
    }
}

private fun swiftRoundValue(value: Double): Long = if (value < 0) -Math.floor(-value + 0.5).toLong() else Math.floor(value + 0.5).toLong()

// MARK: - xG race

/** A goal on the race: the running xG of the side that scored, at the moment it did. */
private data class GoalMarker(val elapsed: Double, val xg: Double, val home: Boolean)

private fun goalMarkers(points: List<GameDetail.XGRacePoint>): List<GoalMarker> {
    val markers = mutableListOf<GoalMarker>()
    for (i in 1 until points.size) {
        val previous = points[i - 1]
        val point = points[i]
        if (point.awayGoals > previous.awayGoals) markers += GoalMarker(point.elapsed, point.awayXG, home = false)
        if (point.homeGoals > previous.homeGoals) markers += GoalMarker(point.elapsed, point.homeXG, home = true)
    }
    return markers
}

/**
 * The two clubs' colors for the race lines. Several matchups pair near-identical
 * navies, which turns the chart into one line; when the colors are that close
 * the home line takes a contrasting accent so the two stay apart.
 */
internal fun raceColors(game: Game): Pair<Color, Color> {
    val away = TeamColor.color(game.awayTeam)
    val home = TeamColor.color(game.homeTeam)
    val dr = away.red - home.red
    val dg = away.green - home.green
    val db = away.blue - home.blue
    val distance = sqrt(dr * dr + dg * dg + db * db)
    return if (distance < 0.45f) away to Color(0.86f, 0.56f, 0.10f) else away to home
}

@Composable
private fun XGRaceCard(detail: GameDetail, game: Game) {
    val points = detail.xgRace
    val end = max(3600.0, points.lastOrNull()?.elapsed ?: 3600.0)
    val top = max(1.0, (points.maxOfOrNull { max(it.awayXG, it.homeXG) } ?: 1.0) * 1.15)
    val goals = goalMarkers(points)
    val (awayColor, homeColor) = raceColors(game)
    val last = points.lastOrNull()
    CardBlock("xG race") {
        Column(Modifier.padding(RinkGeo.padCard), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                LegendDot(displayTeamAbbr(game.awayTeam), awayColor)
                LegendDot(displayTeamAbbr(game.homeTeam), homeColor)
            }
            XGRaceChart(
                points, goals, end, top, awayColor, homeColor,
                Modifier.fillMaxWidth().height(180.dp).semantics {
                    contentDescription = "Expected goals race: ${teamFullName(game.awayTeam)} ${RateStyle.DECIMAL.format(last?.awayXG ?: 0.0)}, " +
                        "${teamFullName(game.homeTeam)} ${RateStyle.DECIMAL.format(last?.homeXG ?: 0.0)}"
                },
            )
            Text("Cumulative expected goals by period. Dots mark goals.", style = RinkType.micro, color = RinkPalette.inkTertiary)
        }
    }
}

@Composable
private fun LegendDot(label: String, color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Text(label, style = RinkType.micro, color = RinkPalette.inkSecondary)
    }
}

/** Both sides' running xG as step lines, period gridlines under them, goals as dots. */
@Composable
private fun XGRaceChart(
    points: List<GameDetail.XGRacePoint>,
    goals: List<GoalMarker>,
    end: Double,
    top: Double,
    awayColor: Color,
    homeColor: Color,
    modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    val labelStyle = RinkType.micro.copy(color = RinkPalette.inkTertiary)
    Canvas(modifier) {
        val left = 28.dp.toPx()
        val bottom = 18.dp.toPx()
        val topPad = 6.dp.toPx()
        val right = 6.dp.toPx()
        val plotW = size.width - left - right
        val plotH = size.height - topPad - bottom
        fun x(elapsed: Double) = left + (elapsed / end).toFloat() * plotW
        fun y(xg: Double) = topPad + (1f - (xg / top).toFloat()) * plotH

        var tick = 0.0
        while (tick < end) {
            drawLine(RinkPalette.divider, Offset(x(tick), topPad), Offset(x(tick), topPad + plotH), strokeWidth = 1f)
            val period = (tick / 1200).toInt() + 1
            val label = when {
                period <= 3 -> "P$period"
                period == 4 -> "OT"
                else -> "${period - 3}OT"
            }
            drawText(measurer, label, Offset(x(tick) + 2.dp.toPx(), topPad + plotH + 2.dp.toPx()), style = labelStyle)
            tick += 1200
        }
        // Horizontal gridlines at whole or half goals, labelled on the leading edge.
        val step = if (top > 4) 1.0 else 0.5
        var level = 0.0
        while (level <= top) {
            drawLine(RinkPalette.divider, Offset(left, y(level)), Offset(left + plotW, y(level)), strokeWidth = 1f)
            val layout = measurer.measure(String.format(Locale.US, "%.1f", level), labelStyle)
            val ty = (y(level) - layout.size.height / 2f).coerceIn(0f, size.height - bottom - layout.size.height)
            drawText(layout, topLeft = Offset(0f, ty))
            level += step
        }

        fun stepPath(value: (GameDetail.XGRacePoint) -> Double): Path {
            val path = Path()
            points.forEachIndexed { index, point ->
                val px = x(point.elapsed)
                val py = y(value(point))
                if (index == 0) path.moveTo(px, py)
                else {
                    // stepEnd: hold the previous value until this point, then jump.
                    path.lineTo(px, y(value(points[index - 1])))
                    path.lineTo(px, py)
                }
            }
            return path
        }
        drawPath(stepPath { it.awayXG }, awayColor, style = Stroke(width = 2.dp.toPx()))
        drawPath(stepPath { it.homeXG }, homeColor, style = Stroke(width = 2.dp.toPx()))
        for (goal in goals) {
            val center = Offset(x(goal.elapsed), y(goal.xg))
            drawCircle(Color.White, radius = 5.5.dp.toPx(), center = center)
            drawCircle(if (goal.home) homeColor else awayColor, radius = 4.5.dp.toPx(), center = center)
        }
    }
}

// MARK: - Chances

/** "P2 12:34", "OT 3:05", "2OT 4:10" in the playoffs, where overtime keeps going and there is no shootout. */
private fun periodLabel(play: GameDetail.BigPlay, game: Game): String {
    val period = when {
        play.period <= 3 -> "P${play.period}"
        play.period == 4 -> "OT"
        else -> if (game.seasonPhase == SeasonPhase.PLAYOFFS) "${play.period - 3}OT" else "SO"
    }
    val clock = if (play.clock.startsWith("0") && play.clock.length > 4) play.clock.drop(1) else play.clock
    return "$period $clock"
}

/** "EDM 2-1": the score after a goal, leader first, or "2-2" when tied. */
private fun scoreAfter(play: GameDetail.BigPlay, game: Game): String? {
    val score = play.score ?: return null
    if (score.size != 2) return null
    val (away, home) = score
    if (away == home) return "$away-$home"
    val leader = if (away > home) game.awayTeam else game.homeTeam
    return "${displayTeamAbbr(leader)} ${max(away, home)}-${min(away, home)}"
}

@Composable
private fun BigPlaysCard(detail: GameDetail, game: Game) {
    CardBlock("Goals and top chances") {
        detail.bigPlays.forEachIndexed { index, play ->
            Row(
                Modifier.fillMaxWidth()
                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .padding(horizontal = RinkGeo.padInline, vertical = 10.dp)
                    .semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Column(Modifier.width(58.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(periodLabel(play, game), style = RinkType.micro, color = RinkPalette.inkTertiary, maxLines = 1)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        TeamColorDot(play.team, 6.dp)
                        Text(displayTeamAbbr(play.team), style = RinkType.micro, color = RinkPalette.inkSecondary)
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        play.shooter?.let { shooter ->
                            FitText(
                                shooter + (if (play.isGoal) play.goalNumber?.let { " ($it)" } ?: "" else ""),
                                if (play.isGoal) RinkType.bodyBold else RinkType.small,
                                RinkPalette.ink,
                                Modifier.weight(1f, fill = false),
                                minScale = 0.85f,
                            )
                        }
                        play.strength?.let { strength ->
                            Text(
                                strength,
                                style = RinkType.micro.copy(fontWeight = FontWeight.Bold),
                                color = RinkPalette.inkSecondary,
                                modifier = Modifier.border(1.dp, RinkPalette.hairline, RoundedCornerShape(3.dp)).padding(horizontal = 4.dp, vertical = 1.dp),
                            )
                        }
                    }
                    play.assistLine?.let { Text(it, style = RinkType.small, color = RinkPalette.inkSecondary, maxLines = 2) }
                    Text(
                        listOfNotNull(play.resultLabel, play.description.ifEmpty { null }).joinToString(" · "),
                        style = RinkType.small,
                        color = if (play.isGoal) RinkPalette.inkTertiary else RinkPalette.inkSecondary,
                        maxLines = 3,
                    )
                }
                Column(Modifier.width(72.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (play.isGoal) scoreAfter(play, game)?.let { Text(it, style = RinkType.smallBold, color = RinkPalette.ink, maxLines = 1) }
                    play.xg?.let { xg ->
                        Text(
                            "${RateStyle.DECIMAL.format(xg)} xG",
                            style = RinkType.statSmall.copy(fontWeight = if (play.isGoal) FontWeight.Bold else FontWeight.Normal),
                            color = if (play.isGoal) RinkPalette.performanceHigh else RinkPalette.inkSecondary,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
        FootnoteRow("Every goal, with its assists, plus the five most dangerous shots that did not score. PP power play, SH shorthanded, EN empty net.")
    }
}

// MARK: - Player lines

@Composable
private fun PlayerLines(detail: GameDetail, game: Game, linesTeam: String, onLinesTeam: (String) -> Unit) {
    val isPro = LocalGraph.current.subscriptions.isPro
    if (isPro) {
        val team = linesTeam.ifEmpty { game.awayTeam }
        RinkSegmented(
            segments = listOf(
                Segment(game.awayTeam, teamFullName(game.awayTeam)),
                Segment(game.homeTeam, teamFullName(game.homeTeam)),
            ),
            selection = team,
            onSelect = onLinesTeam,
            modifier = Modifier.padding(horizontal = 12.dp).padding(top = 16.dp),
        )
        val skaters = detail.players(GameDetail.Role.SKATER, team).take(20)
        if (skaters.isNotEmpty()) {
            CardBlock("Skaters") {
                LineHeader(listOf("TOI" to 40, "G" to 22, "A" to 22, "P" to 24, "SOG" to 38, "ixG" to 40, "GAx" to 40))
                skaters.forEachIndexed { index, line ->
                    LineRow(
                        line, index, game,
                        listOf(
                            Cell(line.toiLabel ?: "-", null, 40),
                            Cell(count(line.goals), null, 22),
                            Cell(count(line.assists), null, 22),
                            Cell(count(line.points), null, 24),
                            Cell(count(line.sog), null, 38),
                            rated(line.ixg, RateStyle.DECIMAL, 40),
                            rated(line.gax, RateStyle.SIGNED_DECIMAL, 40),
                        ),
                    )
                }
            }
        }
        val goalies = detail.players(GameDetail.Role.GOALIE, team)
        if (goalies.isNotEmpty()) {
            CardBlock("Goalies") {
                LineHeader(listOf("SV/SA" to 48, "GA" to 24, "xGA" to 40, "GSAx" to 42, "SV%" to 42))
                goalies.forEachIndexed { index, line ->
                    LineRow(
                        line, index, game,
                        listOf(
                            Cell("${line.saves?.toString() ?: "-"}/${line.shotsAgainst?.toString() ?: "-"}", null, 48),
                            Cell(count(line.goalsAgainst), null, 24),
                            rated(line.xga, RateStyle.DECIMAL, 40),
                            rated(line.gsax, RateStyle.SIGNED_DECIMAL, 42),
                            line.svPct?.let { Cell(RecentMetricKey.savePercentage(it.value), it.percentile, 42) } ?: Cell("-", null, 42),
                        ),
                    )
                }
            }
        }
    } else {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).rinkCard().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SfIcon("lock.fill", 18.dp, RinkPalette.inkTertiary)
            Text("Every player's line", style = RinkType.cardTitle, color = RinkPalette.ink)
            Text(
                "Individual expected goals, goals above expected, and each goalie's GSAx and save percentage for every player, ranked against the season.",
                style = RinkType.small,
                color = RinkPalette.inkSecondary,
                textAlign = TextAlign.Center,
            )
            PlusDirectCTA(PaywallTrigger.AdvancedBoxScore, PlusCTAStyle.CAPSULE)
        }
    }
}

private data class Cell(val text: String, val percentile: Int?, val width: Int)

private fun count(value: Int?): String = value?.toString() ?: "-"

private fun rated(value: RatedValue?, style: RateStyle, width: Int): Cell =
    if (value == null) Cell("-", null, width) else Cell(style.format(value.value), value.percentile, width)

@Composable
private fun LineHeader(columns: List<Pair<String, Int>>) {
    Row(
        Modifier.fillMaxWidth().height(26.dp).background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("PLAYER", style = RinkType.micro, color = RinkPalette.inkTertiary, modifier = Modifier.weight(1f))
        columns.forEach { (label, width) ->
            FitText(label, RinkType.micro, RinkPalette.inkTertiary, Modifier.width(width.dp), minScale = 0.8f, textAlign = TextAlign.End)
        }
    }
}

@Composable
private fun LineRow(line: GameDetail.PlayerLine, index: Int, game: Game, cells: List<Cell>) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val player = vm.player(line.playerId, game.season, game.seasonPhase)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 40.dp)
            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .then(if (player != null) Modifier.clickable { navigator.push(Route.PlayerProfile(player)) } else Modifier)
            .padding(horizontal = RinkGeo.padInline)
            .testTag("playerLineRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            FitText(player?.name ?: line.name ?: "Player", RinkType.bodyBold, RinkPalette.ink, minScale = 0.8f)
            line.position?.let { position ->
                // The feed sends wingers as "L" / "R"; every other screen says LW / RW.
                Text(
                    when (position) {
                        "L" -> "LW"
                        "R" -> "RW"
                        else -> position
                    },
                    style = RinkType.micro,
                    color = RinkPalette.inkTertiary,
                )
            }
        }
        cells.forEach { cell ->
            FitText(
                cell.text,
                RinkType.statSmall.copy(fontWeight = if (cell.percentile == null) FontWeight.Normal else FontWeight.SemiBold),
                cell.percentile?.let { RinkPalette.textColor(it) } ?: RinkPalette.ink,
                Modifier.width(cell.width.dp),
                minScale = 0.8f,
                textAlign = TextAlign.End,
            )
        }
    }
}

// MARK: - Upcoming

@Composable
private fun UpcomingCards(game: Game) {
    val vm = LocalGraph.current.dashboard
    val hasStandings = (vm.standings[normalizedTeamAbbreviation(game.awayTeam)]?.games ?: 0) > 0
    if ((game.seasonPhase == SeasonPhase.REGULAR && hasStandings) || vm.projection(game) != null) {
        MatchupCard(game)
        SeriesCard(game)
        Footnote(
            "Win chance and ratings come from StatScout Power Ratings: goals a game better or worse than an average team, from expected and actual goals, adjusted for schedule, with home ice worth about 0.2 goals. Power play, penalty kill and xGF% (each club's share of expected goals) cover every game with a shot breakdown, ranked across the league. The shot breakdown posts here after the final.",
        )
    } else {
        Notice(
            "calendar",
            "Not started yet",
            "The score and shot breakdown post here when the game goes final. Scout both rosters from the team pages above.",
        )
    }
}

@Composable
private fun MatchupCard(game: Game) {
    val vm = LocalGraph.current.dashboard
    val away = normalizedTeamAbbreviation(game.awayTeam)
    val home = normalizedTeamAbbreviation(game.homeTeam)
    val table = vm.standings
    val awayRow = table[away]
    val homeRow = table[home]
    val awayRating = vm.teamRating(away)
    val homeRating = vm.teamRating(home)
    val summaries = vm.teamSummaries
    val awaySummary = summaries[away]
    val homeSummary = summaries[home]
    fun perGame(goals: Int?, games: Int?): Pair<String, Double>? {
        if (goals == null || games == null || games <= 0) return null
        val value = goals.toDouble() / games
        return String.format(Locale.US, "%.2f", value) to value
    }
    fun place(team: String): String? {
        val (rank, division) = StandingsRow.divisionPlace(team, table) ?: return null
        return "${StandingsRow.ordinal(rank).lowercase()} ${division.label}"
    }
    fun lastFive(team: String): String? = vm.recentResults(team, game).takeIf { it.isNotEmpty() }?.joinToString(" ")
    fun both(a: Double?, b: Double?): Pair<Double, Double>? = if (a != null && b != null) a to b else null

    CardBlock("Matchup") {
        vm.projection(game)?.let { WinChance(game, it) }
        Row(
            Modifier.fillMaxWidth().height(30.dp).background(RinkPalette.surfaceAlt).padding(horizontal = RinkGeo.padCard),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamLabel(game.awayTeam)
            Spacer(Modifier.weight(1f))
            TeamLabel(game.homeTeam)
        }
        MatchupRow(
            "Record",
            awayRow?.takeIf { it.games > 0 }?.record,
            homeRow?.takeIf { it.games > 0 }?.record,
            index = 0,
        )
        MatchupRow(
            "Points", awayRow?.points?.toString(), homeRow?.points?.toString(),
            compare = (awayRow?.points ?: 0).toDouble() to (homeRow?.points ?: 0).toDouble(), index = 1,
        )
        MatchupRow("Division", place(away), place(home), index = 2)
        MatchupRow("Last 5", lastFive(away), lastFive(home), index = 3)
        val awayGF = perGame(awayRow?.goalsFor, awayRow?.games)
        val homeGF = perGame(homeRow?.goalsFor, homeRow?.games)
        MatchupRow("Goals for / game", awayGF?.first, homeGF?.first, compare = both(awayGF?.second, homeGF?.second), index = 4)
        val awayGA = perGame(awayRow?.goalsAgainst, awayRow?.games)
        val homeGA = perGame(homeRow?.goalsAgainst, homeRow?.games)
        MatchupRow("Goals against / game", awayGA?.first, homeGA?.first, compare = both(awayGA?.second?.let { -it }, homeGA?.second?.let { -it }), index = 5)
        SummaryRow("Power play", awaySummary?.powerPlay, homeSummary?.powerPlay, 6)
        SummaryRow("Penalty kill", awaySummary?.penaltyKill, homeSummary?.penaltyKill, 7)
        SummaryRow("xGF%", awaySummary?.expectedGoalsShare, homeSummary?.expectedGoalsShare, 8)
        MatchupRow(
            "Power rating",
            awayRating?.let { TeamRating.signed(it.rating) },
            homeRating?.let { TeamRating.signed(it.rating) },
            compare = both(awayRating?.rating, homeRating?.rating),
            index = 9,
        )
        MatchupRow(
            "Power rank",
            awayRating?.let { "#${it.rank}" },
            homeRating?.let { "#${it.rank}" },
            compare = both(awayRating?.rank?.let { -it.toDouble() }, homeRating?.rank?.let { -it.toDouble() }),
            index = 10,
        )
    }
}

/** A share stat with its league rank: "24.0% (9th)". */
@Composable
private fun SummaryRow(label: String, away: TeamSeasonSummary.Stat?, home: TeamSeasonSummary.Stat?, index: Int) {
    fun text(stat: TeamSeasonSummary.Stat?): String? =
        stat?.let { String.format(Locale.US, "%.1f", it.value * 100) + "% (${TeamSeasonSummary.ordinal(it.rank)})" }
    val compare = if (away != null && home != null) -away.rank.toDouble() to -home.rank.toDouble() else null
    MatchupRow(label, text(away), text(home), compare = compare, index = index)
}

/** The two clubs' chances as one split bar in their colors. */
@Composable
private fun WinChance(game: Game, projection: GameProjection) {
    val away = projection.winProbability(game.awayTeam, game.homeTeam)
    val home = 1 - away
    val (awayColor, homeColor) = raceColors(game)
    val awayPct = swiftRoundValue(away * 100)
    val homePct = swiftRoundValue(home * 100)
    Column(
        Modifier.fillMaxWidth().padding(RinkGeo.padCard).clearAndSetSemantics {
            contentDescription = "Win chance: ${teamFullName(game.awayTeam)} $awayPct percent, ${teamFullName(game.homeTeam)} $homePct percent"
        },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${displayTeamAbbr(game.awayTeam)} $awayPct%", style = RinkType.smallBold, color = RinkPalette.ink)
            Spacer(Modifier.weight(1f))
            Text("Win chance", style = RinkType.micro, color = RinkPalette.inkTertiary)
            Spacer(Modifier.weight(1f))
            Text("$homePct% ${displayTeamAbbr(game.homeTeam)}", style = RinkType.smallBold, color = RinkPalette.ink)
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp)) {
            val awayWidth = max(4f, (maxWidth.value * away.toFloat()) - 1f).dp
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Box(Modifier.width(awayWidth).fillMaxHeight().clip(CircleShape).background(awayColor))
                Box(Modifier.weight(1f).fillMaxHeight().clip(CircleShape).background(homeColor))
            }
        }
    }
}

/** Away value, label, home value; the better side in bold when the two can be compared. */
@Composable
private fun MatchupRow(label: String, away: String?, home: String?, compare: Pair<Double, Double>? = null, index: Int) {
    val awayBetter = compare?.let { it.first > it.second } ?: false
    val homeBetter = compare?.let { it.second > it.first } ?: false
    Row(
        Modifier.fillMaxWidth().height(38.dp)
            .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
            .padding(horizontal = RinkGeo.padCard)
            .clearAndSetSemantics { contentDescription = "$label: away ${away ?: "none"}, home ${home ?: "none"}" },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FitText(
            away ?: "-",
            if (awayBetter) RinkType.statMed else RinkType.statSmall,
            if (awayBetter) RinkPalette.ink else RinkPalette.inkSecondary,
            Modifier.width(104.dp),
            minScale = 0.75f,
        )
        FitText(label, RinkType.small, RinkPalette.inkTertiary, Modifier.weight(1f), minScale = 0.8f, textAlign = TextAlign.Center)
        FitText(
            home ?: "-",
            if (homeBetter) RinkType.statMed else RinkType.statSmall,
            if (homeBetter) RinkPalette.ink else RinkPalette.inkSecondary,
            Modifier.width(104.dp),
            minScale = 0.75f,
            textAlign = TextAlign.End,
        )
    }
}

/** Earlier meetings this season, each linking to its game. */
@Composable
private fun SeriesCard(game: Game) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val meetings = vm.meetings(game)
    if (meetings.isEmpty()) return
    CardBlock("Season series") {
        meetings.forEachIndexed { index, meeting ->
            Row(
                Modifier.fillMaxWidth().height(40.dp)
                    .background(if (index % 2 == 0) RinkPalette.surface else RinkPalette.surfaceAlt)
                    .clickable { navigator.push(Route.Game(meeting.id)) }
                    .padding(horizontal = RinkGeo.padCard),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(meeting.dayLabel(), style = RinkType.small, color = RinkPalette.inkSecondary)
                Spacer(Modifier.weight(1f))
                Text(
                    "${displayTeamAbbr(meeting.awayTeam)} ${meeting.awayScore ?: 0}, ${displayTeamAbbr(meeting.homeTeam)} ${meeting.homeScore ?: 0}" +
                        (meeting.extraPeriodLabel?.let { " ($it)" } ?: ""),
                    style = RinkType.smallBold,
                    color = RinkPalette.ink,
                )
                SfIcon("chevron.right", 11.dp, RinkPalette.inkTertiary, Modifier.padding(start = 6.dp))
            }
        }
    }
}
