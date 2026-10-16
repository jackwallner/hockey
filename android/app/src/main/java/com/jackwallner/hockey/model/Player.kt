package com.jackwallner.hockey.model

import java.text.NumberFormat
import java.time.Instant
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.serialization.json.JsonObject

data class Player(
    val playerId: Int,
    val name: String,
    val team: String,
    val position: String,
    val handedness: String,
    val updatedAt: Instant,
    val season: Int?,
    val seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    val playerType: String? = null,
    val source: String? = null,
    val metrics: List<Metric>,
    val standardStats: List<StandardStat>?,
    val games: List<GameTrend> = emptyList(),
) {
    val id: String get() = "$playerId-${season ?: 0}-${seasonPhase.raw}"

    /** Metrics that carry a real rank. See [Metric.isUnranked]. */
    val rankedMetrics: List<Metric> get() = metrics.filter { !it.isUnranked }

    val overallPercentile: Int
        get() {
            val metrics = rankedMetrics
            if (metrics.isEmpty()) return 0
            // A forward with Scoring, Shot Quality and Play Driving metrics
            // shouldn't have his headline diluted by averaging unrelated skills:
            // take the best category.
            val categories = metrics.map { it.category }.toSet()
            if (categories.size > 1) {
                val best = metrics.groupBy { it.category }.values
                    .maxOf { group -> group.sumOf { it.percentile }.toDouble() / group.size }
                return swiftRound(best)
            }
            return swiftRound(metrics.sumOf { it.percentile }.toDouble() / metrics.size)
        }

    val headlineMetric: Metric? get() = rankedMetrics.maxByOrNull { it.percentile }

    val latestGame: GameTrend? get() = games.maxByOrNull { it.date }

    val shareSummary: String
        get() {
            val headline = headlineMetric?.let { metric ->
                val valueText = if (metric.value.isEmpty()) "${metric.percentile.ordinal} percentile"
                else "${metric.value}, ${metric.percentile.ordinal} percentile"
                "${metric.label} $valueText"
            } ?: "${overallPercentile.ordinal} overall percentile"
            return "$name · $team $displayPosition\nOverall: ${overallPercentile.ordinal} percentile\nTop stat: $headline\nHockey Edge: Puck StatScout"
        }

    fun percentile(category: MetricCategory): Int? {
        val categoryMetrics = rankedMetrics.filter { it.category == category }
        if (categoryMetrics.isEmpty()) return null
        return swiftRound(categoryMetrics.sumOf { it.percentile }.toDouble() / categoryMetrics.size)
    }

    fun matchesPlayerType(category: MetricCategory?): Boolean {
        category ?: return true
        // An unknown role label falls through to "include" so a player who lost
        // it upstream but carries real metrics is never dropped.
        val type = playerType?.lowercase()?.takeIf { it in KNOWN_TYPES } ?: return true
        return when (category) {
            MetricCategory.SCORING, MetricCategory.SHOT_QUALITY, MetricCategory.PLAY_DRIVING -> type == "f" || type == "d"
            MetricCategory.GOALTENDING -> type == "g"
        }
    }

    /** The category a player leads with, from the cohort, else his most common metric category. */
    val primaryCategory: MetricCategory
        get() = when (playerType?.lowercase()) {
            "f" -> MetricCategory.SCORING
            "d" -> MetricCategory.PLAY_DRIVING
            "g" -> MetricCategory.GOALTENDING
            else -> metrics.groupingBy { it.category }.eachCount().maxByOrNull { it.value }?.key ?: MetricCategory.SCORING
        }

    /** Never "TBD" next to real stats: fall back to the cohort label. L and R read LW and RW. */
    val displayPosition: String
        get() {
            val trimmed = position.trim().uppercase()
            if (trimmed.isNotEmpty() && trimmed != "TBD" && trimmed != "\u2014" && trimmed != "-") {
                return when (trimmed) { "L" -> "LW"; "R" -> "RW"; else -> trimmed }
            }
            return positionGroup.raw
        }

    val initials: String
        get() {
            val parts = name.split(" ").filter { it.isNotEmpty() }
            val first = parts.firstOrNull() ?: return ""
            if (parts.size == 1) return first.take(1)
            val last = parts.last()
            val suffix = last.trim { !it.isLetterOrDigit() }.uppercase()
            if (suffix in setOf("JR", "SR", "II", "III", "IV", "V") && parts.size > 2) {
                return first.take(1) + parts[parts.size - 2].take(1)
            }
            return first.take(1) + last.take(1)
        }

    val isGoalie: Boolean get() = playerType?.lowercase() == "g" || positionGroup == PlayerPositionGroup.GOALIE

    /** In hockey the line that cannot be crossed is skater vs goalie. */
    val isDefensivePlayer: Boolean get() = isGoalie

    fun canCompareHeadToHead(other: Player): Boolean = isGoalie == other.isGoalie

    val positionGroup: PlayerPositionGroup
        get() = when (playerType?.lowercase()) {
            "f" -> PlayerPositionGroup.FORWARD
            "d" -> PlayerPositionGroup.DEFENSE
            "g" -> PlayerPositionGroup.GOALIE
            else -> when (position.trim().uppercase()) {
                "G" -> PlayerPositionGroup.GOALIE
                "D" -> PlayerPositionGroup.DEFENSE
                "C", "L", "R", "W", "LW", "RW", "F" -> PlayerPositionGroup.FORWARD
                else -> if (primaryCategory == MetricCategory.GOALTENDING) PlayerPositionGroup.GOALIE else PlayerPositionGroup.FORWARD
            }
        }

    /** "312 min", "41 SOG", "410 SA": the volume a category's rates were measured over. Null when the line has none. */
    fun volumeCaption(category: MetricCategory): String? = when (category) {
        MetricCategory.SCORING, MetricCategory.PLAY_DRIVING -> MetricWeight.ICE_TIME.value(this)?.let { "${swiftRoundDouble(it).toInt()} min" }
        MetricCategory.SHOT_QUALITY -> MetricWeight.SHOTS_ON_GOAL.value(this)?.let { "${it.toInt()} SOG" }
        MetricCategory.GOALTENDING -> MetricWeight.SHOTS_AGAINST.value(this)?.let { "${it.toInt()} SA" }
    }

    fun metrics(kind: MetricKind): List<Metric> =
        HockeyMetricRegistry.sorted(metrics.filter { HockeyMetricRegistry.kind(it) == kind })

    fun preferredHeadlineMetric(kind: MetricKind): Metric? {
        val candidates = metrics(kind)
        val preferred = if (kind == MetricKind.ADVANCED) positionGroup.preferredAdvancedMetrics else positionGroup.preferredTraditionalMetrics
        for (label in preferred) candidates.firstOrNull { it.label == label }?.let { return it }
        return candidates.firstOrNull()
    }

    companion object {
        private val KNOWN_TYPES = setOf("f", "d", "g")
        private val labelPool = HashMap<String, String>()

        /** Labels repeat across thousands of rows; share one copy of each. */
        @Synchronized
        internal fun intern(value: String): String = labelPool.getOrPut(value) { value }

        /**
         * Mirrors `Player.init(from:)`: required id/name/team/position/handedness/
         * updated_at/metrics; one undecodable metric fails the row, as on iOS.
         */
        fun fromJson(o: JsonObject): Player {
            val metrics = o.array("metrics") ?: throw RowDecodeException("missing metrics")
            val updated = o.requireString("updated_at")
            return Player(
                playerId = o.requireInt("id"),
                name = o.requireString("name"),
                team = intern(o.requireString("team")),
                position = intern(o.requireString("position")),
                handedness = intern(o.requireString("handedness")),
                updatedAt = parseDate(updated) ?: throw RowDecodeException("bad updated_at"),
                season = o.int("season"),
                seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad season_type") }
                    ?: SeasonPhase.REGULAR,
                playerType = o.string("player_type")?.let(::intern),
                source = o.string("source")?.let(::intern),
                metrics = metrics.map { Metric.fromJson(it as? JsonObject ?: throw RowDecodeException("bad metric")) },
                standardStats = o.array("standard_stats")?.map {
                    StandardStat.fromJson(it as? JsonObject ?: throw RowDecodeException("bad stat"))
                },
                games = o.array("games")?.map { GameTrend.fromJson(it as? JsonObject ?: throw RowDecodeException("bad game")) }
                    ?: emptyList(),
            )
        }
    }
}

