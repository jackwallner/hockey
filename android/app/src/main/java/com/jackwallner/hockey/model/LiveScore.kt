package com.jackwallner.hockey.model

import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * The running score of a game under way, read straight from the NHL's public
 * scoreboard. The backend publishes a score only at the final, so this is
 * what lets a game in progress show its score and clock.
 */
data class LiveScore(
    val gameId: String,
    val awayScore: Int,
    val homeScore: Int,
    val awayShots: Int?,
    val homeShots: Int?,
    /** NHL `gameState`: FUT, PRE, LIVE, CRIT, FINAL or OFF. */
    val state: String,
    val period: Int,
    val periodType: String,
    /** "12:34" left in the period. */
    val timeRemaining: String?,
    val inIntermission: Boolean,
) {
    val isFinal: Boolean get() = state in setOf("FINAL", "OFF")
    val isUnderway: Boolean get() = state in setOf("LIVE", "CRIT")

    /** "1st", "2nd", "3rd", "OT", "2OT". */
    val periodLabel: String
        get() = when {
            periodType == "SO" -> "SO"
            period == 1 -> "1st"
            period == 2 -> "2nd"
            period == 3 -> "3rd"
            period == 4 -> "OT"
            else -> "${period - 3}OT"
        }

    /** "2nd 12:34", "2nd INT", "Shootout", "End 3rd", "Final/OT". */
    val clockLabel: String
        get() {
            if (isFinal) {
                return when (periodType) {
                    "OT" -> if (period > 4) "Final/${period - 3}OT" else "Final/OT"
                    "SO" -> "Final/SO"
                    else -> "Final"
                }
            }
            if (periodType == "SO") return "Shootout"
            if (inIntermission) return "$periodLabel INT"
            val remaining = timeRemaining
            if (remaining == null || remaining == "00:00") return "End $periodLabel"
            val clock = if (remaining.startsWith("0")) remaining.drop(1) else remaining
            return "$periodLabel $clock"
        }

    fun score(isHome: Boolean): Int = if (isHome) homeScore else awayScore

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Games from one `score/<date>` payload that have started. */
        fun parse(body: String): List<LiveScore> {
            val root = runCatching { json.parseToJsonElement(body) as? JsonObject }.getOrNull() ?: return emptyList()
            val games = root.array("games") ?: return emptyList()
            return games.mapNotNull { element ->
                val game = element as? JsonObject ?: return@mapNotNull null
                val state = game.string("gameState") ?: return@mapNotNull null
                val id = game.prim("id")?.content ?: return@mapNotNull null
                val away = game.obj("awayTeam")
                val home = game.obj("homeTeam")
                val awayScore = away?.int("score") ?: return@mapNotNull null
                val homeScore = home?.int("score") ?: return@mapNotNull null
                if (state == "FUT" || state == "PRE") return@mapNotNull null
                val descriptor = game.obj("periodDescriptor")
                val clock = game.obj("clock")
                LiveScore(
                    gameId = id,
                    awayScore = awayScore,
                    homeScore = homeScore,
                    awayShots = away.int("sog"),
                    homeShots = home.int("sog"),
                    state = state,
                    period = descriptor?.int("number") ?: game.int("period") ?: 1,
                    periodType = descriptor?.string("periodType") ?: "REG",
                    timeRemaining = clock?.string("timeRemaining"),
                    inIntermission = clock?.bool("inIntermission") ?: false,
                )
            }
        }

        /** The NHL files a game under its local date; `Game.gameDate` holds it at Eastern midnight. */
        fun dateKey(date: Instant): String = date.atZone(EASTERN).toLocalDate().toString()
    }
}
