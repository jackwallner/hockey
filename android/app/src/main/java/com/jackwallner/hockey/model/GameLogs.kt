package com.jackwallner.hockey.model

import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlinx.serialization.json.JsonObject

/** One player's contribution in one game (one row per player_type). */
data class PlayerGameLog(
    val playerId: Int,
    val season: Int,
    /** Every "last N games" window filters on this; playoffs are the newest rows. */
    val seasonPhase: SeasonPhase,
    /** NHL game id, e.g. "2026020012". The join key to [Game]. */
    val gameId: String? = null,
    val gameDate: Instant,
    val playerType: String,
    val team: String?,
    val opponent: String?,
    /** Ice time in whole minutes (the column keeps its original name). */
    val plays: Int,
    /** Shot attempts for a skater, shots against for a goalie. */
    val touches: Int,
    /** JSONB of nullable numbers; nulls are dropped. */
    val metrics: Map<String, Double>,
) {
    companion object {
        fun fromJson(o: JsonObject) = PlayerGameLog(
            playerId = o.requireInt("player_id"),
            season = o.requireInt("season"),
            seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad phase") } ?: SeasonPhase.REGULAR,
            gameId = o.string("game_id"),
            gameDate = parseDay(o.requireString("game_date")) ?: throw RowDecodeException("bad game_date"),
            playerType = o.requireString("player_type"),
            team = o.string("team"),
            opponent = o.string("opponent"),
            plays = o.int("plays") ?: 0,
            touches = o.int("touches") ?: 0,
            metrics = o.numberMap("metrics"),
        )
    }
}

/** Stats over a trailing span of weeks (2 / 4 / 8), summed from the game logs. */
data class RecentFormWindow(
    val label: String,
    val span: Int,
    val games: Int,
    val plays: Int,
    val touches: Int,
    val metrics: Map<String, Double>,
) {
    companion object {
        /** Same three choices, same wording, on every surface. */
        val windows: List<Pair<String, Int>> = RecentWindow.entries.map { it.label to it.value }

        /** What to call a window of [games] played in a [span]-week window. */
        @Suppress("UNUSED_PARAMETER")
        fun caption(games: Int, span: Int): String = if (games == 1) "1 game" else "$games games"

        /**
         * Logs from the trailing [weeks] before the newest one in the set,
         * newest first. A card holding one player's or one club's logs anchors
         * on the latest game in them.
         */
        fun logs(logs: List<PlayerGameLog>, weeks: Int, zone: ZoneId = ZoneId.systemDefault()): List<PlayerGameLog> {
            val anchor = logs.maxOfOrNull { it.gameDate } ?: return emptyList()
            val start = anchor.atZone(zone).minusDays(weeks * 7L).toInstant()
            return logs.filter { it.gameDate > start }.sortedByDescending { it.gameDate }
        }

        /** Season labels the Recent card draws bars for, in display order. */
        fun recentLabels(goalie: Boolean): List<String> =
            if (goalie) listOf("SV%", "GSAx/60", "GAA", "HD SV%") else listOf("P/60", "ixG/60", "Shots/60", "Sh%")

        fun build(label: String, span: Int, logs: List<PlayerGameLog>): RecentFormWindow {
            val combined = LinkedHashMap<String, Double>()
            for (log in logs) {
                for ((key, value) in log.metrics) combined[key] = (combined[key] ?: 0.0) + value
            }
            // Games, not rows: a team window has one row per player per game.
            val games = logs.map { it.gameDate }.toSet().size
            return RecentFormWindow(label, span, games, logs.sumOf { it.plays }, logs.sumOf { it.touches }, combined)
        }
    }

    /** Ice time in the window, in hours. */
    private val hours: Double? get() = (metrics["toi_seconds"] ?: 0.0).takeIf { it > 0 }?.let { it / 3_600 }

    /**
     * The window's value for a season metric, rebuilt from summed counts.
     * Rates only: a four-week total read against a full-season ruler would
     * mislead. Null when the window has no denominator for it.
     */
    fun value(seasonLabel: String): Double? {
        fun total(key: String): Double? = metrics[key]
        fun per60(key: String): Double? {
            val h = hours ?: return null
            val sum = total(key) ?: return null
            return sum / h
        }
        return when (seasonLabel) {
            "P/60" -> per60("points")
            "ixG/60" -> per60("ixg")
            "Shots/60" -> per60("shot_attempts")
            "Sh%" -> {
                val goals = total("goals") ?: return null
                val shots = total("shots_on_goal")?.takeIf { it > 0 } ?: return null
                goals / shots * 100
            }
            "SV%" -> {
                val saves = total("saves") ?: return null
                val faced = total("shots_against")?.takeIf { it > 0 } ?: return null
                saves / faced
            }
            "GAA" -> per60("goals_against")
            "GSAx/60" -> {
                val h = hours ?: return null
                val xga = total("xga") ?: return null
                val against = total("goals_against") ?: return null
                (xga - against) / h
            }
            "HD SV%" -> {
                val faced = total("hd_shots_against")?.takeIf { it > 0 } ?: return null
                val against = total("hd_goals_against") ?: return null
                1 - against / faced
            }
            else -> null
        }
    }
}