/** Swift's `round` (half away from zero) on a non-negative mean. */
internal fun swiftRound(value: Double): Int = swiftRoundDouble(value).toInt()

/** C `printf("%.Nf")`: rounds the exact binary value (0.155 prints 0.15), where Java's `String.format` rounds the shortest decimal (0.16). */
internal fun cFixed(value: Double, decimals: Int): String =
    java.math.BigDecimal(value).setScale(decimals, java.math.RoundingMode.HALF_EVEN).toPlainString()

/** Swift's `.rounded()`: half away from zero (Java's `Math.round` rounds -0.5 up). */
internal fun swiftRoundDouble(value: Double): Double = if (value < 0) -Math.floor(-value + 0.5) else Math.floor(value + 0.5)

enum class SeasonPhase(val raw: String) {
    REGULAR("REG"),
    PLAYOFFS("POST");

    /** One name everywhere: "Regular Season", never the bare adjective. */
    val label: String get() = if (this == REGULAR) "Regular Season" else "Playoffs"

    companion object {
        fun from(raw: String): SeasonPhase? = entries.firstOrNull { it.raw == raw }
    }
}

data class Metric(
    val label: String,
    val value: String,
    val percentile: Int,
    val category: MetricCategory,
    /** Live season only: whether the player clears the prorated bar. Null means it qualified. */
    val qualified: Boolean? = null,
    /** False for counting stats built outside the registry, so a zero there is unranked too. */
    val rankable: Boolean? = null,
    val id: String = derivedId(category, label),
) {
    /**
     * A traditional counting stat at zero (0 G, 0 SHG, 0 SO). The feed ranks the
     * tie's midpoint, so most of the league read 47th percentile at something
     * they had never done. The value shows; the rank is left out.
     */
    val isUnranked: Boolean
        get() {
            if (rankable == false) return true
            val definition = HockeyMetricRegistry.definition(label, category) ?: return false
            if (definition.kind != MetricKind.TRADITIONAL) return false
            if (HockeyMetricRegistry.aggregation(label, category) != MetricAggregation.Sum) return false
            val number = metricNumericValue(value) ?: return false
            return number == 0.0
        }

    /** Below the prorated playing-time bar for this metric. */
    val isSmallSample: Boolean get() = qualified == false

    companion object {
        /** The bundle leaves the id out; it is fully determined by category and label. */
        fun derivedId(category: MetricCategory, label: String): String =
            category.raw.lowercase().replace(" ", "-") + "-" + label

        fun fromJson(o: JsonObject): Metric {
            val category = MetricCategory.from(o.requireString("category")) ?: throw RowDecodeException("bad category")
            return Metric(
                label = Player.intern(o.requireString("label")),
                value = o.requireString("value").let { if (it.length <= 6) Player.intern(it) else it },
                percentile = o.requireInt("percentile"),
                category = category,
                qualified = o.bool("qualified"),
                rankable = o.bool("rankable"),
                id = o.string("id") ?: Player.intern(derivedId(category, o.requireString("label"))),
            )
        }
    }
}

