package com.jackwallner.hockey.model

import java.text.NumberFormat
import java.util.Locale

/**
 * What the data can and cannot say about a season. StatScout carries every
 * season from 2008-09 on, where MoneyPuck's expected-goals model starts, so
 * the only gaps worth naming are the career rollup and a live season whose
 * source files have not caught up with the games already played.
 */
object MetricCoverage {
    /** One short sentence explaining what this season is missing, or null when it has the full set. */
    @Suppress("UNUSED_PARAMETER")
    fun note(season: Int, category: MetricCategory? = null): String? {
        if (!StatScoutSeason.isAllTime(season)) return null
        return "Career totals span ${SeasonLabel.display(StatScoutSeason.EARLIEST)} onward. Rate metrics are averaged over every season a player qualified."
    }

    /** The live season's own gap: a source that exists for this year but has not published yet. */
    fun pendingNote(shotsStatus: String?, summaryStatus: String?): String? {
        fun pending(status: String?): Boolean {
            val s = status?.lowercase() ?: return false
            return s != "ready" && s != "not_applicable" && s != "unavailable"
        }
        if (pending(shotsStatus)) {
            return "Expected goals for the latest games are still arriving from MoneyPuck. Shot-based metrics will catch up after the next update."
        }
        if (pending(summaryStatus)) {
            return "NHL standard stats (+/-, power-play points, game-winners) for the latest games are still arriving."
        }
        return null
    }

    /** Every metric reaches back to the start of the dataset. */
    @Suppress("UNUSED_PARAMETER")
    fun isTracked(label: String, season: Int): Boolean = true
}

/** A metric the Trends board ranks by, keyed to the rollup column. */
data class TrendMetric(val key: String, val label: String, val unit: String, val decimals: Int, val lowerIsBetter: Boolean) {
    val id: String get() = key

    /** This metric's then, now and change for one row. */
    data class Values(val then: Double?, val now: Double?, val delta: Double?)

    /** The window values as the rollup publishes them. */
    fun values(form: RecentForm): Values = Values(form.priorMetrics[key], form.metrics[key], form.delta[key])

    fun display(value: Double): String = format(value)

    fun format(value: Double): String {
        if (label.endsWith("SV%")) return RecentMetricKey.savePercentage(value)
        if (decimals == 0) return NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong()) + unit
        return cFixed(value, decimals) + unit
    }

    companion object {
        private fun m(key: String, label: String, unit: String, decimals: Int, lower: Boolean = false) = TrendMetric(key, label, unit, decimals, lower)

        /**
         * Forwards and defensemen read the same board. The rollup has no
         * per-game on-ice shares, so the advanced list is individual expected
         * goals and the rates built on it.
         */
        val skaterAdvanced = listOf(
            m("points_per_60", "P/60", "", 2),
            m("ixg_per_60", "ixG/60", "", 2),
            m("gax", "GAx", "", 1),
            m("shots_per_60", "Shots/60", "", 1),
            m("hd_shots_per_60", "HD Shots/60", "", 1),
            m("shooting_pct", "Sh%", "%", 1),
            m("goals_per_60", "G/60", "", 2),
        )
        val goalieAdvanced = listOf(
            m("gsax", "GSAx", "", 1),
            m("gsax_per_60", "GSAx/60", "", 2),
            m("hd_sv_pct", "HD SV%", "", 3),
            m("shots_against_per_60", "SA/60", "", 1),
        )

        /** The counting line, summed across the window rather than averaged. */
        val skaterStandard = listOf(
            m("points", "P", "", 0),
            m("goals", "G", "", 0),
            m("assists", "A", "", 0),
            m("shots_on_goal", "SOG", "", 0),
            m("ixg", "ixG", "", 1),
            m("hd_shots", "HD Shots", "", 0),
            m("blocks", "Blocks", "", 0),
            m("hits", "Hits", "", 0),
        )
        val goalieStandard = listOf(
            m("sv_pct", "SV%", "", 3),
            m("gaa", "GAA", "", 2, true),
            m("saves", "Saves", "", 0),
            m("goals_against", "GA", "", 0, true),
            m("wins", "W", "", 0),
            m("shutouts", "SO", "", 0),
        )

        fun advanced(side: TrendSide): List<TrendMetric> = if (side == TrendSide.GOALIE) goalieAdvanced else skaterAdvanced

        fun standard(side: TrendSide): List<TrendMetric> = if (side == TrendSide.GOALIE) goalieStandard else skaterStandard

        fun list(side: TrendSide, mode: TrendStatMode): List<TrendMetric> {
            val picked = if (mode == TrendStatMode.ADVANCED) advanced(side) else standard(side)
            return picked.ifEmpty { standard(side) }
        }
    }
}

enum class TrendStatMode(val label: String) { ADVANCED("Advanced"), STANDARD("Standard") }

/** Which cohort the Trends board ranks; a defenseman's point pace is not a winger's. */
enum class TrendSide(val label: String, val shortLabel: String, val playerType: String) {
    FORWARD("Forwards", "F", "f"),
    DEFENSE("Defensemen", "D", "d"),
    GOALIE("Goalies", "G", "g");

    val positionGroup: PlayerPositionGroup
        get() = when (this) {
            FORWARD -> PlayerPositionGroup.FORWARD
            DEFENSE -> PlayerPositionGroup.DEFENSE
            GOALIE -> PlayerPositionGroup.GOALIE
        }

    val hasAdvancedMetrics: Boolean get() = TrendMetric.advanced(this).isNotEmpty()
}
