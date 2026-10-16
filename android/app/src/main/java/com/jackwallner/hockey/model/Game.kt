package com.jackwallner.hockey.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.json.JsonObject

/**
 * One NHL game from `public.games`, synced from the league schedule. Scores
 * are null until the game is final; a game past its start time with no score
 * is in progress, not 0-0.
 */
data class Game(
    val id: String,
    val season: Int,
    val seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    /** REG, or the playoff round: R1, R2, CF or SCF. */
    val gameType: String = "REG",
    /** League week, for anchoring and coverage captions only; the app groups games by date. */
    val week: Int,
    val kickoff: Instant?,
    val gameDate: Instant = kickoff ?: Instant.EPOCH,
    val awayTeam: String,
    val homeTeam: String,
    val awayScore: Int? = null,
    val homeScore: Int? = null,
    val overtime: Boolean = false,
    val stadium: String? = null,
    /** "OT", "SO", or "2OT" and up for a playoff game; null in regulation. */
    val finalPeriod: String? = null,
) {
    val isFinal: Boolean get() = awayScore != null && homeScore != null

    fun involves(team: String): Boolean {
        val abbr = normalizedTeamAbbreviation(team)
        return normalizedTeamAbbreviation(awayTeam) == abbr || normalizedTeamAbbreviation(homeTeam) == abbr
    }

    fun opponent(team: String): String =
        if (normalizedTeamAbbreviation(awayTeam) == normalizedTeamAbbreviation(team)) homeTeam else awayTeam

    fun isHome(team: String): Boolean = normalizedTeamAbbreviation(homeTeam) == normalizedTeamAbbreviation(team)

    fun score(team: String): Int? = if (isHome(team)) homeScore else awayScore

    /** "OT", "SO", "2OT" for a final decided past regulation, else null. */
    val extraPeriodLabel: String? get() = if (isFinal && overtime) finalPeriod ?: "OT" else null

    /** "Final", "Final/OT", "Final/SO", "Final/2OT". */
    val finalLabel: String get() = extraPeriodLabel?.let { "Final/$it" } ?: "Final"

    /**
     * "W", "L" or "OTL" for a final, from [team]'s side. A regular-season
     * overtime or shootout loss earns a point; a playoff overtime loss is a loss.
     */
    fun result(team: String): String? {
        val mine = score(team) ?: return null
        val theirs = score(opponent(team)) ?: return null
        if (mine > theirs) return "W"
        return if (overtime && seasonPhase == SeasonPhase.REGULAR) "OTL" else "L"
    }

    /** "W 4-3 OT", "L 2-3 SO", team score first. */
    fun resultLine(team: String): String? {
        val result = result(team) ?: return null
        val mine = score(team) ?: return null
        val theirs = score(opponent(team)) ?: return null
        val shown = if (result == "OTL") "L" else result
        return "$shown $mine-$theirs${extraPeriodLabel?.let { " $it" } ?: ""}"
    }

    /** "vs HOU" at home, "at HOU" away. */
    fun matchupLabel(team: String): String = "${if (isHome(team)) "vs" else "at"} ${displayTeamAbbr(opponent(team))}"

    val roundLabel: String get() = GameDay.roundLabel(gameType)

    fun status(now: Instant = Instant.now()): GameStatus {
        if (isFinal) return GameStatus.FINAL
        val kickoff = kickoff ?: return GameStatus.UPCOMING
        if (now < kickoff) return GameStatus.UPCOMING
        // Past a normal game length with no final, the score is on its way.
        return if (Duration.between(kickoff, now).seconds < 3.25 * 3_600) GameStatus.IN_PROGRESS else GameStatus.AWAITING_SCORE
    }

    /** "Tue 7:00 PM" in the phone's zone. */
    fun kickoffLabel(zone: ZoneId = ZoneId.systemDefault()): String {
        val kickoff = kickoff ?: return DateText.gameDay(gameDate)
        return DateTimeFormatter.ofPattern("EEE h:mm a", Locale.US).format(kickoff.atZone(zone))
    }

    /** "Tue, Oct 7". */
    fun dayLabel(zone: ZoneId = ZoneId.systemDefault()): String {
        val kickoff = kickoff ?: return DateText.gameDay(gameDate)
        return DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US).format(kickoff.atZone(zone))
    }

    val sortInstant: Instant get() = kickoff ?: gameDate

    companion object {
        fun fromJson(o: JsonObject): Game {
            val rawDate = o.requireString("game_date")
            return Game(
                id = o.requireString("game_id"),
                season = o.requireInt("season"),
                seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad phase") } ?: SeasonPhase.REGULAR,
                gameType = o.string("game_type") ?: "REG",
                week = o.requireInt("week"),
                kickoff = o.string("kickoff_at")?.let(::parseDate),
                gameDate = parseDate(rawDate) ?: throw RowDecodeException("bad game_date"),
                awayTeam = o.requireString("away_team"),
                homeTeam = o.requireString("home_team"),
                awayScore = o.int("away_score"),
                homeScore = o.int("home_score"),
                overtime = o.bool("overtime") ?: false,
                stadium = o.string("stadium"),
                finalPeriod = o.string("final_period"),
            )
        }

        /** In progress, then finals, then upcoming, each by start time. */
        fun slateOrder(games: List<Game>, now: Instant = Instant.now()): List<Game> = games.sortedWith(
            compareBy<Game> { it.status(now).sortOrder }.thenBy { it.sortInstant }.thenBy { it.id },
        )
    }
}