data class StandardStat(val label: String, val value: String, val id: String = "std-$label") {
    companion object {
        fun fromJson(o: JsonObject) = StandardStat(
            label = Player.intern(o.requireString("label")),
            value = o.requireString("value").let { if (it.length <= 6) Player.intern(it) else it },
            id = o.string("id") ?: Player.intern("std-${o.requireString("label")}"),
        )
    }
}

data class GameTrend(
    val id: String,
    val date: Instant,
    val opponent: String,
    val summary: String,
    val percentileDelta: Int,
    val keyMetric: String,
) {
    companion object {
        fun fromJson(o: JsonObject) = GameTrend(
            id = o.requireString("id"),
            date = parseDate(o.requireString("date")) ?: throw RowDecodeException("bad date"),
            opponent = o.requireString("opponent"),
            summary = o.requireString("summary"),
            percentileDelta = o.requireInt("percentile_delta"),
            keyMetric = o.requireString("key_metric"),
        )
    }
}

/**
 * Shared meaning for `standard_stats` values. Most are plain numbers; `TOI/GP`
 * is a clock ("19:42") and ranks by its minutes, and for a few stats the
 * smaller number is the better one.
 */
object StandardStatSemantics {
    enum class Winner { LEFT, RIGHT }

    fun numericValue(label: String, value: String): Double? = when (label.uppercase()) {
        "TOI/GP" -> MetricWeight.clockMinutes(value)
        else -> metricNumericValue(value)
    }

    /** Fewer is better: goals against average, penalty minutes, and a goalie's losses and overtime losses. */
    fun higherIsBetter(label: String): Boolean = label.uppercase() !in setOf("GAA", "PIM", "L", "OT")

