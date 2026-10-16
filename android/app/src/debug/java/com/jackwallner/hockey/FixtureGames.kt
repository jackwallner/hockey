package com.jackwallner.hockey

import com.jackwallner.hockey.model.Game
import com.jackwallner.hockey.model.GameDetail
import com.jackwallner.hockey.model.PlayerProfile
import com.jackwallner.hockey.model.StandingsRow
import com.jackwallner.hockey.model.TeamRating
import com.jackwallner.hockey.model.leagueTeamAbbreviations
import com.jackwallner.hockey.model.swiftRound
import com.jackwallner.hockey.model.swiftRoundDouble
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Invented schedule, results and shot breakdowns for the screenshot harness, a
 * port of the iOS `ScreenshotFixtureGames`. Eight rounds of a 32-team circle
 * schedule over the two weeks to last night, so every club has eight finals.
 * Every number comes from a hash of the game id, so a run never changes.
 */
internal object FixtureGames {
    private val season get() = ScreenshotFixtureApi.season
    private val zone: ZoneId get() = ZoneId.systemDefault()

    /** FNV-1a over the text, so every invented number is stable across runs. */
    fun fnv(text: String): ULong {
        var hash = 0xcbf29ce484222325uL
        for (byte in text.toByteArray(Charsets.UTF_8)) {
            hash = (hash xor byte.toUByte().toULong()) * 0x100000001b3uL
        }
        hash = hash xor (hash shr 29)
        hash *= 0xbf58476d1ce4e5b9uL
        hash = hash xor (hash shr 32)
        return hash
    }

    /** A stable value in 0..<1 for a text and a salt. */
    fun unit(text: String, salt: Int): Double = (fnv("$text-$salt") % 10_000uL).toDouble() / 10_000

    private fun plusDays(instant: Instant, days: Int): Instant = instant.atZone(zone).plusDays(days.toLong()).toInstant()

    /** Fourteen days before the last slot, which is last night. */
    private val openingNight: Instant by lazy { plusDays(ScreenshotFixtureApi.asOf.plusSeconds(3 * 3_600), -14) }

    val games: List<Game> by lazy {
        val finals = makeGames()
        if (ScreenshotFixtureApi.slate) finals + makeSlate() else finals
    }

    val gameIds: Set<String> get() = games.filter { it.isFinal }.map { it.id }.toSet()

    /** Sixteen clubs tonight and eight on each of the two days after. Seattle plays tomorrow, not tonight. */
    private fun makeSlate(): List<Game> {
        val now = Instant.now()
        val startOfToday = LocalDate.now(zone).atStartOfDay(zone).toInstant()
        val endOfToday = plusDays(startOfToday, 1).minusSeconds(60)
        val teams = leagueTeamAbbreviations.sorted().filter { it != "SEA" }
        val result = mutableListOf<Game>()
        fun add(index: Int, away: String, home: String, kickoff: Instant) {
            result += Game(
                id = String.format(Locale.US, "20260300%02d", index), season = season, week = 3,
                kickoff = kickoff, awayTeam = away, homeTeam = home,
            )
        }
        for (index in 0 until 8) {
            val kickoff = if (index < 2) {
                maxOf(startOfToday.plusSeconds(60), now.minusSeconds(3_600))
            } else {
                minOf(endOfToday, now.plusSeconds(index * 1_200L))
            }
            add(index, teams[index], teams[30 - index], kickoff)
        }
        for (day in 1..2) {
            val base = plusDays(startOfToday, day).plusSeconds(19 * 3_600L)
            // Sixteen consecutive clubs from a rotating start, so no club plays twice in a day.
            val pool = (0 until 16).map { teams[(day * 7 + 3 + it) % teams.size] }
            for (index in 0 until 8) {
                val away = if (day == 1 && index == 0) "SEA" else pool[index]
                add(day * 10 + index, away, pool[8 + index], base.plusSeconds(index % 4 * 1_800L))
            }
        }
        return result
    }

    /** A rating per club from the invented finals: goal difference per game, best first. */
    fun teamRatings(): List<TeamRating> {
        val table = StandingsRow.build(games.filter { it.isFinal }, leagueTeamAbbreviations)
        val rows = table.values.filter { it.games > 0 }
            .map { it to it.differential.toDouble() / it.games }
            .sortedWith(compareByDescending<Pair<StandingsRow, Double>> { it.second }.thenBy { it.first.team })
        return rows.mapIndexed { index, (row, rating) ->
            TeamRating(
                season = season, team = row.team, rank = index + 1, games = row.games,
                throughWeek = 3, rating = rating,
                offense = row.goalsFor.toDouble() / row.games - 3.0,
                defense = 3.0 - row.goalsAgainst.toDouble() / row.games,
                schedule = unit(row.team, 11) - 0.5,
                wins = row.wins, losses = row.losses, ties = row.otLosses,
                pointsFor = row.goalsFor, pointsAgainst = row.goalsAgainst,
            )
        }
    }

