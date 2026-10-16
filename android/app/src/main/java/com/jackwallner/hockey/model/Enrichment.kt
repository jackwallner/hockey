package com.jackwallner.hockey.model

import java.time.Instant
import java.time.LocalDate
import java.time.Period
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlinx.serialization.json.JsonObject

/**
 * Who a player is and how much he plays, from `public.player_profiles`. Every
 * field is optional; screens leave a line out rather than wait for it.
 */
data class PlayerProfile(
    val playerId: Int,
    val season: Int,
    val jersey: Int? = null,
    val birthDate: LocalDate? = null,
    val heightInches: Int? = null,
    val weightPounds: Int? = null,
    /** "Richmond Hill, ON, CAN". */
    val birthplace: String? = null,
    val yearsExperience: Int? = null,
    /** The league's Calder eligibility; null before the feed carried it. */
    val isRookie: Boolean? = null,
    val draftYear: Int? = null,
    val draftRound: Int? = null,
    val draftPick: Int? = null,
    val draftTeam: String? = null,
    /** Season ice time in seconds, all situations. */
    val toiSeconds: Int? = null,
    /** Ice time per game in seconds. */
    val toiPerGame: Int? = null,
    val powerPlayToiSeconds: Int? = null,
    val penaltyKillToiSeconds: Int? = null,
    /** Share of the club's skater minutes this player was on the ice for. */
    val toiShare: Double? = null,
) {
    fun age(on: LocalDate = LocalDate.now()): Int? = birthDate?.let { Period.between(it, on).years }

    /** `6'1", 196 lb`. */
    val sizeLabel: String?
        get() {
            val h = heightInches?.takeIf { it > 0 } ?: return null
            val height = "${h / 12}'${h % 12}\""
            val w = weightPounds?.takeIf { it > 0 } ?: return height
            return "$height, $w lb"
        }

    /** "2015 Rd 1, #1 overall", or "Undrafted". The feed's pick is the overall number. */
    val draftLabel: String?
        get() {
            if (draftYear != null && draftRound != null && draftPick != null) return "$draftYear Rd $draftRound, #$draftPick overall"
            return if (yearsExperience != null) "Undrafted" else null
        }

    /** "21:14". */
    val toiPerGameLabel: String?
        get() {
            val t = toiPerGame?.takeIf { it > 0 } ?: return null
            return String.format(Locale.US, "%d:%02d", t / 60, t % 60)
        }

    /** "3:12 PP · 1:48 PK" per game, for the deployment line. */
    fun specialTeamsLabel(games: Int): String? {
        if (games <= 0) return null
        fun clock(seconds: Int?): String? {
            val s = seconds?.takeIf { it > 0 } ?: return null
            val per = s / games
            return String.format(Locale.US, "%d:%02d", per / 60, per % 60)
        }
        val parts = listOfNotNull(clock(powerPlayToiSeconds)?.let { "$it PP" }, clock(penaltyKillToiSeconds)?.let { "$it PK" })
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    companion object {
        /** Seconds arrive as numerics ("toi_per_gp": 1437.2); round, never fail the row. */
        private fun seconds(o: JsonObject, key: String): Int? =
            o.double(key)?.takeIf { it.isFinite() }?.let { swiftRoundDouble(it).toInt() }

        fun fromJson(o: JsonObject) = PlayerProfile(
            playerId = o.requireInt("player_id"),
            season = o.requireInt("season"),
            jersey = o.int("jersey"),
            birthDate = o.string("birth_date")?.let { raw ->
                try {
                    LocalDate.parse(raw.take(10))
                } catch (_: DateTimeParseException) {
                    null
                }
            },
            heightInches = o.int("height_in"),
            weightPounds = o.int("weight_lb"),
            birthplace = o.string("birthplace"),
            yearsExperience = o.int("years_exp"),
            isRookie = o.bool("is_rookie"),
            draftYear = o.int("draft_year"),
            draftRound = o.int("draft_round"),
            draftPick = o.int("draft_pick"),
            draftTeam = o.string("draft_team"),
            toiSeconds = seconds(o, "toi_seconds"),
            toiPerGame = seconds(o, "toi_per_gp"),
            powerPlayToiSeconds = seconds(o, "pp_toi_seconds"),
            penaltyKillToiSeconds = seconds(o, "pk_toi_seconds"),
            toiShare = o.double("toi_share"),
        )
    }
}

/**
 * One club's power rating from `public.team_ratings`: goals per game better
 * or worse than an average team on neutral ice. The `ties` column holds
 * overtime and shootout losses, `points_for` goals for.
 */
data class TeamRating(
    val season: Int,
    val team: String,
    val rank: Int,
    val games: Int,
    val throughWeek: Int,
    val rating: Double,
    val offense: Double,
    val defense: Double,
    val schedule: Double,
    val wins: Int,
    val losses: Int,
    val ties: Int,
    val pointsFor: Int,
    val pointsAgainst: Int,
) {
    companion object {
        /** "+0.58", "-0.12": ratings live within about half a goal of zero. */
        fun signed(value: Double): String {
            val rounded = swiftRoundDouble(value * 100) / 100.0
            if (rounded == 0.0) return "0.00"
            return String.format(Locale.US, "%+.2f", rounded)
        }

        fun fromJson(o: JsonObject) = TeamRating(
            season = o.requireInt("season"),
            team = o.requireString("team"),
            rank = o.requireInt("rank"),
            games = o.requireInt("games"),
            throughWeek = o.requireInt("through_week"),
            rating = o.double("rating") ?: throw RowDecodeException("rating"),
            offense = o.double("offense") ?: throw RowDecodeException("offense"),
            defense = o.double("defense") ?: throw RowDecodeException("defense"),
            schedule = o.double("schedule") ?: throw RowDecodeException("schedule"),
            wins = o.requireInt("wins"),
            losses = o.requireInt("losses"),
            ties = o.requireInt("ties"),
            pointsFor = o.requireInt("points_for"),
            pointsAgainst = o.requireInt("points_against"),
        )
    }
}

/** A projected result for an unplayed game, from the two power ratings plus home ice. */
data class GameProjection(val gameId: String, val homeMargin: Double, val homeWinProbability: Double) {
    /**
     * "EDM 62%", the favourite's chance to win, or "Toss-up" when it rounds to
     * 50%. Hockey reads a matchup as a win chance, not a spread.
     */
    fun label(home: String, away: String): String {
        val favouriteChance = maxOf(homeWinProbability, 1 - homeWinProbability)
        if (favouriteChance < 0.505) return "Toss-up"
        val favourite = if (homeWinProbability >= 0.5) home else away
        return "${displayTeamAbbr(favourite)} ${swiftRound(favouriteChance * 100)}%"
    }

    fun winProbability(team: String, home: String): Double =
        if (normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(home)) homeWinProbability else 1 - homeWinProbability

    companion object {
        fun fromJson(o: JsonObject) = GameProjection(
            gameId = o.requireString("game_id"),
            homeMargin = o.double("home_margin") ?: throw RowDecodeException("home_margin"),
            homeWinProbability = o.double("home_win_prob") ?: throw RowDecodeException("home_win_prob"),
        )
    }
}

/**
 * A club's line in the standings, from posted finals. `ties` holds overtime
 * and shootout losses (a point each); `pointsFor` and `pointsAgainst` are goals.
 */
data class StandingsRow(
    val team: String,
    val wins: Int = 0,
    val losses: Int = 0,
    val ties: Int = 0,
    val pointsFor: Int = 0,
    val pointsAgainst: Int = 0,
    /** "W2", "L1", "OT1"; null before a game. */
    val streak: String? = null,
) {
    val games: Int get() = wins + losses + ties
    val otLosses: Int get() = ties
    val goalsFor: Int get() = pointsFor
    val goalsAgainst: Int get() = pointsAgainst
    val differential: Int get() = pointsFor - pointsAgainst

    /** Standings points: two for a win, one for an overtime or shootout loss. */
    val points: Int get() = wins * 2 + ties

    /** Points percentage, the NHL's own tiebreaker before regulation wins. */
    val winPercentage: Double get() = if (games == 0) 0.0 else points.toDouble() / (games * 2)

    /** "12-5-2", always three numbers, the way hockey records are written. */
    val record: String get() = "$wins-$losses-$ties"

    companion object {
        /** Regular-season finals only, oldest first so the streak reads off the end. */
        fun build(games: List<Game>, teams: List<String>): Map<String, StandingsRow> {
            val rows = teams.associateWith { StandingsRow(it) }.toMutableMap()
            val finals = games.filter { it.seasonPhase == SeasonPhase.REGULAR && it.isFinal }.sortedBy { it.sortInstant }
            val results = HashMap<String, MutableList<String>>()
            for (game in finals) {
                for (side in listOf(game.homeTeam, game.awayTeam)) {
                    val team = normalizedTeamAbbreviation(side)
                    val row = rows[team] ?: continue
                    val result = game.result(side) ?: continue
                    val mine = game.score(side) ?: continue
                    val theirs = game.score(game.opponent(side)) ?: continue
                    rows[team] = row.copy(
                        wins = row.wins + if (result == "W") 1 else 0,
                        losses = row.losses + if (result == "L") 1 else 0,
                        ties = row.ties + if (result != "W" && result != "L") 1 else 0,
                        pointsFor = row.pointsFor + mine,
                        pointsAgainst = row.pointsAgainst + theirs,
                    )
                    results.getOrPut(team) { mutableListOf() }.add(if (result == "OTL") "OT" else result)
                }
            }
            for ((team, list) in results) {
                val last = list.lastOrNull() ?: continue
                val run = list.asReversed().takeWhile { it == last }.size
                rows[team] = rows.getValue(team).copy(streak = "$last$run")
            }
            return rows
        }

        /** Points, then points percentage, then goal differential, then name. */
        fun ordered(rows: List<StandingsRow>): List<StandingsRow> = rows.sortedWith(
            compareByDescending<StandingsRow> { it.points }
                .thenByDescending { it.winPercentage }
                .thenByDescending { it.differential }
                .thenBy { it.team },
        )

        /** A club's place inside its division by the Standings ordering; null before it has played. */
        fun divisionPlace(team: String, table: Map<String, StandingsRow>): Pair<Int, LeagueDivision>? {
            val abbr = normalizedTeamAbbreviation(team)
            val division = LeagueDivision.of(abbr) ?: return null
            val row = table[abbr] ?: return null
            if (row.games <= 0) return null
            val rows = ordered(division.teams.mapNotNull { table[it] })
            val index = rows.indexOfFirst { it.team == abbr }
            if (index < 0) return null
            return (index + 1) to division
        }

        /** "1ST", "2ND", "3RD", "4TH", "11TH", "22ND". */
        fun ordinal(number: Int): String {
            val teens = (number % 100) in 11..13
            val suffix = if (teens) "TH" else when (number % 10) {
                1 -> "ST"
                2 -> "ND"
                3 -> "RD"
                else -> "TH"
            }
            return "$number$suffix"
        }
    }
}

/**
 * A club's season at a glance from its posted finals and game breakdowns:
 * the numbers a standings page leaves out, each with its league rank.
 */
data class TeamSeasonSummary(
    val team: String,
    val games: Int,
    val goalsFor: Stat,
    val goalsAgainst: Stat,
    val shotsFor: Stat? = null,
    val shotsAgainst: Stat? = null,
    val powerPlay: Stat? = null,
    val penaltyKill: Stat? = null,
    val expectedGoalsShare: Stat? = null,
) {
    /** [rank] 1 is best in the league. */
    data class Stat(val value: Double, val rank: Int = 0)

    companion object {
        private class Totals {
            var games = 0; var goalsFor = 0; var goalsAgainst = 0
            var detailed = 0; var shotsFor = 0; var shotsAgainst = 0
            var ppGoals = 0; var ppChances = 0; var pkAgainst = 0; var pkChances = 0
            var xgFor = 0.0; var xgAgainst = 0.0
        }

        /** Every club's summary, ranked. [xg] covers the games with a built breakdown. */
        fun build(games: List<Game>, xg: Map<String, GameXG>, teams: List<String>): Map<String, TeamSeasonSummary> {
            val totals = HashMap<String, Totals>()
            for (game in games) {
                if (game.seasonPhase != SeasonPhase.REGULAR || !game.isFinal) continue
                for (side in listOf(game.awayTeam, game.homeTeam)) {
                    val team = normalizedTeamAbbreviation(side)
                    val home = game.isHome(side)
                    val t = totals.getOrPut(team) { Totals() }
                    t.games += 1
                    t.goalsFor += game.score(side) ?: 0
                    t.goalsAgainst += game.score(game.opponent(side)) ?: 0
                    val x = xg[game.id] ?: continue
                    t.detailed += 1
                    t.xgFor += if (home) x.home else x.away
                    t.xgAgainst += if (home) x.away else x.home
                    t.shotsFor += (if (home) x.homeShots else x.awayShots) ?: 0
                    t.shotsAgainst += (if (home) x.awayShots else x.homeShots) ?: 0
                    t.ppGoals += (if (home) x.homePowerPlayGoals else x.awayPowerPlayGoals) ?: 0
                    t.ppChances += (if (home) x.homePowerPlays else x.awayPowerPlays) ?: 0
                    t.pkAgainst += (if (home) x.awayPowerPlayGoals else x.homePowerPlayGoals) ?: 0
                    t.pkChances += (if (home) x.awayPowerPlays else x.homePowerPlays) ?: 0
                }
            }
            var out = LinkedHashMap<String, TeamSeasonSummary>()
            for (team in teams) {
                val t = totals[team] ?: continue
                if (t.games <= 0) continue
                val detailed = maxOf(t.detailed, 1).toDouble()
                out[team] = TeamSeasonSummary(
                    team = team,
                    games = t.games,
                    goalsFor = Stat(t.goalsFor.toDouble() / t.games),
                    goalsAgainst = Stat(t.goalsAgainst.toDouble() / t.games),
                    shotsFor = if (t.detailed > 0) Stat(t.shotsFor / detailed) else null,
                    shotsAgainst = if (t.detailed > 0) Stat(t.shotsAgainst / detailed) else null,
                    powerPlay = if (t.ppChances > 0) Stat(t.ppGoals.toDouble() / t.ppChances) else null,
                    penaltyKill = if (t.pkChances > 0) Stat(1 - t.pkAgainst.toDouble() / t.pkChances) else null,
                    expectedGoalsShare = if (t.xgFor + t.xgAgainst > 0) Stat(t.xgFor / (t.xgFor + t.xgAgainst)) else null,
                )
            }
            out = rank(out, true, { it.goalsFor }) { s, v -> s.copy(goalsFor = v) }
            out = rank(out, false, { it.goalsAgainst }) { s, v -> s.copy(goalsAgainst = v) }
            out = rank(out, true, { it.shotsFor }) { s, v -> s.copy(shotsFor = v) }
            out = rank(out, false, { it.shotsAgainst }) { s, v -> s.copy(shotsAgainst = v) }
            out = rank(out, true, { it.powerPlay }) { s, v -> s.copy(powerPlay = v) }
            out = rank(out, true, { it.penaltyKill }) { s, v -> s.copy(penaltyKill = v) }
            out = rank(out, true, { it.expectedGoalsShare }) { s, v -> s.copy(expectedGoalsShare = v) }
            return out
        }

        /** Competition ranking: ties share the better rank. */
        private fun rank(
            table: LinkedHashMap<String, TeamSeasonSummary>,
            higherIsBetter: Boolean,
            get: (TeamSeasonSummary) -> Stat?,
            set: (TeamSeasonSummary, Stat) -> TeamSeasonSummary,
        ): LinkedHashMap<String, TeamSeasonSummary> {
            val values = table.mapNotNull { (team, s) -> get(s)?.let { team to it.value } }.toMap()
            val out = LinkedHashMap(table)
            for ((team, value) in values) {
                val better = values.values.count { if (higherIsBetter) it > value + 1e-9 else it < value - 1e-9 }
                val summary = out.getValue(team)
                out[team] = set(summary, get(summary)!!.copy(rank = better + 1))
            }
            return out
        }

        /** "1st", "2nd", "32nd". */
        fun ordinal(rank: Int): String = StandingsRow.ordinal(rank).lowercase()
    }
}

internal val UTC: ZoneId = ZoneOffset.UTC
internal fun Instant.toUtcDate(): LocalDate = atZone(UTC).toLocalDate()