    /** Midpoint rank against every peer carrying the same stat. */
    fun percentile(label: String, value: String, peerValues: List<String>): Int {
        val current = numericValue(label, value) ?: return 50
        var values = peerValues.mapNotNull { numericValue(label, it) }
        if (values.isEmpty()) values = listOf(current)
        val below = values.count { it < current }
        val equal = values.count { it == current }
        val raw = (below + equal / 2.0) / values.size * 100
        val oriented = if (higherIsBetter(label)) raw else 100 - raw
        return swiftRound(oriented).coerceIn(1, 100)
    }

    fun winner(label: String, left: String?, right: String?): Winner? {
        val l = left?.let { numericValue(label, it) } ?: return null
        val r = right?.let { numericValue(label, it) } ?: return null
        if (l == r) return null
        val leftWins = if (higherIsBetter(label)) l > r else l < r
        return if (leftWins) Winner.LEFT else Winner.RIGHT
    }
}

/**
 * The leading number in a formatted feed value: "6.2%" -> 6.2, "3,322" -> 3322,
 * "+2.3" -> 2.3. Matches Foundation's `Scanner.scanDouble` on these inputs.
 */
fun metricNumericValue(value: String): Double? {
    var s = value.trim().replace(",", "")
    if (s.startsWith(".")) s = "0$s"
    if (s.startsWith("-.")) s = "-0" + s.drop(1)
    val match = NUMBER_PREFIX.find(s) ?: return null
    return match.value.toDoubleOrNull()
}

/**
 * Shared ranks for ties (1, 2, 2, 4), the way a stat sheet prints them: two
 * forwards on 31 goals are not 21st and 22nd. [values] is in display
 * order; a null never ties.
 */
fun competitionRanks(values: List<Double?>): List<Int> {
    val ranks = ArrayList<Int>(values.size)
    for (index in values.indices) {
        if (index > 0 && values[index] != null && values[index] == values[index - 1]) ranks += ranks[index - 1]
        else ranks += index + 1
    }
    return ranks
}

/** A player's value for one metric, as a number, for ranking. */
fun metricValue(player: Player, label: String, category: MetricCategory): Double? =
    player.metrics.firstOrNull { it.label == label && it.category == category }?.let { metricNumericValue(it.value) }

private val NUMBER_PREFIX = Regex("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?")

/**
 * The display shape of a metric value, inferred from the feed's own strings so
 * an aggregate of "6.2%" renders as a percentage with the same precision.
 */
data class MetricValueFormat(
    val decimals: Int = 0,
    val isPercent: Boolean = false,
    val isSigned: Boolean = false,
    val hasGrouping: Boolean = false,
    /** Save percentages ship as ".915", never "0.915". */
    val dropsLeadingZero: Boolean = false,
) {
    fun string(value: Double): String {
        var text = when {
            decimals == 0 && hasGrouping -> NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong())
            decimals == 0 -> swiftRoundDouble(value).toLong().toString()
            else -> cFixed(value, decimals)
        }
        if (dropsLeadingZero && text.startsWith("0.")) text = text.drop(1)
        if (isSigned && value > 0) text = "+$text"
        if (isPercent) text += "%"
        return text
    }

    companion object {
        fun inferred(samples: List<String>): MetricValueFormat {
            var format = MetricValueFormat()
            for (sample in samples) {
                val trimmed = sample.trim()
                if (trimmed.endsWith("%")) format = format.copy(isPercent = true)
                if (trimmed.startsWith("+")) format = format.copy(isSigned = true)
                if (trimmed.contains(",")) format = format.copy(hasGrouping = true)
                if (trimmed.startsWith(".")) format = format.copy(dropsLeadingZero = true)
                val dot = trimmed.indexOf('.')
                val digits = if (dot < 0) 0 else trimmed.substring(dot + 1).takeWhile { it.isDigit() }.length
                format = format.copy(decimals = maxOf(format.decimals, digits))
            }
            return format
        }
    }
}

enum class MetricCategory(val raw: String) {
    SCORING("Scoring"),
    SHOT_QUALITY("Shot Quality"),
    PLAY_DRIVING("Play Driving"),
    GOALTENDING("Goaltending");

    /** Short form for segmented controls and chips. */
    val shortLabel: String
        get() = when (this) {
            SCORING -> "Scoring"
            SHOT_QUALITY -> "Shots"
            PLAY_DRIVING -> "Driving"
            GOALTENDING -> "Goalies"
        }

