package com.jackwallner.hockey.data

import com.jackwallner.hockey.model.DataCoverage
import com.jackwallner.hockey.model.DataFreshness
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.GameProjection
import com.jackwallner.hockey.model.GameXG
import com.jackwallner.hockey.model.LiveScore
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.PlayerProfile
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.double
import com.jackwallner.hockey.model.int
import com.jackwallner.hockey.model.lenientList
import com.jackwallner.hockey.model.parseDay
import com.jackwallner.hockey.model.string
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** A response the app cannot use: a non-2xx status or a body that isn't the expected JSON. */
class BadServerResponse(val status: Int) : IOException("Bad server response ($status)")

/** Every row of a non-empty page failed to decode: the schema moved under the app. */
class DataFormatException(message: String) : Exception(message)

interface StatcastProviding {
    suspend fun fetchHistoricalPlayers(): List<Player>
    suspend fun fetchCurrentPlayers(): List<Player>
    suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog>
    suspend fun fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Instant): List<PlayerGameLog>
    suspend fun fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int): List<RecentForm>
    suspend fun fetchDataCoverage(season: Int): DataCoverage?
    suspend fun fetchDataFreshness(season: Int): DataFreshness? = null
    suspend fun fetchGames(season: Int): List<Game> = emptyList()
    suspend fun fetchGameLogs(gameId: String): List<PlayerGameLog> = emptyList()
    suspend fun fetchGameIdsWithStats(season: Int): Set<String> = emptySet()
    suspend fun fetchGameDetail(gameId: String): GameDetail? = null
    suspend fun fetchPlayerProfiles(season: Int): List<PlayerProfile> = emptyList()
    suspend fun fetchTeamRatings(season: Int): List<TeamRating> = emptyList()
    suspend fun fetchGameProjections(season: Int): List<GameProjection> = emptyList()

    /** Fixture and test providers have no live games. */
    suspend fun fetchLiveScores(dates: Set<String>): Map<String, LiveScore> = emptyMap()
    suspend fun fetchGameExpectedGoals(season: Int): Map<String, GameXG> = emptyMap()
}

/** PostgREST over HTTPS, the same queries the iOS `StatcastAPI` makes. */
class StatcastApi(private val baseUrl: String, private val apiKey: String, private val log: (String) -> Unit = {}) : StatcastProviding {
    private val json = Json { ignoreUnknownKeys = true }

    /** Career rollup (season 0) plus every season before the live one. */
    override suspend fun fetchHistoricalPlayers(): List<Player> = fetchPlayers(
        listOf(
            "or" to "(season.eq.${StatScoutSeason.ALL_TIME},and(season.gte.${StatScoutSeason.EARLIEST},season.lt.${StatScoutSeason.current}))",
        ),
    )

    override suspend fun fetchCurrentPlayers(): List<Player> = fetchPlayers(listOf("season" to "eq.${StatScoutSeason.current}"))

    /** One player's games for a single season and phase; playoffs never pad a regular-season window. */
    override suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> =
        get(
            "player_game_logs",
            listOf(
                "select" to "*",
                "player_id" to "eq.$playerId",
                "season" to "eq.$season",
                "season_type" to "eq.${seasonPhase.raw}",
                "order" to "game_date.desc",
            ),
        )!!.lenientList(PlayerGameLog::fromJson)