enum class GameStatus(val sortOrder: Int) {
    IN_PROGRESS(0), AWAITING_SCORE(1), FINAL(2), UPCOMING(3);

    /** The one word every screen uses for a game with no posted final. */
    val liveLabel: String get() = if (this == AWAITING_SCORE) "Final soon" else "In progress"
}

/**
 * A selectable day of the schedule. Hockey plays most nights, so the unit a
 * fan thinks in is the date, not the week.
 */
data class GameDay(val date: LocalDate, val phase: SeasonPhase) {
    val id: String get() = "${phase.raw}-$date"

    /** "Today", "Yesterday", "Tomorrow", else "Tue, Oct 7". */
    fun label(today: LocalDate = LocalDate.now()): String = when (date) {
        today -> "Today"
        today.minusDays(1) -> "Yesterday"
        today.plusDays(1) -> "Tomorrow"
        else -> DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US).format(date)
    }

    val label: String get() = label(LocalDate.now())

    /** Short chip text: "Oct 7". */
    val shortLabel: String get() = DateTimeFormatter.ofPattern("MMM d", Locale.US).format(date)

    fun games(from: List<Game>, zone: ZoneId = ZoneId.systemDefault()): List<Game> =
        from.filter { day(it, zone) == date && it.seasonPhase == phase }

    companion object {
        fun roundLabel(gameType: String): String = when (gameType.uppercase()) {
            "R1" -> "Round 1"
            "R2" -> "Round 2"
            "CF" -> "Conference Final"
            "SCF" -> "Stanley Cup Final"
            else -> "Regular Season"
        }

        /** The local calendar day a game belongs to, from its start time when known. */
        fun day(game: Game, zone: ZoneId = ZoneId.systemDefault()): LocalDate =
            (game.kickoff ?: game.gameDate).atZone(zone).toLocalDate()

        fun days(games: List<Game>, zone: ZoneId = ZoneId.systemDefault()): List<GameDay> {
            val seen = LinkedHashMap<String, GameDay>()
            for (game in games) {
                val d = GameDay(day(game, zone), game.seasonPhase)
                seen[d.id] = d
            }
            return seen.values.sortedBy { it.date }
        }

        /**
         * The day a fan means by "tonight": today's slate while there is one;
         * before 2 PM, yesterday's finals while nothing has started today. With
         * no games today, the most recent day with games; before the season, the first.
         */
        fun current(games: List<Game>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): GameDay? {
            val days = days(games, zone)
            if (days.isEmpty()) return null
            val local = now.atZone(zone)
            val today = local.toLocalDate()
            val todays = days.firstOrNull { it.date == today }
            if (todays != null) {
                val started = todays.games(games, zone).any { (it.kickoff ?: it.gameDate) <= now }
                if (started || local.hour >= 14) return todays
                return days.lastOrNull { it.date < today } ?: todays
            }
            return days.lastOrNull { it.date < today } ?: days.first()
        }
    }
}

object DateText {
    private val GAME_DAY = DateTimeFormatter.ofPattern("MMM d", Locale.US)

    /** Game dates are Eastern midnight; format them in Eastern so the west coast keeps the right day. */
    fun gameDay(date: Instant): String = GAME_DAY.format(date.atZone(EASTERN))
}