    /** Registry-driven display order: advanced first, then traditional. */
    val metricPriorityOrder: List<String>
        get() = HockeyMetricRegistry.definitions.filter { it.category == this }.sortedBy { it.priority }.map { it.label }

    fun sortMetrics(a: String, b: String): Boolean {
        val order = metricPriorityOrder
        val ia = order.indexOf(a).let { if (it < 0) order.size else it }
        val ib = order.indexOf(b).let { if (it < 0) order.size else it }
        return ia < ib
    }

    companion object {
        fun from(raw: String): MetricCategory? = entries.firstOrNull { it.raw.equals(raw, ignoreCase = true) }
    }
}

enum class PlayerPositionGroup(val raw: String) {
    FORWARD("F"), DEFENSE("D"), GOALIE("G");

    val displayName: String
        get() = when (this) {
            FORWARD -> "Forwards"
            DEFENSE -> "Defensemen"
            GOALIE -> "Goalies"
        }

    /** For a segmented control sharing a row: "Defensemen" does not fit a fifth of the screen. */
    val pickerLabel: String
        get() = when (this) {
            FORWARD -> "Forwards"
            DEFENSE -> "Defense"
            GOALIE -> "Goalies"
        }

    val singular: String
        get() = when (this) {
            FORWARD -> "Forward"
            DEFENSE -> "Defenseman"
            GOALIE -> "Goalie"
        }

    val cohortDescription: String get() = "Among ${displayName.lowercase()}"

    val isSkater: Boolean get() = this != GOALIE

    val primaryCategory: MetricCategory
        get() = when (this) {
            FORWARD -> MetricCategory.SCORING
            DEFENSE -> MetricCategory.PLAY_DRIVING
            GOALIE -> MetricCategory.GOALTENDING
        }

    /** The categories this cohort appears in, in board order. */
    val categories: List<MetricCategory>
        get() = when (this) {
            FORWARD -> listOf(MetricCategory.SCORING, MetricCategory.SHOT_QUALITY, MetricCategory.PLAY_DRIVING)
            DEFENSE -> listOf(MetricCategory.PLAY_DRIVING, MetricCategory.SHOT_QUALITY, MetricCategory.SCORING)
            GOALIE -> listOf(MetricCategory.GOALTENDING)
        }

    val preferredAdvancedMetrics: List<String>
        get() = when (this) {
            FORWARD -> listOf("ixG", "GAx", "P/60", "xGF%")
            DEFENSE -> listOf("xGF%", "Rel xGF%", "xGA/60", "ixG")
            GOALIE -> listOf("GSAx", "HD SV%", "GSAx/60")
        }

    val preferredTraditionalMetrics: List<String>
        get() = when (this) {
            FORWARD -> listOf("P", "G", "A")
            DEFENSE -> listOf("P", "Blocks", "A")
            GOALIE -> listOf("SV%", "GAA", "W")
        }
}

enum class MetricKind(val label: String) { ADVANCED("Advanced"), TRADITIONAL("Traditional") }

enum class MetricFamily(val label: String) {
    PRODUCTION("Production"), EXPECTED_GOALS("Expected Goals"), SHOOTING("Shooting"), POSSESSION("Possession"),
    DEFENSE("Defense"), USAGE("Usage"), GOALTENDING("Goaltending"), WORKLOAD("Workload"),
}

data class MetricDefinition(
    val label: String,
    val category: MetricCategory,
    val kind: MetricKind,
    val family: MetricFamily,
    val positions: Set<PlayerPositionGroup>,
    val higherIsBetter: Boolean,
    val priority: Int,
    val description: String,
)

/** How several players' values for one metric collapse into one number. */
sealed interface MetricAggregation {
    data object Sum : MetricAggregation
    data class Weighted(val weight: MetricWeight) : MetricAggregation
}

/** The denominator a rate was computed against, read off the standard line. */
enum class MetricWeight {
    /** Total ice time in minutes: TOI/GP times GP. */
    ICE_TIME, SHOTS_ON_GOAL, SHOT_ATTEMPTS, SHOTS_AGAINST, GAMES;

    /** Null when the player has no volume, which drops him from a weighted mean. */
    fun value(player: Player): Double? = when (this) {
        ICE_TIME -> totalIceTime(player)
        SHOTS_ON_GOAL, SHOT_ATTEMPTS -> plain("SOG", player)
        SHOTS_AGAINST -> plain("SA", player)
        GAMES -> plain("GP", player)
    }

