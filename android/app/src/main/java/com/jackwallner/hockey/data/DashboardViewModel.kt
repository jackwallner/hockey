package com.jackwallner.hockey.data

import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.hockey.model.DataCoverage
import com.jackwallner.hockey.model.DataFreshness
import com.jackwallner.hockey.model.DataFreshnessStatus
import com.jackwallner.hockey.model.HockeyMetricRegistry
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.GameProjection
import com.jackwallner.hockey.model.GameDay
import com.jackwallner.hockey.model.GameStatus
import com.jackwallner.hockey.model.GameXG
import com.jackwallner.hockey.model.LiveScore
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.MetricKind
import com.jackwallner.hockey.model.LeagueConference
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.PlayerPositionGroup
import com.jackwallner.hockey.model.PlayerProfile
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.RecentWindow
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandingsRow
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.TeamSeasonSummary
import com.jackwallner.hockey.model.TrendWindow
import com.jackwallner.hockey.model.metricNumericValue
import com.jackwallner.hockey.model.leagueTeamAbbreviations
import com.jackwallner.hockey.model.normalizedTeamAbbreviation
import com.jackwallner.hockey.model.searchMatches
import com.jackwallner.hockey.model.teamFullName
import java.io.IOException
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * The shared state behind every screen: the league snapshot, season and
 * position selection, the schedule, enrichment and Recent Form windows. A port
 * of the iOS `DashboardViewModel`, with the same gates and the same rules for
 * accepting or refusing a refresh.
 */