    override suspend fun fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Instant): List<PlayerGameLog> {
        val since = DateTimeFormatter.ofPattern("yyyy-MM-dd").format(sinceDate.atZone(com.jackwallner.hockey.model.EASTERN))
        return paged { offset ->
            get(
                "player_game_logs",
                listOf(
                    "select" to "*",
                    "team" to "eq.$team",
                    "season" to "eq.$season",
                    "season_type" to "eq.${seasonPhase.raw}",
                    "game_date" to "gte.$since",
                    "order" to "game_date.desc",
                    "limit" to PAGE.toString(),
                    "offset" to offset.toString(),
                ),
            )!!
        }.flatMap { it.lenientList(PlayerGameLog::fromJson) }
    }

    /** The whole league's rolling window for one length, paged. */
    override suspend fun fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int): List<RecentForm> = paged { offset ->
        get(
            "player_recent_form",
            listOf(
                "select" to "*",
                "season" to "eq.$season",
                "season_type" to "eq.${seasonPhase.raw}",
                "window_weeks" to "eq.$windowWeeks",
                "order" to "player_id.asc",
                "limit" to PAGE.toString(),
                "offset" to offset.toString(),
            ),
        )!!
    }.flatMap { it.lenientList(RecentForm::fromJson) }

    /** One row, read for its coverage columns; ordered by week so a playoff row wins. */
    override suspend fun fetchDataCoverage(season: Int): DataCoverage? {
        val rows = get(
            "player_recent_form",
            listOf(
                "select" to "as_of,end_week,season_type",
                "season" to "eq.$season",
                "as_of" to "not.is.null",
                "order" to "end_week.desc.nullslast,as_of.desc",
                "limit" to "1",
            ),
            allowPartial = false,
        ) as? JsonArray
        val row = rows?.firstOrNull() as? JsonObject ?: return null
        val asOf = row.string("as_of")?.let { parseDay(it) } ?: return null
        return DataCoverage(asOf, row.int("end_week"), row.string("season_type")?.let { SeasonPhase.from(it) } ?: SeasonPhase.REGULAR)
    }

    /** The optional status endpoint; a 404 means "not deployed", never a player-data error. */
    override suspend fun fetchDataFreshness(season: Int): DataFreshness? {
        val rows = get(
            "data_refresh_status",
            listOf(
                "season" to "eq.$season",
                "order" to "published_at.desc.nullslast,last_checked_at.desc",
                "limit" to "1",
            ),
            missingIsNull = true,
            allowPartial = false,
        ) ?: return null
        val first = (rows as? JsonArray)?.firstOrNull() as? JsonObject ?: return null
        return DataFreshness.fromJson(first)
    }

    /** The whole season's schedule, about 1,400 rows, paged because the server caps a response at 1,000. */
    override suspend fun fetchGames(season: Int): List<Game> = paged { offset ->
        get(
            "games",
            listOf(
                "select" to "*",
                "season" to "eq.$season",
                "order" to "kickoff_at.asc,game_id.asc",
                "limit" to PAGE.toString(),
                "offset" to offset.toString(),
            ),
        )!!
    }.flatMap { it.lenientList(Game::fromJson) }

    override suspend fun fetchGameLogs(gameId: String): List<PlayerGameLog> = get(
        "player_game_logs",
        listOf("select" to "*", "game_id" to "eq.$gameId", "limit" to "100"),
    )!!.lenientList(PlayerGameLog::fromJson)

    /** Every game has a goalie, so goalie rows alone answer "has stats". Paged: about 1,400 games a season. */
    override suspend fun fetchGameIdsWithStats(season: Int): Set<String> = paged { offset ->
        get(
            "player_game_logs",
            listOf(
                "select" to "game_id",
                "season" to "eq.$season",
                "player_type" to "eq.g",
                "order" to "game_id.asc,player_id.asc",
                "limit" to PAGE.toString(),
                "offset" to offset.toString(),
            ),
        )!!
    }.flatMap { page -> (page as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.string("game_id") } }.toSet()

    /** Both sides' xG for every built game of the season, read out of `team_stats` so the list never downloads full breakdowns. */
    override suspend fun fetchGameExpectedGoals(season: Int): Map<String, GameXG> {
        val select = listOf(
            "game_id",
            "away_xg:team_stats->away->xg->value", "home_xg:team_stats->home->xg->value",
            "away_ppg:team_stats->away->pp_goals", "away_ppo:team_stats->away->pp_opportunities",
            "home_ppg:team_stats->home->pp_goals", "home_ppo:team_stats->home->pp_opportunities",
            "away_sog:team_stats->away->sog", "home_sog:team_stats->home->sog",
        ).joinToString(",")
        val out = LinkedHashMap<String, GameXG>()
        val pages = paged { offset ->
            get(
                "game_details",
                listOf(
                    "select" to select,
                    "season" to "eq.$season",
                    "order" to "game_id.asc",
                    "limit" to PAGE.toString(),
                    "offset" to offset.toString(),
                ),
            )!!
        }
        for (page in pages) {
            for (element in (page as? JsonArray).orEmpty()) {
                val row = element as? JsonObject ?: continue
                val id = row.string("game_id") ?: continue
                val away = row.double("away_xg") ?: continue
                val home = row.double("home_xg") ?: continue
                out[id] = GameXG(
                    away = away, home = home,
                    awayPowerPlayGoals = row.double("away_ppg")?.toInt(), awayPowerPlays = row.double("away_ppo")?.toInt(),
                    homePowerPlayGoals = row.double("home_ppg")?.toInt(), homePowerPlays = row.double("home_ppo")?.toInt(),
                    awayShots = row.double("away_sog")?.toInt(), homeShots = row.double("home_sog")?.toInt(),
                )
            }
        }
        return out
    }

    /** The NHL scoreboard for the given NHL game dates ("2026-10-11"), straight from the league. */
    override suspend fun fetchLiveScores(dates: Set<String>): Map<String, LiveScore> = LiveScoreClient.fetch(dates)

    override suspend fun fetchGameDetail(gameId: String): GameDetail? {
        val rows = get("game_details", listOf("select" to "*", "game_id" to "eq.$gameId", "limit" to "1")) as? JsonArray
        val first = rows?.firstOrNull() as? JsonObject ?: return null
        return GameDetail.fromJson(first)
    }

    /** Optional context: a missing table reads as no profiles. */
    override suspend fun fetchPlayerProfiles(season: Int): List<PlayerProfile> {
        val all = mutableListOf<PlayerProfile>()
        var offset = 0
        while (true) {
            val page = get(
                "player_profiles",
                listOf(
                    "select" to "*",
                    "season" to "eq.$season",
                    "order" to "player_id.asc",
                    "limit" to PAGE.toString(),
                    "offset" to offset.toString(),
                ),
                missingIsNull = true,
            ) as? JsonArray ?: return emptyList()
            all += page.lenientList(PlayerProfile::fromJson)
            if (page.size < PAGE) return all
            offset += PAGE
        }
    }

    override suspend fun fetchTeamRatings(season: Int): List<TeamRating> =
        get("team_ratings", listOf("select" to "*", "season" to "eq.$season", "order" to "rank.asc"), missingIsNull = true)
            ?.lenientList(TeamRating::fromJson).orEmpty()

    /** Paged: an NHL season has well over the server's 1,000-row page of unplayed games. */
    override suspend fun fetchGameProjections(season: Int): List<GameProjection> {
        val all = mutableListOf<GameProjection>()
        var offset = 0
        while (true) {
            val page = get(
                "game_projections",
                listOf(
                    "select" to "game_id,home_margin,home_win_prob",
                    "season" to "eq.$season",
                    "order" to "game_id.asc",
                    "limit" to PAGE.toString(),
                    "offset" to offset.toString(),
                ),
                missingIsNull = true,
            ) as? JsonArray ?: return all
            all += page.lenientList(GameProjection::fromJson)
            if (page.size < PAGE) return all
            offset += PAGE
        }
    }

    private suspend fun fetchPlayers(filters: List<Pair<String, String>>): List<Player> {
        val all = mutableListOf<Player>()
        var offset = 0
        while (true) {
            val rows = get(
                "player_snapshots",
                listOf(
                    "select" to "*",
                    // Stable key so offset paging can't skip or repeat rows mid-refresh.
                    "order" to "season.asc,season_type.asc,id.asc",
                    "limit" to PAGE.toString(),
                    "offset" to offset.toString(),
                ) + filters,
            ) as? JsonArray ?: throw DataFormatException("Player page was not an array")
            val page = rows.lenientList(Player::fromJson)
            if (rows.isNotEmpty() && page.isEmpty()) throw DataFormatException("All player rows failed to decode")
            all += page
            if (rows.size < PAGE) break
            offset += PAGE
        }
        return all
    }

    private suspend fun paged(fetch: suspend (Int) -> JsonElement): List<JsonElement> {
        val pages = mutableListOf<JsonElement>()
        var offset = 0
        while (true) {
            val page = fetch(offset)
            pages += page
            if ((page as? JsonArray)?.size ?: 0 < PAGE) break
            offset += PAGE
        }
        return pages
    }

    /**
     * One GET against `rest/v1/<table>`. Bypasses caches: the pipeline rewrites
     * rows in place and a stale page is worse than a slow one.
     */
    private suspend fun get(
        table: String,
        query: List<Pair<String, String>>,
        missingIsNull: Boolean = false,
        allowPartial: Boolean = true,
    ): JsonElement? = withContext(Dispatchers.IO) {
        val qs = query.joinToString("&") { (k, v) -> "${enc(k)}=${enc(v)}" }
        val connection = URL("${baseUrl.trimEnd('/')}/rest/v1/$table?$qs").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.useCaches = false
            connection.setRequestProperty("Authorization", "Bearer $apiKey")
            connection.setRequestProperty("apikey", apiKey)
            connection.setRequestProperty("Accept", "application/json")
            val t0 = System.currentTimeMillis()
            val status = connection.responseCode
            val t1 = System.currentTimeMillis()
            if (status == 404 && missingIsNull) return@withContext null
            val ok = status in 200..299 || (allowPartial && status == 206)
            if (!ok) throw BadServerResponse(status)
            val body = connection.inputStream.use { it.readBytes().decodeToString() }
            val t2 = System.currentTimeMillis()
            try {
                json.parseToJsonElement(body).also { log("$table ${body.length}B status ${t1 - t0}ms body ${t2 - t1}ms parse ${System.currentTimeMillis() - t2}ms") }
            } catch (error: kotlinx.serialization.SerializationException) {
                throw DataFormatException(error.message ?: "Bad JSON")
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private companion object {
        const val PAGE = 1000
    }
}

/** Reads the NHL's public scoreboard, which the app polls while a game is on. */
object LiveScoreClient {
    suspend fun fetch(dates: Set<String>): Map<String, LiveScore> = withContext(Dispatchers.IO) {
        val scores = LinkedHashMap<String, LiveScore>()
        for (date in dates) {
            val body = runCatching {
                val connection = URL("https://api-web.nhle.com/v1/score/$date").openConnection() as HttpURLConnection
                try {
                    connection.connectTimeout = 10_000
                    connection.readTimeout = 10_000
                    connection.useCaches = false
                    if (connection.responseCode != 200) null
                    else connection.inputStream.use { it.readBytes().decodeToString() }
                } finally {
                    connection.disconnect()
                }
            }.getOrNull() ?: continue
            for (score in LiveScore.parse(body)) scores[score.gameId] = score
        }
        scores
    }
}

/** No configuration: the app shows its "can't load" screen rather than an empty league. */
object OfflineStatcastApi : StatcastProviding {
    override suspend fun fetchHistoricalPlayers(): List<Player> = emptyList()
    override suspend fun fetchCurrentPlayers(): List<Player> = emptyList()
    override suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> = emptyList()
    override suspend fun fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Instant): List<PlayerGameLog> = emptyList()
    override suspend fun fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int): List<RecentForm> = emptyList()
    override suspend fun fetchDataCoverage(season: Int): DataCoverage? = null
}