    companion object {
        private fun plain(label: String, player: Player): Double? {
            val raw = player.standardStats?.firstOrNull { it.label == label }?.value ?: return null
            return metricNumericValue(raw)?.takeIf { it > 0 }
        }

        /** "19:42" per game times games played. A goalie line has no TOI/GP, so goalies weight by games. */
        private fun totalIceTime(player: Player): Double? {
            val games = plain("GP", player) ?: return null
            val raw = player.standardStats?.firstOrNull { it.label == "TOI/GP" }?.value ?: return games
            val perGame = clockMinutes(raw)?.takeIf { it > 0 } ?: return games
            return perGame * games
        }

        /** "19:42" -> 19.7 minutes. */
        fun clockMinutes(raw: String): Double? {
            val parts = raw.split(":")
            if (parts.size == 2) {
                val minutes = parts[0].toDoubleOrNull()
                val seconds = parts[1].toDoubleOrNull()
                if (minutes != null && seconds != null) return minutes + seconds / 60
            }
            return metricNumericValue(raw)
        }
    }
}

/**
 * One metric pooled across a roster with the registry's aggregation rule:
 * counting stats add up, rates are weighted by the volume behind them.
 */
object RosterAggregate {
    /** Roster aggregates that are context rather than a verdict. None in hockey; kept for a future share metric. */
    val descriptiveOnlyLabels: Set<String> = emptySet()

    fun value(label: String, category: MetricCategory, roster: List<Player>): Double? {
        val rule = HockeyMetricRegistry.aggregation(label, category)
        val values = roster.mapNotNull { player ->
            val metric = player.metrics.firstOrNull { it.label == label && it.category == category } ?: return@mapNotNull null
            val value = metricNumericValue(metric.value) ?: return@mapNotNull null
            when (rule) {
                MetricAggregation.Sum -> value to 1.0
                // No volume means no rate to trust: drop the player rather than
                // let an unweighted value slide in as if it were weight 1.
                is MetricAggregation.Weighted -> rule.weight.value(player)?.let { value to it }
            }
        }
        if (values.isEmpty()) return null
        return when (rule) {
            MetricAggregation.Sum -> values.sumOf { it.first }
            is MetricAggregation.Weighted -> {
                val totalWeight = values.sumOf { it.second }
                if (totalWeight <= 0) null else values.sumOf { it.first * it.second } / totalWeight
            }
        }
    }

    /** Games a club has played, read off its roster: the most games any one player has. */
    fun teamGames(roster: List<Player>): Double? =
        roster.mapNotNull { MetricWeight.GAMES.value(it) }.maxOrNull()?.takeIf { it > 0 }
}

/**
 * Last name for a narrow column header, without a generational suffix.
 */
val Player.surname: String
    get() {
        val suffixes = setOf("JR", "JR.", "SR", "SR.", "II", "III", "IV", "V")
        return name.split(" ").filter { it.isNotEmpty() }.lastOrNull { it.uppercase() !in suffixes } ?: name
    }

object HockeyMetricRegistry {
    private val SKATERS = setOf(PlayerPositionGroup.FORWARD, PlayerPositionGroup.DEFENSE)
    private val GOALIES = setOf(PlayerPositionGroup.GOALIE)

    private fun d(
        label: String, category: MetricCategory, kind: MetricKind, family: MetricFamily,
        positions: Set<PlayerPositionGroup>, priority: Int, description: String, higherIsBetter: Boolean = true,
    ) = MetricDefinition(label, category, kind, family, positions, higherIsBetter, priority, description)

    private val S = MetricCategory.SCORING
    private val Q = MetricCategory.SHOT_QUALITY
    private val P = MetricCategory.PLAY_DRIVING
    private val G = MetricCategory.GOALTENDING
    private val A = MetricKind.ADVANCED
    private val T = MetricKind.TRADITIONAL

