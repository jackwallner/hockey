package com.jackwallner.hockey

import com.jackwallner.hockey.data.KeyValueStore
import com.jackwallner.hockey.data.PlayerCaching
import com.jackwallner.hockey.data.StatcastProviding
import com.jackwallner.hockey.model.DataCoverage
import com.jackwallner.hockey.model.DataFreshness
import com.jackwallner.hockey.model.DataFreshnessStatus
import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.GameTrend
import com.jackwallner.hockey.model.GameXG
import com.jackwallner.hockey.model.Metric
import com.jackwallner.hockey.model.MetricCategory
import com.jackwallner.hockey.model.Player
import com.jackwallner.hockey.model.PlayerGameLog
import com.jackwallner.hockey.model.PlayerProfile
import com.jackwallner.hockey.model.RatedValue
import com.jackwallner.hockey.model.RecentForm
import com.jackwallner.hockey.model.RecentMetricKey
import com.jackwallner.hockey.model.SeasonPhase
import com.jackwallner.hockey.model.StandardStat
import com.jackwallner.hockey.model.StatScoutSeason
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.swiftRound
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min

/**
 * Deterministic, fictional NHL rows used only by the store screenshot harness,
 * a port of the iOS `ScreenshotFixtureAPI`. Every frame is still drawn by the
 * shipped screens; only the provider is swapped. Debug builds only.
 */
object ScreenshotFixtureApi : StatcastProviding {
    val season = StatScoutSeason.current
    private val priorSeason = season - 1

    /** `fixtureFresh`: no followed players or club and no onboarding flag, the first-run look. */
    var fresh = false

    /** `fixtureSlate`: a live night plus the next two days, so Games has a Today and a future day. */
    var slate = false

    /**
     * Yesterday at noon, in the phone's own calendar: the fixture data runs
     * through it, two weeks after a fictional opening night. Anchored to the
     * capture day so "Today", "Yesterday" and the current game day resolve the
     * same way on every run.
     */
    val asOf: Instant by lazy {
        LocalDate.now().minusDays(1).atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
    }

    private val playersBySeason: Map<Int, List<Player>> by lazy {
        mapOf(season to makePlayers(season, prior = false), priorSeason to makePlayers(priorSeason, prior = true))
    }

    /** Seeds the fan context so the Following board is deterministic. */
    fun prepareDefaults(defaults: KeyValueStore) {
        if (fresh) {
            defaults.remove("favorites.playerIds")
            defaults.remove("favoriteTeam")
            defaults.putBoolean("hasCompletedOnboarding", false)
        } else {
            defaults.putString("favorites.playerIds", "12001,12008,12013")
            defaults.putString("favoriteTeam", "SEA")
            defaults.putBoolean("hasCompletedOnboarding", true)
        }
        defaults.putString("stats.board", "STANDARD")
        defaults.remove("statcast.dataFreshness")
        defaults.remove("statcast.displayedDataRevision")
    }

    /** In-memory cache so the prior season loads through the same lazy path as production. */
    val cache = object : PlayerCaching {
        override fun loadCurrentPlayers(): List<Player> = emptyList()
        override fun loadHistoricalPlayers(): List<Player> = playersBySeason[priorSeason].orEmpty()
        override fun saveCurrentPlayers(players: List<Player>) = Unit
    }

    override suspend fun fetchHistoricalPlayers(): List<Player> = withContext(Dispatchers.Default) { playersBySeason[priorSeason].orEmpty() }

    override suspend fun fetchCurrentPlayers(): List<Player> = withContext(Dispatchers.Default) { playersBySeason[season].orEmpty() }

    override suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> = withContext(Dispatchers.Default) {
        if (seasonPhase != SeasonPhase.REGULAR || season != this@ScreenshotFixtureApi.season) return@withContext emptyList()
        val player = playersBySeason[season]?.firstOrNull { it.playerId == playerId } ?: return@withContext emptyList()
        return@withContext makeGameLogs(player)
    }

    override suspend fun fetchTeamGameLogs(team: String, season: Int, seasonPhase: SeasonPhase, sinceDate: Instant): List<PlayerGameLog> = withContext(Dispatchers.Default) {
        if (seasonPhase != SeasonPhase.REGULAR) return@withContext emptyList()
        val players = playersBySeason[season] ?: return@withContext emptyList()
        return@withContext players.filter { it.team == team }.flatMap(::makeGameLogs).filter { it.gameDate >= sinceDate }
    }