/** One player's league-anchored weekly window from `player_recent_form`. */
data class RecentForm(
    val playerId: Int,
    val season: Int,
    val seasonPhase: SeasonPhase,
    val playerType: String,
    val windowWeeks: Int,
    /** Date of the last game in the window. */
    val asOf: Instant?,
    val startWeek: Int?,
    val endWeek: Int?,
    val team: String?,
    val games: Int,
    val plays: Int,
    val touches: Int,
    val metrics: Map<String, Double>,
    val priorMetrics: Map<String, Double>,
    val delta: Map<String, Double>,
) {
    val id: String get() = "$playerId-${seasonPhase.raw}-$playerType-$windowWeeks"

    /** Dates covered, e.g. "Sep 24 - Oct 7". Null when the rollup carries no anchor date. */
    val weekRangeLabel: String? get() = weekRangeLabel(null)

    /** The span, starting no earlier than [notBefore] (opening night). */
    fun weekRangeLabel(notBefore: Instant?, zone: ZoneId = ZoneId.systemDefault()): String? {
        val asOf = asOf ?: return null
        var start = asOf.atZone(zone).minusDays(windowWeeks * 7L - 1).toInstant()
        if (notBefore != null && notBefore > start && notBefore <= asOf) start = notBefore
        val style = java.time.format.DateTimeFormatter.ofPattern("MMM d", Locale.US)
        return "${style.format(start.atZone(zone))} - ${style.format(asOf.atZone(zone))}"
    }

    /**
     * Small samples make wild deltas. A skater needs an hour of ice time in
     * the window before a rate is worth ranking; a goalie two starts' worth.
     */
    val isSmallSample: Boolean get() = isSmallSample(2)

    fun isSmallSample(minimumGames: Int): Boolean {
        if (games < minimumGames) return true
        return if (playerType == "g") plays < 100 else plays < 60
    }

    companion object {
        fun fromJson(o: JsonObject) = RecentForm(
            playerId = o.requireInt("player_id"),
            season = o.requireInt("season"),
            seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad phase") } ?: SeasonPhase.REGULAR,
            playerType = o.requireString("player_type"),
            windowWeeks = o.int("window_weeks") ?: o.requireInt("window_games"),
            // A Postgres date at local midnight, as iOS reads it.
            asOf = o.string("as_of")?.let { parseDay(it, ZoneId.systemDefault()) },
            startWeek = o.int("start_week"),
            endWeek = o.int("end_week"),
            team = o.string("team"),
            games = o.int("games") ?: 0,
            plays = o.int("plays") ?: 0,
            touches = o.int("touches") ?: 0,
            metrics = o.numberMap("metrics"),
            priorMetrics = o.numberMap("prior_metrics"),
            delta = o.numberMap("delta"),
        )
    }
}