    val definitions: List<MetricDefinition> = listOf(
        // Scoring. Rates lead; the counting stats every box score carries follow.
        d("P/60", S, A, MetricFamily.PRODUCTION, SKATERS, 10, "Points per 60 minutes of ice time, all situations. Production with the ice time taken out."),
        d("Primary P", S, A, MetricFamily.PRODUCTION, SKATERS, 20, "Goals plus primary assists. Secondary assists are left out because they track linemates more than the player."),
        d("Game Score", S, A, MetricFamily.PRODUCTION, SKATERS, 30, "MoneyPuck game score per game played: one number that weighs goals, assists, shots, blocks, penalties, faceoffs and on-ice shot share."),
        d("G", S, T, MetricFamily.PRODUCTION, SKATERS, 110, "Goals, all situations."),
        d("A", S, T, MetricFamily.PRODUCTION, SKATERS, 120, "Assists, primary and secondary."),
        d("P", S, T, MetricFamily.PRODUCTION, SKATERS, 130, "Points: goals plus assists."),
        d("PP P", S, T, MetricFamily.PRODUCTION, SKATERS, 140, "Power-play points, scored at 5 on 4."),
        d("SOG", S, T, MetricFamily.SHOOTING, SKATERS, 150, "Shots on goal."),
        d("Sh%", S, T, MetricFamily.SHOOTING, SKATERS, 160, "Goals divided by shots on goal."),

        // Shot Quality. MoneyPuck's expected goals model.
        d("ixG", Q, A, MetricFamily.EXPECTED_GOALS, SKATERS, 10, "Individual expected goals: the sum of each shot's probability of scoring given its location, type, rebound and rush context. From MoneyPuck."),
        d("GAx", Q, A, MetricFamily.EXPECTED_GOALS, SKATERS, 20, "Goals above expected: actual goals minus individual expected goals. Positive means finishing above what the shots deserved."),
        d("ixG/60", Q, A, MetricFamily.EXPECTED_GOALS, SKATERS, 30, "Individual expected goals per 60 minutes, all situations."),
        d("xG/Shot", Q, A, MetricFamily.SHOOTING, SKATERS, 40, "Expected goals per unblocked shot attempt: how dangerous the average shot is."),
        d("Shots/60", Q, A, MetricFamily.SHOOTING, SKATERS, 50, "Shot attempts per 60 minutes, blocked and missed included."),
        d("Shot Att", Q, T, MetricFamily.SHOOTING, SKATERS, 110, "Shot attempts: on goal, missed and blocked."),
        d("HD Shots", Q, T, MetricFamily.SHOOTING, SKATERS, 120, "High-danger shots, the attempts MoneyPuck rates at 20% or more to score."),
        d("Rebounds", Q, T, MetricFamily.SHOOTING, SKATERS, 130, "Rebounds created by the player's shots."),

        // Play Driving. 5 on 5 on-ice share metrics plus the counting stats a defenseman is judged on.
        d("xGF%", P, A, MetricFamily.POSSESSION, SKATERS, 10, "Share of 5-on-5 expected goals that went the player's way while on the ice. 50% is even."),
        d("Rel xGF%", P, A, MetricFamily.POSSESSION, SKATERS, 20, "On-ice xGF% minus the team's xGF% with the player on the bench. Separates the player from the team."),
        d("CF%", P, A, MetricFamily.POSSESSION, SKATERS, 30, "Corsi for percentage: share of all 5-on-5 shot attempts while on the ice."),
        d("Rel CF%", P, A, MetricFamily.POSSESSION, SKATERS, 40, "On-ice CF% minus the team's CF% with the player on the bench."),
        d("HDCF%", P, A, MetricFamily.POSSESSION, SKATERS, 50, "Share of 5-on-5 high-danger shot attempts while on the ice."),
        d("GF%", P, A, MetricFamily.POSSESSION, SKATERS, 60, "Share of 5-on-5 goals while on the ice. Swings on goaltending and shooting luck; compare with xGF%."),
        d("xGF/60", P, A, MetricFamily.POSSESSION, SKATERS, 70, "5-on-5 expected goals for per 60 minutes while on the ice."),
        d("xGA/60", P, A, MetricFamily.DEFENSE, SKATERS, 80, "5-on-5 expected goals against per 60 minutes while on the ice. Lower is better.", higherIsBetter = false),
        d("Blocks", P, T, MetricFamily.DEFENSE, SKATERS, 110, "Shots blocked."),
        d("Hits", P, T, MetricFamily.DEFENSE, SKATERS, 120, "Hits credited by the home scorer."),
        d("Takeaways", P, T, MetricFamily.DEFENSE, SKATERS, 130, "Takeaways credited by the home scorer."),
        d("Giveaways", P, T, MetricFamily.DEFENSE, SKATERS, 140, "Giveaways credited by the home scorer. Lower is better.", higherIsBetter = false),

        // Goaltending. Goals saved above expected is the headline; save percentage and GAA are on the broadcast.
        d("GSAx", G, A, MetricFamily.GOALTENDING, GOALIES, 10, "Goals saved above expected: expected goals faced minus goals allowed. From MoneyPuck."),
        d("GSAx/60", G, A, MetricFamily.GOALTENDING, GOALIES, 20, "Goals saved above expected per 60 minutes."),
        d("HD SV%", G, A, MetricFamily.GOALTENDING, GOALIES, 30, "Save percentage on high-danger shots."),
        d("xGA/60", G, A, MetricFamily.WORKLOAD, GOALIES, 40, "Expected goals faced per 60 minutes: how much danger the goalie saw."),
        d("Rebound%", G, A, MetricFamily.GOALTENDING, GOALIES, 50, "Share of shots on goal that produced a rebound. Lower is better.", higherIsBetter = false),
        d("SV%", G, T, MetricFamily.GOALTENDING, GOALIES, 110, "Saves divided by shots on goal."),
        d("GAA", G, T, MetricFamily.GOALTENDING, GOALIES, 120, "Goals against per 60 minutes. Lower is better.", higherIsBetter = false),
        d("W", G, T, MetricFamily.PRODUCTION, GOALIES, 130, "Wins."),
        d("SO", G, T, MetricFamily.PRODUCTION, GOALIES, 140, "Shutouts."),
        d("Saves", G, T, MetricFamily.WORKLOAD, GOALIES, 150, "Shots on goal stopped."),
        d("GA", G, T, MetricFamily.GOALTENDING, GOALIES, 160, "Goals against. Lower is better.", higherIsBetter = false),
    )