    private fun makeGames(): List<Game> {
        val order = leagueTeamAbbreviations.sorted().toMutableList()
        val result = mutableListOf<Game>()
        var number = 1
        for (round in 0 until 8) {
            for (index in 0 until 16) {
                val a = order[index]
                val b = order[31 - index]
                val flip = (round + index) % 2 == 0
                val away = if (flip) a else b
                val home = if (flip) b else a
                val slot = round * 2 + if (index < 8) 0 else 1
                val day = min(slot, 14)
                val kickoff = plusDays(openingNight, day).plusSeconds((index % 8 / 2) * 1_800L)
                val id = String.format(Locale.US, "20260200%02d", number)
                number += 1
                val seed = fnv(id)
                var awayGoals = 1 + (seed % 5uL).toInt()
                var homeGoals = 1 + ((seed / 7uL) % 5uL).toInt()
                var overtime = false
                if (awayGoals == homeGoals) {
                    if (seed % 2uL == 0uL) homeGoals += 1 else awayGoals += 1
                    overtime = true
                } else if (abs(awayGoals - homeGoals) == 1 && (seed / 13uL) % 4uL == 0uL) {
                    overtime = true
                }
                result += Game(
                    id = id, season = season, week = 1 + day / 7, kickoff = kickoff,
                    awayTeam = away, homeTeam = home,
                    awayScore = awayGoals, homeScore = homeGoals, overtime = overtime,
                )
            }
            // Circle method: the first club stays put, the rest rotate one place.
            val last = order.removeAt(order.size - 1)
            order.add(1, last)
        }
        return result
    }

    // Rosters for the game page.

    private val firstNames = listOf("Aksel", "Bram", "Calder", "Dario", "Emil", "Felix", "Gavin", "Hugo", "Ivar", "Joran", "Kasper", "Leif", "Magnus", "Nils", "Oskar", "Pierce")
    private val lastNames = listOf("Ashgrove", "Brandvold", "Corwin", "Dunmore", "Eskildsen", "Falkner", "Garrick", "Halvorsen", "Ingram", "Jessup", "Kellner", "Lundgren", "Maddox", "Norwood", "Overby", "Penhall", "Quist", "Rademaker", "Sundquist", "Tolliver")

    data class RosterPlayer(val id: Int, val name: String, val position: String)
    data class Roster(val skaters: List<RosterPlayer>, val goalie: RosterPlayer)

    /** Six skaters and a goalie per club. A club's fixture players come first, so the game page agrees with the boards. */
    fun gameRoster(team: String): Roster {
        val teamIndex = leagueTeamAbbreviations.indexOf(team).coerceAtLeast(0)
        val seeded = ScreenshotFixtureApi.seeds.filter { it.team == team }
        val skaters = seeded.filter { it.type != "g" }.map { RosterPlayer(it.id, shortName(it.name), it.position) }.toMutableList()
        val positions = listOf("C", "L", "R", "D", "D", "L")
        var slot = 0
        while (skaters.size < 6) {
            val first = firstNames[(teamIndex + slot * 3) % firstNames.size]
            val last = lastNames[(teamIndex * 2 + slot * 5) % lastNames.size]
            skaters += RosterPlayer(30_000 + teamIndex * 20 + slot, "${first.first()}. $last", positions[skaters.size % positions.size])
            slot += 1
        }
        val goalie = seeded.firstOrNull { it.type == "g" }?.let { RosterPlayer(it.id, shortName(it.name), "G") }
            ?: RosterPlayer(
                30_000 + teamIndex * 20 + 19,
                "${firstNames[(teamIndex + 7) % firstNames.size].first()}. ${lastNames[(teamIndex * 3 + 4) % lastNames.size]}",
                "G",
            )
        return Roster(skaters.take(6), goalie)
    }

    private fun shortName(full: String): String {
        val parts = full.split(" ").filter { it.isNotEmpty() }
        if (parts.size < 2) return full
        return "${parts.first().first()}. ${parts.last()}"
    }

    // Game detail.