/** Season metric label to the rolling rollup's column, plus the window formatter. */
object RecentMetricKey {
    fun key(label: String): String? = when (label) {
        // Scoring.
        "G" -> "goals"
        "A" -> "assists"
        "P" -> "points"
        "P/60" -> "points_per_60"
        "Primary P" -> "primary_points"
        "SOG" -> "shots_on_goal"
        "Sh%" -> "shooting_pct"
        // Shot Quality.
        "ixG" -> "ixg"
        "GAx" -> "gax"
        "ixG/60" -> "ixg_per_60"
        "Shots/60" -> "shots_per_60"
        "Shot Att" -> "shot_attempts"
        "HD Shots" -> "hd_shots"
        // Play Driving (counting stats only; on-ice shares have no per-game feed).
        "Blocks" -> "blocks"
        "Hits" -> "hits"
        "Takeaways" -> "takeaways"
        "Giveaways" -> "giveaways"
        // Goaltending.
        "GSAx" -> "gsax"
        "GSAx/60" -> "gsax_per_60"
        "SV%" -> "sv_pct"
        "GAA" -> "gaa"
        "HD SV%" -> "hd_sv_pct"
        "xGA/60" -> "xga_per_60"
        "Saves" -> "saves"
        "GA" -> "goals_against"
        "W" -> "wins"
        "SO" -> "shutouts"
        else -> null
    }

    /** True where a falling number is the improvement. */
    fun lowerIsBetter(label: String): Boolean = label in setOf("GAA", "GA", "Giveaways", "Rebound%")

    /** Counting stats whole, xG totals tenths, per-60 rates hundredths, save percentages thousandths. */
    fun decimals(label: String): Int = when (label) {
        "SV%", "HD SV%", "xG/Shot" -> 3
        "P/60", "ixG/60", "GSAx/60", "xGA/60", "xGF/60", "GAA", "Game Score" -> 2
        "ixG", "GAx", "GSAx", "Rel xGF%", "Rel CF%", "Shots/60" -> 1
        else -> if (label.endsWith("%")) 1 else 0
    }

    /** A save percentage reads ".915", a share "54.2%", a rate its decimals and a count none. */
    fun format(value: Double, label: String): String {
        if (label.endsWith("SV%")) return savePercentage(value)
        val places = decimals(label)
        if (label.endsWith("%")) return cFixed(value, 1) + "%"
        if (places == 0) return NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong())
        return cFixed(value, places)
    }

    /** 0.915 or 91.5 -> ".915". The rollup stores save percentage as a fraction. */
    fun savePercentage(value: Double): String {
        val fraction = if (value > 1.5) value / 100 else value
        val text = cFixed(fraction, 3)
        return if (text.startsWith("0")) text.drop(1) else text
    }
}

/** Per-player and per-team windows: the same league-anchored week ranges Trends uses. */
enum class RecentWindow(val value: Int) {
    TWO(2), FOUR(4), EIGHT(8);

    val label: String get() = "Last $value weeks"
    val segmentLabel: String get() = "$value wks"
    val shortLabel: String get() = "${value}W"

    companion object {
        fun of(value: Int): RecentWindow? = entries.firstOrNull { it.value == value }
    }
}

/** League-anchored windows used only by Trends. */
enum class TrendWindow(val value: Int) {
    TWO(2), FOUR(4), EIGHT(8);

    val label: String get() = "Last $value weeks"
    val segmentLabel: String get() = "$value weeks"

    companion object {
        fun of(value: Int): TrendWindow? = entries.firstOrNull { it.value == value }
    }
}

/** Keeps a followed list in the fan's order and in the selected season/phase. */
object FanStatsSelection {
    fun players(ids: List<Int>, from: List<Player>, season: Int, phase: SeasonPhase): List<Player> {
        val byId = LinkedHashMap<Int, Player>()
        for (p in from) if (p.season == season && p.seasonPhase == phase) byId.putIfAbsent(p.playerId, p)
        val seen = HashSet<Int>()
        return ids.mapNotNull { id -> if (seen.add(id)) byId[id] else null }
    }

    fun summary(player: Player): List<StandardStat> {
        val labels = when (player.positionGroup) {
            PlayerPositionGroup.FORWARD -> listOf("G", "A", "P", "SOG")
            PlayerPositionGroup.DEFENSE -> listOf("P", "+/-", "Blk", "TOI/GP")
            PlayerPositionGroup.GOALIE -> listOf("W", "GAA", "SV%")
        }
        return labels.mapNotNull { label -> player.standardStats?.firstOrNull { it.label == label } }
    }
}
