package com.jackwallner.hockey.model

import java.util.Locale
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * A basic box score rebuilt from one game's `player_game_logs` rows: raw NHL
 * boxscore counts joined with MoneyPuck's shot-level expected goals. Nothing
 * here is a roster average or a percentile.
 */
class GameBoxScore(logs: List<PlayerGameLog>) {
    data class PlayerLine(val playerId: Int, val team: String, val playerType: String, val metrics: Map<String, Double>) {
        val id: String get() = "$playerId-$playerType"
        val isGoalie: Boolean get() = playerType.lowercase() == "g"
        fun value(key: String): Double = metrics[key] ?: 0.0
        fun int(key: String): Int = swiftRound(value(key))

        /** "19:42", from `toi_seconds`. */
        val toiLabel: String?
            get() {
                val seconds = int("toi_seconds")
                if (seconds <= 0) return null
                return String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60)
            }
    }

    val lines: List<PlayerLine> = logs.map { log ->
        PlayerLine(log.playerId, normalizedTeamAbbreviation(log.team ?: ""), log.playerType, log.metrics)
    }

    val isEmpty: Boolean get() = lines.isEmpty()

    fun lines(team: String): List<PlayerLine> {
        val abbr = normalizedTeamAbbreviation(team)
        return lines.filter { it.team == abbr }
    }

    companion object {
        /** "1 G, 1 A, 4 SOG, 0.62 ixG, 19:42 TOI" for a skater, leaving out what he did not do. */
        fun skaterSummary(line: PlayerLine): String {
            val parts = mutableListOf<String>()
            if (line.int("goals") > 0) parts += "${line.int("goals")} G"
            if (line.int("assists") > 0) parts += "${line.int("assists")} A"
            if (parts.isEmpty()) parts += "0 P"
            parts += "${line.int("shots_on_goal")} SOG"
            if (line.metrics["ixg"] != null) parts += "${cFixed(line.value("ixg"), 2)} ixG"
            line.toiLabel?.let { parts += "$it TOI" }
            return parts.joinToString(", ")
        }

        /** "28 saves on 30 shots, 2 GA" for a goalie. */
        fun goalieSummary(line: PlayerLine): String {
            val parts = mutableListOf("${line.int("saves")} saves on ${line.int("shots_against")} shots")
            parts += "${line.int("goals_against")} GA"
            if (line.metrics["xga"] != null) parts += "${cFixed(line.value("xga"), 2)} xGA"
            return parts.joinToString(", ")
        }

        /** A player's one-line game summary. */
        fun summary(line: PlayerLine): String = if (line.isGoalie) goalieSummary(line) else skaterSummary(line)
    }
}

/** "1", "1.5": Swift's `.precision(.fractionLength(0...1))`. */
fun formatUpToOneDecimal(value: Double): String {
    val rounded = swiftRoundDouble(value * 10) / 10
    return if (rounded == Math.floor(rounded)) rounded.toLong().toString() else String.format(Locale.US, "%.1f", rounded)
}

/** A number with its percentile among this season's team games or qualifying player games. */
data class RatedValue(val value: Double, val percentile: Int? = null) {
    companion object {
        fun from(element: kotlinx.serialization.json.JsonElement?): RatedValue? = when (element) {
            is JsonPrimitive -> if (element.isString) null else element.doubleOrNull?.let { RatedValue(it) }
            is JsonObject -> element.double("value")?.let { RatedValue(it, element.int("pct")) }
            else -> null
        }
    }
}

/**
 * Each side's expected goals for one final, the number the Games list shows
 * under a score, plus the power-play and shot counts the season team
 * summaries add up.
 */
data class GameXG(
    val away: Double,
    val home: Double,
    val awayPowerPlayGoals: Int? = null,
    val awayPowerPlays: Int? = null,
    val homePowerPlayGoals: Int? = null,
    val homePowerPlays: Int? = null,
    val awayShots: Int? = null,
    val homeShots: Int? = null,
) {
    /** "xG 2.9-1.7", away first like the rows above it. */
    val label: String get() = "xG " + cFixed(away, 1) + "-" + cFixed(home, 1)
}