    private data class Shot(val elapsed: Double, val xg: Double, val team: String, val isGoal: Boolean, val shooter: RosterPlayer)

    /** Abramowitz and Stegun 7.1.26, close enough for a percentile on a store screenshot. */
    private fun erf(x: Double): Double {
        val sign = if (x < 0) -1.0 else 1.0
        val t = 1.0 / (1.0 + 0.3275911 * abs(x))
        val poly = ((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592
        return sign * (1.0 - poly * t * exp(-x * x))
    }

    private fun json(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to json(v) })
        is List<*> -> JsonArray(value.map(::json))
        else -> JsonPrimitive(value.toString())
    }

    fun gameDetail(game: Game): GameDetail? {
        val seed = game.id
        val awayRoster = gameRoster(game.awayTeam)
        val homeRoster = gameRoster(game.homeTeam)
        val awayGoals = game.awayScore ?: 0
        val homeGoals = game.homeScore ?: 0
        val end = if (game.overtime) 3_900.0 else 3_600.0

        fun totalXG(goals: Int, salt: Int) = max(0.9, goals * 0.55 + 0.9 + unit(seed, salt) * 1.4)
        val awayXG = totalXG(awayGoals, 1)
        val homeXG = totalXG(homeGoals, 2)
        val awaySOG = 24 + (unit(seed, 3) * 12).toInt()
        val homeSOG = 24 + (unit(seed, 4) * 12).toInt()

        // Shots: every goal, plus enough misses and saves to reach the shot count.
        fun shots(team: String, roster: Roster, goals: Int, sog: Int, xg: Double, salt: Int): MutableList<Shot> {
            val count = max(goals + 4, sog)
            data class Raw(val time: Double, val weight: Double, val shooter: RosterPlayer)
            val raw = (0 until count).map { index ->
                val time = 30 + unit(seed + team, salt * 100 + index) * 3_500
                val weight = 0.04 + unit(seed + team, salt * 100 + 50 + index).pow(2.2) * 0.55
                val shooter = roster.skaters[(unit(seed + team, salt * 100 + 80 + index) * roster.skaters.size).toInt()]
                Raw(time, weight, shooter)
            }.sortedBy { it.time }
            // The goals are the shots that landed nearest a spread of moments.
            val goalIndexes = mutableSetOf<Int>()
            for (goal in 0 until goals) {
                val per = count / max(goals, 1)
                var candidate = goal * count / max(goals, 1) + (unit(seed + team, salt * 100 + 90 + goal) * max(per, 1)).toInt()
                candidate = min(candidate, count - 1)
                while (candidate in goalIndexes) candidate = (candidate + 1) % count
                goalIndexes += candidate
            }
            val scale = xg / raw.sumOf { it.weight }
            return raw.mapIndexed { index, shot ->
                Shot(shot.time, shot.weight * scale, team, index in goalIndexes, shot.shooter)
            }.toMutableList()
        }
        val awayShots = shots(game.awayTeam, awayRoster, awayGoals, awaySOG, awayXG, 1)
        val homeShots = shots(game.homeTeam, homeRoster, homeGoals, homeSOG, homeXG, 2)

        // An overtime game: the winner's last goal is the overtime goal.
        if (game.overtime) {
            val list = if (awayGoals > homeGoals) awayShots else homeShots
            val index = list.indexOfLast { it.isGoal }
            if (index >= 0) list[index] = list[index].copy(elapsed = 3_620 + unit(seed, 9) * 220)
        }

        val events = (awayShots + homeShots).sortedBy { it.elapsed }
        val race = mutableListOf(listOf(0.0, 0.0, 0.0, 0.0, 0.0))
        var runningAway = 0.0
        var runningHome = 0.0
        var goalsAway = 0
        var goalsHome = 0
        for (shot in events) {
            if (shot.team == game.awayTeam) {
                runningAway += shot.xg
                if (shot.isGoal) goalsAway += 1
            } else {
                runningHome += shot.xg
                if (shot.isGoal) goalsHome += 1
            }
            race += listOf(swiftRoundDouble(shot.elapsed), runningAway, runningHome, goalsAway.toDouble(), goalsHome.toDouble())
        }
        race += listOf(end, runningAway, runningHome, goalsAway.toDouble(), goalsHome.toDouble())

        // Percentiles follow the value through a plausible league spread.
        fun rated(value: Double, mean: Double, sd: Double): Map<String, Any> {
            val z = (value - mean) / sd
            val cdf = 0.5 * (1 + erf(z / sqrt(2.0)))
            return mapOf("value" to value, "pct" to max(1, min(99, swiftRound(cdf * 100))))
        }
        fun teamStats(xg: Double, sog: Int, goals: Int, salt: Int, xgShare: Double): Map<String, Any> {
            val attempts = (sog + 14 + (unit(seed, salt + 40) * 14).toInt()).toDouble()
            return mapOf(
                "xg" to rated(xg, 2.8, 0.9),
                "xg_5v5" to rated(xg * 0.82, 2.1, 0.7),
                "xgf_pct_5v5" to rated(xgShare, 0.5, 0.08),
                "cf_pct_5v5" to rated(0.42 + unit(seed, salt + 20) * 0.16, 0.5, 0.07),
                "hd_chances" to rated((6 + (unit(seed, salt + 30) * 9).toInt()).toDouble(), 10.0, 3.5),
                "sog" to sog.toDouble(),
                "shot_attempts" to rated(attempts, 55.0, 10.0),
                "goals" to goals.toDouble(),
                "gax" to rated(goals - xg, 0.0, 1.3),
                "pp_goals" to (unit(seed, salt + 50) * 2.4).toInt().toDouble(),
                "pp_opportunities" to (2 + (unit(seed, salt + 60) * 3).toInt()).toDouble(),
                "faceoff_pct" to rated(0.44 + unit(seed, salt + 70) * 0.12, 0.5, 0.06),
                "hits" to (14 + (unit(seed, salt + 80) * 20).toInt()).toDouble(),
                "blocks" to (8 + (unit(seed, salt + 90) * 14).toInt()).toDouble(),
                "pim" to ((unit(seed, salt + 95) * 4).toInt() * 2).toDouble(),
            )
        }
        val share = awayXG / (awayXG + homeXG)
        val teamBlock = mapOf(
            "away" to teamStats(awayXG, awaySOG, awayGoals, 1, share),
            "home" to teamStats(homeXG, homeSOG, homeGoals, 2, 1 - share),
        )

        // Player lines: team goals go to the skaters who took the goal shots.
        fun skaterLines(team: String, roster: Roster, shots: List<Shot>, goals: Int): List<Map<String, Any>> =
            roster.skaters.map { skater ->
                val mine = shots.filter { it.shooter.id == skater.id }
                val ixg = mine.sumOf { it.xg }
                val scored = mine.count { it.isGoal }
                val key = seed + skater.name
                val assists = (unit(key, 7) * 2.2).toInt() * if (goals > 0) 1 else 0
                val toi = (if (skater.position == "D") 1_380 else 1_130) + (unit(key, 8) * 240).toInt()
                val shotsOnGoal = max(scored, swiftRound(mine.size * 0.7))
                mapOf(
                    "role" to "skater", "player_id" to skater.id, "name" to skater.name, "team" to team,
                    "position" to skater.position, "toi" to toi,
                    "goals" to scored, "assists" to assists, "points" to scored + assists,
                    "sog" to shotsOnGoal, "shot_attempts" to mine.size + (unit(key, 9) * 3).toInt(),
                    "hd_shots" to (unit(key, 10) * 3).toInt(),
                    "ixg" to mapOf("value" to ixg, "pct" to 20 + (unit(key, 11) * 75).toInt()),
                    "gax" to mapOf("value" to scored - ixg, "pct" to 20 + (unit(key, 12) * 75).toInt()),
                    "ixg_per_60" to mapOf("value" to ixg / (toi / 3_600.0), "pct" to 20 + (unit(key, 13) * 75).toInt()),
                )
            }
        fun goalieLine(team: String, goalie: RosterPlayer, against: Int, faced: Int, xga: Double): Map<String, Any> {
            val saves = max(0, faced - against)
            val key = seed + team
            return mapOf(
                "role" to "goalie", "player_id" to goalie.id, "name" to goalie.name, "team" to team, "position" to "G",
                "toi" to end.toInt(), "shots_against" to faced, "saves" to saves, "goals_against" to against,
                "xga" to mapOf("value" to xga, "pct" to 20 + (unit(key, 21) * 75).toInt()),
                "gsax" to mapOf("value" to xga - against, "pct" to 20 + (unit(key, 22) * 75).toInt()),
                "sv_pct" to mapOf("value" to if (faced > 0) saves.toDouble() / faced else 1.0, "pct" to 20 + (unit(key, 23) * 75).toInt()),
            )
        }
        val players = skaterLines(game.awayTeam, awayRoster, awayShots, awayGoals) +
            skaterLines(game.homeTeam, homeRoster, homeShots, homeGoals) +
            listOf(
                goalieLine(game.awayTeam, awayRoster.goalie, homeGoals, homeSOG, homeXG),
                goalieLine(game.homeTeam, homeRoster.goalie, awayGoals, awaySOG, awayXG),
            )

        // The chances that decided it: every goal plus the five biggest misses.
        val descriptions = listOf("Wrist shot, slot", "Snap shot, slot, rebound", "One-timer, high slot", "Backhand, in tight", "Slap shot, off the rush", "Tip-in, crease")
        val runningScore = intArrayOf(0, 0)
        fun play(shot: Shot, index: Int): Map<String, Any> {
            val period = min(4, (shot.elapsed / 1_200).toInt() + 1)
            val inPeriod = shot.elapsed.toInt() - (period - 1) * 1_200
            val results = listOf("SAVE", "SAVE", "MISS")
            val row = linkedMapOf<String, Any>(
                "period" to period,
                "clock" to String.format(Locale.US, "%d:%02d", inPeriod / 60, inPeriod % 60),
                "team" to shot.team,
                "description" to descriptions[(fnv("$seed$index") % descriptions.size.toULong()).toInt()],
                "xg" to shot.xg,
                "result" to if (shot.isGoal) "GOAL" else results[(fnv("${seed}r$index") % 3uL).toInt()],
                "player_id" to shot.shooter.id,
                "shooter" to shot.shooter.name,
            )
            if (!shot.isGoal) return row
            runningScore[if (shot.team == game.awayTeam) 0 else 1] += 1
            val mates = (if (shot.team == game.awayTeam) awayRoster else homeRoster).skaters.filter { it.id != shot.shooter.id }
            val start = (fnv("${seed}a$index") % max(1, mates.size).toULong()).toInt()
            val count = (fnv("${seed}n$index") % 3uL).toInt()
            row["assists"] = (0 until min(count, mates.size)).map { mates[(start + it) % mates.size].name }
            row["score"] = runningScore.toList()
            row["goal_number"] = 1 + (fnv("${seed}g$index") % 6uL).toInt()
            if (fnv("${seed}s$index") % 4uL == 0uL) row["strength"] = "PP"
            return row
        }
        val goalShots = events.filter { it.isGoal }
        val topMisses = events.filter { !it.isGoal }.sortedByDescending { it.xg }.take(5)
        val bigPlays = (goalShots + topMisses).sortedBy { it.elapsed }.mapIndexed { index, shot -> play(shot, index) }

        val payload = mapOf(
            "game_id" to game.id,
            "away_team" to game.awayTeam,
            "home_team" to game.homeTeam,
            "team_stats" to teamBlock,
            "players" to players,
            "win_probability" to race,
            "big_plays" to bigPlays,
        )
        return runCatching { GameDetail.fromJson(json(payload) as JsonObject) }.getOrNull()
    }