    private val byKey: Map<Pair<String, MetricCategory>, MetricDefinition> =
        definitions.associateBy { it.label to it.category }

    fun definition(label: String, category: MetricCategory): MetricDefinition? = byKey[label to category]

    /**
     * Per-60 rates and shares weight by ice time, per-shot rates by shots,
     * goalie rates by shots against; counting stats add up.
     */
    fun aggregation(label: String, category: MetricCategory): MetricAggregation = when (category) {
        MetricCategory.SCORING -> when (label) {
            "Sh%" -> MetricAggregation.Weighted(MetricWeight.SHOTS_ON_GOAL)
            "P/60", "Game Score" -> MetricAggregation.Weighted(MetricWeight.ICE_TIME)
            else -> MetricAggregation.Sum
        }
        MetricCategory.SHOT_QUALITY -> when (label) {
            "xG/Shot" -> MetricAggregation.Weighted(MetricWeight.SHOT_ATTEMPTS)
            "ixG/60", "Shots/60" -> MetricAggregation.Weighted(MetricWeight.ICE_TIME)
            else -> MetricAggregation.Sum
        }
        MetricCategory.PLAY_DRIVING -> when (label) {
            "Blocks", "Hits", "Takeaways", "Giveaways" -> MetricAggregation.Sum
            else -> MetricAggregation.Weighted(MetricWeight.ICE_TIME)
        }
        MetricCategory.GOALTENDING -> when (label) {
            "W", "SO", "Saves", "GA", "GSAx" -> MetricAggregation.Sum
            "GAA", "GSAx/60", "xGA/60" -> MetricAggregation.Weighted(MetricWeight.ICE_TIME)
            else -> MetricAggregation.Weighted(MetricWeight.SHOTS_AGAINST)
        }
    }

    fun kind(metric: Metric): MetricKind = definition(metric.label, metric.category)?.kind ?: MetricKind.ADVANCED

    fun isSupported(metric: Metric, position: PlayerPositionGroup): Boolean =
        definition(metric.label, metric.category)?.positions?.contains(position) ?: true

    fun sorted(metrics: List<Metric>): List<Metric> = metrics.sortedWith { lhs, rhs ->
        val left = definition(lhs.label, lhs.category)?.priority ?: Int.MAX_VALUE
        val right = definition(rhs.label, rhs.category)?.priority ?: Int.MAX_VALUE
        if (left == right) lhs.label.compareTo(rhs.label) else left.compareTo(right)
    }
}

data class TeamRoute(val abbr: String)

/** "1st", "22nd", "113th". */
val Int.ordinal: String
    get() {
        val mod100 = this % 100
        val suffix = if (mod100 in 11..13) "th" else when (this % 10) {
            1 -> "st"
            2 -> "nd"
            3 -> "rd"
            else -> "th"
        }
        return "$this$suffix"
    }

internal fun Double.roundToIntSafe(): Int = if (isNaN()) 0 else roundToInt()