/**
 * Shot-level breakdown for one game, from `public.game_details`: expected
 * goals by side, every skater's and goalie's line, the cumulative xG race,
 * and the chances that decided it.
 */
data class GameDetail(
    val gameId: String,
    val awayTeam: String,
    val homeTeam: String,
    val away: Map<String, RatedValue>,
    val home: Map<String, RatedValue>,
    val players: List<PlayerLine>,
    val xgRace: List<XGRacePoint>,
    val bigPlays: List<BigPlay>,
) {
    enum class Role { SKATER, GOALIE }

    data class PlayerLine(
        val role: Role,
        val playerId: Int,
        val name: String?,
        val team: String,
        val position: String?,
        /** Seconds on ice. */
        val toi: Int?,
        val goals: Int? = null,
        val assists: Int? = null,
        val points: Int? = null,
        val sog: Int? = null,
        val shotAttempts: Int? = null,
        val hdShots: Int? = null,
        val ixg: RatedValue? = null,
        val gax: RatedValue? = null,
        val ixgPer60: RatedValue? = null,
        val shotsAgainst: Int? = null,
        val saves: Int? = null,
        val goalsAgainst: Int? = null,
        val xga: RatedValue? = null,
        val gsax: RatedValue? = null,
        val svPct: RatedValue? = null,
    ) {
        val id: String get() = "${role.name.lowercase()}-$playerId"

        /** "18:42". */
        val toiLabel: String? get() = toi?.let { String.format(Locale.US, "%d:%02d", it / 60, it % 60) }

        companion object {
            fun fromJson(o: JsonObject): PlayerLine {
                val role = when (o.requireString("role")) {
                    "skater" -> Role.SKATER
                    "goalie" -> Role.GOALIE
                    else -> throw RowDecodeException("role")
                }
                // A present-but-malformed rated value fails the line, as Swift's decoder does.
                fun rated(key: String): RatedValue? {
                    val el = o[key] ?: return null
                    if (el is JsonNull) return null
                    return RatedValue.from(el) ?: throw RowDecodeException(key)
                }
                return PlayerLine(
                    role = role,
                    playerId = o.requireInt("player_id"),
                    name = o.string("name"),
                    team = o.requireString("team"),
                    position = o.string("position"),
                    toi = o.int("toi"),
                    goals = o.int("goals"),
                    assists = o.int("assists"),
                    points = o.int("points"),
                    sog = o.int("sog"),
                    shotAttempts = o.int("shot_attempts"),
                    hdShots = o.int("hd_shots"),
                    ixg = rated("ixg"),
                    gax = rated("gax"),
                    ixgPer60 = rated("ixg_per_60"),
                    shotsAgainst = o.int("shots_against"),
                    saves = o.int("saves"),
                    goalsAgainst = o.int("goals_against"),
                    xga = rated("xga"),
                    gsax = rated("gsax"),
                    svPct = rated("sv_pct"),
                )
            }
        }
    }

    data class BigPlay(
        val period: Int,
        val clock: String,
        val team: String,
        val description: String,
        val xg: Double?,
        /** GOAL, SAVE, MISS or BLOCK. */
        val result: String,
        val playerId: Int?,
        val shooter: String?,
        /** Goals only: assisting players' full names, primary first. */
        val assists: List<String>? = null,
        /** Goals only: "PP", "SH" or "EN"; null at even strength. */
        val strength: String? = null,
        /** Goals only: the score after it, `[away, home]`. */
        val score: List<Int>? = null,
        /** Goals only: the scorer's season goal count, the "(5)" of a summary. */
        val goalNumber: Int? = null,
    ) {
        val id: String get() = "$period-$clock-$team-$result-${playerId ?: 0}"
        val isGoal: Boolean get() = result.uppercase() == "GOAL"

        /** "Saved", "Missed", "Blocked" for a chance that did not score. */
        val resultLabel: String?
            get() = when (result.uppercase()) {
                "SAVE" -> "Saved"
                "MISS" -> "Missed"
                "BLOCK" -> "Blocked"
                else -> null
            }

        /** "Draisaitl, Nugent-Hopkins", "Unassisted", or null before the feed carried assists. */
        val assistLine: String?
            get() {
                if (!isGoal) return null
                val assists = assists ?: return null
                if (assists.isEmpty()) return "Unassisted"
                // Brothers on one line ("Protas, Protas") need their initials.
                val last = assists.map(::lastName)
                return assists.zip(last).joinToString(", ") { (full, surname) ->
                    if (last.count { it == surname } > 1 && full.isNotEmpty()) "${full.first()}. $surname" else surname
                }
            }

        companion object {
            /** "Connor McDavid" -> "McDavid", "James van Riemsdyk" -> "van Riemsdyk". */
            fun lastName(name: String): String {
                val parts = name.split(" ", limit = 2)
                return if (parts.size == 2) parts[1] else name
            }

            fun fromJson(o: JsonObject) = BigPlay(
                period = o.requireInt("period"),
                clock = o.requireString("clock"),
                team = o.requireString("team"),
                description = o.requireString("description"),
                xg = o.double("xg"),
                result = o.requireString("result"),
                playerId = o.int("player_id"),
                shooter = o.string("shooter"),
                assists = o.array("assists")?.map {
                    (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull ?: throw RowDecodeException("assists")
                },
                strength = o.string("strength"),
                score = o.array("score")?.map { el ->
                    (el as? JsonPrimitive)?.doubleOrNull?.toInt() ?: throw RowDecodeException("score")
                },
                goalNumber = o.int("goal_number"),
            )
        }
    }

    /** One point on the cumulative expected-goals race. */
    data class XGRacePoint(val elapsed: Double, val awayXG: Double, val homeXG: Double, val awayGoals: Int, val homeGoals: Int)

    fun stats(team: String): Map<String, RatedValue> =
        if (normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(homeTeam)) home else away

    /** Skaters by individual expected goals, goalies by goals saved above expected. */
    fun players(role: Role): List<PlayerLine> = when (role) {
        Role.SKATER -> players.filter { it.role == Role.SKATER }.sortedByDescending { it.ixg?.value ?: Double.NEGATIVE_INFINITY }
        Role.GOALIE -> players.filter { it.role == Role.GOALIE }.sortedByDescending { it.gsax?.value ?: Double.NEGATIVE_INFINITY }
    }

    fun players(role: Role, team: String): List<PlayerLine> =
        players(role).filter { normalizedTeamAbbreviation(it.team) == normalizedTeamAbbreviation(team) }

    companion object {
        fun fromJson(o: JsonObject): GameDetail {
            val sides = o.obj("team_stats")
            fun side(key: String): Map<String, RatedValue> {
                val raw = sides?.obj(key) ?: return emptyMap()
                return raw.mapNotNull { (k, v) -> RatedValue.from(v)?.let { k to it } }.toMap()
            }
            val race = (o["win_probability"] as? JsonArray).orEmpty().mapNotNull { row ->
                val values = (row as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.doubleOrNull } ?: return@mapNotNull null
                if (values.size >= 5) {
                    XGRacePoint(values[0], values[1], values[2], swiftRound(values[3]), swiftRound(values[4]))
                } else {
                    null
                }
            }
            return GameDetail(
                gameId = o.requireString("game_id"),
                awayTeam = o.requireString("away_team"),
                homeTeam = o.requireString("home_team"),
                away = side("away"),
                home = side("home"),
                players = o["players"]?.lenientList(PlayerLine::fromJson).orEmpty(),
                xgRace = race,
                bigPlays = o["big_plays"]?.lenientList(BigPlay::fromJson).orEmpty(),
            )
        }
    }
}