    override suspend fun fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int): List<RecentForm> = withContext(Dispatchers.Default) {
        if (seasonPhase != SeasonPhase.REGULAR || season != this@ScreenshotFixtureApi.season) return@withContext emptyList()
        return@withContext playersBySeason[this@ScreenshotFixtureApi.season].orEmpty().map { makeRecentForm(it, windowWeeks) }
    }

    override suspend fun fetchDataCoverage(season: Int): DataCoverage? = withContext(Dispatchers.Default) { if (season == this@ScreenshotFixtureApi.season) coverage() else null }

    override suspend fun fetchGames(season: Int): List<Game> = withContext(Dispatchers.Default) { if (season == this@ScreenshotFixtureApi.season) FixtureGames.games else emptyList() }

    override suspend fun fetchTeamRatings(season: Int): List<TeamRating> = withContext(Dispatchers.Default) { if (season == this@ScreenshotFixtureApi.season) FixtureGames.teamRatings() else emptyList() }

    override suspend fun fetchGameIdsWithStats(season: Int): Set<String> = withContext(Dispatchers.Default) { if (season == this@ScreenshotFixtureApi.season) FixtureGames.gameIds else emptySet() }

    override suspend fun fetchGameExpectedGoals(season: Int): Map<String, GameXG> = withContext(Dispatchers.Default) {
        if (season != this@ScreenshotFixtureApi.season) return@withContext emptyMap()
        val out = LinkedHashMap<String, GameXG>()
        for (game in FixtureGames.games) {
            if (!game.isFinal || game.id !in FixtureGames.gameIds) continue
            val detail = FixtureGames.gameDetail(game) ?: continue
            val away = detail.away["xg"]?.value ?: continue
            val home = detail.home["xg"]?.value ?: continue
            fun count(side: Map<String, RatedValue>, key: String) = side[key]?.value?.toInt()
            out[game.id] = GameXG(
                away = away, home = home,
                awayPowerPlayGoals = count(detail.away, "pp_goals"), awayPowerPlays = count(detail.away, "pp_opportunities"),
                homePowerPlayGoals = count(detail.home, "pp_goals"), homePowerPlays = count(detail.home, "pp_opportunities"),
                awayShots = count(detail.away, "sog"), homeShots = count(detail.home, "sog"),
            )
        }
        return@withContext out
    }

    override suspend fun fetchGameDetail(gameId: String): GameDetail? = withContext(Dispatchers.Default) {
        val game = FixtureGames.games.firstOrNull { it.id == gameId }?.takeIf { it.isFinal } ?: return@withContext null
        return@withContext FixtureGames.gameDetail(game)
    }

    override suspend fun fetchPlayerProfiles(season: Int): List<PlayerProfile> = withContext(Dispatchers.Default) { if (season == this@ScreenshotFixtureApi.season) FixtureGames.profiles() else emptyList() }

    override suspend fun fetchDataFreshness(season: Int): DataFreshness? = withContext(Dispatchers.Default) {
        if (season != this@ScreenshotFixtureApi.season) return@withContext null
        return@withContext DataFreshness(
            status = DataFreshnessStatus.READY,
            revision = "screenshot-fixture-v13",
            sourcePublishedAt = asOf,
            publishedAt = asOf,
            checkedAt = asOf,
            coverage = coverage(),
            message = "Fixture data through last night",
            isCached = false,
        )
    }

    private fun coverage() = DataCoverage(asOf = asOf, week = 3, phase = SeasonPhase.REGULAR, gamesIncluded = FixtureGames.games.size)

    data class Seed(val id: Int, val name: String, val team: String, val position: String, val type: String, val percentile: Int, val headline: Double)

    /** ixG for a skater after eight games, xGF% for a defenseman, GSAx for a goalie. */
    val seeds = listOf(
        Seed(12001, "Callum Therrien", "SEA", "C", "f", 96, 4.9),
        Seed(12002, "Rasmus Holloway", "EDM", "L", "f", 92, 3.8),
        Seed(12003, "Jonas Whitlock", "TOR", "R", "f", 88, 3.4),
        Seed(12004, "Tobias Marchetti", "COL", "C", "f", 85, 3.1),
        Seed(12005, "Anders Pelletier", "BOS", "L", "f", 80, 2.7),
        Seed(12006, "Dmitri Vasko", "DAL", "C", "f", 74, 2.2),
        Seed(12007, "Owen Castellan", "SEA", "R", "f", 90, 3.5),
        Seed(12008, "Mikael Sandvik", "SEA", "D", "d", 94, 57.4),
        Seed(12009, "Lucas Brannigan", "NJD", "D", "d", 89, 55.8),
        Seed(12010, "Pavel Drozdov", "CAR", "D", "d", 84, 54.6),
        Seed(12011, "Hunter Leclair", "VGK", "D", "d", 79, 53.1),
        Seed(12012, "Gustav Nyqvist", "MIN", "D", "d", 73, 51.9),
        Seed(12013, "Henrik Dalgaard", "SEA", "G", "g", 93, 3.4),
        Seed(12014, "Ilya Morozov", "FLA", "G", "g", 88, 2.6),
        Seed(12015, "Samuel Whitaker", "WPG", "G", "g", 82, 1.7),
        Seed(12016, "Teodor Lindahl", "NYR", "G", "g", 76, 0.9),
        Seed(12017, "Elias Rourke", "CGY", "R", "f", 71, 2.0),
        Seed(12018, "Viktor Halden", "OTT", "C", "f", 68, 1.8),
        Seed(12019, "Casimir Brandt", "STL", "L", "f", 64, 1.6),
        Seed(12020, "Noel Ferreira", "TBL", "C", "f", 60, 1.4),
        Seed(12021, "Axel Mortensen", "SEA", "L", "f", 83, 2.9),
        Seed(12022, "Leo Calloway", "SEA", "C", "f", 66, 1.7),
        Seed(12023, "Finn Aldercott", "SEA", "D", "d", 77, 52.4),
        Seed(12024, "Rowan Teague", "SEA", "D", "d", 58, 49.7),
        Seed(12025, "Marek Soukup", "SEA", "G", "g", 61, -0.4),
    )

    private fun round(value: Double): Int = swiftRound(value)

    /**
     * Goals, assists and shots on goal for a skater, from how good the player is
     * plus a little noise per player. Shared by the metric rows and the standard line.
     */
    private fun counting(seed: Seed, season: Double): Triple<Int, Int, Int> {
        val strength = (seed.percentile - 50) / 50.0
        fun noise(salt: Int) = FixtureGames.unit("std-${seed.id}", salt) - 0.5
        val goals = max(0, round((1 + 7 * strength + 3 * noise(1)) * (if (seed.type == "d") 0.4 else 1.0) * season))
        val assists = max(0, round((2 + 8 * strength + 3 * noise(2)) * (if (seed.type == "d") 0.9 else 1.0) * season))
        val shots = max(1, round((14 + 26 * strength + 6 * noise(3)) * season))
        return Triple(goals, assists, shots)
    }

    private fun makePlayers(season: Int, prior: Boolean): List<Player> = seeds.map { seed ->
        val scale = if (prior) 0.84 else 1.0
        val percentile = if (prior) max(55, seed.percentile - 4) else seed.percentile
        val volume = if (prior) 9.5 else 1.0
        Player(
            playerId = seed.id,
            name = seed.name,
            team = seed.team,
            position = seed.position,
            handedness = if (seed.position == "G") "L" else "R",
            updatedAt = asOf,
            season = season,
            seasonPhase = SeasonPhase.REGULAR,
            playerType = seed.type,
            source = "screenshot-fixture",
            metrics = metrics(seed, scale, volume, percentile),
            standardStats = standardStats(seed, scale, volume),
            games = gameTrends(seed, prior),
        )
    }

    /** One metric per registry label, scaled by how good the player is. */
    private fun metrics(seed: Seed, scale: Double, volume: Double, percentile: Int): List<Metric> {
        val rank = 0.72 + percentile / 100.0 * 0.28
        fun off(n: Int) = max(50, percentile - n)
        fun rate(label: String, base: Double, offset: Int, category: MetricCategory) = metric(label, base * rank * scale, off(offset), category)
        fun count(label: String, base: Double, offset: Int, category: MetricCategory) = metric(label, base * rank * scale * volume, off(offset), category)
        val (goals, assists, shots) = counting(seed, scale * volume)
        fun exact(label: String, value: Int, offset: Int, category: MetricCategory) = metric(label, value.toDouble(), off(offset), category)
        return when (seed.type) {
            "f" -> listOf(
                rate("P/60", 3.6, 0, MetricCategory.SCORING), exact("Primary P", goals + assists * 2 / 3, 2, MetricCategory.SCORING),
                exact("G", goals, 3, MetricCategory.SCORING), exact("A", assists, 4, MetricCategory.SCORING),
                exact("P", goals + assists, 1, MetricCategory.SCORING),
                exact("SOG", shots, 6, MetricCategory.SCORING),
                metric("Sh%", goals.toDouble() / shots * 100, off(8), MetricCategory.SCORING),
                metric("ixG", seed.headline * scale * volume, percentile, MetricCategory.SHOT_QUALITY),
                metric("GAx", 1.2 * scale * volume, off(9), MetricCategory.SHOT_QUALITY),
                rate("ixG/60", 1.3, 2, MetricCategory.SHOT_QUALITY), rate("Shots/60", 12.4, 5, MetricCategory.SHOT_QUALITY),
                count("HD Shots", 11.0, 5, MetricCategory.SHOT_QUALITY),
                rate("xGF%", 56.0, 4, MetricCategory.PLAY_DRIVING), rate("CF%", 54.0, 6, MetricCategory.PLAY_DRIVING),
                rate("xGF/60", 3.1, 7, MetricCategory.PLAY_DRIVING), count("Hits", 12.0, 25, MetricCategory.PLAY_DRIVING),
            )
            "d" -> listOf(
                metric("xGF%", seed.headline * scale, percentile, MetricCategory.PLAY_DRIVING),
                metric("Rel xGF%", 4.6 * scale, off(3), MetricCategory.PLAY_DRIVING),
                metric("xGA/60", 2.1 / scale, off(5), MetricCategory.PLAY_DRIVING),
                count("Blocks", 14.0, 8, MetricCategory.PLAY_DRIVING), count("Hits", 11.0, 20, MetricCategory.PLAY_DRIVING),
                rate("P/60", 1.9, 6, MetricCategory.SCORING), exact("P", goals + assists, 5, MetricCategory.SCORING),
                exact("A", assists, 6, MetricCategory.SCORING),
                metric("ixG", 1.4 * scale * volume, off(10), MetricCategory.SHOT_QUALITY),
            )
            else -> listOf(
                metric("GSAx", seed.headline * scale * volume, percentile, MetricCategory.GOALTENDING),
                metric("GSAx/60", 0.38 * scale, off(2), MetricCategory.GOALTENDING),
                metric("SV%", 0.925 * (0.97 + 0.03 * scale), off(1), MetricCategory.GOALTENDING),
                metric("GAA", 2.2 / scale, off(3), MetricCategory.GOALTENDING),
                metric("HD SV%", 0.858 * (0.97 + 0.03 * scale), off(6), MetricCategory.GOALTENDING),
                metric("xGA/60", 2.5, off(10), MetricCategory.GOALTENDING),
                metric("Rebound%", 6.8 / scale, off(7), MetricCategory.GOALTENDING),
                metric("Saves", 150 * volume, off(12), MetricCategory.GOALTENDING),
                metric("W", 4 * volume, off(9), MetricCategory.GOALTENDING),
            )
        }
    }

    private fun metric(label: String, value: Double, percentile: Int, category: MetricCategory) =
        Metric(label = label, value = formatted(label, value), percentile = percentile, category = category, qualified = true)

    private fun formatted(label: String, value: Double): String = when (label) {
        "Sh%", "xGF%", "CF%", "HDCF%", "GF%", "Rebound%" -> String.format(Locale.US, "%.1f%%", value)
        "GAx", "GSAx", "Rel xGF%", "Rel CF%" -> String.format(Locale.US, "%+.1f", value)
        "SV%", "HD SV%" -> RecentMetricKey.savePercentage(value)
        "P/60", "ixG/60", "xGF/60", "xGA/60", "GSAx/60", "GAA", "Game Score" -> String.format(Locale.US, "%.2f", value)
        "ixG", "Shots/60" -> String.format(Locale.US, "%.1f", value)
        else -> NumberFormat.getIntegerInstance(Locale.US).format(swiftRound(value))
    }

    private fun standardStats(seed: Seed, scale: Double, volume: Double): List<StandardStat> {
        fun s(label: String, value: String) = StandardStat(label = label, value = value)
        val rank = 0.72 + seed.percentile / 100.0 * 0.28
        fun total(base: Double) = "${round(base * rank * scale * volume)}"
        val games = if (volume > 1) 76 else 8
        if (seed.type == "g") {
            val started = if (volume > 1) 58 else 6
            val shots = round(29.0 * started)
            val saves = round(shots * (0.905 + 0.03 * rank * scale))
            val wins = round(started * 0.45 * rank * scale)
            return listOf(
                s("GP", "$started"), s("GS", "$started"),
                s("W", "$wins"), s("L", "${max(0, started - wins - 2)}"), s("OT", "2"),
                s("GAA", String.format(Locale.US, "%.2f", (shots - saves).toDouble() / (started * 60.0) * 60)),
                s("SV%", RecentMetricKey.savePercentage(saves.toDouble() / shots)),
                s("SO", if (volume > 1) "4" else "1"),
                s("SA", "$shots"), s("SV", "$saves"),
            )
        }
        val (goals, assists, shots) = counting(seed, scale * volume)
        val season = scale * volume
        val strength = (seed.percentile - 50) / 50.0
        fun noise(salt: Int) = FixtureGames.unit("std-${seed.id}", salt) - 0.5
        val stats = mutableListOf(
            s("GP", "$games"), s("G", "$goals"), s("A", "$assists"),
            s("P", "${goals + assists}"), s("+/-", String.format(Locale.US, "%+d", round((1 + 5 * strength + 4 * noise(4)) * season))),
            s("PIM", total(4.0)), s("PPG", total(1.5)), s("PPP", total(3.5)),
            s("SHG", "0"), s("GWG", total(1.0)), s("SOG", "$shots"),
            s("Sh%", String.format(Locale.US, "%.1f%%", if (shots > 0) goals.toDouble() / shots * 100 else 0.0)),
            s("TOI/GP", if (seed.type == "d") "23:48" else "18:52"),
            s("Hits", total(12.0)), s("Blk", total(if (seed.type == "d") 14.0 else 5.0)),
        )
        if (seed.position == "C") stats += s("FO%", "52.4%")
        return stats
    }

    private fun daysBefore(days: Int): Instant = asOf.atZone(ZoneId.systemDefault()).minusDays(days.toLong()).toInstant()

    private fun gameTrends(seed: Seed, prior: Boolean): List<GameTrend> {
        val opponents = listOf("VAN", "CGY", "LAK", "SJS", "ANA")
        return (0 until 5).map { index ->
            GameTrend(
                id = "${seed.id}-${if (prior) "prior" else "current"}-$index",
                date = daysBefore(index * 2),
                opponent = opponents[index],
                summary = if (index == 0) "Strong finish" else "Solid night",
                percentileDelta = (if (prior) 1 else 2) * (5 - index),
                keyMetric = if (seed.type == "g") "GSAx" else "ixG",
            )
        }
    }

    /** Eight games over the two weeks before the capture date. */
    private val gameDayOffsets = listOf(12, 10, 9, 7, 5, 3, 2, 0)

    private fun makeGameLogs(player: Player): List<PlayerGameLog> {
        val type = player.playerType ?: "f"
        val opponents = listOf("VAN", "CGY", "LAK", "SJS", "ANA", "VGK", "UTA", "STL")
        return gameDayOffsets.mapIndexed { index, offset ->
            PlayerGameLog(
                playerId = player.playerId,
                season = season,
                seasonPhase = SeasonPhase.REGULAR,
                gameDate = daysBefore(offset),
                playerType = type,
                team = player.team,
                opponent = opponents[index],
                plays = plays(type),
                touches = touches(type),
                metrics = gameMetrics(type, 1.0 + index * 0.04),
            )
        }
    }

    /** Ice time in whole minutes. */
    private fun plays(type: String) = when (type) {
        "f" -> 19
        "d" -> 24
        else -> 60
    }

    /** Shot attempts for a skater, shots against for a goalie. */
    private fun touches(type: String) = when (type) {
        "f" -> 6
        "d" -> 4
        else -> 28
    }

    private fun gameMetrics(type: String, f: Double): Map<String, Double> = when (type) {
        "g" -> mapOf(
            "shots_against" to 28 * f, "saves" to 26 * f, "goals_against" to 2.0,
            "xga" to 2.4 * f, "hd_shots_against" to 8 * f, "hd_goals_against" to 1.0,
            "toi_seconds" to 3_600.0, "decision_win" to 1.0, "shutout" to 0.0, "started" to 1.0,
        )
        else -> mapOf(
            "goals" to 0.6 * f, "assists" to 0.7 * f, "primary_assists" to 0.4 * f,
            "points" to 1.3 * f, "shots_on_goal" to 3.4 * f, "shot_attempts" to 6 * f,
            "ixg" to 0.62 * f, "hd_shots" to 1.4 * f, "hits" to 1.6 * f,
            "blocks" to 0.9 * f, "takeaways" to 0.8 * f, "giveaways" to 0.7,
            "pim" to 0.5, "plus_minus" to 0.4 * f, "pp_goals" to 0.2 * f,
            "faceoffs_won" to 7.0, "faceoffs_lost" to 6.0, "toi_seconds" to if (type == "d") 1_440.0 else 1_140.0,
        )
    }

    private fun makeRecentForm(player: Player, windowWeeks: Int): RecentForm {
        val type = player.playerType ?: "f"
        val seed = (FixtureGames.fnv("recent-${player.playerId}") % 9uL).toDouble() / 10
        val games = if (type == "g") max(2, windowWeeks) else min(windowWeeks * 3, 8)
        val metrics: Map<String, Double>
        val delta: Map<String, Double>
        if (type == "g") {
            metrics = mapOf(
                "sv_pct" to 0.931 - seed / 20, "gaa" to 2.1 + seed, "gsax" to 3.2 - seed * 2,
                "gsax_per_60" to 0.41 - seed / 5, "hd_sv_pct" to 0.861 - seed / 20,
                "shots_against_per_60" to 27.5, "saves" to 140.0, "goals_against" to 10.0,
                "games" to games.toDouble(), "wins" to games - 1.0,
            )
            delta = mapOf(
                "sv_pct" to 0.018 - seed / 25, "gaa" to -0.4 + seed / 2, "gsax" to 2.1 - seed,
                "gsax_per_60" to 0.22 - seed / 6, "hd_sv_pct" to 0.02 - seed / 30,
                "shots_against_per_60" to 1.1,
            )
        } else {
            metrics = mapOf(
                "points_per_60" to 3.8 - seed, "goals_per_60" to 1.6 - seed / 2, "ixg_per_60" to 1.3 - seed / 4,
                "gax" to 1.4 - seed, "shooting_pct" to 17 - seed * 6, "shots_per_60" to 12.8,
                "hd_shots_per_60" to 4.1, "blocks_per_60" to 1.0, "hits_per_60" to 3.2,
                "goals" to 5.0, "assists" to 6.0, "points" to 11.0, "shots_on_goal" to 28.0,
                "ixg" to 3.9 - seed, "games" to games.toDouble(),
            )
            delta = mapOf(
                "points_per_60" to 1.4 - seed, "goals_per_60" to 0.7 - seed / 3, "ixg_per_60" to 0.3 - seed / 8,
                "gax" to 0.9 - seed / 2, "shooting_pct" to 4.2 - seed * 3, "shots_per_60" to 1.1,
                "hd_shots_per_60" to 0.6, "blocks_per_60" to 0.1, "hits_per_60" to 0.2,
            )
        }
        // Every player moved by a different amount, so the board does not read as
        // one number repeated down the page.
        val wobble = 0.6 + FixtureGames.unit("wobble-${player.playerId}", windowWeeks) * 0.9
        // Over half the players slid instead, so Cooling off has real decliners to show.
        val direction = if (seed >= 0.4) -1.0 else 1.0
        val moved = delta.mapValues { it.value * wobble * direction }
        val priorMetrics = metrics.toMutableMap().apply { moved.forEach { (k, change) -> this[k] = (this[k] ?: 0.0) - change } }
        return RecentForm(
            playerId = player.playerId,
            season = season,
            seasonPhase = SeasonPhase.REGULAR,
            playerType = type,
            windowWeeks = windowWeeks,
            asOf = asOf,
            startWeek = 1,
            endWeek = 3,
            team = player.team,
            games = games,
            plays = plays(type) * games,
            touches = touches(type) * games,
            metrics = metrics,
            priorMetrics = priorMetrics,
            delta = moved,
        )
    }
}