    // Bios.

    fun profiles(): List<PlayerProfile> {
        val towns = listOf("Fairhaven, WA, USA", "Kestrel Bay, ON, CAN", "Norrby, SWE", "Valmont, MN, USA", "Harbourgate, BC, CAN", "Lindholm, FIN", "Stonebridge, MI, USA", "Ravenna Falls, QC, CAN")
        return ScreenshotFixtureApi.seeds.mapIndexed { index, seed ->
            val perGame = when (seed.type) {
                "d" -> 1_428
                "g" -> 3_600
                else -> 1_132
            }
            val goalie = seed.type == "g"
            PlayerProfile(
                playerId = seed.id,
                season = season,
                jersey = 8 + (index * 7) % 80,
                birthDate = LocalDate.of(1993 + index % 8, 1 + index % 9, 10 + index % 9),
                heightInches = if (goalie) 76 else if (seed.type == "d") 75 else 72 + index % 3,
                weightPounds = 185 + (index * 4) % 30,
                birthplace = towns[index % towns.size],
                yearsExperience = 2 + index % 9,
                draftYear = 2013 + index % 8,
                draftRound = 1 + index % 3,
                draftPick = 3 + (index * 11) % 60,
                draftTeam = seed.team,
                toiSeconds = perGame * 8,
                toiPerGame = perGame,
                powerPlayToiSeconds = if (goalie) null else 190 * 8,
                penaltyKillToiSeconds = if (goalie) null else 70 * 8,
                toiShare = if (goalie) null else 0.11 + (index % 5) / 100.0,
            )
        }
    }
}
