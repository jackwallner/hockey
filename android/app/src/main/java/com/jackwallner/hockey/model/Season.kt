package com.jackwallner.hockey.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

object StatScoutSeason {
    /**
     * The season the pipeline is writing, named for the year it opens in
     * (2026 is 2026-27): September on is this year, earlier is last year.
     * Floored at 2026, the season the app shipped with.
     */
    val current: Int = resolve(ZonedDateTime.now())

    fun resolve(now: ZonedDateTime): Int = maxOf(2026, if (now.monthValue >= 9) now.year else now.year - 1)

    /** The only season without StatScout+, and the one every screen opens on. */
    val free: Int get() = current

    /** Oldest season with per-game history, the floor for Recent Form. */
    const val EARLIEST_RECENT_FORM = 2025

    /** MoneyPuck's expected-goals data starts with 2008-09. */
    const val EARLIEST = 2008

    /** Sentinel for the career rollup; zero sorts below every real year. */
    const val ALL_TIME = 0

    fun isAllTime(season: Int): Boolean = season == ALL_TIME

    /**
     * Start of a rolling game-log window on [season], anchored to the season's
     * end (1 July of the following year) rather than to now, so the offseason
     * and past seasons still find their games.
     */
    fun gameLogWindowStart(season: Int, days: Long = 120, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant {
        val seasonEnd = LocalDate.of(season + 1, 7, 1).atStartOfDay(zone).toInstant()
        val anchor = if (now < seasonEnd) now else seasonEnd
        return anchor.atZone(zone).minusDays(days).toInstant()
    }
}

/**
 * NHL seasons span two calendar years. The feed keys a season by its start
 * year (2026 is 2026-27); every label the user sees goes through here.
 */
object SeasonLabel {
    fun display(season: Int): String {
        if (StatScoutSeason.isAllTime(season)) return "All Time"
        return "%d-%02d".format(season, (season + 1) % 100)
    }

    /** "2026-27 Regular Season", worded like the season menu. */
    fun display(season: Int, phase: SeasonPhase): String =
        if (StatScoutSeason.isAllTime(season)) "All Time" else "${display(season)} ${phase.label}"
}