class DashboardViewModel(
    private val provider: StatcastProviding,
    private val cache: PlayerCaching?,
    private val defaults: KeyValueStore,
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher = Dispatchers.Default,
    private val clock: () -> Instant = Instant::now,
    private val log: (String) -> Unit = {},
) {
    // MARK: Selection

    var players by mutableStateOf<List<Player>>(emptyList())
        private set
    var playerHistories by mutableStateOf<Map<Int, List<Player>>>(emptyMap())
        private set
    var searchText by mutableStateOf("")
    var selectedConference by mutableStateOf(LeagueConference.ALL)
    /** Calder-eligible players only. Applies on the live season, the only one with the league's rookie flag. */
    var rookiesOnly by mutableStateOf(false)

    private var selectedPositionState by mutableStateOf(PlayerPositionGroup.FORWARD)
    var selectedPosition: PlayerPositionGroup
        get() = selectedPositionState
        set(value) {
            if (value == selectedPositionState) return
            selectedPositionState = value
            userSortMetricState = null
            applyDefaultSortDirection()
        }

    /** Bridge for callers that speak in wire-format categories. */
    var selectedCategory: MetricCategory?
        get() = selectedPosition.primaryCategory
        set(value) {
            when (value) {
                MetricCategory.SCORING, MetricCategory.SHOT_QUALITY -> selectedPosition = PlayerPositionGroup.FORWARD
                MetricCategory.PLAY_DRIVING -> selectedPosition = PlayerPositionGroup.DEFENSE
                MetricCategory.GOALTENDING -> selectedPosition = PlayerPositionGroup.GOALIE
                null -> Unit
            }
        }

    private var userSortMetricState by mutableStateOf<String?>(null)
    var sortDescending by mutableStateOf(true)
    var selectedSeason by mutableStateOf(StatScoutSeason.free)
    var selectedPhase by mutableStateOf(SeasonPhase.REGULAR)

    val sortLabel: String get() = currentSortMetric ?: "Top Metric"

    val currentSortMetric: String?
        get() {
            val user = userSortMetricState
            if (user != null && user in availableSortMetrics) return user
            return determineSortMetricLabel()
        }

    val availableSortMetrics: List<String> by derivedStateOf {
        HockeyMetricRegistry.sorted(eligibleMetrics).map { it.label }.distinct()
    }

    val availableAdvancedSortMetrics: List<String>
        get() = availableSortMetrics.filter { label ->
            eligibleMetrics.any { it.label == label && HockeyMetricRegistry.definition(it.label, it.category)?.kind == MetricKind.ADVANCED }
        }

    fun setUserSortMetric(label: String?) {
        userSortMetricState = label
        applyDefaultSortDirection()
    }

    fun toggleSortDirection() {
        sortDescending = !sortDescending
    }

    /** "Best first" for the active metric. */
    private fun applyDefaultSortDirection() {
        val label = currentSortMetric
        val metric = label?.let { l -> eligibleMetrics.firstOrNull { it.label == l } }
        sortDescending = if (label == null || metric == null) true
        else HockeyMetricRegistry.definition(label, metric.category)?.higherIsBetter ?: true
    }

    /** Mirrors the subscription gate; set by the UI so the VM never depends on the store. */
    var isPro by mutableStateOf(false)
        private set

    val freeSeason: Int get() = StatScoutSeason.free

    fun isSeasonLocked(season: Int): Boolean = !isPro && season != freeSeason

    val recentFormSeason: Int get() = freeSeason

    /** The live season and the one before it, newest first, floored at the oldest rollup. */
    val recentFormSeasons: List<Int>
        get() = listOf(recentFormSeason, recentFormSeason - 1).filter { it >= StatScoutSeason.EARLIEST_RECENT_FORM }

    fun supportsRecentForm(season: Int): Boolean = season in recentFormSeasons

    /** Switch season first (the header acknowledges the tap), then load what it needs. */
    fun selectSeason(season: Int) {
        selectedSeason = season
        if (hasLoadedHistorical || season == freeSeason) return
        seasonLoadJob = scope.launch { loadHistoricalIfNeeded() }
    }

    var seasonLoadJob: Job? = null
        private set

    /** Push Pro in and re-clamp so a free user can never land on a locked season. */
    fun applyProState(pro: Boolean) {
        isPro = pro
        clampSelectedSeason()
    }

    private fun clampSelectedSeason() {
        if (!isSeasonLocked(selectedSeason)) return
        val target = availableSeasons.firstOrNull { !isSeasonLocked(it) } ?: freeSeason
        if (selectedSeason != target) selectedSeason = target
    }

    // MARK: Load state

    /** True from the first frame so the board shows a spinner, not an empty season. */
    var isLoading by mutableStateOf(true)
        private set
    var isHistoricalLoading by mutableStateOf(false)
        private set
    var hasLoadedHistorical by mutableStateOf(false)
        private set
    var loadingMessage by mutableStateOf("Starting up…")
        private set
    var loadingProgress by mutableStateOf(0.05)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var lastFetchFailed by mutableStateOf(false)
        private set
    /** The network failed, not the data: drives the offline framing. */
    var lastFailureWasConnectivity by mutableStateOf(false)
        private set
    private var hasStartedLoading = false
    private var loadTask: Deferred<Unit>? = null
    private var freshnessCheckTask: Deferred<FreshnessCheckResult>? = null
    private var lastForegroundCheckAt: Instant? = null
    private var lastStatusCheckAt: Instant? = null

    var dataFreshness by mutableStateOf<DataFreshness?>(null)
        private set
    /** Revision represented by what is on screen; can lag the server while a new one is pending. */
    var displayedDataRevision by mutableStateOf<String?>(null)
        private set
    var localLastCheckedAt by mutableStateOf<Instant?>(null)
        private set
    /** The last game the data covers, as opposed to when rows were written. */
    var dataCoverage by mutableStateOf<DataCoverage?>(null)
        private set

    val freshnessRevision: String? get() = displayedDataRevision

    val freshnessForDisplay: DataFreshness?
        get() {
            val remote = dataFreshness ?: return null
            val freshness = remote.copy(coverage = dataCoverage)
            if (lastFetchFailed) {
                return freshness.copy(
                    status = DataFreshnessStatus.FAILED,
                    message = errorMessage ?: "Showing saved data while the latest refresh is retried.",
                    isCached = true,
                )
            }
            val server = freshness.revision
            val displayed = displayedDataRevision
            if (freshness.status != DataFreshnessStatus.READY || server == null || displayed == null || server == displayed) return freshness
            return freshness.copy(
                status = DataFreshnessStatus.STALE,
                message = "New game data is ready, but this screen is still showing the last complete revision.",
                isCached = true,
            )
        }

    val freshnessStatus: DataFreshnessStatus
        get() {
            if (lastFetchFailed) return DataFreshnessStatus.FAILED
            return freshnessForDisplay?.status ?: if (players.isEmpty() && isLoading) DataFreshnessStatus.CHECKING else DataFreshnessStatus.READY
        }

    val lastCheckedAt: Instant? get() = localLastCheckedAt ?: dataFreshness?.checkedAt

    var isRefreshing by mutableStateOf(false)
        private set

    enum class FreshnessCheckResult { UNAVAILABLE, UNCHANGED, UPDATED, PENDING, PARTIAL, STALE, FAILED, THROTTLED }

    val isReady: Boolean get() = players.isNotEmpty()

    // MARK: Season data

    /** Unique players in the selected season and phase. Empty when there is none. */
    val seasonPlayers: List<Player> by derivedStateOf { playersFor(selectedSeason, selectedPhase) }

    private val teamCache by derivedStateOf {
        val teams = sortedSetOf<String>()
        val accum = HashMap<String, Pair<Int, Int>>()
        for (player in seasonPlayers) {
            val abbr = normalizedTeamAbbreviation(player.team)
            teams += abbr
            val score = player.overallPercentile
            if (score > 0) {
                val (sum, count) = accum[abbr] ?: (0 to 0)
                accum[abbr] = (sum + score) to (count + 1)
            }
        }
        teams.toList() to accum.mapValues { it.value.first.toDouble() / it.value.second }
    }

    val teamsWithData: List<String> get() = teamCache.first
    val teamScores: Map<String, Double> get() = teamCache.second

    val teamCounts: Map<String, Int> get() = seasonPlayers.groupingBy { normalizedTeamAbbreviation(it.team) }.eachCount()

    val lastUpdated: Instant? get() = players.maxOfOrNull { it.updatedAt }

    suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> =
        provider.fetchGameLogs(playerId, season, seasonPhase)

    suspend fun fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Instant): List<PlayerGameLog> =
        provider.fetchTeamGameLogs(team, season, seasonPhase, sinceDate)

    init {
        if (cache != null) {
            DataFreshnessCache.load(defaults)?.let { cached ->
                dataFreshness = cached.copy(isCached = true)
                dataCoverage = cached.coverage
                displayedDataRevision = DataFreshnessCache.loadDisplayedRevision(defaults)
                localLastCheckedAt = cached.checkedAt
            }
        }
    }

    /** Every supported season, newest first, with the career rollup at the top. */
    val availableSeasons: List<Int> by derivedStateOf {
        val seasons = (StatScoutSeason.EARLIEST..maxOf(freeSeason, StatScoutSeason.EARLIEST)).toMutableSet()
        playerHistories.values.forEach { history -> history.forEach { p -> p.season?.let(seasons::add) } }
        listOf(StatScoutSeason.ALL_TIME) + (seasons - StatScoutSeason.ALL_TIME).sortedDescending()
    }

    /** Trends and Teams can't honestly show a career row; see the iOS note. */
    val seasonsExcludingAllTime: List<Int> get() = availableSeasons.filter { !StatScoutSeason.isAllTime(it) }

    // MARK: Games

    var games by mutableStateOf<List<Game>>(emptyList())
        private set
    var gameIdsWithStats by mutableStateOf<Set<String>>(emptySet())
        private set
    /** Both sides' expected goals for finals with a built breakdown. */
    var gameXG by mutableStateOf<Map<String, GameXG>>(emptyMap())
        private set
    var isGamesLoading by mutableStateOf(false)
        private set
    var gamesError by mutableStateOf<String?>(null)
        private set
    private var gamesLoadedAt: Instant? = null
    private var gamesTask: Deferred<Unit>? = null

    val currentGameDay: GameDay? get() = GameDay.current(games, clock())

    /** Running scores for games under way, keyed by game id. Only games the schedule does not yet call final. */
    var liveScores by mutableStateOf<Map<String, LiveScore>>(emptyMap())
        private set

    fun liveScore(game: Game): LiveScore? = if (game.isFinal) null else liveScores[game.id]

    /** Re-reads the scoreboard for every game that has started without a posted final. */
    suspend fun refreshLiveScores(now: Instant = clock()) {
        val started = games.filter { it.status(now) == GameStatus.IN_PROGRESS || it.status(now) == GameStatus.AWAITING_SCORE }
        if (started.isEmpty()) {
            if (liveScores.isNotEmpty()) liveScores = emptyMap()
            return
        }
        val dates = started.map { LiveScore.dateKey(it.gameDate) }.toSet()
        val fetched = runCatchingNonCancel { provider.fetchLiveScores(dates) }.orEmpty()
        val ids = started.map { it.id }.toSet()
        // A failed read keeps the last scores on screen rather than blanking them.
        if (fetched.isEmpty()) return
        liveScores = fetched.filterKeys { it in ids }
    }

    // MARK: Enrichment

    var profiles by mutableStateOf<Map<Int, PlayerProfile>>(emptyMap())
        private set
    var teamRatings by mutableStateOf<Map<String, TeamRating>>(emptyMap())
        private set
    var projections by mutableStateOf<Map<String, GameProjection>>(emptyMap())
        private set

    fun profile(player: Player): PlayerProfile? = profiles[player.playerId]?.takeIf { it.season == player.season }

    fun teamRating(team: String): TeamRating? = teamRatings[normalizedTeamAbbreviation(team)]

    fun projection(game: Game): GameProjection? = if (game.isFinal) null else projections[game.id]

    private suspend fun loadProfiles() {
        val loaded = runCatchingNonCancel { provider.fetchPlayerProfiles(freeSeason) } ?: return
        if (loaded.isEmpty()) return
        profiles = firstWins(loaded)
    }

    private fun firstWins(list: List<PlayerProfile>): Map<Int, PlayerProfile> {
        val out = LinkedHashMap<Int, PlayerProfile>()
        for (p in list) out.putIfAbsent(p.playerId, p)
        return out
    }

    val standings: Map<String, StandingsRow> get() = StandingsRow.build(games, leagueTeamAbbreviations)

    /** "2ND PACIFIC": the club's place in its division from posted finals, or null before it has played. */
    fun divisionStanding(team: String): String? {
        val (place, division) = StandingsRow.divisionPlace(team, standings) ?: return null
        return "${StandingsRow.ordinal(place)} ${division.label.uppercase()}"
    }

    /** The schedule, at most once a minute unless forced. Failures keep what is on screen. */
    suspend fun loadGames(force: Boolean = false) {
        gamesTask?.let { it.await(); return }
        val loadedAt = gamesLoadedAt
        if (!force && loadedAt != null && Duration.between(loadedAt, clock()).seconds < 60) return
        val task = scope.async { performGamesLoad() }
        gamesTask = task
        try {
            task.await()
        } finally {
            if (gamesTask === task) gamesTask = null
        }
    }

    private suspend fun performGamesLoad() {
        isGamesLoading = games.isEmpty()
        val season = freeSeason
        try {
            val (loadedGames, loadedIds) = coroutineScope {
                val schedule = async { provider.fetchGames(season) }
                val withStats = async { provider.fetchGameIdsWithStats(season) }
                schedule.await() to withStats.await()
            }
            if (loadedGames.isNotEmpty() || games.isEmpty()) games = loadedGames
            gameIdsWithStats = loadedIds
            gamesError = null
            gamesLoadedAt = clock()
            val (ratings, projected) = coroutineScope {
                val r = async { runCatchingNonCancel { provider.fetchTeamRatings(season) } }
                val p = async { runCatchingNonCancel { provider.fetchGameProjections(season) } }
                val x = async { runCatchingNonCancel { provider.fetchGameExpectedGoals(season) } }
                x.await()?.takeIf { it.isNotEmpty() }?.let { gameXG = it }
                r.await() to p.await()
            }
            if (!ratings.isNullOrEmpty()) {
                val map = LinkedHashMap<String, TeamRating>()
                for (r in ratings) map.putIfAbsent(normalizedTeamAbbreviation(r.team), r)
                teamRatings = map
            }
            if (projected != null) {
                val map = LinkedHashMap<String, GameProjection>()
                for (p in projected) map.putIfAbsent(p.gameId, p)
                projections = map
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            gamesError = "Couldn't load games. Check your connection and try again."
        }
        isGamesLoading = false
    }

    fun game(id: String): Game? = games.firstOrNull { it.id == id }

    /** A team's game on the day the Games tab calls current, else its next game, else its last one. */
    fun currentGame(team: String): Game? {
        currentGameDay?.games(games)?.firstOrNull { it.involves(team) }?.let { return it }
        val mine = games.filter { it.involves(team) }.sortedBy { it.sortInstant }
        return mine.firstOrNull { !it.isFinal } ?: mine.lastOrNull()
    }

    /** "W-L-OTL" from posted regular-season finals, optionally through one game. */
    fun record(team: String, through: Game? = null): String? {
        val cutoff = through?.kickoff ?: Instant.MAX
        val finals = games.filter {
            it.seasonPhase == SeasonPhase.REGULAR && it.isFinal && it.involves(team) && it.sortInstant <= cutoff
        }
        if (finals.isEmpty()) return null
        val results = finals.mapNotNull { it.result(team) }
        val wins = results.count { it == "W" }
        val losses = results.count { it == "L" }
        val otLosses = results.count { it == "OTL" }
        return "$wins-$losses-$otLosses"
    }

    /** A club's last `count` regular-season results before `game`, oldest first: "W", "L", or "OT". */
    fun recentResults(team: String, before: Game, count: Int = 5): List<String> {
        val cutoff = before.sortInstant
        return games
            .filter { it.seasonPhase == SeasonPhase.REGULAR && it.isFinal && it.involves(team) && it.sortInstant < cutoff }
            .sortedBy { it.sortInstant }
            .takeLast(count)
            .mapNotNull { it.result(team) }
            .map { if (it == "OTL") "OT" else it }
    }

    /** Every club's regular season at a glance, with league ranks. */
    val teamSummaries: Map<String, TeamSeasonSummary> by derivedStateOf {
        TeamSeasonSummary.build(games, gameXG, leagueTeamAbbreviations)
    }

    /** Earlier meetings of the two clubs this season, oldest first. */
    fun meetings(game: Game): List<Game> {
        val cutoff = game.sortInstant
        return games.filter {
            it.id != game.id && it.isFinal && it.involves(game.awayTeam) && it.involves(game.homeTeam) && it.sortInstant < cutoff
        }.sortedBy { it.sortInstant }
    }

    fun schedule(team: String): List<Game> = games.filter { it.involves(team) }.sortedBy { it.sortInstant }

    fun hasStats(game: Game): Boolean = game.id in gameIdsWithStats

    suspend fun fetchGameDetail(gameId: String): GameDetail? = provider.fetchGameDetail(gameId)

    suspend fun fetchGameLogs(gameId: String): List<PlayerGameLog> = provider.fetchGameLogs(gameId)

    /** The row for a game-log line, for names and links. */
    fun player(id: Int, season: Int, phase: SeasonPhase): Player? {
        val history = playerHistories[id].orEmpty()
        return history.firstOrNull { it.season == season && it.seasonPhase == phase } ?: history.firstOrNull { it.season == season }
    }

    // MARK: Recent form

    var recentFormByWindow by mutableStateOf<Map<Int, Map<Int, RecentForm>>>(emptyMap())
        private set
    var recentFormLoadingWindows by mutableStateOf<Set<Int>>(emptySet())
        private set
    var recentFormError by mutableStateOf<String?>(null)
        private set
    private var recentFormContext: String? = null
    private val recentFormTasks = HashMap<Int, Deferred<Unit>>()
    private var recentFormRowsByWindow by mutableStateOf<Map<Int, List<RecentForm>>>(emptyMap())

    /**
     * Two weeks, so movement exists by the third week of October. A longer default left the paid
     * board with nothing to rank through the opening month of every season.
     */
    var recentWindow by mutableStateOf(TrendWindow.TWO)

    /** True while a board shows recent form rather than season totals. */
    var showingRecent by mutableStateOf(false)

    fun recentForm(playerId: Int, window: TrendWindow? = null, season: Int? = null, phase: SeasonPhase? = null): RecentForm? {
        val s = season ?: selectedSeason
        val p = phase ?: selectedPhase
        return recentFormByWindow[(window ?: recentWindow).value]?.get(playerId)?.takeIf { it.season == s && it.seasonPhase == p }
    }

    fun recentForm(playerId: Int, window: RecentWindow, season: Int? = null, phase: SeasonPhase? = null): RecentForm? {
        val s = season ?: selectedSeason
        val p = phase ?: selectedPhase
        return recentFormByWindow[window.value]?.get(playerId)?.takeIf { it.season == s && it.seasonPhase == p }
    }

    val isRecentFormLoading: Boolean get() = recentWindow.value in recentFormLoadingWindows

    fun recentFormAsOf(window: TrendWindow, season: Int, phase: SeasonPhase): Instant? =
        recentFormRowsByWindow[window.value]?.filter { it.season == season && it.seasonPhase == phase }?.mapNotNull { it.asOf }?.maxOrNull()

    /** Every row for a window and side; a two-way player has one row per player_type. */
    fun recentFormRows(window: TrendWindow, playerType: String, season: Int, phase: SeasonPhase): List<RecentForm> =
        recentFormRowsByWindow[window.value].orEmpty().filter { it.playerType == playerType && it.season == season && it.seasonPhase == phase }

    /** After a new revision is adopted; in-flight requests can't repopulate a newer snapshot. */
    fun invalidateRecentFormCache() {
        recentFormTasks.values.forEach { it.cancel() }
        recentFormTasks.clear()
        recentFormLoadingWindows = emptySet()
        recentFormByWindow = emptyMap()
        recentFormRowsByWindow = emptyMap()
        recentFormContext = null
        recentFormError = null
    }

    suspend fun reloadRecentForm(window: TrendWindow? = null, season: Int? = null, phase: SeasonPhase? = null) {
        val target = window ?: recentWindow
        recentFormTasks.remove(target.value)?.cancel()
        recentFormByWindow = recentFormByWindow - target.value
        recentFormRowsByWindow = recentFormRowsByWindow - target.value
        recentFormError = null
        loadRecentFormIfNeeded(target, season, phase)
    }

    suspend fun loadRecentFormIfNeeded(window: TrendWindow? = null, season: Int? = null, phase: SeasonPhase? = null) {
        val target = window ?: recentWindow
        val targetSeason = season ?: selectedSeason
        val targetPhase = phase ?: selectedPhase
        val context = "$targetSeason-${targetPhase.raw}"
        if (recentFormContext != context) {
            recentFormTasks.values.forEach { it.cancel() }
            recentFormTasks.clear()
            recentFormLoadingWindows = emptySet()
            recentFormByWindow = emptyMap()
            recentFormRowsByWindow = emptyMap()
            recentFormContext = context
        }
        if (recentFormByWindow[target.value] != null) return
        recentFormTasks[target.value]?.let { runCatching { it.await() }; return }

        recentFormLoadingWindows = recentFormLoadingWindows + target.value
        recentFormError = null
        val task = scope.async {
            try {
                val rows = provider.fetchRecentForm(targetSeason, targetPhase, target.value)
                if (recentFormContext != context || !rows.all { it.season == targetSeason && it.seasonPhase == targetPhase }) return@async
                val byPlayer = HashMap<Int, RecentForm>()
                for (row in rows) {
                    val existing = byPlayer[row.playerId]
                    if (existing != null && existing.plays >= row.plays) continue
                    byPlayer[row.playerId] = row
                }
                recentFormByWindow = recentFormByWindow + (target.value to byPlayer)
                recentFormRowsByWindow = recentFormRowsByWindow + (target.value to rows)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                recentFormError = "Couldn't load recent form."
            } finally {
                recentFormLoadingWindows = recentFormLoadingWindows - target.value
            }
        }
        recentFormTasks[target.value] = task
        try {
            task.await()
        } catch (_: CancellationException) {
        } finally {
            if (recentFormTasks[target.value] === task) recentFormTasks.remove(target.value)
        }
    }

    suspend fun loadRecentFormIfNeeded(window: RecentWindow, season: Int? = null, phase: SeasonPhase? = null) {
        val trend = TrendWindow.of(window.value) ?: return
        loadRecentFormIfNeeded(trend, season, phase)
    }

    /** Unique players for any season, for drill-downs opened from a player page. */
    fun players(season: Int, phase: SeasonPhase? = null): List<Player> = playersFor(season, phase ?: selectedPhase)

    private fun playersFor(season: Int, phase: SeasonPhase): List<Player> {
        val seen = HashSet<Int>()
        val out = ArrayList<Player>()
        for (history in playerHistories.values) {
            for (p in history) {
                if (p.season == season && p.seasonPhase == phase && seen.add(p.playerId)) out += p
            }
        }
        return out
    }

    /** Clubs whose name or abbreviation matches the search: typing "oilers" is usually after Edmonton. */
    val searchedTeams: List<String>
        get() {
            val query = searchText.trim()
            if (query.isEmpty()) return emptyList()
            return teamsWithData.filter {
                selectedConference.contains(it) && (teamFullName(it).searchMatches(query) || it.searchMatches(query))
            }.sortedBy { teamFullName(it) }
        }

    private val eligibleMetrics: List<Metric> by derivedStateOf {
        val position = selectedPositionState
        seasonPlayers.filter { it.positionGroup == position }.flatMap { it.metrics }.filter { HockeyMetricRegistry.isSupported(it, position) }
    }

    val filteredPlayers: List<Player> by derivedStateOf {
        val gateLabel = if (qualifierLevel == QualifierLevel.QUALIFIED) currentSortMetricLabelForGate else null
        val position = selectedPositionState
        val search = searchText
        seasonPlayers.filter { player ->
            val matchesSearch = search.isEmpty() || player.name.searchMatches(search) ||
                player.team.searchMatches(search) || teamFullName(player.team).searchMatches(search)
            if (!matchesSearch || player.positionGroup != position || !matchesBoardFilters(player)) return@filter false
            val matching = player.metrics.filter { HockeyMetricRegistry.isSupported(it, position) }
            matching.isNotEmpty() && isQualifiedForBoard(player, matching, gateLabel)
        }
    }

    /** Conference, plus the rookie filter where it applies. */
    fun matchesBoardFilters(player: Player): Boolean {
        if (!selectedConference.contains(player.team)) return false
        return !isRookieFilterActive || isRookie(player)
    }

    /** The league flags rookies for the live season only. */
    val canFilterRookies: Boolean get() = selectedSeason == freeSeason && profiles.values.any { it.isRookie == true }

    val isRookieFilterActive: Boolean get() = rookiesOnly && canFilterRookies

    fun isRookie(player: Player): Boolean = profile(player)?.isRookie == true

    enum class QualifierLevel(val label: String, val description: String) {
        ALL("All Players", "Small samples dimmed"),
        QUALIFIED("Qualified", "Playing-time minimum");

        companion object {
            fun from(raw: String?): QualifierLevel? = entries.firstOrNull { it.label == raw }
        }
    }

    private var qualifierState by mutableStateOf(QualifierLevel.from(defaults.getString(QUALIFIER_KEY)) ?: QualifierLevel.ALL)

    /** All players by default, small samples dimmed below; Qualified hides them. */
    var qualifierLevel: QualifierLevel
        get() = qualifierState
        set(value) {
            qualifierState = value
            defaults.putString(QUALIFIER_KEY, value.label)
        }

    fun isQualified(player: Player, category: MetricCategory?): Boolean = when (qualifierLevel) {
        QualifierLevel.ALL -> true
        QualifierLevel.QUALIFIED -> isPlayerQualified(player, category)
    }

    /** Whether a player clears the bar, whatever the filter says: the feed's own prorated flag. */
    fun isPlayerQualified(player: Player, category: MetricCategory?): Boolean = hasQualifyingMetric(player, category)

    /** Per metric: a skater over the shot bar for Sh% is not thereby qualified for a 5-on-5 board. */
    fun isQualified(player: Player, metric: Metric): Boolean = metric.qualified != false

    private fun isQualifiedForBoard(player: Player, metrics: List<Metric>, sortLabel: String?): Boolean {
        if (qualifierLevel != QualifierLevel.QUALIFIED) return true
        if (sortLabel != null) metrics.firstOrNull { it.label == sortLabel }?.let { return isQualified(player, it) }
        return metrics.any { isQualified(player, it) }
    }

    private val currentSortMetricLabelForGate: String? get() = userSortMetricState ?: determineSortMetricLabel()

    val leaderboard: List<Player> by derivedStateOf {
        val label = currentSortMetric
        val reference = label?.let { l -> eligibleMetrics.firstOrNull { it.label == l } }
        if (label == null || reference == null) return@derivedStateOf filteredPlayers.sortedBy { it.name }
        val sorted = filteredPlayers.sortedWith(metricComparator(label, reference.category, sortDescending))
        // Small samples go below the rest, so the top of a board is never a three-game call-up.
        val isSmall = { player: Player ->
            val metric = player.metrics.firstOrNull { it.label == label && it.category == reference.category }
            metric != null && !isQualified(player, metric)
        }
        sorted.filterNot(isSmall) + sorted.filter(isSmall)
    }

    /** Board subtitle volume: "412 min", "41 SOG", "612 SA". */
    fun volumeCaption(player: Player, category: MetricCategory?): String? = player.volumeCaption(category ?: player.primaryCategory)

    private fun determineSortMetricLabel(): String? {
        val position = selectedPositionState
        val preferred = position.preferredAdvancedMetrics + position.preferredTraditionalMetrics
        for (label in preferred) if (eligibleMetrics.any { it.label == label }) return label
        return availableSortMetrics.firstOrNull()
    }

    val currentSortMetricForDisplay: Pair<String?, MetricCategory?>
        get() {
            val label = currentSortMetric ?: return null to null
            val metric = eligibleMetrics.firstOrNull { it.label == label } ?: return null to null
            return label to metric.category
        }

    /** A club's roster, standouts first. */
    fun players(team: String): List<Player> {
        val normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation(it.team) == normalized }.sortedByDescending { it.overallPercentile }
    }

    fun teamScore(abbr: String): Double = teamScores[normalizedTeamAbbreviation(abbr)] ?: 0.0

    val qualifiedSeasonPlayers: List<Player>
        get() = seasonPlayers.filter { player ->
            val categories = player.metrics.map { it.category }.toSet()
            if (categories.isEmpty()) isQualified(player, null as MetricCategory?) else categories.any { isQualified(player, it) }
        }

    data class MetricExtreme(val player: Player, val percentile: Int, val actualValue: String)
    data class MetricLeaderEntry(val label: String, val category: MetricCategory, val best: MetricExtreme?, val worst: MetricExtreme?)

    /** Best and worst by percentile (direction-correct), never by parsing values. */
    val allMetrics: List<MetricLeaderEntry>
        get() {
            val map = LinkedHashMap<String, Pair<MetricCategory, MutableList<MetricExtreme>>>()
            for (player in seasonPlayers) {
                if (!matchesBoardFilters(player)) continue
                for (metric in player.metrics) {
                    if (!isQualified(player, metric.category)) continue
                    val key = "${metric.label}|${metric.category.raw}"
                    map.getOrPut(key) { metric.category to mutableListOf() }.second += MetricExtreme(player, metric.percentile, metric.value)
                }
            }
            return map.mapNotNull { (key, data) ->
                val label = key.substringBefore("|")
                val byPercentile = data.second.sortedBy { it.percentile }
                val best = byPercentile.lastOrNull() ?: return@mapNotNull null
                val worst = byPercentile.firstOrNull()
                MetricLeaderEntry(label, data.first, best, if (worst?.player?.id == best.player.id) null else worst)
            }.sortedBy { it.label }
        }

    // MARK: Loading

    suspend fun loadIfNeeded() {
        if (hasStartedLoading) return
        hasStartedLoading = true
        load()
    }

    suspend fun load() {
        loadTask?.let { it.await(); return }
        val task = scope.async { performLoad() }
        loadTask = task
        isRefreshing = true
        try {
            task.await()
        } finally {
            if (loadTask === task) loadTask = null
            isRefreshing = freshnessCheckTask != null
        }
    }

    /** A changed ready revision triggers a full load; otherwise just the schedule. */
    suspend fun refreshOnForeground(now: Instant = clock()) {
        val interval = if (dataFreshness?.status == DataFreshnessStatus.PENDING) 120L else 300L
        lastForegroundCheckAt?.let { if (Duration.between(it, now).seconds < interval) return }
        lastForegroundCheckAt = now
        if (checkForUpdates(false) == FreshnessCheckResult.UPDATED) load() else loadGames()
    }

    suspend fun checkForUpdates(force: Boolean = false): FreshnessCheckResult {
        freshnessCheckTask?.let { return it.await() }
        val last = lastStatusCheckAt
        val interval = if (dataFreshness?.status == DataFreshnessStatus.PENDING) 120L else 300L
        if (!force && last != null && Duration.between(last, clock()).seconds < interval) return FreshnessCheckResult.THROTTLED
        val task = scope.async { performFreshnessCheck() }
        freshnessCheckTask = task
        isRefreshing = true
        return try {
            task.await()
        } finally {
            if (freshnessCheckTask === task) freshnessCheckTask = null
            isRefreshing = loadTask != null
        }
    }

    private suspend fun performFreshnessCheck(): FreshnessCheckResult {
        val now = clock()
        lastStatusCheckAt = now
        localLastCheckedAt = now
        return try {
            val remote = provider.fetchDataFreshness(freeSeason) ?: return FreshnessCheckResult.UNAVAILABLE
            dataFreshness = remote.copy(checkedAt = remote.checkedAt ?: now, isCached = false)
            persistFreshness()
            when (remote.status) {
                DataFreshnessStatus.READY ->
                    if (remote.revision != null && remote.revision != displayedDataRevision) FreshnessCheckResult.UPDATED else FreshnessCheckResult.UNCHANGED
                DataFreshnessStatus.PENDING -> FreshnessCheckResult.PENDING
                DataFreshnessStatus.PARTIAL ->
                    if (remote.revision != null && remote.revision != displayedDataRevision) FreshnessCheckResult.UPDATED else FreshnessCheckResult.PARTIAL
                DataFreshnessStatus.STALE -> FreshnessCheckResult.STALE
                DataFreshnessStatus.CHECKING -> FreshnessCheckResult.UNCHANGED
                DataFreshnessStatus.OFFLINE, DataFreshnessStatus.FAILED -> FreshnessCheckResult.FAILED
            }
        } catch (_: CancellationException) {
            FreshnessCheckResult.FAILED
        } catch (_: Throwable) {
            dataFreshness?.let { existing ->
                dataFreshness = existing.copy(
                    status = DataFreshnessStatus.OFFLINE,
                    checkedAt = now,
                    message = "We couldn't check for new game data.",
                    isCached = true,
                )
                persistFreshness()
            }
            FreshnessCheckResult.FAILED
        }
    }

    private suspend fun performLoad() {
        hasStartedLoading = true
        // The schedule does not depend on the player snapshot, so scores and standings load alongside it.
        scope.launch { loadGames() }
        isLoading = players.isEmpty()
        loadingMessage = if (players.isEmpty()) "Loading saved players…" else "Refreshing player data…"
        loadingProgress = if (players.isEmpty()) 0.12 else 0.2

        val started = System.currentTimeMillis()
        val cached = withContext(io) { runCatching { cache?.loadCurrentPlayers() }.getOrNull().orEmpty() }
        log("cache ${cached.size} players in ${System.currentTimeMillis() - started}ms")
        if (players.isEmpty() && cached.isNotEmpty()) ingestPlayers(cached)

        loadingMessage = "Checking for updates…"
        loadingProgress = 0.45
        isLoading = players.isEmpty()
        errorMessage = null
        lastFetchFailed = false
        lastFailureWasConnectivity = false

        val freshnessResult = checkForUpdates(true)
        log("status $freshnessResult at ${System.currentTimeMillis() - started}ms")
        val revisionAtStart = dataFreshness?.revision

        var acceptedCurrent: List<Player> = emptyList()
        var loadedCurrentData = false
        var playersToIngest: List<Player> = emptyList()

        try {
            val current = provider.fetchCurrentPlayers()
            log("fetched ${current.size} players at ${System.currentTimeMillis() - started}ms")
            val fallback = cached.ifEmpty { playerHistories.values.flatten() }
            val hasCompleteFallback = PlayerSnapshotValidator.isCompleteCurrent(fallback)
            val passes = PlayerSnapshotValidator.isCompleteCurrent(current)
            acceptedCurrent = if (passes || !hasCompleteFallback) current else emptyList()
            // Without the status endpoint, a regression can still clear the minimum: keep the complete cache.
            if (acceptedCurrent.isNotEmpty() &&
                (freshnessResult == FreshnessCheckResult.UNAVAILABLE || freshnessResult == FreshnessCheckResult.FAILED) &&
                hasUnsafeSnapshotRegression(current, fallback)
            ) acceptedCurrent = emptyList()
            val all = if (acceptedCurrent.isEmpty()) fallback else mergePlayers(acceptedCurrent)

            if (all.isEmpty()) {
                // Offseason, cold cache or offline: fall back to bundled history so the app is usable.
                val historical = withContext(io) { runCatching { cache?.loadHistoricalPlayers() }.getOrNull().orEmpty() }
                if (historical.isNotEmpty()) ingestPlayers(historical)
                else {
                    errorMessage = "No players found."
                    lastFetchFailed = true
                }
            } else {
                loadingMessage = "Preparing leaderboard…"
                loadingProgress = 0.85
                playersToIngest = all
                if (acceptedCurrent.isNotEmpty()) loadedCurrentData = true
                else if (current.isNotEmpty()) {
                    errorMessage = "Showing complete saved data while the live feed finishes updating."
                    lastFetchFailed = true
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            lastFetchFailed = true
            when (error) {
                is DataFormatException, is SerializationException -> errorMessage = "Data format changed - app may need an update."
                is IOException -> {
                    errorMessage = if (players.isEmpty()) "Can't reach data feed. Check your connection."
                    else "Showing saved data. Pull to refresh when your connection improves."
                    lastFailureWasConnectivity = true
                }
                else -> errorMessage = if (players.isEmpty()) "Something went wrong loading player data."
                else "Showing saved data. Pull to refresh to try again."
            }
        }
        isLoading = false
        loadingProgress = 1.0
        log("board ready at ${System.currentTimeMillis() - started}ms")

        val candidateCoverage = runCatchingNonCancel { provider.fetchDataCoverage(freeSeason) }

        // Bracket the candidate with a second status read so a new revision can't pair with older rows.
        val endingResult = checkForUpdates(true)
        val revisionAtEnd = dataFreshness?.revision
        val drifted = revisionAtStart != null && revisionAtEnd != null && revisionAtEnd != revisionAtStart
        if (drifted) {
            playersToIngest = emptyList()
            acceptedCurrent = emptyList()
            loadedCurrentData = false
            dataFreshness?.let {
                dataFreshness = it.copy(
                    status = DataFreshnessStatus.CHECKING,
                    message = "A newer game revision arrived while this update was loading.",
                    isCached = true,
                )
            }
        } else if (playersToIngest.isNotEmpty()) {
            // Past seasons can finish loading during the awaits above; merge again so they survive.
            ingestPlayers(mergePlayers(playersToIngest))
        }
        if (loadedCurrentData) {
            dataCoverage = dataFreshness?.coverage ?: candidateCoverage
            val toSave = acceptedCurrent
            withContext(io) { runCatching { cache?.saveCurrentPlayers(toSave) } }
            adoptLoadedRevision(acceptedCurrent, canUseServerRevision(freshnessResult, endingResult))
        } else if (lastFetchFailed) {
            dataFreshness?.let {
                dataFreshness = it.copy(
                    status = DataFreshnessStatus.FAILED,
                    message = errorMessage ?: "Showing saved data while the latest refresh is retried.",
                    isCached = true,
                )
            }
        }
        persistFreshness()
        loadProfiles()
        loadGames(force = true)
    }

    private fun adoptLoadedRevision(loaded: List<Player>, useServerRevision: Boolean) {
        val current = dataFreshness
        val candidate = if (useServerRevision &&
            (current?.status == DataFreshnessStatus.READY || current?.status == DataFreshnessStatus.PARTIAL) &&
            current.revision != null
        ) current.revision else fallbackRevision(loaded, dataCoverage)
        candidate ?: return
        val changed = displayedDataRevision != candidate
        displayedDataRevision = candidate
        if (changed) invalidateRecentFormCache()
        dataFreshness = if (current != null) {
            current.copy(
                status = if (current.status == DataFreshnessStatus.CHECKING) DataFreshnessStatus.READY else current.status,
                revision = if (useServerRevision) current.revision else candidate,
                coverage = dataCoverage,
                isCached = false,
            )
        } else {
            DataFreshness(status = DataFreshnessStatus.READY, revision = candidate, checkedAt = localLastCheckedAt ?: clock(), coverage = dataCoverage)
        }
    }

    private fun canUseServerRevision(initial: FreshnessCheckResult, ending: FreshnessCheckResult): Boolean {
        val allowed = setOf(FreshnessCheckResult.UPDATED, FreshnessCheckResult.UNCHANGED, FreshnessCheckResult.PARTIAL)
        return initial in allowed && ending in allowed
    }

    private fun fallbackRevision(players: List<Player>, coverage: DataCoverage?): String? {
        val latest = players.maxOfOrNull { it.updatedAt } ?: return null
        return "players-${latest.epochSecond}-week-${coverage?.week ?: 0}-asof-${coverage?.asOf?.epochSecond ?: 0}"
    }

    private fun hasUnsafeSnapshotRegression(candidate: List<Player>, fallback: List<Player>): Boolean {
        val season = StatScoutSeason.current
        val fallbackCurrent = fallback.filter { it.season == season && it.seasonPhase == SeasonPhase.REGULAR }
        val candidateCurrent = candidate.filter { it.season == season && it.seasonPhase == SeasonPhase.REGULAR }
        if (fallbackCurrent.isEmpty() || candidateCurrent.isEmpty()) return false
        val fallbackTeams = fallbackCurrent.map { normalizedTeamAbbreviation(it.team) }.toSet()
        val candidateTeams = candidateCurrent.map { normalizedTeamAbbreviation(it.team) }.toSet()
        if (!candidateTeams.containsAll(fallbackTeams)) return true
        val fallbackIds = fallbackCurrent.map { it.playerId }.toSet()
        val candidateIds = candidateCurrent.map { it.playerId }.toSet()
        val missing = (fallbackIds - candidateIds).size
        return missing.toDouble() / fallbackIds.size > 0.20
    }

    private fun persistFreshness() {
        if (cache == null) return
        val freshness = dataFreshness ?: return
        DataFreshnessCache.save(freshness.copy(coverage = dataCoverage), displayedDataRevision, defaults)
    }

    suspend fun loadHistoricalIfNeeded() {
        if (hasLoadedHistorical || isHistoricalLoading) return
        isHistoricalLoading = true
        loadingMessage = "Loading past seasons…"
        loadingProgress = 0.12
        var historical = withContext(io) { runCatching { cache?.loadHistoricalPlayers() }.getOrNull().orEmpty() }
        // Fixture providers may disable the cache; fetch their history directly.
        if (historical.isEmpty()) historical = runCatchingNonCancel { provider.fetchHistoricalPlayers() }.orEmpty()
        loadingMessage = "Preparing season history…"
        loadingProgress = 0.78
        if (historical.isNotEmpty()) {
            // Merge on the main thread with no suspension before ingest, so a current-season
            // ingest that lands meanwhile is never overwritten by a stale snapshot.
            ingestPlayers(mergePlayers(historical))
            hasLoadedHistorical = true
        }
        isHistoricalLoading = false
        loadingProgress = 1.0
    }

    private fun ingestPlayers(all: List<Player>) {
        val grouped = all.groupBy { it.playerId }
        val histories = HashMap<Int, List<Player>>(grouped.size)
        val latest = ArrayList<Player>(grouped.size)
        for ((id, history) in grouped) {
            val sorted = history.sortedWith { a, b ->
                val s1 = a.season
                val s2 = b.season
                when {
                    s1 == null && s2 == null -> 0
                    s1 == null -> 1
                    s2 == null -> -1
                    s1 == s2 && a.seasonPhase != b.seasonPhase -> if (a.seasonPhase == SeasonPhase.REGULAR) -1 else 1
                    else -> s2.compareTo(s1)
                }
            }
            histories[id] = sorted
            sorted.firstOrNull()?.let(latest::add)
        }
        playerHistories = histories
        players = latest
    }

    private fun mergePlayers(replacements: List<Player>): List<Player> {
        val merged = LinkedHashMap<String, Player>()
        for (history in playerHistories.values) for (p in history) merged[p.id] = p
        for (p in replacements) merged[p.id] = p
        return merged.values.toList()
    }

    companion object {
        private const val QUALIFIER_KEY = "stats.qualifier"

        fun hasQualifyingMetric(player: Player, category: MetricCategory?): Boolean =
            player.metrics.any { (category == null || it.category == category) && it.qualified != false }

        /** Rank by the direction-correct percentile; the raw number only breaks a tied bucket. */
        fun metricComparator(label: String, category: MetricCategory, descending: Boolean): Comparator<Player> {
            val percentileDescending = descending != lowerIsBetter(label, category)
            return Comparator { first, second ->
                val a = first.metrics.firstOrNull { it.label == label && it.category == category }
                val b = second.metrics.firstOrNull { it.label == label && it.category == category }
                when {
                    a == null && b == null -> first.name.compareTo(second.name)
                    a == null -> 1
                    b == null -> -1
                    a.percentile != b.percentile ->
                        if (percentileDescending) b.percentile.compareTo(a.percentile) else a.percentile.compareTo(b.percentile)
                    else -> {
                        val av = metricNumericValue(a.value)
                        val bv = metricNumericValue(b.value)
                        if (av != null && bv != null && av != bv) {
                            if (descending) bv.compareTo(av) else av.compareTo(bv)
                        } else first.name.compareTo(second.name)
                    }
                }
            }
        }

        fun rawNumeric(value: String): Double? = metricNumericValue(value)

        fun lowerIsBetter(label: String, category: MetricCategory): Boolean =
            HockeyMetricRegistry.definition(label, category)?.higherIsBetter?.not() ?: false

        fun defaultSortDescending(label: String?, category: MetricCategory?): Boolean {
            if (label == null || category == null) return true
            return !lowerIsBetter(label, category)
        }
    }
}

/** The last known-good status, kept apart from the player cache so a failed check can't replace good data. */
object DataFreshnessCache {
    private const val KEY = "statcast.dataFreshness"
    private const val DISPLAYED_REVISION_KEY = "statcast.displayedDataRevision"

    fun load(defaults: KeyValueStore): DataFreshness? {
        val text = defaults.getString(KEY) ?: return null
        return runCatching { DataFreshness.fromJson(Json.parseToJsonElement(text) as JsonObject) }.getOrNull()
    }

    fun save(freshness: DataFreshness, displayedRevision: String?, defaults: KeyValueStore) {
        defaults.putString(KEY, freshness.toJson().toString())
        if (displayedRevision != null) defaults.putString(DISPLAYED_REVISION_KEY, displayedRevision) else defaults.remove(DISPLAYED_REVISION_KEY)
    }

    fun loadDisplayedRevision(defaults: KeyValueStore): String? = defaults.getString(DISPLAYED_REVISION_KEY)
}

/** `try?` that still lets cancellation through. */
internal suspend fun <T> runCatchingNonCancel(block: suspend () -> T): T? = try {
    block()
} catch (error: CancellationException) {
    throw error
} catch (_: Throwable) {
    null
}
